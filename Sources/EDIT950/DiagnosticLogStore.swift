import Combine
import Foundation

enum DiagnosticLogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

/// A user-readable, size-limited activity timeline that survives relaunches.
///
/// Paths below the user's home and temporary directories are shortened before
/// they reach disk. The log intentionally records operation state and metadata,
/// never IMG, P9, S9 or audio contents.
@MainActor
final class DiagnosticLogStore: ObservableObject {
    nonisolated static let defaultMaximumBytes = 1_500_000
    nonisolated static let defaultMaximumVisibleBytes = 96_000

    private(set) var text: String
    @Published private(set) var visibleText: String
    @Published private(set) var storageWarning: String?

    let appName: String
    let fileURL: URL
    let sessionID: String

    private let maximumBytes: Int
    private let now: () -> Date
    private var persistedByteCount: Int

    init(
        appName: String,
        fileURL: URL? = nil,
        maximumBytes: Int = DiagnosticLogStore.defaultMaximumBytes,
        startSession: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.appName = appName
        self.fileURL = fileURL ?? Self.defaultFileURL(for: appName)
        self.maximumBytes = max(256, maximumBytes)
        self.now = now
        sessionID = String(UUID().uuidString.prefix(8)).uppercased()

        let loaded = (try? String(contentsOf: self.fileURL, encoding: .utf8)) ?? ""
        let retained = Self.trimmed(loaded, maximumBytes: self.maximumBytes)
        text = retained
        visibleText = Self.visibleTail(retained)
        persistedByteCount = retained.utf8.count
        if retained != loaded {
            do {
                try Self.write(retained, to: self.fileURL)
            } catch {
                storageWarning = error.localizedDescription
            }
        }

        if startSession {
            record(
                .info,
                category: "lifecycle",
                message: "Session started",
                fields: Self.environmentFields(sessionID: sessionID)
            )
        }
    }

    func record(
        _ level: DiagnosticLogLevel = .info,
        category: String,
        message: String,
        fields: [String: String] = [:]
    ) {
        let timestamp = Self.timestampFormatter.string(from: now())
        let safeCategory = Self.singleLine(Self.redact(category))
        let safeMessage = Self.singleLine(Self.redact(message))
        let renderedFields = fields.keys.sorted().map { key -> String in
            let safeKey = Self.singleLine(Self.redact(key))
            let safeValue = Self.singleLine(Self.redact(fields[key] ?? ""))
            return "\(safeKey)=\"\(Self.escaped(safeValue))\""
        }
        let suffix = renderedFields.isEmpty ? "" : " · " + renderedFields.joined(separator: " ")
        let line = "\(timestamp) [\(appName)] [\(level.rawValue)] [\(safeCategory)] \(safeMessage)\(suffix)\n"
        let combined = text + line
        let retained = Self.trimmed(combined, maximumBytes: maximumBytes)
        let needsCompaction = retained != combined

        text = retained
        visibleText = Self.visibleTail(retained)
        do {
            if needsCompaction || persistedByteCount + line.utf8.count > maximumBytes {
                try Self.write(retained, to: fileURL)
                persistedByteCount = retained.utf8.count
            } else {
                try Self.append(line, to: fileURL)
                persistedByteCount += line.utf8.count
            }
            storageWarning = nil
        } catch {
            storageWarning = error.localizedDescription
        }
    }

    func clear() {
        text = ""
        visibleText = ""
        persistedByteCount = 0
        do {
            try Self.write("", to: fileURL)
            storageWarning = nil
        } catch {
            storageWarning = error.localizedDescription
        }
        record(
            .info,
            category: "diagnostics",
            message: "Log cleared by user",
            fields: ["session": sessionID]
        )
    }

    func saveCopy(to destination: URL) throws {
        try Self.write(text, to: destination)
    }

    func reloadFromDisk() {
        do {
            let loaded = try String(contentsOf: fileURL, encoding: .utf8)
            let retained = Self.trimmed(loaded, maximumBytes: maximumBytes)
            text = retained
            visibleText = Self.visibleTail(retained)
            persistedByteCount = retained.utf8.count
            storageWarning = nil
            if retained != loaded {
                try Self.write(retained, to: fileURL)
            }
        } catch {
            storageWarning = error.localizedDescription
        }
    }

    static func defaultFileURL(for appName: String) -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let filename = appName
            .replacingOccurrences(
                of: "[^A-Za-z0-9._-]",
                with: "-",
                options: .regularExpression
            )
        return base
            .appendingPathComponent("950TOOLS", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("\(filename).log", isDirectory: false)
    }

    private static func environmentFields(sessionID: String) -> [String: String] {
        let bundle = Bundle.main
        let version = bundle.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "DEV"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "DEV"
        return [
            "session": sessionID,
            "version": version,
            "build": build,
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "process": ProcessInfo.processInfo.processName,
            "timeZone": TimeZone.current.identifier
        ]
    }

    private static func redact(_ value: String) -> String {
        var result = value
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if !home.isEmpty {
            result = result.replacingOccurrences(of: home + "/", with: "~/")
            if result == home { result = "~" }
        }
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path
        if !temporary.isEmpty {
            result = result.replacingOccurrences(
                of: temporary.hasSuffix("/") ? temporary : temporary + "/",
                with: "<temporary>/"
            )
            if result == temporary { result = "<temporary>" }
        }
        result = result
            .replacingOccurrences(of: "/private/tmp/", with: "<temporary>/")
            .replacingOccurrences(of: "/tmp/", with: "<temporary>/")
        if result.count > 24_000 {
            let end = result.index(result.startIndex, offsetBy: 24_000)
            result = String(result[..<end]) + "… <truncated>"
        }
        return result
    }

    private static func singleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ↵ ")
            .replacingOccurrences(of: "\n", with: " ↵ ")
            .replacingOccurrences(of: "\r", with: " ↵ ")
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func trimmed(_ value: String, maximumBytes: Int) -> String {
        let data = Data(value.utf8)
        guard data.count > maximumBytes else { return value }
        let marker = "… Earlier diagnostic entries were removed to keep the log size limited.\n"
        let available = max(0, maximumBytes - marker.utf8.count)
        var suffix = String(decoding: data.suffix(available), as: UTF8.self)
        if let newline = suffix.firstIndex(of: "\n") {
            suffix.removeSubrange(suffix.startIndex...newline)
        }
        return marker + suffix
    }

    private static func visibleTail(_ value: String) -> String {
        let data = Data(value.utf8)
        guard data.count > defaultMaximumVisibleBytes else { return value }
        let marker = "… Showing the latest diagnostic entries. Copy or Save for the complete log.\n"
        let available = max(0, defaultMaximumVisibleBytes - marker.utf8.count)
        var suffix = String(decoding: data.suffix(available), as: UTF8.self)
        if let newline = suffix.firstIndex(of: "\n") {
            suffix.removeSubrange(suffix.startIndex...newline)
        }
        return marker + suffix
    }

    private static func ensureParentDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private static func write(_ value: String, to url: URL) throws {
        try ensureParentDirectory(for: url)
        try value.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func append(_ value: String, to url: URL) throws {
        try ensureParentDirectory(for: url)
        if !FileManager.default.fileExists(atPath: url.path) {
            try write(value, to: url)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(value.utf8))
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        formatter.timeZone = .current
        return formatter
    }()
}
