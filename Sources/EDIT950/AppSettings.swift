import AppKit
import Foundation
import UniformTypeIdentifiers

enum AkaiFileAssociation: String, CaseIterable, Hashable, Identifiable {
    case img
    case p9
    case s9

    var id: String { rawValue }
    var filenameExtension: String { rawValue.uppercased() }

    var title: String {
        switch self {
        case .img: "AKAI Disk Image"
        case .p9: "S950 Program"
        case .s9: "S950 Sample"
        }
    }

    var typeIdentifier: String {
        switch self {
        case .img: "com.local.akai-disk-image"
        case .p9: "com.local.akai-s950-program"
        case .s9: "com.local.akai-s950-sample"
        }
    }

    var contentType: UTType {
        UTType(typeIdentifier)!
    }
}

enum SAMPLETOOLSInterop {
    static let bundleIdentifier = "com.e45recordings.SAMPLETOOLS"
    static let outputSuffix = "_OUTPUT"
    static let roundTripDirectoryPrefix = "EDIT950-ROUNDTRIP-"

    @MainActor
    static func installedApplicationURL() -> URL? {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        )
    }

    static func isSAMPLETOOLSApplication(_ url: URL?) -> Bool {
        guard let url else { return false }
        return Bundle(url: url)?.bundleIdentifier == bundleIdentifier
    }

    static func roundTripDirectoryName(for identifier: UUID) -> String {
        roundTripDirectoryPrefix + identifier.uuidString
    }

    static func roundTripIdentifier(in url: URL) -> UUID? {
        let directoryName = url.deletingLastPathComponent().lastPathComponent
        guard directoryName.hasPrefix(roundTripDirectoryPrefix) else {
            return nil
        }
        return UUID(
            uuidString: String(directoryName.dropFirst(roundTripDirectoryPrefix.count))
        )
    }

    static func isExpectedReturn(
        _ candidateURL: URL,
        roundTripIdentifier: UUID
    ) -> Bool {
        guard candidateURL.pathExtension.caseInsensitiveCompare("wav")
                == .orderedSame
        else { return false }
        let candidateBase = candidateURL.deletingPathExtension()
            .lastPathComponent
        return self.roundTripIdentifier(in: candidateURL)
                == roundTripIdentifier
            && candidateBase.uppercased().hasSuffix(outputSuffix)
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let fullDiskAccessSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )!

    static func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(fullDiskAccessSettingsURL)
    }

    static let executableDefault: String = {
        let resources = Bundle.main.resourceURL
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        return resources.appendingPathComponent("akaiutil", isDirectory: false).path
    }()
    nonisolated static var applicationBundleContentType: UTType {
        .applicationBundle
    }

    @Published var executablePath: String { didSet { save() } }
    @Published var defaultMono: Bool { didSet { save() } }
    @Published var preserveSampleRate: Bool { didSet { save() } }
    @Published var compressedS900: Bool { didSet { save() } }
    @Published var backupBeforeDestructive: Bool { didSet { save() } }
    @Published var backupFolderPath: String { didSet { save() } }
    @Published var openExportDestination: Bool { didSet { save() } }
    @Published var audioEditorPath: String { didSet { save() } }
    @Published var autoOpenLogOnError: Bool { didSet { save() } }
    @Published var ejectAfterUSBCopy: Bool { didSet { save() } }
    @Published var mediaCleanupPolicy: RemovableMediaCleanupPolicy {
        didSet { save() }
    }
    @Published var detectedVersion = "Not checked"
    @Published private(set) var defaultFileAssociations: Set<AkaiFileAssociation> = []
    @Published private(set) var isUpdatingFileAssociations = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // AKAI Util is a separately launched, bundled helper. Always prefer the
        // copy signed with this application instead of a stale machine-specific
        // preference from releases that required a separately installed binary.
        executablePath = Self.executableDefault
        defaultMono = defaults.object(forKey: "defaultMono") as? Bool ?? true
        preserveSampleRate = defaults.object(forKey: "preserveSampleRate") as? Bool ?? true
        compressedS900 = defaults.object(forKey: "compressedS900") as? Bool ?? false
        backupBeforeDestructive = defaults.object(forKey: "backupBeforeDestructive") as? Bool ?? true
        backupFolderPath = defaults.string(forKey: "backupFolderPath") ?? ""
        openExportDestination = defaults.object(forKey: "openExportDestination") as? Bool ?? false
        audioEditorPath = defaults.string(forKey: "audioEditorPath") ?? ""
        autoOpenLogOnError = defaults.object(forKey: "autoOpenLogOnError") as? Bool ?? true
        ejectAfterUSBCopy = defaults.object(forKey: "ejectAfterUSBCopy") as? Bool ?? false
        if let data = defaults.data(forKey: "removableMediaCleanupPolicy"),
           let policy = try? JSONDecoder().decode(
               RemovableMediaCleanupPolicy.self,
               from: data
           ) {
            mediaCleanupPolicy = policy
        } else {
            mediaCleanupPolicy = RemovableMediaCleanupPolicy()
        }
    }

    var defaultImportOptions: ImportOptions {
        ImportOptions(
            family: .s900,
            compressedS900: compressedS900,
            convertToMono: defaultMono,
            preserveSampleRate: preserveSampleRate,
            collisionPolicy: .rename
        )
    }

    var executableURL: URL { URL(fileURLWithPath: executablePath) }
    var audioEditorURL: URL? {
        guard !audioEditorPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: audioEditorPath)
        return Self.isRunnableApplication(at: url) ? url : nil
    }
    func validateExecutable() async {
        let path = executablePath
        guard FileManager.default.isExecutableFile(atPath: path) else {
            detectedVersion = "Not executable"
            return
        }
        detectedVersion = await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["-h"]
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(decoding: data, as: UTF8.self)
                if let range = output.range(of: #"Rev\.\s+([0-9]+(?:\.[0-9]+)*)"#, options: .regularExpression) {
                    let versionText = output[range]
                        .replacingOccurrences(of: "Rev.", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    return "AKAI Util \(versionText)"
                }
                return "Executable detected"
            } catch {
                return error.localizedDescription
            }
        }.value
    }

    func chooseAudioEditor() {
        let panel = NSOpenPanel()
        panel.title = "Choose Audio Editor"
        panel.prompt = "Choose Editor"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [Self.applicationBundleContentType]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if panel.runModal() == .OK,
           let url = panel.url,
           Self.isRunnableApplication(at: url) {
            audioEditorPath = url.path
        }
    }

    func chooseBackupFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Default IMG Backup Folder"
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if !backupFolderPath.isEmpty {
            panel.directoryURL = URL(
                fileURLWithPath: backupFolderPath,
                isDirectory: true
            )
        }
        if panel.runModal() == .OK, let url = panel.url {
            storeBackupDestination(url)
        }
    }

    func clearBackupFolder() {
        backupFolderPath = ""
        defaults.removeObject(forKey: "backupFolderBookmark")
        defaults.removeObject(forKey: "backupFolderPath")
    }

    func backupDestination(for imageURL: URL) -> URL {
        if !backupFolderPath.isEmpty {
            return storedBackupDestination()
                ?? URL(
                    fileURLWithPath: backupFolderPath,
                    isDirectory: true
                )
        }
        return imageURL.deletingLastPathComponent()
    }

    nonisolated static func isRunnableApplication(at url: URL) -> Bool {
        guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
              let bundle = Bundle(url: url),
              let executableURL = bundle.executableURL
        else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: executableURL.path)
    }

    func refreshFileAssociations() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            defaultFileAssociations = []
            return
        }
        defaultFileAssociations = Set(AkaiFileAssociation.allCases.filter {
            guard let applicationURL = NSWorkspace.shared.urlForApplication(
                toOpen: $0.contentType
            ) else {
                return false
            }
            return Bundle(url: applicationURL)?.bundleIdentifier
                == bundleIdentifier
        })
    }

    func makeEDIT950Default(
        for associations: [AkaiFileAssociation]
    ) async throws {
        guard !associations.isEmpty else { return }
        isUpdatingFileAssociations = true
        defer {
            isUpdatingFileAssociations = false
            refreshFileAssociations()
        }

        let applicationURL = Bundle.main.bundleURL
        for association in associations {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                NSWorkspace.shared.setDefaultApplication(
                    at: applicationURL,
                    toOpen: association.contentType
                ) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    func restoreDefaults() {
        executablePath = Self.executableDefault
        defaultMono = true
        preserveSampleRate = true
        compressedS900 = false
        backupBeforeDestructive = true
        clearBackupFolder()
        openExportDestination = false
        audioEditorPath = ""
        autoOpenLogOnError = true
        ejectAfterUSBCopy = false
        mediaCleanupPolicy = RemovableMediaCleanupPolicy()
        defaults.removeObject(forKey: "lastExportBookmark")
        Task { await validateExecutable() }
    }

    func storeExportDestination(_ url: URL) {
        if let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(bookmark, forKey: "lastExportBookmark")
        }
        defaults.set(url.path, forKey: "lastExportPath")
    }

    func lastExportDestination() -> URL? {
        if let data = defaults.data(forKey: "lastExportBookmark") {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                if stale { storeExportDestination(url) }
                return url
            }
        }
        return defaults.string(forKey: "lastExportPath").map(URL.init(fileURLWithPath:))
    }

    private func storeBackupDestination(_ url: URL) {
        if let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(bookmark, forKey: "backupFolderBookmark")
        }
        backupFolderPath = url.path
    }

    private func storedBackupDestination() -> URL? {
        if let data = defaults.data(forKey: "backupFolderBookmark") {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                if stale { storeBackupDestination(url) }
                return url
            }
        }
        guard !backupFolderPath.isEmpty else { return nil }
        return URL(fileURLWithPath: backupFolderPath, isDirectory: true)
    }

    private func save() {
        defaults.set(executablePath, forKey: "executablePath")
        defaults.set(defaultMono, forKey: "defaultMono")
        defaults.set(preserveSampleRate, forKey: "preserveSampleRate")
        defaults.set(compressedS900, forKey: "compressedS900")
        defaults.set(backupBeforeDestructive, forKey: "backupBeforeDestructive")
        defaults.set(backupFolderPath, forKey: "backupFolderPath")
        defaults.set(openExportDestination, forKey: "openExportDestination")
        defaults.set(audioEditorPath, forKey: "audioEditorPath")
        defaults.set(autoOpenLogOnError, forKey: "autoOpenLogOnError")
        defaults.set(ejectAfterUSBCopy, forKey: "ejectAfterUSBCopy")
        if let data = try? JSONEncoder().encode(mediaCleanupPolicy) {
            defaults.set(data, forKey: "removableMediaCleanupPolicy")
        }
    }

    func setDefaultCleanupName(_ name: String, enabled: Bool) {
        var policy = mediaCleanupPolicy
        policy.setDefault(name, enabled: enabled)
        mediaCleanupPolicy = policy
    }

    func addCustomCleanupName(_ name: String) throws {
        var policy = mediaCleanupPolicy
        try policy.addCustomName(name)
        mediaCleanupPolicy = policy
    }

    func removeCustomCleanupName(_ name: String) {
        var policy = mediaCleanupPolicy
        policy.customNames.removeAll {
            $0.caseInsensitiveCompare(name) == .orderedSame
        }
        mediaCleanupPolicy = policy
    }

    func addCleanupException(_ exception: String) throws {
        var policy = mediaCleanupPolicy
        try policy.addException(exception)
        mediaCleanupPolicy = policy
    }

    func removeCleanupException(_ exception: String) {
        var policy = mediaCleanupPolicy
        policy.exceptions.removeAll {
            $0.caseInsensitiveCompare(exception) == .orderedSame
        }
        mediaCleanupPolicy = policy
    }
}
