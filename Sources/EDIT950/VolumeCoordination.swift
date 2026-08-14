import Darwin
import Foundation

struct VolumeUseRecord: Codable, Equatable, Sendable {
    let appName: String
    let instanceID: UUID
    let processID: Int32
    let volumePath: String
    let detail: String
    let createdAt: Date
}

enum VolumeCoordinationError: LocalizedError, Equatable {
    case ejectInProgress(volumeName: String, appName: String)
    case volumeInUse(volumeName: String, uses: [VolumeUseRecord])
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .ejectInProgress(volumeName, appName):
            return "\(volumeName) is already being prepared for Safe Eject in \(appName). Wait for that operation to finish, then try again."
        case let .volumeInUse(volumeName, uses):
            let descriptions = uses.map { "\($0.appName): \($0.detail)" }
                .sorted()
                .joined(separator: "\n")
            return "Safe Eject stopped before cleanup because \(volumeName) is in use by another 950TOOLS app:\n\n\(descriptions)\n\nFinish or close that work, then try Safe Eject again. The volume remains mounted and no metadata was removed."
        case let .unavailable(message):
            return "950TOOLS could not coordinate access to the removable volume. Nothing was ejected or cleaned. \(message)"
        }
    }
}

final class VolumeUseLease {
    private let fileURL: URL
    private let lock = NSLock()
    private var isReleased = false

    fileprivate init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func release() {
        lock.lock()
        guard !isReleased else {
            lock.unlock()
            return
        }
        isReleased = true
        lock.unlock()
        try? FileManager.default.removeItem(at: fileURL)
    }

    deinit { release() }
}

final class VolumeEjectLease {
    private let directoryURL: URL
    private let lock = NSLock()
    private var isReleased = false

    fileprivate init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func release() {
        lock.lock()
        guard !isReleased else {
            lock.unlock()
            return
        }
        isReleased = true
        lock.unlock()
        try? FileManager.default.removeItem(at: directoryURL)
    }

    deinit { release() }
}

struct VolumeCoordinationCenter {
    let appName: String
    let instanceID: UUID
    let processID: Int32

    private let rootURL: URL
    private let processIsAlive: (Int32) -> Bool
    private let fileManager = FileManager.default

    init(
        appName: String,
        instanceID: UUID = UUID(),
        processID: Int32 = getpid(),
        rootURL: URL? = nil,
        processIsAlive: @escaping (Int32) -> Bool = Self.liveProcess
    ) {
        self.appName = appName
        self.instanceID = instanceID
        self.processID = processID
        self.rootURL = rootURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("950TOOLS", isDirectory: true)
            .appendingPathComponent("VolumeCoordination", isDirectory: true)
        self.processIsAlive = processIsAlive
    }

    func beginUse(of volumeURL: URL, detail: String) throws -> VolumeUseLease {
        let identity = volumeIdentity(volumeURL)
        do {
            try ensureRoot()
            if let owner = try liveEjectOwner(for: identity.key) {
                throw VolumeCoordinationError.ejectInProgress(
                    volumeName: identity.name,
                    appName: owner.appName
                )
            }
            let usesDirectory = usesURL(for: identity.key)
            try fileManager.createDirectory(
                at: usesDirectory,
                withIntermediateDirectories: true
            )
            let record = VolumeUseRecord(
                appName: appName,
                instanceID: instanceID,
                processID: processID,
                volumePath: identity.path,
                detail: detail,
                createdAt: Date()
            )
            let fileURL = usesDirectory.appendingPathComponent(
                "\(instanceID.uuidString)-\(UUID().uuidString).json"
            )
            try JSONEncoder().encode(record).write(to: fileURL, options: .atomic)
            let lease = VolumeUseLease(fileURL: fileURL)
            if let owner = try liveEjectOwner(for: identity.key) {
                lease.release()
                throw VolumeCoordinationError.ejectInProgress(
                    volumeName: identity.name,
                    appName: owner.appName
                )
            }
            return lease
        } catch let error as VolumeCoordinationError {
            throw error
        } catch {
            throw VolumeCoordinationError.unavailable(error.localizedDescription)
        }
    }

    func beginEject(of volumeURL: URL) throws -> VolumeEjectLease {
        let identity = volumeIdentity(volumeURL)
        do {
            try ensureRoot()
            let lockURL = ejectURL(for: identity.key)
            let stagingURL = rootURL.appendingPathComponent(
                ".eject-staging-\(UUID().uuidString)",
                isDirectory: true
            )
            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
            let owner = VolumeUseRecord(
                appName: appName,
                instanceID: instanceID,
                processID: processID,
                volumePath: identity.path,
                detail: "Safe Eject",
                createdAt: Date()
            )
            try JSONEncoder().encode(owner).write(
                to: stagingURL.appendingPathComponent("owner.json"),
                options: .atomic
            )

            do {
                if let existing = try liveEjectOwner(for: identity.key) {
                    try? fileManager.removeItem(at: stagingURL)
                    throw VolumeCoordinationError.ejectInProgress(
                        volumeName: identity.name,
                        appName: existing.appName
                    )
                }
                try fileManager.moveItem(at: stagingURL, to: lockURL)
            } catch let error as VolumeCoordinationError {
                throw error
            } catch {
                try? fileManager.removeItem(at: stagingURL)
                if let existing = try liveEjectOwner(for: identity.key) {
                    throw VolumeCoordinationError.ejectInProgress(
                        volumeName: identity.name,
                        appName: existing.appName
                    )
                }
                throw error
            }

            let lease = VolumeEjectLease(directoryURL: lockURL)
            let blockers = try liveUses(for: identity.key).filter {
                $0.instanceID != instanceID
            }
            guard blockers.isEmpty else {
                lease.release()
                throw VolumeCoordinationError.volumeInUse(
                    volumeName: identity.name,
                    uses: blockers
                )
            }
            return lease
        } catch let error as VolumeCoordinationError {
            throw error
        } catch {
            throw VolumeCoordinationError.unavailable(error.localizedDescription)
        }
    }

    private func ensureRoot() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    private func liveEjectOwner(for key: String) throws -> VolumeUseRecord? {
        let lockURL = ejectURL(for: key)
        guard fileManager.fileExists(atPath: lockURL.path) else { return nil }
        let ownerURL = lockURL.appendingPathComponent("owner.json")
        guard let data = try? Data(contentsOf: ownerURL),
              let owner = try? JSONDecoder().decode(VolumeUseRecord.self, from: data),
              processIsAlive(owner.processID)
        else {
            try? fileManager.removeItem(at: lockURL)
            return nil
        }
        return owner
    }

    private func liveUses(for key: String) throws -> [VolumeUseRecord] {
        let directory = usesURL(for: key)
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        var live: [VolumeUseRecord] = []
        for fileURL in try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let record = try? JSONDecoder().decode(
                    VolumeUseRecord.self,
                    from: data
                  ), processIsAlive(record.processID)
            else {
                try? fileManager.removeItem(at: fileURL)
                continue
            }
            live.append(record)
        }
        return live
    }

    private func volumeIdentity(_ url: URL) -> (path: String, name: String, key: String) {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        let path = canonical.path
        return (path, canonical.lastPathComponent, Self.fnv1a64(path))
    }

    private func usesURL(for key: String) -> URL {
        rootURL.appendingPathComponent("uses", isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
    }

    private func ejectURL(for key: String) -> URL {
        rootURL.appendingPathComponent("eject-\(key).lock", isDirectory: true)
    }

    private static func liveProcess(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    private static func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }
}
