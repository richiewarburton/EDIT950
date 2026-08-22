import Foundation

enum P9AuditionSyncState: Equatable {
    case disconnected
    case syncing(Int)
    case auditioned(Int)
    case error(String)

    var title: String {
        switch self {
        case .disconnected: return "PLAY Disconnected"
        case .syncing: return "Syncing"
        case .auditioned: return "Auditioned"
        case .error: return "Sync Error"
        }
    }
}

struct P9LiveEditSessionRequest: Codable, Equatable {
    static let currentVersion = 1
    static let fileExtension = "edit950session"

    let protocolVersion: Int
    let instanceID: String
    let imagePath: String
    let programFilename: String
    let programData: Data
    let baselineProgramData: Data
    let revision: Int
    let createdAt: Date

    func validated(now: Date = Date()) throws -> P9LiveEditSessionRequest {
        guard protocolVersion == Self.currentVersion,
              UUID(uuidString: instanceID) != nil,
              !imagePath.isEmpty,
              !programFilename.isEmpty,
              revision >= 0,
              abs(createdAt.timeIntervalSince(now)) <= 300
        else {
            throw AppError.verificationFailed(
                "The PLAY950 edit-session request is invalid or has expired."
            )
        }
        _ = try P9Program(data: programData)
        _ = try P9Program(data: baselineProgramData)
        return self
    }

    static func read(from url: URL, now: Date = Date()) throws -> P9LiveEditSessionRequest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(
            P9LiveEditSessionRequest.self,
            from: Data(contentsOf: url)
        ).validated(now: now)
    }
}

@MainActor
final class P9LiveAuditionClient {
    static let updateNotification = Notification.Name(
        "com.e45recordings.PLAY950.EditTransaction"
    )
    static let acknowledgementNotification = Notification.Name(
        "com.e45recordings.PLAY950.EditAcknowledgement"
    )
    static let sessionNotification = Notification.Name(
        "com.e45recordings.PLAY950.EditSessionState"
    )
    static let queryNotification = Notification.Name(
        "com.e45recordings.PLAY950.EditSessionQuery"
    )

    let instanceID: String
    private(set) var revision: Int
    var onStateChange: ((P9AuditionSyncState) -> Void)?

    private var acknowledgementObserver: NSObjectProtocol?
    private var sessionObserver: NSObjectProtocol?
    private var pendingData: Data?
    private var latestData: Data?
    private var scheduledPublish: Task<Void, Never>?
    private var lastPublish = Date.distantPast
    private let minimumPublishInterval: TimeInterval = 0.04

    init(instanceID: String, initialRevision: Int) {
        self.instanceID = instanceID
        revision = initialRevision
    }

    func start() {
        guard acknowledgementObserver == nil else { return }
        let center = DistributedNotificationCenter.default()
        acknowledgementObserver = center.addObserver(
            forName: Self.acknowledgementNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let instanceID = note.object as? String
            let revision = note.userInfo?["revision"] as? Int
            let error = note.userInfo?["error"] as? String
            MainActor.assumeIsolated {
                self?.receiveAcknowledgement(
                    instanceID: instanceID,
                    revision: revision,
                    error: error
                )
            }
        }
        sessionObserver = center.addObserver(
            forName: Self.sessionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let instanceID = note.object as? String
            let state = note.userInfo?["state"] as? String
            MainActor.assumeIsolated {
                self?.receiveSessionState(instanceID: instanceID, state: state)
            }
        }
        center.postNotificationName(
            Self.queryNotification,
            object: instanceID,
            userInfo: ["protocolVersion": P9LiveEditSessionRequest.currentVersion],
            deliverImmediately: true
        )
        onStateChange?(.syncing(revision))
    }

    func stop() {
        scheduledPublish?.cancel()
        let center = DistributedNotificationCenter.default()
        if let acknowledgementObserver { center.removeObserver(acknowledgementObserver) }
        if let sessionObserver { center.removeObserver(sessionObserver) }
        acknowledgementObserver = nil
        sessionObserver = nil
    }

    func publish(programData: Data) {
        latestData = programData
        pendingData = programData
        let elapsed = Date().timeIntervalSince(lastPublish)
        if elapsed >= minimumPublishInterval {
            publishPending()
            return
        }
        guard scheduledPublish == nil else { return }
        let delay = minimumPublishInterval - elapsed
        scheduledPublish = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(max(0, delay) * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            self?.scheduledPublish = nil
            self?.publishPending()
        }
    }

    private func publishPending() {
        guard let data = pendingData else { return }
        pendingData = nil
        revision &+= 1
        lastPublish = Date()
        onStateChange?(.syncing(revision))
        DistributedNotificationCenter.default().postNotificationName(
            Self.updateNotification,
            object: instanceID,
            userInfo: [
                "protocolVersion": P9LiveEditSessionRequest.currentVersion,
                "revision": revision,
                "transactionID": UUID().uuidString,
                "programBase64": data.base64EncodedString()
            ],
            deliverImmediately: true
        )
    }

    private func receiveAcknowledgement(
        instanceID notifyingInstanceID: String?,
        revision acknowledgedRevision: Int?,
        error: String?
    ) {
        guard notifyingInstanceID == instanceID,
              let acknowledgedRevision
        else { return }
        if let error, !error.isEmpty {
            onStateChange?(.error(error))
        } else if acknowledgedRevision == revision {
            onStateChange?(.auditioned(acknowledgedRevision))
        }
    }

    private func receiveSessionState(instanceID notifyingInstanceID: String?, state: String?) {
        guard notifyingInstanceID == instanceID else { return }
        switch state {
        case "connected":
            if let latestData {
                publish(programData: latestData)
            } else {
                onStateChange?(.syncing(revision))
            }
        case "disconnected":
            onStateChange?(.disconnected)
        default:
            break
        }
    }
}
