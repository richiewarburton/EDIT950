import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum FocusedExportDestination: Equatable {
    case newImage(URL, FormatPreset)
    case existingImage(URL)

    var url: URL {
        switch self {
        case .newImage(let url, _), .existingImage(let url): return url
        }
    }
}

struct FocusedExportPreview: Equatable {
    let program: Tools950Interop.NativeProgram
    let dependencies: [Tools950Interop.Dependency]
    let requiredBytes: UInt64
    let requiredFileCount: Int
    let warnings: [String]
}

struct FocusedExportPresentation: Identifiable, Equatable {
    var id: UUID { request.requestID }
    let requestURL: URL
    let request: Tools950Interop.Request
    let preview: FocusedExportPreview
}

struct FocusedExportSheet: View {
    @EnvironmentObject private var model: AppModel

    enum DestinationMode: String, CaseIterable, Identifiable {
        case new = "New IMG"
        case existing = "Existing IMG"
        var id: String { rawValue }
    }

    let presentation: FocusedExportPresentation
    let onExport: (FocusedExportDestination, Bool) -> Void
    let onCancel: () -> Void

    @State private var destinationMode: DestinationMode = .new
    @State private var density: FormatPreset = .s900High
    @State private var destinationURL: URL?
    @State private var openInPLAY950: Bool

    init(
        presentation: FocusedExportPresentation,
        onExport: @escaping (FocusedExportDestination, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.onExport = onExport
        self.onCancel = onCancel
        _openInPLAY950 = State(
            initialValue: presentation.request.openInPLAY950AfterExport ?? false
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: "square.and.arrow.up.on.square")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.suiteAmber)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Export Program to IMG").font(SuiteFont.medium(15)).tracking(2.4)
                    Text("EDIT950 owns this destination and will not write until you confirm.")
                        .foregroundStyle(Color.suiteUnit)
                }
            }

            GroupBox("Exact source selection") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow { Text("IMG").foregroundStyle(Color.suiteUnit); Text(presentation.request.source.path).lineLimit(1) }
                    GridRow { Text("Volume").foregroundStyle(Color.suiteUnit); Text(presentation.preview.program.volumePath) }
                    GridRow {
                        Text("Program").foregroundStyle(Color.suiteUnit)
                        Text("#\(presentation.preview.program.directoryIndex) · \(presentation.preview.program.filename) · \(presentation.preview.program.internalName ?? "—")")
                    }
                    GridRow {
                        Text("Closure").foregroundStyle(Color.suiteUnit)
                        Text("\(presentation.preview.requiredFileCount) files · \(Int64(presentation.preview.requiredBytes).formattedByteCount)")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Authoritative S9 dependencies") {
                if presentation.preview.dependencies.isEmpty {
                    Text("No non-blank S9 layers are referenced.")
                        .foregroundStyle(Color.suiteUnit)
                } else {
                    ForEach(Array(presentation.preview.dependencies.enumerated()), id: \.offset) { _, dependency in
                        Text("#\(dependency.directoryIndex ?? 0) · \(dependency.filename) · \(dependency.internalName ?? "—")")
                    }
                }
            }

            if !presentation.preview.warnings.isEmpty {
                GroupBox("Source information updated") {
                    ForEach(presentation.preview.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "info.circle.fill")
                            .foregroundStyle(Color.suiteBlue)
                    }
                }
            }

            Picker("Destination", selection: $destinationMode) {
                ForEach(DestinationMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: destinationMode) { _, _ in destinationURL = nil }

            if destinationMode == .new {
                Picker("S950 density", selection: $density) {
                    Text("Low density · 800 KB").tag(FormatPreset.s900Low)
                    Text("High density · 1.6 MB").tag(FormatPreset.s900High)
                }
                .pickerStyle(.radioGroup)
            }

            HStack {
                Text(destinationURL?.path ?? "No destination selected")
                    .lineLimit(1)
                    .foregroundStyle(destinationURL == nil ? .secondary : .primary)
                Spacer()
                Button(destinationMode == .new ? "Choose New IMG…" : "Choose Existing IMG…") {
                    chooseDestination()
                }
            }

            if model.isAssessingFocusedDestination {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading destination capacity and collisions…")
                        .foregroundStyle(Color.suiteUnit)
                }
            } else if let assessment = model.focusedDestinationAssessment,
                      assessment.destinationPath == destinationURL?.path {
                GroupBox("Destination preflight") {
                    VStack(alignment: .leading, spacing: 5) {
                        if let available = assessment.availableBytes {
                            LabeledContent(
                                "Bytes",
                                value: "\(Int64(assessment.requiredBytes).formattedByteCount) required · \(Int64(available).formattedByteCount) free"
                            )
                        } else {
                            LabeledContent(
                                "Image capacity",
                                value: "\(Int64(assessment.requiredBytes).formattedByteCount) native input · free blocks verified after formatting"
                            )
                        }
                        if let available = assessment.availableEntries {
                            LabeledContent(
                                "Directory slots",
                                value: "\(assessment.requiredEntries) required · \(available) available"
                            )
                        } else {
                            LabeledContent(
                                "Directory slots",
                                value: "\(assessment.requiredEntries) required · new image starts empty"
                            )
                        }
                        LabeledContent(
                            "Collisions",
                            value: assessment.collisions.isEmpty
                                ? "None observed"
                                : assessment.collisions.joined(separator: ", ")
                        )
                        if assessment.isSourceAlias {
                            Label("Destination resolves to the source IMG.", systemImage: "xmark.octagon.fill")
                                .foregroundStyle(Color.suiteRed)
                        } else if assessment.destinationAlreadyExists {
                            Label("New-image mode refuses an existing path.", systemImage: "xmark.octagon.fill")
                                .foregroundStyle(Color.suiteRed)
                        }
                    }
                }
            } else if let error = model.focusedDestinationAssessmentError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(Color.suiteRed)
            }

            Label(
                "Before writing, EDIT950 rechecks SHA-256, source closure, sampler-visible collisions, free bytes, and directory slots. Existing images receive a verified mandatory backup and automatic rollback.",
                systemImage: "checkmark.shield"
            )
            .font(SuiteFont.regular(11))
            .foregroundStyle(Color.suiteUnit)

            Toggle("Open the verified result in PLAY950 after export", isOn: $openInPLAY950)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                Button("Export and Verify") {
                    guard let destinationURL else { return }
                    let destination: FocusedExportDestination = destinationMode == .new
                        ? .newImage(destinationURL, density)
                        : .existingImage(destinationURL)
                    onExport(destination, openInPLAY950)
                }
                .buttonStyle(SuitePrimaryButtonStyle(role: .neutral))
                .disabled(
                    destinationURL == nil
                        || model.isAssessingFocusedDestination
                        || model.focusedDestinationAssessmentError != nil
                        || model.focusedDestinationAssessment?.canProceed == false
                )
            }
        }
        .padding(22)
        .frame(width: 680)
        .interactiveDismissDisabled()
    }

    private func chooseDestination() {
        if destinationMode == .new {
            let panel = NSSavePanel()
            panel.title = "Create Focused S950 IMG"
            panel.prompt = "Choose"
            panel.nameFieldStringValue =
                (presentation.preview.program.filename as NSString)
                .deletingPathExtension + ".img"
            panel.allowedContentTypes = [UTType(filenameExtension: "img") ?? .data]
            if panel.runModal() == .OK, let url = panel.url {
                destinationURL = url
                model.assessFocusedDestination(
                    .newImage(url, density),
                    presentation: presentation
                )
            }
        } else {
            let panel = NSOpenPanel()
            panel.title = "Choose Existing S950 IMG"
            panel.prompt = "Choose"
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [UTType(filenameExtension: "img") ?? .data]
            if panel.runModal() == .OK, let url = panel.url {
                destinationURL = url
                model.assessFocusedDestination(
                    .existingImage(url),
                    presentation: presentation
                )
            }
        }
    }
}

struct FocusedExportOutcome: Equatable {
    let result: Tools950Interop.ExportProgramResult
}

enum FocusedExportFailurePoint: Equatable {
    case afterFirstMutation
    case afterAllImports
    case beforeVerification
}

struct FocusedExportCapacity: Equatable {
    let freeBytes: UInt64
    let maximumFileCount: Int?
    let fileCount: Int
}

struct FocusedDestinationAssessment: Equatable {
    let destinationPath: String
    let requiredBytes: UInt64
    let availableBytes: UInt64?
    let requiredEntries: Int
    let availableEntries: Int?
    let collisions: [String]
    let isSourceAlias: Bool
    let destinationAlreadyExists: Bool

    var canProceed: Bool {
        !isSourceAlias
            && !destinationAlreadyExists
            && collisions.isEmpty
            && (availableBytes.map { requiredBytes <= $0 } ?? true)
            && (availableEntries.map { requiredEntries <= $0 } ?? true)
    }
}

enum FocusedExportError: LocalizedError, Equatable {
    case sourceUnavailable(String)
    case sourceFingerprintChanged(expected: String, actual: String)
    case sourceMetadataInvalid(String)
    case volumeNotFound(String)
    case volumeAmbiguous
    case programIdentityMismatch(String)
    case dependencyMissing(String)
    case dependencyAmbiguous(String)
    case destinationInvalid(String)
    case sourceDestinationAlias
    case collision([String])
    case insufficientBytes(required: UInt64, available: UInt64)
    case insufficientDirectoryEntries(required: Int, available: Int)
    case verificationFailed(String)
    case mutationRolledBack(cause: String, restoredSHA256: String)
    case rollbackFailed(cause: String, rollback: String, backupPath: String)

    var errorCode: String {
        switch self {
        case .sourceUnavailable: return "sourceUnavailable"
        case .sourceFingerprintChanged: return "sourceFingerprintChanged"
        case .sourceMetadataInvalid: return "sourceMetadataInvalid"
        case .volumeNotFound: return "volumeNotFound"
        case .volumeAmbiguous: return "volumeAmbiguous"
        case .programIdentityMismatch: return "programIdentityMismatch"
        case .dependencyMissing: return "missingDependency"
        case .dependencyAmbiguous: return "ambiguousDependency"
        case .destinationInvalid: return "invalidDestination"
        case .sourceDestinationAlias: return "sourceDestinationAlias"
        case .collision: return "destinationCollision"
        case .insufficientBytes: return "insufficientByteCapacity"
        case .insufficientDirectoryEntries: return "insufficientDirectoryCapacity"
        case .verificationFailed: return "verificationFailed"
        case .mutationRolledBack: return "mutationFailedRolledBack"
        case .rollbackFailed: return "rollbackFailed"
        }
    }

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable(let detail):
            return "The requested source IMG is unavailable: \(detail)"
        case .sourceFingerprintChanged(let expected, let actual):
            return "The source IMG fingerprint changed. Requested \(expected); current \(actual). Refresh FIND950 before exporting."
        case .sourceMetadataInvalid(let detail):
            return "The source IMG metadata is invalid: \(detail)"
        case .volumeNotFound(let path):
            return "The exact requested volume was not found: \(path)."
        case .volumeAmbiguous:
            return "The destination must expose exactly one S950 volume for focused export."
        case .programIdentityMismatch(let detail):
            return "The requested P9 identity does not match the current source: \(detail)"
        case .dependencyMissing(let name):
            return "The current P9 references \(name), but no matching S9 exists in the exact source volume."
        case .dependencyAmbiguous(let name):
            return "The current P9 reference \(name) matches more than one S9 in the exact source volume."
        case .destinationInvalid(let detail):
            return "The focused-export destination is invalid: \(detail)"
        case .sourceDestinationAlias:
            return "The source IMG and destination resolve to the same file."
        case .collision(let names):
            return "The destination already contains sampler-visible collision(s): \(names.joined(separator: ", "))."
        case .insufficientBytes(let required, let available):
            return "The export needs \(Int64(required).formattedByteCount), but the destination has \(Int64(available).formattedByteCount) free."
        case .insufficientDirectoryEntries(let required, let available):
            return "The export needs \(required) directory entries, but only \(available) are free."
        case .verificationFailed(let detail):
            return "Focused export verification failed: \(detail)"
        case .mutationRolledBack(let cause, let restoredSHA256):
            return "Focused export failed after mutation began. EDIT950 restored the destination byte-for-byte (SHA-256 \(restoredSHA256)). Cause: \(cause)"
        case .rollbackFailed(let cause, let rollback, let backupPath):
            return "Focused export failed and automatic restoration failed. Preserve \(backupPath) and do not use the destination. Export error: \(cause) Restoration error: \(rollback)"
        }
    }
}

final class FocusedProgramExportCoordinator {
    private struct NativeArtifact {
        let identity: Tools950Interop.Dependency
        let isProgram: Bool
        let data: Data
        let stagingURL: URL

        var filename: String { identity.filename }
    }

    private struct StagedSource {
        let workspace: TemporaryWorkspace
        let sourceURL: URL
        let sourceSHA256: String
        let sourceByteSize: UInt64
        let volumePath: String
        let program: Tools950Interop.NativeProgram
        let artifacts: [NativeArtifact]
        let warnings: [String]

        var dependencies: [Tools950Interop.Dependency] {
            artifacts.filter { !$0.isProgram }.map(\.identity)
        }

        var requiredBytes: UInt64 {
            artifacts.reduce(0) {
                $0 + FocusedProgramExportCoordinator.s950AllocatedBytes(
                    UInt64($1.data.count)
                )
            }
        }
    }

    private struct StagedCollection {
        let workspace: TemporaryWorkspace
        let sourceURLs: [URL]
        let sourceSHA256s: [String]
        let artifacts: [NativeArtifact]
        let warnings: [String]

        var requiredBytes: UInt64 {
            artifacts.reduce(0) {
                $0 + FocusedProgramExportCoordinator.s950AllocatedBytes(
                    UInt64($1.data.count)
                )
            }
        }
    }

    private struct DestinationSnapshot {
        let volumePath: String
        let files: [AkaiFile]
        let freeBytes: UInt64
        let allocationBlockSize: UInt64
        let maximumFileCount: Int?
        let fileCount: Int
    }

    let executableURL: URL
    let backupDirectory: URL?
    private let controller = AkaiCommandController()
#if AKAI_TESTING
    var failureInjector: ((FocusedExportFailurePoint) throws -> Void)?
    var capacityOverride: ((FocusedExportCapacity) -> FocusedExportCapacity)?
#endif

    init(executableURL: URL, backupDirectory: URL? = nil) {
        self.executableURL = executableURL
        self.backupDirectory = backupDirectory
    }

    func preview(_ request: Tools950Interop.Request) async throws -> FocusedExportPreview {
        let staged = try await stageAuthoritativeSource(request)
        defer { staged.workspace.remove() }
        return FocusedExportPreview(
            program: staged.program,
            dependencies: staged.dependencies,
            requiredBytes: staged.requiredBytes,
            requiredFileCount: staged.artifacts.count,
            warnings: staged.warnings
        )
    }

    func previewCollection(
        _ request: Tools950Interop.CollectionRequest
    ) async throws -> CollectionExportPreview {
        let staged = try await stageAuthoritativeCollection(request)
        defer { staged.workspace.remove() }
        return CollectionExportPreview(
            requestedItemCount: request.items.count,
            sourceCount: request.sources.count,
            requiredBytes: staged.requiredBytes,
            requiredFileCount: staged.artifacts.count,
            filenames: staged.artifacts.map(\.filename),
            warnings: staged.warnings
        )
    }

    func exportCollection(
        _ request: Tools950Interop.CollectionRequest,
        finalURL: URL,
        preset: FormatPreset
    ) async throws -> CollectionExportOutcome {
        guard preset == .s900Low || preset == .s900High else {
            throw FocusedExportError.destinationInvalid(
                "Collection export supports only 800 KB or 1.6 MB S950 images."
            )
        }
        let staged = try await stageAuthoritativeCollection(request)
        defer { staged.workspace.remove() }
        return try await exportCollectionNew(
            staged,
            finalURL: finalURL,
            preset: preset
        )
    }

    func export(
        _ request: Tools950Interop.Request,
        to destination: FocusedExportDestination
    ) async throws -> FocusedExportOutcome {
        let staged = try await stageAuthoritativeSource(request)
        defer { staged.workspace.remove() }
        switch destination {
        case .newImage(let finalURL, let preset):
            guard preset == .s900Low || preset == .s900High else {
                throw FocusedExportError.destinationInvalid(
                    "Focused export supports only 800 KB or 1.6 MB S950 images."
                )
            }
            return try await exportNew(staged, finalURL: finalURL, preset: preset)
        case .existingImage(let destinationURL):
            return try await exportExisting(staged, destinationURL: destinationURL)
        }
    }

    func assess(
        preview: FocusedExportPreview,
        sourceURL: URL,
        destination: FocusedExportDestination
    ) async throws -> FocusedDestinationAssessment {
        let canonicalSource = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        switch destination {
        case .newImage(let url, _):
            let canonical = canonicalNonexistentURL(url)
            try validateDestinationURL(canonical)
            return FocusedDestinationAssessment(
                destinationPath: url.path,
                requiredBytes: preview.requiredBytes,
                availableBytes: nil,
                requiredEntries: preview.requiredFileCount,
                availableEntries: nil,
                collisions: [],
                isSourceAlias: canonical == canonicalSource,
                destinationAlreadyExists: FileManager.default.fileExists(
                    atPath: canonical.path
                )
            )
        case .existingImage(let url):
            let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
            try validateDestinationURL(canonical)
            if canonical == canonicalSource {
                return FocusedDestinationAssessment(
                    destinationPath: url.path,
                    requiredBytes: preview.requiredBytes,
                    availableBytes: nil,
                    requiredEntries: preview.requiredFileCount,
                    availableEntries: nil,
                    collisions: [],
                    isSourceAlias: true,
                    destinationAlreadyExists: false
                )
            }
            _ = try await controller.open(
                imageURL: canonical,
                executableURL: executableURL,
                readOnly: true
            )
            do {
                let snapshot = try await destinationSnapshot()
                await controller.close()
                let incoming = Set(
                    ([preview.program.filename] + preview.dependencies.map(\.filename))
                        .map(nativeFilenameKey)
                )
                let collisions = snapshot.files.map(\.name).filter {
                    incoming.contains(nativeFilenameKey($0))
                }
                return FocusedDestinationAssessment(
                    destinationPath: url.path,
                    requiredBytes: preview.requiredBytes,
                    availableBytes: snapshot.freeBytes,
                    requiredEntries: preview.requiredFileCount,
                    availableEntries: snapshot.maximumFileCount.map {
                        max(0, $0 - snapshot.fileCount)
                    },
                    collisions: collisions,
                    isSourceAlias: false,
                    destinationAlreadyExists: false
                )
            } catch {
                await controller.close()
                throw error
            }
        }
    }

    private func stageAuthoritativeSource(
        _ request: Tools950Interop.Request
    ) async throws -> StagedSource {
        guard request.messageType == .exportProgramRequest else {
            throw FocusedExportError.sourceMetadataInvalid("The request is not a focused export.")
        }
        let sourceURL = request.source.url.resolvingSymlinksInPath()
        let values: URLResourceValues
        do {
            values = try sourceURL.resourceValues(forKeys: [
                .isRegularFileKey, .fileSizeKey, .contentModificationDateKey
            ])
        } catch {
            throw FocusedExportError.sourceUnavailable(error.localizedDescription)
        }
        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0
        else {
            throw FocusedExportError.sourceUnavailable("It is not a non-empty regular file.")
        }
        let sourceByteSize = UInt64(fileSize)
        guard sourceByteSize <= Tools950Interop.maximumSourceBytes else {
            throw FocusedExportError.sourceMetadataInvalid("The source exceeds protocol-v1 size bounds.")
        }
        let sourceSHA256 = try ImageFileOperations.sha256Hex(of: sourceURL)
        guard sourceSHA256 == request.source.sha256 else {
            throw FocusedExportError.sourceFingerprintChanged(
                expected: request.source.sha256,
                actual: sourceSHA256
            )
        }
        var warnings: [String] = []
        if let expectedSize = request.source.byteSize, expectedSize != sourceByteSize {
            warnings.append(
                "FIND950 observed \(expectedSize) source bytes; EDIT950 observed \(sourceByteSize). The complete SHA-256 still matched."
            )
        }
        if let expectedDate = request.source.modifiedAt,
           let actualDate = values.contentModificationDate,
           abs(expectedDate.timeIntervalSince(actualDate)) > 1 {
            warnings.append(
                "The source modification time differs from FIND950's observation; the complete SHA-256 still matched."
            )
        }

        let workspace = try TemporaryWorkspace(prefix: "akai-focused-export")
        do {
            _ = try await controller.open(
                imageURL: sourceURL,
                executableURL: executableURL,
                readOnly: true
            )
            let recursive = try await controller.send("dirrec")
            let volumes = AkaiOutputParser.parseVolumes(recursive.output)
            guard volumes.contains(where: { $0.path == request.program.volumePath }) else {
                throw FocusedExportError.volumeNotFound(request.program.volumePath)
            }
            _ = try await controller.send(
                try AkaiCommandBuilder.changeDirectory(request.program.volumePath)
            )
            let directory = try await controller.send("dir")
            let files = AkaiOutputParser.parseDirectory(directory.output).0
            let atIndex = files.filter { $0.index == request.program.directoryIndex }
            guard atIndex.count == 1, let requestedFile = atIndex.first else {
                throw FocusedExportError.programIdentityMismatch(
                    "directory index \(request.program.directoryIndex) is missing or ambiguous"
                )
            }
            guard (requestedFile.name as NSString).pathExtension.uppercased() == "P9",
                  nativeFilenameKey(requestedFile.name) == nativeFilenameKey(request.program.filename)
            else {
                throw FocusedExportError.programIdentityMismatch(
                    "index \(request.program.directoryIndex) is \(requestedFile.name), not \(request.program.filename)"
                )
            }

            let programData = try await exportNativeData(
                requestedFile,
                workspace: workspace,
                sequence: 0
            )
            let nativeProgram = try P9Program(data: programData)
            if let expectedInternal = request.program.internalName,
               nativeNameKey(expectedInternal) != nativeNameKey(nativeProgram.name) {
                throw FocusedExportError.programIdentityMismatch(
                    "internal name is \(nativeProgram.name), not \(expectedInternal)"
                )
            }
            let resolvedProgram = Tools950Interop.NativeProgram(
                volumePath: request.program.volumePath,
                directoryIndex: requestedFile.index,
                filename: requestedFile.name,
                internalName: nativeProgram.name
            )
            let programStagingURL = workspace.url.appendingPathComponent(
                stagingFilename(requestedFile.name)
            )
            try programData.write(to: programStagingURL, options: .atomic)

            let indexes = Set(nativeProgram.keygroups.indices)
            let referencedNames = try nativeProgram.sampleNames(at: indexes).filter {
                let key = nativeNameKey($0)
                return !key.isEmpty && key != "2 SAMPLE"
            }
            var authoritativeSamples: [(AkaiFile, Data, String)] = []
            var seen = Set<String>()
            for name in referencedNames {
                let key = nativeNameKey(name)
                guard seen.insert(key).inserted else { continue }
                let matches = files.filter {
                    $0.isSample
                        && nativeNameKey(($0.name as NSString).deletingPathExtension) == key
                }
                guard !matches.isEmpty else { throw FocusedExportError.dependencyMissing(name) }
                guard matches.count == 1, let sample = matches.first else {
                    throw FocusedExportError.dependencyAmbiguous(name)
                }
                let data = try await exportNativeData(
                    sample,
                    workspace: workspace,
                    sequence: authoritativeSamples.count + 1
                )
                let internalName = try S9NativeSample.internalName(in: data)
                authoritativeSamples.append((sample, data, internalName))
            }

            var artifacts: [NativeArtifact] = authoritativeSamples.map { sample, data, internalName in
                let stagingURL = workspace.url.appendingPathComponent(stagingFilename(sample.name))
                return NativeArtifact(
                    identity: .init(
                        directoryIndex: sample.index,
                        filename: sample.name,
                        internalName: internalName
                    ),
                    isProgram: false,
                    data: data,
                    stagingURL: stagingURL
                )
            }
            for artifact in artifacts {
                try artifact.data.write(to: artifact.stagingURL, options: .atomic)
            }
            artifacts.append(
                NativeArtifact(
                    identity: .init(
                        directoryIndex: requestedFile.index,
                        filename: requestedFile.name,
                        internalName: nativeProgram.name
                    ),
                    isProgram: true,
                    data: programData,
                    stagingURL: programStagingURL
                )
            )
            guard artifacts.count <= Tools950Interop.maximumDependencyCount + 1 else {
                throw FocusedExportError.sourceMetadataInvalid("The authoritative closure is too large.")
            }

            let observed = request.observedDependencies ?? []
            let authoritative = artifacts.filter { !$0.isProgram }.map(\.identity)
            if !observedDependenciesMatch(
                observed,
                authoritative: authoritative
            ) {
                let count = authoritative.count
                warnings.append(
                    "FIND950’s saved sample list was out of date. EDIT950 re-read \(resolvedProgram.filename) and will use its current \(count) linked sample\(count == 1 ? "" : "s")."
                )
            }
            await controller.close()
            guard try ImageFileOperations.sha256Hex(of: sourceURL) == sourceSHA256 else {
                throw FocusedExportError.verificationFailed(
                    "The source fingerprint changed during read-only staging."
                )
            }
            return StagedSource(
                workspace: workspace,
                sourceURL: sourceURL,
                sourceSHA256: sourceSHA256,
                sourceByteSize: sourceByteSize,
                volumePath: request.program.volumePath,
                program: resolvedProgram,
                artifacts: artifacts,
                warnings: warnings
            )
        } catch {
            await controller.close()
            workspace.remove()
            throw error
        }
    }

    private func stageAuthoritativeCollection(
        _ request: Tools950Interop.CollectionRequest
    ) async throws -> StagedCollection {
        guard request.messageType == .exportCollectionRequest else {
            throw FocusedExportError.sourceMetadataInvalid(
                "The request is not a collection export."
            )
        }
        let workspace = try TemporaryWorkspace(prefix: "akai-collection-export")
        var artifactsByName: [String: NativeArtifact] = [:]
        var artifactOrigins: [String: String] = [:]
        var warnings: [String] = []
        var sourceURLs: [URL] = []
        var sourceSHA256s: [String] = []

        do {
            for (sourceIndex, source) in request.sources.enumerated() {
                try Task.checkCancellation()
                let sourceURL = source.url.resolvingSymlinksInPath()
                let values: URLResourceValues
                do {
                    values = try sourceURL.resourceValues(forKeys: [
                        .isRegularFileKey, .fileSizeKey, .contentModificationDateKey
                    ])
                } catch {
                    throw FocusedExportError.sourceUnavailable(error.localizedDescription)
                }
                guard values.isRegularFile == true,
                      let fileSize = values.fileSize,
                      fileSize > 0
                else {
                    throw FocusedExportError.sourceUnavailable(
                        "\(source.path) is not a non-empty regular file."
                    )
                }
                let observedHash = try ImageFileOperations.sha256Hex(of: sourceURL)
                guard observedHash == source.sha256 else {
                    throw FocusedExportError.sourceFingerprintChanged(
                        expected: source.sha256,
                        actual: observedHash
                    )
                }
                if let expectedSize = source.byteSize,
                   expectedSize != UInt64(fileSize) {
                    warnings.append(
                        "FIND950 observed \(expectedSize) bytes for \(sourceURL.lastPathComponent); EDIT950 observed \(fileSize). The complete SHA-256 still matched."
                    )
                }
                sourceURLs.append(sourceURL)
                sourceSHA256s.append(observedHash)

                _ = try await controller.open(
                    imageURL: sourceURL,
                    executableURL: executableURL,
                    readOnly: true
                )
                let recursive = try await controller.send("dirrec")
                let availableVolumes = Set(
                    AkaiOutputParser.parseVolumes(recursive.output).map(\.path)
                )
                let sourceItems = request.items.filter {
                    $0.sourceIndex == sourceIndex
                }
                let grouped = Dictionary(grouping: sourceItems, by: \.volumePath)
                for volumePath in grouped.keys.sorted() {
                    guard availableVolumes.contains(volumePath) else {
                        throw FocusedExportError.volumeNotFound(volumePath)
                    }
                    _ = try await controller.send(
                        try AkaiCommandBuilder.changeDirectory(volumePath)
                    )
                    let directory = try await controller.send("dir")
                    let files = AkaiOutputParser.parseDirectory(directory.output).0
                    for item in (grouped[volumePath] ?? []).sorted(by: {
                        $0.directoryIndex < $1.directoryIndex
                    }) {
                        let matches = files.filter { $0.index == item.directoryIndex }
                        guard matches.count == 1, let file = matches.first,
                              nativeFilenameKey(file.name) == nativeFilenameKey(item.filename),
                              (file.name as NSString).pathExtension.uppercased()
                                == (item.kind == "program" ? "P9" : "S9")
                        else {
                            throw FocusedExportError.programIdentityMismatch(
                                "\(sourceURL.lastPathComponent) \(volumePath) index \(item.directoryIndex) no longer resolves exactly to \(item.filename)"
                            )
                        }

                        if item.kind == "sample" {
                            let data = try await exportNativeData(
                                file,
                                workspace: workspace,
                                sequence: artifactsByName.count
                            )
                            let internalName = try S9NativeSample.internalName(in: data)
                            try mergeCollectionArtifact(
                                file: file,
                                data: data,
                                internalName: internalName,
                                isProgram: false,
                                origin: "\(sourceURL.lastPathComponent) \(volumePath)",
                                workspace: workspace,
                                artifactsByName: &artifactsByName,
                                artifactOrigins: &artifactOrigins,
                                warnings: &warnings
                            )
                            continue
                        }

                        let programData = try await exportNativeData(
                            file,
                            workspace: workspace,
                            sequence: artifactsByName.count
                        )
                        let program = try P9Program(data: programData)
                        try mergeCollectionArtifact(
                            file: file,
                            data: programData,
                            internalName: program.name,
                            isProgram: true,
                            origin: "\(sourceURL.lastPathComponent) \(volumePath)",
                            workspace: workspace,
                            artifactsByName: &artifactsByName,
                            artifactOrigins: &artifactOrigins,
                            warnings: &warnings
                        )
                    }
                }
                await controller.close()
                guard try ImageFileOperations.sha256Hex(of: sourceURL) == observedHash else {
                    throw FocusedExportError.verificationFailed(
                        "The source fingerprint changed during read-only collection staging: \(sourceURL.path)."
                    )
                }
            }
            let artifacts = artifactsByName.values.sorted { left, right in
                if left.isProgram != right.isProgram { return !left.isProgram }
                return left.filename.localizedStandardCompare(right.filename)
                    == .orderedAscending
            }
            guard !artifacts.isEmpty, artifacts.count <= 64 else {
                throw FocusedExportError.insufficientDirectoryEntries(
                    required: artifacts.count,
                    available: 64
                )
            }
            return StagedCollection(
                workspace: workspace,
                sourceURLs: sourceURLs,
                sourceSHA256s: sourceSHA256s,
                artifacts: artifacts,
                warnings: Array(Set(warnings)).sorted()
            )
        } catch {
            await controller.close()
            workspace.remove()
            throw error
        }
    }

    private func mergeCollectionArtifact(
        file: AkaiFile,
        data: Data,
        internalName: String,
        isProgram: Bool,
        origin: String,
        workspace: TemporaryWorkspace,
        artifactsByName: inout [String: NativeArtifact],
        artifactOrigins: inout [String: String],
        warnings: inout [String]
    ) throws {
        let key = nativeFilenameKey(file.name)
        if let existing = artifactsByName[key] {
            guard existing.data == data else {
                throw FocusedExportError.collision([file.name])
            }
            let firstOrigin = artifactOrigins[key] ?? "another source"
            warnings.append(
                "\(file.name) appeared in \(firstOrigin) and \(origin); the native bytes were identical, so one copy will be written."
            )
            return
        }
        let stagingURL = workspace.url.appendingPathComponent(stagingFilename(file.name))
        try data.write(to: stagingURL, options: .atomic)
        artifactsByName[key] = NativeArtifact(
            identity: .init(
                directoryIndex: file.index,
                filename: file.name,
                internalName: internalName
            ),
            isProgram: isProgram,
            data: data,
            stagingURL: stagingURL
        )
        artifactOrigins[key] = origin
    }

    private func exportCollectionNew(
        _ source: StagedCollection,
        finalURL: URL,
        preset: FormatPreset
    ) async throws -> CollectionExportOutcome {
        let canonicalFinal = canonicalNonexistentURL(finalURL)
        try validateDestinationURL(canonicalFinal)
        guard !FileManager.default.fileExists(atPath: canonicalFinal.path) else {
            throw FocusedExportError.destinationInvalid(
                "A new-image destination already exists."
            )
        }
        guard !source.sourceURLs.contains(where: { $0 == canonicalFinal }) else {
            throw FocusedExportError.sourceDestinationAlias
        }
        let stageURL = canonicalFinal.deletingLastPathComponent().appendingPathComponent(
            ".\(canonicalFinal.lastPathComponent).akai-collection-\(UUID().uuidString).img"
        )
        defer { try? FileManager.default.removeItem(at: stageURL) }

        do {
            try ImageFileOperations.createZeroFilledImage(
                at: stageURL,
                byteCount: preset.byteCount
            )
            _ = try await controller.open(
                imageURL: stageURL,
                executableURL: executableURL,
                readOnly: false
            )
            _ = try await controller.send(preset.command)
            let before = try await destinationSnapshot()
            try preflight(source.artifacts, snapshot: before)
            try await importAndVerify(
                source.artifacts,
                destinationURL: stageURL,
                before: before,
                requireNoUnrelatedContent: true
            )
            await controller.close()
            for (index, sourceURL) in source.sourceURLs.enumerated() {
                let actual = try ImageFileOperations.sha256Hex(of: sourceURL)
                guard actual == source.sourceSHA256s[index] else {
                    throw FocusedExportError.verificationFailed(
                        "A source IMG changed during collection export: \(sourceURL.path)."
                    )
                }
            }
            guard !FileManager.default.fileExists(atPath: canonicalFinal.path) else {
                throw FocusedExportError.destinationInvalid(
                    "The final destination appeared while EDIT950 was staging the image."
                )
            }
            try FileManager.default.moveItem(at: stageURL, to: canonicalFinal)
            let destinationHash = try ImageFileOperations.sha256Hex(of: canonicalFinal)
            let destinationBytes = try ImageFileOperations.byteSize(of: canonicalFinal)
            return CollectionExportOutcome(
                resultingImage: .init(
                    path: canonicalFinal.path,
                    sha256: destinationHash,
                    byteSize: destinationBytes,
                    modifiedAt: try? canonicalFinal.resourceValues(
                        forKeys: [.contentModificationDateKey]
                    ).contentModificationDate
                ),
                resolvedVolumePath: before.volumePath,
                importedFileCount: source.artifacts.count,
                sourceSHA256s: source.sourceSHA256s,
                warnings: source.warnings
            )
        } catch {
            await controller.close()
            throw error
        }
    }

    private func exportNew(
        _ source: StagedSource,
        finalURL: URL,
        preset: FormatPreset
    ) async throws -> FocusedExportOutcome {
        let canonicalFinal = canonicalNonexistentURL(finalURL)
        try validateDestinationURL(canonicalFinal)
        guard !FileManager.default.fileExists(atPath: canonicalFinal.path) else {
            throw FocusedExportError.destinationInvalid("A new-image destination already exists.")
        }
        guard canonicalFinal != source.sourceURL else {
            throw FocusedExportError.sourceDestinationAlias
        }
        let stageURL = canonicalFinal.deletingLastPathComponent().appendingPathComponent(
            ".\(canonicalFinal.lastPathComponent).akai-focused-\(UUID().uuidString).img"
        )
        defer { try? FileManager.default.removeItem(at: stageURL) }
        do {
            try ImageFileOperations.createZeroFilledImage(at: stageURL, byteCount: preset.byteCount)
            _ = try await controller.open(
                imageURL: stageURL,
                executableURL: executableURL,
                readOnly: false
            )
            _ = try await controller.send(preset.command)
            let before = try await destinationSnapshot()
            try preflight(source.artifacts, snapshot: before)
            try await importAndVerify(
                source.artifacts,
                destinationURL: stageURL,
                before: before,
                requireNoUnrelatedContent: true
            )
            await controller.close()
            guard !FileManager.default.fileExists(atPath: canonicalFinal.path) else {
                throw FocusedExportError.destinationInvalid(
                    "The final destination appeared while EDIT950 was staging the image."
                )
            }
            try FileManager.default.moveItem(at: stageURL, to: canonicalFinal)
            let outcome = try outcome(
                source: source,
                destinationURL: canonicalFinal,
                destinationVolumePath: before.volumePath,
                backupURL: nil,
                backupVerified: false
            )
            return FocusedExportOutcome(result: outcome)
        } catch {
            await controller.close()
            throw error
        }
    }

    private func exportExisting(
        _ source: StagedSource,
        destinationURL: URL
    ) async throws -> FocusedExportOutcome {
        let canonicalDestination = destinationURL.standardizedFileURL.resolvingSymlinksInPath()
        try validateDestinationURL(canonicalDestination)
        guard canonicalDestination != source.sourceURL else {
            throw FocusedExportError.sourceDestinationAlias
        }
        let values = try? canonicalDestination.resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true else {
            throw FocusedExportError.destinationInvalid("The existing destination is not a regular file.")
        }

        let preOperationSHA256 = try ImageFileOperations.sha256Hex(of: canonicalDestination)
        _ = try await controller.open(
            imageURL: canonicalDestination,
            executableURL: executableURL,
            readOnly: true
        )
        let readOnlySnapshot: DestinationSnapshot
        do {
            readOnlySnapshot = try await destinationSnapshot()
            try preflight(source.artifacts, snapshot: readOnlySnapshot)
            await controller.close()
        } catch {
            await controller.close()
            throw error
        }

        let backupURL = try ImageFileOperations.timestampedBackup(
            of: canonicalDestination,
            destinationDirectory: backupDirectory
        )
        guard try ImageFileOperations.sha256Hex(of: backupURL) == preOperationSHA256 else {
            throw FocusedExportError.verificationFailed("The mandatory backup hash does not match the destination's pre-operation hash.")
        }

        var mutationStarted = false
        do {
            guard try ImageFileOperations.sha256Hex(of: canonicalDestination) == preOperationSHA256 else {
                throw FocusedExportError.destinationInvalid(
                    "The existing destination changed after preflight and before mutation."
                )
            }
            _ = try await controller.open(
                imageURL: canonicalDestination,
                executableURL: executableURL,
                readOnly: false
            )
            let current = try await destinationSnapshot()
            try preflight(source.artifacts, snapshot: current)
            mutationStarted = true
            try await importAndVerify(
                source.artifacts,
                destinationURL: canonicalDestination,
                before: current,
                requireNoUnrelatedContent: false
            )
            await controller.close()
            let result = try outcome(
                source: source,
                destinationURL: canonicalDestination,
                destinationVolumePath: current.volumePath,
                backupURL: backupURL,
                backupVerified: true
            )
            return FocusedExportOutcome(result: result)
        } catch {
            await controller.close()
            guard mutationStarted else { throw error }
            let cause = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            do {
                try ImageFileOperations.copyAtomicallyAndVerify(
                    source: backupURL,
                    destination: canonicalDestination
                )
                let restored = try ImageFileOperations.sha256Hex(of: canonicalDestination)
                guard restored == preOperationSHA256 else {
                    throw FocusedExportError.verificationFailed(
                        "The restored destination hash \(restored) differs from \(preOperationSHA256)."
                    )
                }
                throw FocusedExportError.mutationRolledBack(
                    cause: cause,
                    restoredSHA256: restored
                )
            } catch let rollback as FocusedExportError {
                if case .mutationRolledBack = rollback { throw rollback }
                throw FocusedExportError.rollbackFailed(
                    cause: cause,
                    rollback: rollback.localizedDescription,
                    backupPath: backupURL.path
                )
            } catch {
                throw FocusedExportError.rollbackFailed(
                    cause: cause,
                    rollback: error.localizedDescription,
                    backupPath: backupURL.path
                )
            }
        }
    }

    private func destinationSnapshot() async throws -> DestinationSnapshot {
        let recursive = try await controller.send("dirrec")
        let volumes = AkaiOutputParser.parseVolumes(recursive.output)
        guard volumes.count == 1, let volume = volumes.first else {
            throw FocusedExportError.volumeAmbiguous
        }
        _ = try await controller.send(try AkaiCommandBuilder.changeDirectory(volume.path))
        let directory = try await controller.send("dir")
        let parsed = AkaiOutputParser.parseDirectory(directory.output)
        let df = try await controller.send("df")
        let disks = AkaiOutputParser.parseDF(df.output).0
        let free = disks.reduce(Int64(0)) {
            $0 + $1.freeBytes
        }
        let blockSize = UInt64(max(1, disks.map(\.blockSize).max() ?? 1))
        var capacity = FocusedExportCapacity(
            freeBytes: UInt64(max(0, free)),
            maximumFileCount: parsed.1,
            fileCount: max(parsed.2, parsed.0.count)
        )
#if AKAI_TESTING
        capacity = capacityOverride?(capacity) ?? capacity
#endif
        return DestinationSnapshot(
            volumePath: volume.path,
            files: parsed.0,
            freeBytes: capacity.freeBytes,
            allocationBlockSize: blockSize,
            maximumFileCount: capacity.maximumFileCount,
            fileCount: capacity.fileCount
        )
    }

    private func preflight(
        _ artifacts: [NativeArtifact],
        snapshot: DestinationSnapshot
    ) throws {
        let existing = Set(snapshot.files.map { nativeFilenameKey($0.name) })
        let collisions = artifacts.map(\.filename).filter {
            existing.contains(nativeFilenameKey($0))
        }
        guard collisions.isEmpty else { throw FocusedExportError.collision(collisions) }
        if let maximum = snapshot.maximumFileCount {
            let available = max(0, maximum - snapshot.fileCount)
            guard artifacts.count <= available else {
                throw FocusedExportError.insufficientDirectoryEntries(
                    required: artifacts.count,
                    available: available
                )
            }
        }
        let requiredBytes = artifacts.reduce(UInt64(0)) { total, artifact in
            let size = UInt64(artifact.data.count)
            let blocks = (size + snapshot.allocationBlockSize - 1)
                / snapshot.allocationBlockSize
            return total + blocks * snapshot.allocationBlockSize
        }
        guard requiredBytes <= snapshot.freeBytes else {
            throw FocusedExportError.insufficientBytes(
                required: requiredBytes,
                available: snapshot.freeBytes
            )
        }
    }

    private func importAndVerify(
        _ artifacts: [NativeArtifact],
        destinationURL: URL,
        before: DestinationSnapshot,
        requireNoUnrelatedContent: Bool
    ) async throws {
        _ = try await controller.send(
            try AkaiCommandBuilder.localDirectory(artifacts[0].stagingURL.deletingLastPathComponent().path)
        )
        for (index, artifact) in artifacts.enumerated() {
            try Task.checkCancellation()
            _ = try await controller.send(
                try AkaiCommandBuilder.importNative(filename: artifact.stagingURL.lastPathComponent)
            )
            try ImageFileOperations.updateModificationDate(of: destinationURL)
#if AKAI_TESTING
            if index == 0 { try failureInjector?(.afterFirstMutation) }
#endif
        }
#if AKAI_TESTING
        try failureInjector?(.afterAllImports)
#endif
        try Task.checkCancellation()
        let after = try await destinationSnapshot()
        let expectedKeys = Set(artifacts.map { nativeFilenameKey($0.filename) })
        let afterKeys = Set(after.files.map { nativeFilenameKey($0.name) })
        let missing = expectedKeys.subtracting(afterKeys)
        guard missing.isEmpty else {
            throw FocusedExportError.verificationFailed(
                "Missing native entries after import: \(missing.sorted().joined(separator: ", "))."
            )
        }
        if requireNoUnrelatedContent {
            guard after.files.count == artifacts.count, afterKeys == expectedKeys else {
                throw FocusedExportError.verificationFailed(
                    "A new focused IMG contains unrelated native content."
                )
            }
        } else {
            let beforeKeys = Set(before.files.map { nativeFilenameKey($0.name) })
            guard after.files.count == before.files.count + artifacts.count,
                  afterKeys == beforeKeys.union(expectedKeys)
            else {
                throw FocusedExportError.verificationFailed(
                    "The existing destination directory changed beyond the requested additions."
                )
            }
        }
#if AKAI_TESTING
        try failureInjector?(.beforeVerification)
#endif
        for (sequence, artifact) in artifacts.enumerated() {
            guard let stored = after.files.first(where: {
                nativeFilenameKey($0.name) == nativeFilenameKey(artifact.filename)
            }) else {
                throw FocusedExportError.verificationFailed(
                    "Could not resolve \(artifact.filename) for byte verification."
                )
            }
            let verificationWorkspace = try TemporaryWorkspace(
                prefix: "akai-focused-verify"
            )
            defer { verificationWorkspace.remove() }
            let exported = try await exportNativeData(
                stored,
                workspace: verificationWorkspace,
                sequence: sequence
            )
            guard exported == artifact.data else {
                throw FocusedExportError.verificationFailed(
                    "The native bytes re-exported for \(artifact.filename) differ from the staged source bytes."
                )
            }
        }
        try Task.checkCancellation()
    }

    private func exportNativeData(
        _ file: AkaiFile,
        workspace: TemporaryWorkspace,
        sequence: Int
    ) async throws -> Data {
        let folder = workspace.url.appendingPathComponent("read-\(sequence)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try await controller.send(try AkaiCommandBuilder.localDirectory(folder.path))
        _ = try await controller.send(try AkaiCommandBuilder.exportNative(index: file.index))
        let exports = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { ["S9", "P9"].contains($0.pathExtension.uppercased()) }
        guard exports.count == 1, let exported = exports.first else {
            throw FocusedExportError.verificationFailed(
                "AKAI Util did not export exactly one native file for \(file.name)."
            )
        }
        return try Data(contentsOf: exported)
    }

    private func outcome(
        source: StagedSource,
        destinationURL: URL,
        destinationVolumePath: String,
        backupURL: URL?,
        backupVerified: Bool
    ) throws -> Tools950Interop.ExportProgramResult {
        let sourceAfter = try ImageFileOperations.sha256Hex(of: source.sourceURL)
        guard sourceAfter == source.sourceSHA256 else {
            throw FocusedExportError.verificationFailed(
                "The source IMG changed during focused export."
            )
        }
        let destinationHash = try ImageFileOperations.sha256Hex(of: destinationURL)
        let destinationBytes = try ImageFileOperations.byteSize(of: destinationURL)
        return Tools950Interop.ExportProgramResult(
            resultingImage: .init(
                path: destinationURL.path,
                sha256: destinationHash,
                byteSize: destinationBytes,
                modifiedAt: try? destinationURL.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
            ),
            resolvedVolumePath: destinationVolumePath,
            program: source.program,
            dependencies: source.dependencies,
            backupPath: backupURL?.path,
            verification: .init(
                sourceSHA256: source.sourceSHA256,
                destinationSHA256: destinationHash,
                sourceUnchanged: true,
                exactDirectoryVerified: true,
                nativeBytesVerified: true,
                backupVerified: backupVerified,
                rollbackPerformed: false,
                sourceByteSize: source.sourceByteSize,
                destinationByteSize: destinationBytes,
                importedFileCount: source.artifacts.count
            ),
            warnings: source.warnings
        )
    }

    private func validateDestinationURL(_ url: URL) throws {
        guard url.path.hasPrefix("/"),
              url.path.count <= Tools950Interop.maximumPathLength,
              url.pathExtension.caseInsensitiveCompare("img") == .orderedSame,
              url.path != "/"
        else {
            throw FocusedExportError.destinationInvalid(
                "Choose a bounded absolute path with an .img extension."
            )
        }
    }

    private static func s950AllocatedBytes(_ size: UInt64) -> UInt64 {
        let blockSize: UInt64 = 1_024
        return ((size + blockSize - 1) / blockSize) * blockSize
    }

    private func canonicalNonexistentURL(_ url: URL) -> URL {
        url.standardizedFileURL.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent)
    }

    private func stagingFilename(_ nativeFilename: String) -> String {
        nativeFilename.replacingOccurrences(of: " ", with: "_")
    }

    private func nativeFilenameKey(_ filename: String) -> String {
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension.uppercased()
        return "\(nativeNameKey(stem)).\(ext)"
    }

    private func nativeNameKey(_ name: String) -> String {
        name.uppercased()
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func observedDependenciesMatch(
        _ observed: [Tools950Interop.Dependency],
        authoritative: [Tools950Interop.Dependency]
    ) -> Bool {
        guard observed.count == authoritative.count else { return false }
        var remaining = authoritative
        for dependency in observed {
            guard let index = remaining.firstIndex(where: { current in
                if let expectedIndex = dependency.directoryIndex,
                   current.directoryIndex != expectedIndex {
                    return false
                }
                guard nativeFilenameKey(current.filename)
                    == nativeFilenameKey(dependency.filename)
                else { return false }
                if let expectedInternalName = dependency.internalName {
                    return nativeNameKey(current.internalName ?? "")
                        == nativeNameKey(expectedInternalName)
                }
                return true
            }) else { return false }
            remaining.remove(at: index)
        }
        return remaining.isEmpty
    }
}
