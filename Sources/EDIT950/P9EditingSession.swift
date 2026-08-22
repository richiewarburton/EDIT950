import Foundation

enum P9MixedValue<Value: Equatable>: Equatable {
    case value(Value)
    case mixed

    var commonValue: Value? {
        if case .value(let value) = self { return value }
        return nil
    }
}

enum P9ParameterGroup: String, Codable, CaseIterable, Identifiable {
    case filter
    case envelopes
    case tuningPlayback
    case velocity
    case output
    case keyVelocityMapping

    var id: String { rawValue }

    var title: String {
        switch self {
        case .filter: return "Filter"
        case .envelopes: return "Envelopes"
        case .tuningPlayback: return "Tuning / Playback"
        case .velocity: return "Velocity"
        case .output: return "Output"
        case .keyVelocityMapping: return "Key / Velocity Mapping"
        }
    }
}

struct P9ClipboardPayload: Codable, Equatable {
    static let currentVersion = 1
    static let pasteboardType = "com.e45recordings.edit950.p9-keygroup"

    enum Kind: Codable, Equatable {
        case wholeKeygroup
        case parameterGroup(P9ParameterGroup)
    }

    let version: Int
    let kind: Kind
    let sourceProgram: String
    let record: Data

    init(kind: Kind, sourceProgram: String, record: Data) {
        version = Self.currentVersion
        self.kind = kind
        self.sourceProgram = sourceProgram
        self.record = record
    }

    func validated() throws -> P9ClipboardPayload {
        guard version == Self.currentVersion else {
            throw P9EditingError.unsupportedClipboardVersion(version)
        }
        guard record.count == P9Program.keygroupSize else {
            throw P9ProgramError.invalidKeygroupRecord(record.count)
        }
        return self
    }
}

enum P9EditingError: LocalizedError, Equatable {
    case emptySelection
    case unsupportedClipboardVersion(Int)
    case corruptRecoveryJournal
    case recoverySourceMismatch
    case sourceChangedExternally

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "Select at least one keygroup."
        case .unsupportedClipboardVersion(let version):
            return "This keygroup clipboard uses unsupported version \(version)."
        case .corruptRecoveryJournal:
            return "The recovery journal is incomplete or damaged."
        case .recoverySourceMismatch:
            return "The recovery journal belongs to a different program source."
        case .sourceChangedExternally:
            return "The source changed outside EDIT950 after this edit session opened. Reopen it before saving, or use Save As."
        }
    }
}

struct P9RecoverySnapshot: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let sourceIdentity: String
    let baselineData: Data
    let workingData: Data
    let updatedAt: Date

    init(
        sourceIdentity: String,
        baselineData: Data,
        workingData: Data,
        updatedAt: Date = Date()
    ) {
        version = Self.currentVersion
        self.sourceIdentity = sourceIdentity
        self.baselineData = baselineData
        self.workingData = workingData
        self.updatedAt = updatedAt
    }

    func validated(sourceIdentity: String, baselineData: Data) throws -> P9RecoverySnapshot {
        guard version == Self.currentVersion else {
            throw P9EditingError.corruptRecoveryJournal
        }
        guard self.sourceIdentity == sourceIdentity,
              self.baselineData == baselineData
        else { throw P9EditingError.recoverySourceMismatch }
        _ = try P9Program(data: workingData)
        return self
    }
}

enum P9RecoveryJournal {
    static func defaultDirectory() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupport
            .appendingPathComponent("EDIT950", isDirectory: true)
            .appendingPathComponent("Recovery", isDirectory: true)
    }

    static func journalURL(
        sourceIdentity: String,
        directory: URL? = nil
    ) throws -> URL {
        let directory = try directory ?? defaultDirectory()
        let key = String(format: "%016llx", stableHash(sourceIdentity))
        return directory.appendingPathComponent("\(key).p9recovery")
    }

    static func write(
        _ snapshot: P9RecoverySnapshot,
        directory: URL? = nil
    ) throws {
        let url = try journalURL(
            sourceIdentity: snapshot.sourceIdentity,
            directory: directory
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    static func read(
        sourceIdentity: String,
        baselineData: Data,
        directory: URL? = nil
    ) throws -> P9RecoverySnapshot? {
        let url = try journalURL(
            sourceIdentity: sourceIdentity,
            directory: directory
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let snapshot = try decoder.decode(
            P9RecoverySnapshot.self,
            from: Data(contentsOf: url)
        )
        return try snapshot.validated(
            sourceIdentity: sourceIdentity,
            baselineData: baselineData
        )
    }

    static func remove(
        sourceIdentity: String,
        directory: URL? = nil
    ) throws {
        let url = try journalURL(
            sourceIdentity: sourceIdentity,
            directory: directory
        )
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

enum P9SelectionValues {
    static func mixedValue<Value: Equatable>(
        in keygroups: [P9Keygroup],
        _ keyPath: KeyPath<P9Keygroup, Value>
    ) -> P9MixedValue<Value> {
        guard let first = keygroups.first?[keyPath: keyPath] else { return .mixed }
        return keygroups.dropFirst().allSatisfy { $0[keyPath: keyPath] == first }
            ? .value(first)
            : .mixed
    }
}
