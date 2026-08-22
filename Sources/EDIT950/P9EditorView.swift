import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct P9KeygroupDropTarget: Equatable {
    let index: Int
    let insertAfter: Bool
}

private struct P9KeygroupDropDelegate: DropDelegate {
    let targetIndex: Int
    let reorderingDisabled: Bool
    @Binding var draggedOffsets: IndexSet
    @Binding var dropTarget: P9KeygroupDropTarget?
    let move: (IndexSet, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        !reorderingDisabled
            && !draggedOffsets.isEmpty
            && info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        updateTarget(for: info)
    }

    func dropExited(info: DropInfo) {
        if dropTarget?.index == targetIndex {
            dropTarget = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return nil }
        updateTarget(for: info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else { return false }
        let insertAfter = info.location.y >= 17
        let destination = targetIndex + (insertAfter ? 1 : 0)
        let offsets = draggedOffsets
        draggedOffsets = []
        dropTarget = nil
        move(offsets, destination)
        return true
    }

    private func updateTarget(for info: DropInfo) {
        guard validateDrop(info: info) else { return }
        dropTarget = P9KeygroupDropTarget(
            index: targetIndex,
            insertAfter: info.location.y >= 17
        )
    }
}

@MainActor
final class P9EditorDocument: ObservableObject, Identifiable {
    enum Source {
        case local(URL)
        case image(filename: String, imageURL: URL, volumePath: String)
        case newImageProgram(
            filename: String,
            imageURL: URL,
            volumePath: String
        )

        var filename: String {
            switch self {
            case .local(let url): return url.lastPathComponent
            case .image(let filename, _, _),
                 .newImageProgram(let filename, _, _):
                return filename
            }
        }

        var imageURL: URL? {
            switch self {
            case .local: return nil
            case .image(_, let imageURL, _),
                 .newImageProgram(_, let imageURL, _):
                return imageURL
            }
        }

        var volumePath: String? {
            switch self {
            case .image(_, _, let volumePath),
                 .newImageProgram(_, _, let volumePath):
                return volumePath
            case .local:
                return nil
            }
        }

        var isExistingImageProgram: Bool {
            if case .image = self { return true }
            return false
        }

        var isNewImageProgram: Bool {
            if case .newImageProgram = self { return true }
            return false
        }

        var detail: String {
            switch self {
            case .local(let url):
                return url.deletingLastPathComponent().path
            case .image(_, let imageURL, _):
                return "From \(imageURL.lastPathComponent); edits remain in memory until saved or overwritten"
            case .newImageProgram(_, let imageURL, _):
                return "New program for \(imageURL.lastPathComponent); create it in the IMG when ready"
            }
        }

        var recoveryIdentity: String {
            switch self {
            case .local(let url):
                return "local|\(url.standardizedFileURL.resolvingSymlinksInPath().path)"
            case .image(let filename, let imageURL, let volumePath):
                return "image|\(imageURL.standardizedFileURL.resolvingSymlinksInPath().path)|\(volumePath)|\(filename.uppercased())"
            case .newImageProgram(let filename, let imageURL, let volumePath):
                return "new-image-program|\(imageURL.standardizedFileURL.resolvingSymlinksInPath().path)|\(volumePath)|\(filename.uppercased())"
            }
        }
    }

    let id = UUID()
    @Published private(set) var source: Source
    @Published private(set) var originalData: Data
    @Published private(set) var program: P9Program
    @Published var lastSavedURL: URL?
    @Published private(set) var lastSavedData: Data?
    @Published private(set) var pendingKeygroupPaste: P9PendingKeygroupPaste?
    @Published var isPreparingKeygroupPaste = false
    @Published var isOverwritingInImage = false
    @Published var overwriteMessage: String?
    @Published var overwriteErrorMessage: String?
    @Published var isCreatingInImage = false
    @Published var createMessage: String?
    @Published var createErrorMessage: String?
    @Published var abletonImportDraft: AbletonDrumRackImportDraft?
    @Published var isImportingDrumRack = false
    @Published var drumRackImportMessage: String?
    @Published var drumRackImportErrorMessage: String?
    @Published private(set) var editorRevision = 0
    @Published private(set) var recoverySnapshot: P9RecoverySnapshot?
    @Published private(set) var auditionSyncState: P9AuditionSyncState = .disconnected
    weak var undoManager: UndoManager?
    var liveAuditionClient: P9LiveAuditionClient? {
        didSet {
            oldValue?.stop()
            guard let liveAuditionClient else {
                auditionSyncState = .disconnected
                return
            }
            liveAuditionClient.onStateChange = { [weak self] state in
                self?.auditionSyncState = state
            }
            liveAuditionClient.start()
            publishAuditionSnapshot()
        }
    }
    private let recoveryDirectory: URL?
    private var recoveryWriteTask: Task<Void, Never>?
    private var ownsContinuousUndoGroup = false
    private var continuousUndoActionName: String?

    init(
        data: Data,
        source: Source,
        baselineData: Data? = nil,
        recoveryDirectory: URL? = nil
    ) throws {
        originalData = baselineData ?? data
        program = try P9Program(data: data)
        self.source = source
        self.recoveryDirectory = recoveryDirectory
        recoverySnapshot = try? P9RecoveryJournal.read(
            sourceIdentity: source.recoveryIdentity,
            baselineData: originalData,
            directory: recoveryDirectory
        )
    }

    var hasChanges: Bool {
        guard let data = try? program.encoded() else { return true }
        return data != originalData
    }

    var hasUnwrittenChanges: Bool {
        guard let data = try? program.encoded() else { return true }
        if data == originalData, !source.isNewImageProgram {
            return false
        }
        if let lastSavedData, data == lastSavedData {
            return false
        }
        return source.isNewImageProgram || data != originalData
    }

    func replaceProgram(
        with updatedProgram: P9Program,
        refreshEditor: Bool = false,
        actionName: String = "Edit Program",
        registerUndo: Bool = true
    ) {
        guard updatedProgram != program else { return }
        let previousProgram = program
        let structureChanged =
            updatedProgram.keygroups.count != program.keygroups.count
        installProgram(
            updatedProgram,
            refreshEditor: refreshEditor || structureChanged
        )
        if registerUndo {
            registerUndoSnapshot(previousProgram, actionName: actionName)
        }
        scheduleRecoveryWrite()
        publishAuditionSnapshot()
    }

    func performEdit(
        actionName: String,
        refreshEditor: Bool = false,
        _ mutation: (inout P9Program) throws -> Void
    ) rethrows {
        var updatedProgram = program
        try mutation(&updatedProgram)
        replaceProgram(
            with: updatedProgram,
            refreshEditor: refreshEditor,
            actionName: actionName
        )
    }

    func beginContinuousEdit(actionName: String) {
        guard let undoManager,
              undoManager.groupingLevel == 0,
              !ownsContinuousUndoGroup
        else { return }
        undoManager.beginUndoGrouping()
        ownsContinuousUndoGroup = true
        continuousUndoActionName = actionName
    }

    func endContinuousEdit() {
        guard ownsContinuousUndoGroup, let undoManager else { return }
        if let continuousUndoActionName {
            undoManager.setActionName(continuousUndoActionName)
        }
        undoManager.endUndoGrouping()
        ownsContinuousUndoGroup = false
        continuousUndoActionName = nil
    }

    func restoreRecoverySnapshot() throws {
        guard let recoverySnapshot else { return }
        let recovered = try P9Program(data: recoverySnapshot.workingData)
        replaceProgram(
            with: recovered,
            refreshEditor: true,
            actionName: "Restore Recovered Edits"
        )
        self.recoverySnapshot = nil
    }

    func discardRecoverySnapshot() {
        recoverySnapshot = nil
        removeRecoveryJournal()
    }

    func discardUnsavedChanges() {
        removeRecoveryJournal()
    }

    private func installProgram(_ updatedProgram: P9Program, refreshEditor: Bool) {
        let structureChanged =
            updatedProgram.keygroups.count != program.keygroups.count
        program = updatedProgram
        if refreshEditor || structureChanged {
            editorRevision &+= 1
        }
    }

    private func registerUndoSnapshot(
        _ previousProgram: P9Program,
        actionName: String
    ) {
        undoManager?.registerSuiteUndo(
            withTarget: self,
            actionName: actionName
        ) { target in
            let inverse = target.program
            target.installProgram(previousProgram, refreshEditor: true)
            target.registerUndoSnapshot(inverse, actionName: actionName)
            target.scheduleRecoveryWrite()
            target.publishAuditionSnapshot()
        }
    }

    @discardableResult
    func applyKeygroupDraft(
        _ draft: P9Keygroup,
        baseline: P9Keygroup,
        at index: Int
    ) -> Bool {
        guard program.keygroups.indices.contains(index),
              draft.id == index,
              baseline.id == index,
              program.keygroups[index] == baseline,
              draft != baseline
        else { return false }
        var updatedProgram = program
        updatedProgram.keygroups[index] = draft
        replaceProgram(with: updatedProgram)
        return true
    }

    func markOverwritten(with data: Data) throws {
        guard case .image = source else {
            throw AppError.verificationFailed(
                "Only a P9 opened from an IMG can be marked as overwritten."
            )
        }
        replaceProgram(
            with: try P9Program(data: data),
            refreshEditor: true,
            registerUndo: false
        )
        originalData = data
        lastSavedData = nil
        removeRecoveryJournal()
        overwriteMessage = "\(source.filename) overwritten and byte-verified."
    }

    func markCreatedInImage(with data: Data) throws {
        let recoveryIdentity = source.recoveryIdentity
        guard case .newImageProgram(
            let filename,
            let imageURL,
            let volumePath
        ) = source else {
            throw AppError.verificationFailed(
                "Only a new P9 can be marked as created in an IMG."
            )
        }
        replaceProgram(
            with: try P9Program(data: data),
            refreshEditor: true,
            registerUndo: false
        )
        originalData = data
        lastSavedData = nil
        source = .image(
            filename: filename,
            imageURL: imageURL,
            volumePath: volumePath
        )
        removeRecoveryJournal(sourceIdentity: recoveryIdentity)
        createMessage = "\(filename) created and byte-verified in the IMG."
    }

    func markSavedAsNewInImage(
        filename: String,
        imageURL: URL,
        volumePath: String,
        data: Data
    ) throws {
        let recoveryIdentity = source.recoveryIdentity
        guard source.isExistingImageProgram else {
            throw AppError.verificationFailed(
                "Save As New in IMG is available only for a P9 opened from an IMG."
            )
        }
        replaceProgram(
            with: try P9Program(data: data),
            refreshEditor: true,
            registerUndo: false
        )
        originalData = data
        lastSavedData = nil
        source = .image(
            filename: filename,
            imageURL: imageURL,
            volumePath: volumePath
        )
        removeRecoveryJournal(sourceIdentity: recoveryIdentity)
        createMessage = "\(filename) saved as new and byte-verified in the IMG."
    }

    func stageKeygroupPaste(
        records: [Data],
        sampleNameMapping: [String: String],
        statusLines: [String]
    ) throws {
        guard pendingKeygroupPaste == nil else {
            throw AppError.verificationFailed(
                "Apply the current pasted keygroups before pasting another set."
            )
        }
        var validationProgram = program
        try validationProgram.appendKeygroups(
            records: records,
            sampleNameMapping: sampleNameMapping
        )
        pendingKeygroupPaste = P9PendingKeygroupPaste(
            records: records,
            sampleNameMapping: sampleNameMapping,
            statusLines: statusLines
        )
    }

    @discardableResult
    func applyPendingKeygroupPaste() throws -> Range<Int>? {
        guard let pendingKeygroupPaste else { return nil }
        let firstIndex = program.keygroups.count
        var updatedProgram = program
        try updatedProgram.appendKeygroups(
            records: pendingKeygroupPaste.records,
            sampleNameMapping: pendingKeygroupPaste.sampleNameMapping
        )
        replaceProgram(
            with: updatedProgram,
            actionName: "Paste Keygroups"
        )
        self.pendingKeygroupPaste = nil
        return firstIndex..<updatedProgram.keygroups.count
    }

    func saveCopy() throws -> URL? {
        guard pendingKeygroupPaste == nil else {
            throw AppError.verificationFailed(
                "Apply the pasted keygroups before saving the edited P9 copy."
            )
        }
        let panel = NSSavePanel()
        panel.title = "Save P9 As"
        panel.prompt = "Save P9"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [UTType(filenameExtension: "p9") ?? .data]
        let stem = (source.filename as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(stem)-EDITED.P9"
        guard panel.runModal() == .OK, let selectedURL = panel.url else { return nil }
        let destination = selectedURL.pathExtension.caseInsensitiveCompare("p9") == .orderedSame
            ? selectedURL
            : selectedURL.appendingPathExtension("P9")
        let data = try program.encoded()
        try data.write(to: destination, options: .atomic)
        lastSavedURL = destination
        lastSavedData = data
        removeRecoveryJournal()
        return destination
    }

    func saveLocalSource() throws -> URL {
        guard case .local(let sourceURL) = source else {
            throw AppError.verificationFailed(
                "Direct Save is available only for a standalone P9 source."
            )
        }
        let currentSource = try Data(contentsOf: sourceURL)
        let expectedSource = originalData
        guard currentSource == expectedSource else {
            throw P9EditingError.sourceChangedExternally
        }
        let data = try program.encoded()
        try data.write(to: sourceURL, options: .atomic)
        originalData = data
        lastSavedData = data
        lastSavedURL = sourceURL
        removeRecoveryJournal()
        return sourceURL
    }

    private func scheduleRecoveryWrite() {
        recoveryWriteTask?.cancel()
        guard hasUnwrittenChanges,
              let workingData = try? program.encoded()
        else {
            removeRecoveryJournal()
            return
        }
        let snapshot = P9RecoverySnapshot(
            sourceIdentity: source.recoveryIdentity,
            baselineData: originalData,
            workingData: workingData
        )
        let directory = recoveryDirectory
        // Inherit the document's MainActor so an explicit discard cannot race a
        // detached journal write that has already finished its debounce.
        recoveryWriteTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            try? P9RecoveryJournal.write(snapshot, directory: directory)
        }
    }

    private func removeRecoveryJournal(sourceIdentity: String? = nil) {
        recoveryWriteTask?.cancel()
        recoveryWriteTask = nil
        let identity = sourceIdentity ?? source.recoveryIdentity
        let directory = recoveryDirectory
        try? P9RecoveryJournal.remove(
            sourceIdentity: identity,
            directory: directory
        )
    }

    private func publishAuditionSnapshot() {
        guard let data = try? program.encoded() else { return }
        liveAuditionClient?.publish(programData: data)
    }
}

@MainActor
struct P9EditorSheet: View {
    static let baseSize = CGSize(width: 1240, height: 800)

    static func presentationSize(for zoom: SuiteZoomLevel) -> CGSize {
        let scale = CGFloat(zoom.rawValue)
        return CGSize(
            width: baseSize.width * scale,
            height: baseSize.height * scale
        )
    }

    @ObservedObject var document: P9EditorDocument
    @ObservedObject var audition: ProgramAuditionController
    let auditionSamples: [String: ProgramAuditionSample]
    let keygroupTransfer: P9KeygroupTransfer?
    let onCopyKeygroups: ((P9Program, Set<Int>, P9EditorDocument.Source) -> Void)?
    let onPasteKeygroups: ((P9EditorDocument) -> Void)?
    let onOverwriteP9: ((P9EditorDocument, Bool) -> Void)?
    let onSaveP9AsNewInImage: ((P9EditorDocument, String) -> Void)?
    let onCreateP9InImage: ((P9EditorDocument) -> Void)?
    let onChooseAbletonDrumRack: ((P9EditorDocument) -> Void)?
    let onImportAbletonDrumRack:
        ((AbletonDrumRackImportDraft, P9EditorDocument) -> Void)?
    let availableSampleNames: [String]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var suitePreferences: SuitePreferences
    @State private var selection: Set<Int>
    @State private var primaryKeygroupIndex: Int?
    @State private var loudSampleExpanded = false
    @State private var showSpreadSheet = false
    @State private var showOverwriteConfirmation = false
    @State private var showSaveP9Destination = false
    @State private var showSaveAsNewInImagePrompt = false
    @State private var createBackupBeforeOverwrite = true
    @State private var showCloseConfirmation = false
    @State private var showRecoveryConfirmation = false
    @State private var spreadSettings = P9SpreadSettings()
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var keygroupSelectionAnchor: Int?
    @State private var draggedKeygroupOffsets = IndexSet()
    @State private var keygroupDropTarget: P9KeygroupDropTarget?

    init(
        document: P9EditorDocument,
        audition: ProgramAuditionController,
        auditionSamples: [String: ProgramAuditionSample] = [:],
        initialSelection: Set<Int>? = nil,
        showSpreadInitially: Bool = false,
        showOverwriteConfirmationInitially: Bool = false,
        keygroupTransfer: P9KeygroupTransfer? = nil,
        availableSampleNames: [String] = [],
        onCopyKeygroups: ((P9Program, Set<Int>, P9EditorDocument.Source) -> Void)? = nil,
        onPasteKeygroups: ((P9EditorDocument) -> Void)? = nil,
        onOverwriteP9: ((P9EditorDocument, Bool) -> Void)? = nil,
        onSaveP9AsNewInImage: ((P9EditorDocument, String) -> Void)? = nil,
        onCreateP9InImage: ((P9EditorDocument) -> Void)? = nil,
        onChooseAbletonDrumRack: ((P9EditorDocument) -> Void)? = nil,
        onImportAbletonDrumRack:
            ((AbletonDrumRackImportDraft, P9EditorDocument) -> Void)? = nil
    ) {
        self.document = document
        self.audition = audition
        self.auditionSamples = auditionSamples
        self.keygroupTransfer = keygroupTransfer
        self.onCopyKeygroups = onCopyKeygroups
        self.onPasteKeygroups = onPasteKeygroups
        self.onOverwriteP9 = onOverwriteP9
        self.onSaveP9AsNewInImage = onSaveP9AsNewInImage
        self.onCreateP9InImage = onCreateP9InImage
        self.onChooseAbletonDrumRack = onChooseAbletonDrumRack
        self.onImportAbletonDrumRack = onImportAbletonDrumRack
        self.availableSampleNames = availableSampleNames
        let first = document.program.keygroups.first?.id
        let startingSelection = initialSelection ?? first.map { Set([$0]) } ?? []
        _selection = State(initialValue: startingSelection)
        _primaryKeygroupIndex = State(
            initialValue: startingSelection.sorted().first
        )
        _showSpreadSheet = State(
            initialValue: showSpreadInitially && startingSelection.count > 1
        )
        _showOverwriteConfirmation = State(
            initialValue: showOverwriteConfirmationInitially
        )
        let firstNote = startingSelection.sorted().first
            .flatMap { index in
                document.program.keygroups.indices.contains(index)
                    ? document.program.keygroups[index].lowKey
                    : nil
            } ?? 60
        _spreadSettings = State(
            initialValue: P9SpreadSettings(
                startNote: firstNote,
                rootNote: firstNote,
                automaticallyTranspose: true
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .disabled(
                document.isOverwritingInImage
                        || document.isCreatingInImage
                        || document.isImportingDrumRack
                )
            Divider()
            ProgramAuditionControlStrip(
                controller: audition,
                indicatedSampleNames: indicatedEditorSampleNames
            )
            Divider()
            HStack(spacing: 0) {
                keygroupList
                    .frame(width: 240)
                Divider()
                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .disabled(
                document.isOverwritingInImage
                    || document.isCreatingInImage
                    || document.isImportingDrumRack
            )
            Divider()
            footer
        }
        .frame(width: Self.baseSize.width, height: Self.baseSize.height)
        .background(Color.suiteBackground)
        .onChange(of: selection) { _, newSelection in
            if let primaryKeygroupIndex,
               !newSelection.contains(primaryKeygroupIndex) {
                self.primaryKeygroupIndex = newSelection.sorted().first
            } else if primaryKeygroupIndex == nil {
                primaryKeygroupIndex = newSelection.sorted().first
            }
            message = nil
        }
        .onAppear {
            audition.activateEditor(preparedAuditionProgram)
            showRecoveryConfirmation = document.recoverySnapshot != nil
        }
        .onDisappear { audition.deactivateEditor() }
        .onKeyPress("a", phases: .down) { press in
            guard press.modifiers.contains(.command) else {
                return .ignored
            }
            selectAllKeygroups()
            return .handled
        }
        .onChange(of: document.program) { _, _ in
            let validSelection = selection.filter {
                document.program.keygroups.indices.contains($0)
            }
            if validSelection != selection {
                selection = validSelection.isEmpty
                    ? document.program.keygroups.indices.first.map { Set([$0]) } ?? []
                    : validSelection
            }
            audition.updateEditor(preparedAuditionProgram)
        }
        .alert("P9 Editor", isPresented: Binding(
            get: {
                errorMessage != nil
                    || document.overwriteErrorMessage != nil
                    || document.createErrorMessage != nil
                    || document.drumRackImportErrorMessage != nil
            },
            set: {
                if !$0 {
                    errorMessage = nil
                    document.overwriteErrorMessage = nil
                    document.createErrorMessage = nil
                    document.drumRackImportErrorMessage = nil
                }
            }
        )) {
            Button("OK") {
                errorMessage = nil
                document.overwriteErrorMessage = nil
                document.createErrorMessage = nil
                document.drumRackImportErrorMessage = nil
            }
        } message: {
            Text(
                errorMessage
                    ?? document.overwriteErrorMessage
                    ?? document.createErrorMessage
                    ?? document.drumRackImportErrorMessage
                    ?? ""
            )
        }
        .alert(
            "Recover Unsaved Program Edits?",
            isPresented: $showRecoveryConfirmation
        ) {
            Button("Restore") {
                do {
                    try document.restoreRecoverySnapshot()
                    message = "Recovered unsaved edits."
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button("Discard", role: .destructive) {
                document.discardRecoverySnapshot()
            }
        } message: {
            Text(
                "EDIT950 found a recovery journal for this exact program source. The source IMG or P9 has not been changed."
            )
        }
        .alert(
            "Close Program Without Saving?",
            isPresented: $showCloseConfirmation
        ) {
            Button("Save") {
                showCloseConfirmation = false
                saveDocument()
            }
            Button("Cancel", role: .cancel) {
                showCloseConfirmation = false
            }
            Button("Close Without Saving", role: .destructive) {
                showCloseConfirmation = false
                document.discardUnsavedChanges()
                dismiss()
            }
        } message: {
            Text(
                "This version of the program has not been written to its IMG "
                    + "or saved as an edited P9 copy. Closing now will discard it."
            )
        }
        .sheet(isPresented: $showSpreadSheet) {
            P9SpreadSheet(
                keygroupCount: selection.count,
                settings: $spreadSettings,
                onSpread: performSpread
            )
        }
        .sheet(isPresented: $showOverwriteConfirmation) {
            P9OverwriteConfirmationSheet(
                filename: document.source.filename,
                createBackup: $createBackupBeforeOverwrite
            ) { createBackup in
                overwriteInImage(createBackup: createBackup)
            }
        }
        .confirmationDialog(
            "Save P9 As…",
            isPresented: $showSaveP9Destination,
            titleVisibility: .visible
        ) {
            Button("Save in Current IMG…") {
                showSaveAsNewInImagePrompt = true
            }
            Button("Save to Filesystem…") {
                saveCopy()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Choose whether to create a new P9 beside the current program "
                    + "in the open IMG, or save a standalone P9 file."
            )
        }
        .sheet(isPresented: $showSaveAsNewInImagePrompt) {
            P9SaveAsNewInImageSheet(
                sourceFilename: document.source.filename,
                suggestedName: suggestedP9CopyName
            ) { requestedName in
                saveAsNewInImage(named: requestedName)
            }
        }
        .sheet(item: $document.abletonImportDraft) { draft in
            AbletonDrumRackImportSheet(draft: draft) { finalized in
                onImportAbletonDrumRack?(finalized, document)
            }
        }
        .interactiveDismissDisabled(
            document.hasUnwrittenChanges
                || document.isPreparingKeygroupPaste
                || document.isOverwritingInImage
                || document.isCreatingInImage
                || document.isImportingDrumRack
        )
        .scaleEffect(programEditorScale, anchor: .topLeading)
        .frame(
            width: programEditorPresentationSize.width,
            height: programEditorPresentationSize.height,
            alignment: .topLeading
        )
    }

    private var programEditorScale: CGFloat {
        CGFloat(suitePreferences.zoom.rawValue)
    }

    private var programEditorPresentationSize: CGSize {
        Self.presentationSize(for: suitePreferences.zoom)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "pianokeys")
                .font(.system(size: 32))
                .foregroundStyle(Color.suiteYellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(document.source.filename)
                    .font(SuiteFont.medium(15)).tracking(2.4)
                Text(document.source.detail)
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Program")
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
                Text(document.program.name)
                    .font(SuiteFont.medium(11))
                    .monospaced()
            }
            Toggle("Positional crossfade", isOn: positionalCrossfadeBinding)
            Divider()
                .frame(height: 20)
        }
        .padding(12)
    }

    private var preparedAuditionProgram: PreparedProgramAudition {
        PreparedProgramAudition(
            program: document.program,
            availableSamples: auditionSamples
        )
    }

    private var indicatedEditorSampleNames: [String] {
        auditionSamples.values.compactMap { sample in
            audition.indicatedSampleIDs.contains(sample.fileID)
                ? sample.normalizedName : nil
        }.sorted()
    }

    private var selectedKeygroups: [P9Keygroup] {
        selection.sorted().compactMap { index in
            document.program.keygroups.indices.contains(index)
                ? document.program.keygroups[index]
                : nil
        }
    }

    private var primaryKeygroup: P9Keygroup? {
        guard let primaryKeygroupIndex,
              selection.contains(primaryKeygroupIndex),
              document.program.keygroups.indices.contains(primaryKeygroupIndex)
        else { return selectedKeygroups.first }
        return document.program.keygroups[primaryKeygroupIndex]
    }

    private var auditionSyncSystemImage: String {
        switch document.auditionSyncState {
        case .disconnected: return "bolt.slash"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .auditioned: return "waveform"
        case .error: return "exclamationmark.triangle"
        }
    }

    private var auditionSyncColor: Color {
        switch document.auditionSyncState {
        case .auditioned: return .suiteBlue
        case .syncing: return .suiteYellow
        case .disconnected: return .suiteUnit
        case .error: return .suiteRed
        }
    }

    private var keygroupList: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Keygroups")
                    .font(SuiteFont.medium(11))
                Spacer()
                Text("\(selection.count) selected")
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(document.program.keygroups) { keygroup in
                    let isSelected = selection.contains(keygroup.id)
                    HStack {
                        Circle()
                            .fill(
                                audition.isKeygroupHeld(keygroup)
                                    ? isSelected ? Color.suiteYellow : Color.suiteBlue
                                    : Color.clear
                            )
                            .overlay(Circle().stroke(Color.suiteRule2))
                            .frame(width: 7, height: 7)
                        Text("\(keygroup.id + 1)")
                            .font(SuiteFont.medium(11))
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                            .foregroundStyle(
                                isSelected ? Color.suiteOnBlue : Color.suiteLabel
                            )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(
                                keygroup.softSampleName.isEmpty
                                    ? "No soft sample"
                                    : keygroup.softSampleName
                            )
                                .lineLimit(1)
                                .foregroundStyle(
                                    isSelected ? Color.suiteOnBlue : Color.primary
                                )
                            Text(keygroup.noteRangeWithMIDIDescription)
                                .font(SuiteFont.medium(11))
                                .foregroundStyle(
                                    isSelected ? Color.suiteOnBlue : Color.suiteLabel
                                )
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(
                                isSelected ? Color.suiteOnBlue : Color.suiteLabel
                            )
                            .help("Drag to reorder this keygroup")
                    }
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                isSelected
                                    ? Color.suiteBlue
                                    : audition.isKeygroupHeld(keygroup)
                                        ? Color.suiteSlab3
                                        : Color.clear
                            )
                            .padding(.horizontal, 8)
                    }
                    .overlay(alignment: keygroupDropTarget?.insertAfter == true ? .bottom : .top) {
                        if keygroupDropTarget?.index == keygroup.id {
                            Rectangle()
                                .fill(Color.suiteBlue)
                                .frame(height: 2)
                                .padding(.horizontal, 8)
                        }
                    }
                    .onTapGesture {
                        selectKeygroup(
                            keygroup.id,
                            modifiers: NSEvent.modifierFlags
                        )
                    }
                    .onDrag { beginKeygroupDrag(at: keygroup.id) }
                    .onDrop(
                        of: [.plainText],
                        delegate: P9KeygroupDropDelegate(
                            targetIndex: keygroup.id,
                            reorderingDisabled: keygroupReorderingDisabled,
                            draggedOffsets: $draggedKeygroupOffsets,
                            dropTarget: $keygroupDropTarget,
                            move: moveKeygroups
                        )
                    )

                        if keygroup.id < document.program.keygroups.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                                .padding(.trailing, 16)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .id(document.editorRevision)
            .background(Color.suiteSlab)

            HStack {
                Button {
                    addKeygroup()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 18)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Add Keygroup")
                .disabled(
                    document.program.keygroups.count
                            + max(1, selection.count) > 99
                        || document.pendingKeygroupPaste != nil
                        || document.isPreparingKeygroupPaste
                )
                .help("Duplicate every selected keygroup as one ordered block")
                Button(role: .destructive) {
                    deleteSelectedKeygroups()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 18)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Delete Keygroups")
                .disabled(
                    selection.isEmpty
                        || selection.count >= document.program.keygroups.count
                        || document.pendingKeygroupPaste != nil
                        || document.isPreparingKeygroupPaste
                )
                .help("Delete the selected keygroups; at least one must remain")
                Spacer()
                Menu("Select") {
                    Button("Select All Keygroups") {
                        selectAllKeygroups()
                    }
                    .keyboardShortcut("a", modifiers: .command)
                    Button("Keep First Selected Only") {
                        if let first =
                            primaryKeygroupIndex
                            ?? selection.sorted().first
                            ?? document.program.keygroups.first?.id {
                            selection = [first]
                            primaryKeygroupIndex = first
                            keygroupSelectionAnchor = first
                        }
                    }
                }
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if selection.count == 1, let index = selection.first,
           document.program.keygroups.indices.contains(index) {
            IndividualP9KeygroupEditor(
                document: document,
                keygroup: individualKeygroupBinding(index),
                loudSampleExpanded: $loudSampleExpanded,
                availableSampleNames: availableSampleNames
            )
        } else if !selection.isEmpty {
            MixedP9KeygroupEditor(
                document: document,
                selection: selection,
                keygroups: selectedKeygroups,
                primaryKeygroup: primaryKeygroup,
                loudSampleExpanded: $loudSampleExpanded,
                availableSampleNames: availableSampleNames
            )
        } else {
            ContentUnavailableView(
                "Select a Keygroup",
                systemImage: "pianokeys",
                description: Text("Select one keygroup to edit it, or select several for bulk editing.")
            )
        }
    }

    private var footer: some View {
        HStack {
            Label(
                document.source.isExistingImageProgram
                    ? "Edits remain in memory until saved or safely overwritten"
                    : document.source.isNewImageProgram
                        ? "Create in IMG when ready, or save a local P9 copy"
                        : "Save Copy only — the source P9 remains unchanged",
                systemImage: "lock.shield"
            )
            .font(SuiteFont.regular(10))
            .foregroundStyle(Color.suiteUnit)
            if document.liveAuditionClient != nil {
                Label(
                    document.auditionSyncState.title,
                    systemImage: auditionSyncSystemImage
                )
                .font(SuiteFont.medium(10))
                .foregroundStyle(auditionSyncColor)
            }
            if document.isPreparingKeygroupPaste {
                ProgressView()
                    .controlSize(.small)
                Text("Transferring associated samples…")
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
                    .lineLimit(1)
            } else if let pending = document.pendingKeygroupPaste {
                Text(
                    "\(pending.count) pasted keygroup\(pending.count == 1 ? "" : "s") ready to add."
                )
                .font(SuiteFont.medium(10))
                .foregroundStyle(Color.suiteUnit)
                .lineLimit(1)
            } else if document.isOverwritingInImage {
                ProgressView()
                    .controlSize(.small)
                Text("Backing up, overwriting and verifying…")
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
                    .lineLimit(1)
            } else if document.isCreatingInImage {
                ProgressView()
                    .controlSize(.small)
                Text("Creating and verifying the new P9…")
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
                    .lineLimit(1)
            } else if document.isImportingDrumRack {
                ProgressView()
                    .controlSize(.small)
                Text("Converting WAV files and importing S9 samples…")
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
                    .lineLimit(1)
            } else if let overwriteMessage = document.overwriteMessage {
                Text(overwriteMessage)
                    .font(SuiteFont.medium(10))
                    .foregroundStyle(Color.suiteUnit)
                    .lineLimit(1)
            } else if let createMessage = document.createMessage {
                Text(createMessage)
                    .font(SuiteFont.medium(10))
                    .foregroundStyle(Color.suiteUnit)
                    .lineLimit(1)
            } else if let drumRackImportMessage =
                        document.drumRackImportMessage {
                Text(drumRackImportMessage)
                    .font(SuiteFont.medium(10))
                    .foregroundStyle(Color.suiteUnit)
                    .lineLimit(1)
            } else if let message {
                Text(message)
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                chooseAbletonDrumRack()
            } label: {
                Label("Import ADG…", systemImage: "square.grid.3x3")
            }
            .disabled(
                document.source.imageURL == nil
                    || onChooseAbletonDrumRack == nil
                    || onImportAbletonDrumRack == nil
                    || document.pendingKeygroupPaste != nil
                    || document.isPreparingKeygroupPaste
                    || document.isOverwritingInImage
                    || document.isCreatingInImage
                    || document.isImportingDrumRack
                    || document.program.keygroups.count >= 99
            )
            .help(
                document.source.imageURL == nil
                    ? "Open this P9 from a writable S950 IMG to import its samples"
                    : "Convert an Ableton Drum Rack ADG into S9 samples and appended keygroups"
            )
            Button {
                prepareSpread()
            } label: {
                Label("Spread…", systemImage: "pianokeys")
            }
            .disabled(
                selection.count < 2
                    || document.pendingKeygroupPaste != nil
                    || document.isPreparingKeygroupPaste
                    || document.isOverwritingInImage
                    || document.isCreatingInImage
                    || document.isImportingDrumRack
            )
            .help(
                document.pendingKeygroupPaste != nil
                    ? "Apply the pasted keygroups before spreading"
                    : "Map selected keygroups chromatically across single notes"
            )
            Menu {
                Button("Copy Whole Keygroup") {
                    copyPrimaryKeygroup(kind: .wholeKeygroup)
                }
                Menu("Copy Parameter Group") {
                    ForEach(P9ParameterGroup.allCases) { group in
                        Button(group.title) {
                            copyPrimaryKeygroup(kind: .parameterGroup(group))
                        }
                    }
                }
                Divider()
                Button("Paste to Selected Keygroups") {
                    pasteKeygroupClipboard()
                }
                .disabled(keygroupClipboardPayload == nil)
            } label: {
                Label("Copy / Paste", systemImage: "doc.on.clipboard")
            }
            .disabled(selection.isEmpty)
            Menu {
                Button("Copy Selected Keygroups and Samples") {
                    copyCurrentKeygroups()
                }
                .disabled(
                    selection.isEmpty
                        || onCopyKeygroups == nil
                        || document.pendingKeygroupPaste != nil
                        || document.isPreparingKeygroupPaste
                        || document.isOverwritingInImage
                        || document.isCreatingInImage
                        || document.isImportingDrumRack
                )
                Divider()
                if let keygroupTransfer {
                    Text(keygroupTransfer.summary)
                    Button(
                        "Paste \(keygroupTransfer.records.count) at End"
                    ) {
                        pasteCopiedKeygroups()
                    }
                    .disabled(
                        onPasteKeygroups == nil
                            || document.pendingKeygroupPaste != nil
                            || document.isPreparingKeygroupPaste
                            || document.isOverwritingInImage
                            || document.isCreatingInImage
                            || document.isImportingDrumRack
                            || document.program.keygroups.count
                                + keygroupTransfer.records.count > 99
                    )
                } else {
                    Button("Paste Keygroups at End") {}
                        .disabled(true)
                }
            } label: {
                Label("Transfer", systemImage: "doc.on.doc")
            }
            .help(
                keygroupTransfer?.summary
                    ?? "Copy selected keygroups and their associated S9 samples"
            )
            Button("Close") { requestClose() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(SuiteSecondaryButtonStyle())
                .disabled(
                    document.isPreparingKeygroupPaste
                        || document.isOverwritingInImage
                        || document.isCreatingInImage
                        || document.isImportingDrumRack
                )
            if document.pendingKeygroupPaste != nil {
                Button(applyButtonTitle) { applyCurrentEdits() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(SuitePrimaryButtonStyle(role: .neutral))
                    .accessibilityIdentifier("p9-bulk-apply-button")
                    .disabled(!canApply)
            }
            Button("Save") { saveDocument() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(SuitePrimaryButtonStyle(role: .sample))
                .disabled(!canSave)
                .help("Write the current in-memory program explicitly")
            Button("Save P9 As…") { saveP9As() }
                .buttonStyle(SuiteSecondaryButtonStyle())
                .disabled(
                    document.pendingKeygroupPaste != nil
                        || document.isPreparingKeygroupPaste
                        || document.isOverwritingInImage
                        || document.isCreatingInImage
                        || document.isImportingDrumRack
                )
                .help(
                    document.pendingKeygroupPaste != nil
                        ? "Add the pasted keygroups before saving"
                        : document.source.isExistingImageProgram
                            ? "Create a new P9 in the current IMG or save one to the filesystem"
                            : "Save the program as a standalone P9 file"
                )
        }
        .padding(12)
    }

    private var positionalCrossfadeBinding: Binding<Bool> {
        Binding(
            get: { document.program.positionalCrossfade },
            set: { value in
                var program = document.program
                program.positionalCrossfade = value
                document.replaceProgram(
                    with: program,
                    actionName: "Set Positional Crossfade"
                )
            }
        )
    }

    private func individualKeygroupBinding(_ index: Int) -> Binding<P9Keygroup> {
        Binding(
            get: {
                return document.program.keygroups[index]
            },
            set: { updatedKeygroup in
                guard document.program.keygroups.indices.contains(index),
                      updatedKeygroup.id == index
                else { return }
                var program = document.program
                program.keygroups[index] = updatedKeygroup
                document.replaceProgram(
                    with: program,
                    actionName: "Edit Keygroup"
                )
            }
        )
    }

    private var canApply: Bool {
        if document.isPreparingKeygroupPaste
            || document.isOverwritingInImage
            || document.isCreatingInImage
            || document.isImportingDrumRack {
            return false
        }
        if document.pendingKeygroupPaste != nil {
            return true
        }
        return false
    }

    private var canOverwriteInImage: Bool {
        guard onOverwriteP9 != nil,
              document.source.isExistingImageProgram,
              document.pendingKeygroupPaste == nil,
              !document.isPreparingKeygroupPaste,
              !document.isOverwritingInImage,
              !document.isCreatingInImage,
              !document.isImportingDrumRack
        else { return false }
        return true
    }

    private var canCreateInImage: Bool {
        onCreateP9InImage != nil
            && document.source.isNewImageProgram
            && !document.program.keygroups.isEmpty
            && document.pendingKeygroupPaste == nil
            && !document.isPreparingKeygroupPaste
            && !document.isOverwritingInImage
            && !document.isCreatingInImage
            && !document.isImportingDrumRack
    }

    private var canSave: Bool {
        guard document.pendingKeygroupPaste == nil,
              !document.isPreparingKeygroupPaste,
              !document.isOverwritingInImage,
              !document.isCreatingInImage,
              !document.isImportingDrumRack
        else { return false }
        switch document.source {
        case .local: return true
        case .image: return canOverwriteInImage
        case .newImageProgram: return canCreateInImage
        }
    }

    private var applyButtonTitle: String {
        if let pending = document.pendingKeygroupPaste {
            return "Add \(pending.count) Pasted Keygroup\(pending.count == 1 ? "" : "s")"
        }
        return "Apply"
    }

    private func applyCurrentEdits(announce: Bool = true) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        if let pending = document.pendingKeygroupPaste {
            do {
                if let appendedRange = try document.applyPendingKeygroupPaste() {
                    selection = Set(appendedRange)
                    primaryKeygroupIndex = appendedRange.first
                }
                if announce {
                    message =
                        "Applied \(pending.count) pasted keygroup"
                        + "\(pending.count == 1 ? "" : "s"). Save P9 As when ready."
                }
            } catch {
                errorMessage =
                    (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            return
        }
    }

    private func selectAllKeygroups() {
        selection = Set(document.program.keygroups.indices)
        if primaryKeygroupIndex == nil {
            primaryKeygroupIndex = document.program.keygroups.indices.first
        }
        keygroupSelectionAnchor = primaryKeygroupIndex
    }

    private func prepareSpread() {
        guard selection.count > 1,
              let firstIndex = selection.sorted().first,
              document.program.keygroups.indices.contains(firstIndex)
        else { return }
        let firstNote = document.program.keygroups[firstIndex].lowKey
        spreadSettings = P9SpreadSettings(
            startNote: firstNote,
            rootNote: firstNote,
            automaticallyTranspose: true
        )
        showSpreadSheet = true
    }

    private func addKeygroup() {
        applyCurrentEdits(announce: false)
        do {
            var program = document.program
            let duplicated: Range<Int>
            if selection.isEmpty {
                let newIndex = try program.appendKeygroup(copying: nil)
                duplicated = newIndex..<(newIndex + 1)
            } else {
                duplicated = try program.duplicateKeygroups(at: selection)
            }
            document.replaceProgram(
                with: program,
                refreshEditor: true,
                actionName: "Duplicate Keygroups"
            )
            selection = Set(duplicated)
            primaryKeygroupIndex = duplicated.first
            keygroupSelectionAnchor = duplicated.first
            message = duplicated.count == 1
                ? "Duplicated the selected keygroup."
                : "Duplicated \(duplicated.count) selected keygroups."
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func deleteSelectedKeygroups() {
        applyCurrentEdits(announce: false)
        guard let firstDeleted = selection.sorted().first else { return }
        let deletedCount = selection.count
        do {
            var program = document.program
            try program.deleteKeygroups(at: selection)
            document.replaceProgram(
                with: program,
                refreshEditor: true,
                actionName: "Delete Keygroups"
            )
            let next = min(firstDeleted, program.keygroups.count - 1)
            selection = [next]
            primaryKeygroupIndex = next
            keygroupSelectionAnchor = next
            message =
                deletedCount == 1
                    ? "Deleted the selected keygroup."
                    : "Deleted \(deletedCount) selected keygroups."
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private var keygroupReorderingDisabled: Bool {
        document.pendingKeygroupPaste != nil
            || document.isPreparingKeygroupPaste
            || document.isOverwritingInImage
            || document.isCreatingInImage
            || document.isImportingDrumRack
    }

    private func selectKeygroup(
        _ index: Int,
        modifiers: NSEvent.ModifierFlags
    ) {
        let modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) {
            if selection.contains(index) {
                selection.remove(index)
                if primaryKeygroupIndex == index {
                    primaryKeygroupIndex = selection.sorted().first
                }
            } else {
                if selection.isEmpty { primaryKeygroupIndex = index }
                selection.insert(index)
            }
            if primaryKeygroupIndex == nil {
                primaryKeygroupIndex = selection.sorted().first
            }
            keygroupSelectionAnchor = primaryKeygroupIndex
        } else if modifiers.contains(.shift) {
            let anchor = keygroupSelectionAnchor
                ?? primaryKeygroupIndex
                ?? selection.sorted().first
                ?? index
            selection = Set(min(anchor, index)...max(anchor, index))
        } else {
            selection = [index]
            primaryKeygroupIndex = index
            keygroupSelectionAnchor = index
        }
    }

    private func beginKeygroupDrag(at index: Int) -> NSItemProvider {
        guard !keygroupReorderingDisabled else { return NSItemProvider() }
        if !selection.contains(index) {
            selection = [index]
            primaryKeygroupIndex = index
            keygroupSelectionAnchor = index
        }
        draggedKeygroupOffsets = IndexSet(selection)
        let provider = NSItemProvider(
            object: "EDIT950 keygroup \(document.id.uuidString)" as NSString
        )
        provider.suggestedName = "EDIT950 Keygroup"
        return provider
    }

    private func moveKeygroups(from offsets: IndexSet, to destination: Int) {
        guard !keygroupReorderingDisabled else {
            errorMessage = "Finish the current keygroup operation before reordering."
            return
        }
        applyCurrentEdits(announce: false)
        do {
            var program = document.program
            let indexMapping = try program.moveKeygroups(
                fromOffsets: offsets,
                toOffset: destination
            )
            let movedCount = offsets.count
            let updatedSelection = Set(selection.compactMap { indexMapping[$0] })
            let updatedPrimary = primaryKeygroupIndex.flatMap { indexMapping[$0] }
            document.replaceProgram(
                with: program,
                refreshEditor: true,
                actionName: "Reorder Keygroups"
            )
            selection = updatedSelection
            primaryKeygroupIndex = updatedPrimary ?? updatedSelection.sorted().first
            keygroupSelectionAnchor = primaryKeygroupIndex
            message = movedCount == 1
                ? "Reordered the keygroup."
                : "Reordered \(movedCount) keygroups."
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func performSpread(_ settings: P9SpreadSettings) {
        do {
            var program = document.program
            try program.spread(settings, to: selection)
            document.replaceProgram(
                with: program,
                actionName: "Spread Keygroups"
            )
            let endNote = settings.startNote + selection.count - 1
            message = "Spread \(selection.count) keygroups from \(P9Keygroup.noteName(settings.startNote)) to \(P9Keygroup.noteName(endNote))."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var keygroupClipboardPayload: P9ClipboardPayload? {
        let type = NSPasteboard.PasteboardType(P9ClipboardPayload.pasteboardType)
        guard let data = NSPasteboard.general.data(forType: type),
              let payload = try? JSONDecoder().decode(
                P9ClipboardPayload.self,
                from: data
              )
        else { return nil }
        return try? payload.validated()
    }

    private func copyPrimaryKeygroup(kind: P9ClipboardPayload.Kind) {
        guard let primary = primaryKeygroup?.id else {
            NSSound.beep()
            return
        }
        do {
            let record = try document.program.keygroupRecords(at: [primary])[0]
            let payload = P9ClipboardPayload(
                kind: kind,
                sourceProgram: document.program.name,
                record: record
            )
            let data = try JSONEncoder().encode(payload)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(
                data,
                forType: NSPasteboard.PasteboardType(
                    P9ClipboardPayload.pasteboardType
                )
            )
            message = "Copied \(clipboardDescription(kind)) from keygroup \(primary + 1)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pasteKeygroupClipboard() {
        guard let payload = keygroupClipboardPayload else {
            NSSound.beep()
            return
        }
        do {
            try document.performEdit(actionName: "Paste Keygroup Parameters") { program in
                switch payload.kind {
                case .wholeKeygroup:
                    try program.replaceKeygroups(at: selection, with: payload.record)
                case .parameterGroup(let group):
                    try program.applyParameterGroup(
                        group,
                        from: payload.record,
                        to: selection
                    )
                }
            }
            message = "Pasted \(clipboardDescription(payload.kind)) to \(selection.count) keygroup\(selection.count == 1 ? "" : "s")."
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func clipboardDescription(_ kind: P9ClipboardPayload.Kind) -> String {
        switch kind {
        case .wholeKeygroup: return "whole keygroup"
        case .parameterGroup(let group): return group.title
        }
    }

    private func copyCurrentKeygroups() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        applyCurrentEdits(announce: false)
        onCopyKeygroups?(document.program, selection, document.source)
    }

    private func pasteCopiedKeygroups() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        applyCurrentEdits(announce: false)
        onPasteKeygroups?(document)
    }

    private func saveCopy() {
        do {
            applyCurrentEdits(announce: false)
            if let saved = try document.saveCopy() {
                message = "Saved \(saved.lastPathComponent)"
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func saveDocument() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        applyCurrentEdits(announce: false)
        do {
            switch document.source {
            case .local:
                let saved = try document.saveLocalSource()
                message = "Saved \(saved.lastPathComponent)."
            case .image:
                showOverwriteConfirmation = true
            case .newImageProgram:
                createInImage()
            }
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func saveP9As() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        applyCurrentEdits(announce: false)
        if document.source.isExistingImageProgram,
           onSaveP9AsNewInImage != nil {
            showSaveP9Destination = true
        } else {
            saveCopy()
        }
    }

    private func overwriteInImage(createBackup: Bool) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        applyCurrentEdits(announce: false)
        document.overwriteMessage = nil
        onOverwriteP9?(document, createBackup)
    }

    private func createInImage() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        applyCurrentEdits(announce: false)
        document.createMessage = nil
        onCreateP9InImage?(document)
    }

    private var suggestedP9CopyName: String {
        let stem = (document.source.filename as NSString).deletingPathExtension
        let suffix = "-COPY"
        return String(stem.prefix(max(1, P9CanonicalName.maximumLength - suffix.count)))
            + suffix
    }

    private func saveAsNewInImage(named requestedName: String) {
        NSApp.keyWindow?.makeFirstResponder(nil)
        applyCurrentEdits(announce: false)
        document.createMessage = nil
        onSaveP9AsNewInImage?(document, requestedName)
    }

    private func requestClose() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        applyCurrentEdits(announce: false)
        if document.hasUnwrittenChanges {
            showCloseConfirmation = true
        } else {
            dismiss()
        }
    }

    private func chooseAbletonDrumRack() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        applyCurrentEdits(announce: false)
        document.drumRackImportMessage = nil
        document.drumRackImportErrorMessage = nil
        onChooseAbletonDrumRack?(document)
    }
}

private struct P9OverwriteConfirmationSheet: View {
    let filename: String
    @Binding var createBackup: Bool
    let onConfirm: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(
                "Overwrite \(filename) in the IMG?",
                systemImage: "externaldrive.badge.exclamationmark"
            )
            .font(SuiteFont.medium(15)).tracking(2.4)

            Text(
                "The P9 will be replaced, exported again and compared byte-for-byte."
            )

            Toggle(
                "Create and verify a complete IMG backup first",
                isOn: $createBackup
            )

            if createBackup {
                Text(
                    "If replacement or verification fails, the backup will be restored automatically."
                )
                .font(SuiteFont.regular(10))
                .foregroundStyle(Color.suiteUnit)
            } else {
                Label(
                    "Automatic rollback is unavailable without a backup.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(Color.suiteAmber)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(
                    createBackup
                        ? "Back Up and Overwrite"
                        : "Overwrite Without Backup",
                    role: .destructive
                ) {
                    let shouldBackUp = createBackup
                    dismiss()
                    onConfirm(shouldBackUp)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}

private struct P9SaveAsNewInImageSheet: View {
    let sourceFilename: String
    let suggestedName: String
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var requestedName: String

    init(
        sourceFilename: String,
        suggestedName: String,
        onConfirm: @escaping (String) -> Void
    ) {
        self.sourceFilename = sourceFilename
        self.suggestedName = suggestedName
        self.onConfirm = onConfirm
        _requestedName = State(initialValue: suggestedName)
    }

    private var validationError: String? {
        do {
            _ = try P9CanonicalName.canonicalBase(requestedName)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                "Save Edited Program as New",
                systemImage: "doc.badge.plus"
            )
            .font(SuiteFont.medium(15))
            .tracking(2.4)

            Text(
                "The edited program will be written directly beside \(sourceFilename) in the current IMG. The original P9 and all keygroup data remain unchanged."
            )
            .font(SuiteFont.regular(10))
            .foregroundStyle(Color.suiteUnit)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 5) {
                Text("NEW S950 PROGRAM NAME")
                    .font(SuiteFont.medium(9))
                    .tracking(1.1)
                TextField("Program name", text: $requestedName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { confirmIfValid() }
                Text("UP TO 10 SAMPLER-VISIBLE CHARACTERS")
                    .font(SuiteFont.regular(8))
                    .foregroundStyle(Color.suiteUnit)
            }

            if let validationError {
                Label(validationError, systemImage: "exclamationmark.triangle.fill")
                    .font(SuiteFont.regular(9))
                    .foregroundStyle(Color.suiteRed)
            } else {
                Label(
                    "The new P9 will be re-exported and checked byte-for-byte.",
                    systemImage: "checkmark.shield.fill"
                )
                .font(SuiteFont.regular(9))
                .foregroundStyle(Color.suiteBlue)
            }

            HStack(spacing: 9) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SuiteSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save as New") { confirmIfValid() }
                    .buttonStyle(SuitePrimaryButtonStyle(role: .sample))
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationError != nil)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(Color.suitePanel)
    }

    private func confirmIfValid() {
        guard validationError == nil else { return }
        let name = requestedName
        dismiss()
        onConfirm(name)
    }
}

private struct P9SpreadSheet: View {
    let keygroupCount: Int
    @Binding var settings: P9SpreadSettings
    let onSpread: (P9SpreadSettings) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "pianokeys")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.suiteYellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spread Across Keys")
                        .font(SuiteFont.medium(15)).tracking(2.4)
                    Text("\(keygroupCount) selected keygroups")
                        .foregroundStyle(Color.suiteUnit)
                }
            }

            GroupBox("Chromatic mapping") {
                VStack(spacing: 10) {
                    noteRow("Starting note", value: $settings.startNote)
                    noteRow("Sample root note", value: $settings.rootNote)
                        .disabled(!settings.automaticallyTranspose)
                    Toggle(
                        "Automatically transpose to preserve original playback speed",
                        isOn: $settings.automaticallyTranspose
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 5) {
                Label(previewText, systemImage: "arrow.left.and.right")
                    .font(SuiteFont.medium(11))
                if settings.automaticallyTranspose {
                    Text(transposePreviewText)
                        .foregroundStyle(Color.suiteUnit)
                }
                Text("Soft and Loud Transpose are set together. Existing Fine tuning and all other parameters remain unchanged.")
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
            }

            if let validationError {
                Label(validationError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.suiteAmber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Spread Keygroups") {
                    onSpread(settings)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(SuitePrimaryButtonStyle(role: .neutral))
                .disabled(validationError != nil)
            }
        }
        .controlSize(.small)
        .padding(20)
        .frame(width: 520)
    }

    private func noteRow(_ title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(P9Keygroup.noteName(value.wrappedValue))
                .foregroundStyle(Color.suiteUnit)
                .monospacedDigit()
            P9BoundedNumberField(value: value, range: 0...127)
            Stepper("", value: value, in: 0...127)
                .labelsHidden()
        }
    }

    private var endingNote: Int {
        settings.startNote + max(0, keygroupCount - 1)
    }

    private var previewText: String {
        "\(P9Keygroup.noteName(settings.startNote))–\(P9Keygroup.noteName(min(127, endingNote))) on single notes"
    }

    private var transposePreviewText: String {
        let first = settings.rootNote - settings.startNote
        let last = settings.rootNote - endingNote
        if first == last {
            return "Transpose: \(signed(first)) semitones"
        }
        return "Transpose: \(signed(first)) to \(signed(last)) semitones"
    }

    private var validationError: String? {
        do {
            try settings.validate(keygroupCount: keygroupCount)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}

private struct IndividualP9KeygroupEditor: View {
    @ObservedObject var document: P9EditorDocument
    @Binding var keygroup: P9Keygroup
    @Binding var loudSampleExpanded: Bool
    let availableSampleNames: [String]

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    mappingSection
                    softSampleSection
                    playbackSection
                }
                .frame(maxWidth: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 12) {
                    vcfSection
                    amplitudeSection
                    velocitySection
                    loudSampleSection
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .controlSize(.small)
            .padding(12)
        }
        .background(Color.suiteBackground)
    }

    private var mappingSection: some View {
        GroupBox("Mapping") {
            VStack(spacing: 7) {
                numberRow("Low key", value: int(\.lowKey, 0...127), range: 0...127) {
                    P9Keygroup.noteName(keygroup.lowKey)
                }
                numberRow("High key", value: int(\.highKey, 0...127), range: 0...127) {
                    P9Keygroup.noteName(keygroup.highKey)
                }
                numberRow(
                    "Velocity switch threshold",
                    value: int(\.velocityThreshold, 0...128),
                    range: 0...128
                )
                Toggle("Velocity crossfade", isOn: bool(\.velocityCrossfade))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle(
                    "Custom crossfade midpoint",
                    isOn: bool(\.customVelocityCrossfadePoint)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!keygroup.velocityCrossfade)
                numberRow(
                    "Velocity crossfade midpoint",
                    value: int(\.velocityCrossfadePoint, 0...127),
                    range: 0...127
                )
                .disabled(
                    !keygroup.velocityCrossfade
                        || !keygroup.customVelocityCrossfadePoint
                )
            }
            .padding(6)
        }
    }

    private var softSampleSection: some View {
        sampleSection(
            title: "Soft Sample",
            name: string(\.softSampleName),
            loudness: int(\.softLoudness, -50...50),
            filter: int(\.softFilter, 0...99),
            transpose: int(\.softTuning.transpose, P9Tuning.transposeRange),
            fine: int(\.softTuning.fine, P9Tuning.fineRange)
        )
    }

    private var loudSampleSection: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $loudSampleExpanded) {
                sampleFields(
                    name: string(\.loudSampleName),
                    loudness: int(\.loudLoudness, -50...50),
                    filter: int(\.loudFilter, 0...99),
                    transpose: int(\.loudTuning.transpose, P9Tuning.transposeRange),
                    fine: int(\.loudTuning.fine, P9Tuning.fineRange)
                )
                .padding(.top, 8)
            } label: {
                HStack {
                    Text("Loud Sample")
                        .fontWeight(.medium)
                    Spacer()
                    if !loudSampleExpanded {
                        Text(keygroup.loudSampleName.isEmpty ? "Hidden" : keygroup.loudSampleName)
                            .foregroundStyle(Color.suiteUnit)
                            .lineLimit(1)
                    }
                }
            }
            .padding(6)
        }
    }

    private var vcfSection: some View {
        GroupBox("VCF Envelope") {
            VStack(spacing: 7) {
                envelopeRows(
                    attack: int(\.vcfEnvelope.attack, 0...99),
                    decay: int(\.vcfEnvelope.decay, 0...99),
                    sustain: int(\.vcfEnvelope.sustain, 0...99),
                    release: int(\.vcfEnvelope.release, 0...99)
                )
                numberRow("Amount", value: int(\.vcfAmount, -50...50), range: -50...50)
                numberRow("Key-filter", value: int(\.keyFilter, 0...99), range: 0...99)
                    .help("S950 keyboard-to-filter tracking (native 00–99)")
            }
            .padding(6)
        }
    }

    private var amplitudeSection: some View {
        GroupBox("Amplitude ENV") {
            VStack(spacing: 7) {
                envelopeRows(
                    attack: int(\.envelope.attack, 0...99),
                    decay: int(\.envelope.decay, 0...99),
                    sustain: int(\.envelope.sustain, 0...99),
                    release: int(\.envelope.release, 0...99)
                )
            }
            .padding(6)
        }
    }

    private var velocitySection: some View {
        GroupBox("Velocity Sensitivity") {
            VStack(spacing: 7) {
                numberRow(
                    "Loudness",
                    value: int(\.velocitySensitivity.loudness, 0...99),
                    range: 0...99
                )
                numberRow(
                    "Attack",
                    value: int(\.velocitySensitivity.attack, 0...99),
                    range: 0...99
                )
                numberRow(
                    "Filter",
                    value: int(\.velocitySensitivity.filter, 0...99),
                    range: 0...99
                )
                numberRow(
                    "Release",
                    value: int(\.velocitySensitivity.release, -50...50),
                    range: -50...50
                )
                Picker(
                    "Release velocity source",
                    selection: bool(\.releaseVelocityFromNoteOn)
                ) {
                    Text("Note Off").tag(false)
                    Text("Note On").tag(true)
                }
            }
            .padding(6)
        }
    }

    private var playbackSection: some View {
        GroupBox("Playback and Routing") {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Toggle("Constant pitch", isOn: bool(\.constantPitch))
                    Spacer()
                    Toggle("One-shot", isOn: bool(\.oneShot))
                }
                Picker("MIDI channel", selection: midiChannelBinding) {
                    ForEach(1...16, id: \.self) { channel in
                        Text("\(channel)").tag(channel)
                    }
                }
                .help("Displayed as channels 1–16; the P9 stores offsets 00–15")
                Picker("Output", selection: outputBinding) {
                    ForEach(outputChoices) { output in
                        Text(output.displayName).tag(output)
                    }
                }
                numberRow("LFO depth", value: int(\.lfoDepth, 0...99), range: 0...99)
                    .help("Independent S950 LFO depth (native 00–99)")
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private func sampleFields(
        name: Binding<String>,
        loudness: Binding<Int>,
        filter: Binding<Int>,
        transpose: Binding<Int>,
        fine: Binding<Int>
    ) -> some View {
        VStack(spacing: 7) {
            Picker("Sample", selection: name) {
                Text("No sample").tag("")
                ForEach(sampleChoices(current: name.wrappedValue), id: \.self) {
                    sampleName in
                    Text(sampleName).tag(sampleName)
                }
            }
            .help("Choose from the S9 samples available in the open S950 volume")
            numberRow("Loudness", value: loudness, range: -50...50)
            numberRow("Filter", value: filter, range: 0...99)
            numberRow("Transpose", value: transpose, range: P9Tuning.transposeRange)
            numberRow("Fine", value: fine, range: P9Tuning.fineRange)
                .help(
                    "S950 fine tuning in 1/16-semitone steps "
                        + "(\(P9Tuning.fineRange.lowerBound)…\(P9Tuning.fineRange.upperBound))"
                )
        }
    }

    @ViewBuilder
    private func sampleSection(
        title: String,
        name: Binding<String>,
        loudness: Binding<Int>,
        filter: Binding<Int>,
        transpose: Binding<Int>,
        fine: Binding<Int>
    ) -> some View {
        GroupBox(title) {
            sampleFields(
                name: name,
                loudness: loudness,
                filter: filter,
                transpose: transpose,
                fine: fine
            )
            .padding(6)
        }
    }

    @ViewBuilder
    private func envelopeRows(
        attack: Binding<Int>,
        decay: Binding<Int>,
        sustain: Binding<Int>,
        release: Binding<Int>
    ) -> some View {
        numberRow("Attack", value: attack, range: 0...99)
        numberRow("Decay", value: decay, range: 0...99)
        numberRow("Sustain", value: sustain, range: 0...99)
        numberRow("Release", value: release, range: 0...99)
    }

    private func numberRow(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        detail: (() -> String)? = nil
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let detail {
                Text(detail())
                    .foregroundStyle(Color.suiteUnit)
                    .monospacedDigit()
            }
            P9MixedBoundedNumberField(
                value: value.wrappedValue,
                primaryValue: value.wrappedValue,
                range: range,
                onBegin: {
                    document.beginContinuousEdit(actionName: "Set \(title)")
                },
                onChange: { value.wrappedValue = $0 },
                onEnd: document.endContinuousEdit
            )
            Stepper("", value: value, in: range)
                .labelsHidden()
        }
    }

    private func int(_ keyPath: WritableKeyPath<P9Keygroup, Int>, _ range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { keygroup[keyPath: keyPath] },
            set: { value in
                keygroup[keyPath: keyPath] = max(range.lowerBound, min(range.upperBound, value))
            }
        )
    }

    private func bool(_ keyPath: WritableKeyPath<P9Keygroup, Bool>) -> Binding<Bool> {
        Binding(
            get: { keygroup[keyPath: keyPath] },
            set: { keygroup[keyPath: keyPath] = $0 }
        )
    }

    private func string(_ keyPath: WritableKeyPath<P9Keygroup, String>) -> Binding<String> {
        Binding(
            get: { keygroup[keyPath: keyPath] },
            set: { keygroup[keyPath: keyPath] = String($0.uppercased().prefix(10)) }
        )
    }

    private func sampleChoices(current: String) -> [String] {
        var names = availableSampleNames
        if !current.isEmpty,
           !names.contains(where: {
               $0.caseInsensitiveCompare(current) == .orderedSame
           }) {
            names.append(current)
        }
        return names.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var midiChannelBinding: Binding<Int> {
        Binding(
            get: { max(1, min(16, keygroup.midiChannelOffset + 1)) },
            set: { keygroup.midiChannelOffset = $0 - 1 }
        )
    }

    private var outputBinding: Binding<P9Output> {
        Binding(
            get: { keygroup.output },
            set: { keygroup.output = $0 }
        )
    }

    private var outputChoices: [P9Output] {
        if case .unknown = keygroup.output {
            return [keygroup.output] + P9Output.standardChoices
        }
        return P9Output.standardChoices
    }
}

private struct MixedP9KeygroupEditor: View {
    @ObservedObject var document: P9EditorDocument
    let selection: Set<Int>
    let keygroups: [P9Keygroup]
    let primaryKeygroup: P9Keygroup?
    @Binding var loudSampleExpanded: Bool
    let availableSampleNames: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "Mixed fields are labelled Mixed. Any entered, dragged or chosen value is applied absolutely to all \(selection.count) selected keygroups."
                )
                .font(SuiteFont.regular(11))
                .foregroundStyle(Color.suiteUnit)

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        group("Mapping") {
                            numberRow("Low key", \.lowKey, range: 0...127)
                            numberRow("High key", \.highKey, range: 0...127)
                            numberRow(
                                "Velocity threshold",
                                \.velocityThreshold,
                                range: 0...128
                            )
                            choiceRow(
                                "Velocity crossfade",
                                keyPath: \.velocityCrossfade
                            )
                            choiceRow(
                                "Custom midpoint",
                                keyPath: \.customVelocityCrossfadePoint
                            )
                            numberRow(
                                "Crossfade midpoint",
                                \.velocityCrossfadePoint,
                                range: 0...127
                            )
                        }
                        sampleGroup(
                            "Soft Sample",
                            name: \.softSampleName,
                            loudness: \.softLoudness,
                            filter: \.softFilter,
                            transpose: \.softTuning.transpose,
                            fine: \.softTuning.fine
                        )
                        playbackGroup
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(alignment: .leading, spacing: 12) {
                        group("VCF Envelope") {
                            numberRow("Attack", \.vcfEnvelope.attack, range: 0...99)
                            numberRow("Decay", \.vcfEnvelope.decay, range: 0...99)
                            numberRow("Sustain", \.vcfEnvelope.sustain, range: 0...99)
                            numberRow("Release", \.vcfEnvelope.release, range: 0...99)
                            numberRow("Amount", \.vcfAmount, range: -50...50)
                            numberRow("Key-filter", \.keyFilter, range: 0...99)
                        }
                        group("Amplitude ENV") {
                            numberRow("Attack", \.envelope.attack, range: 0...99)
                            numberRow("Decay", \.envelope.decay, range: 0...99)
                            numberRow("Sustain", \.envelope.sustain, range: 0...99)
                            numberRow(
                                "Release",
                                \.envelope.release,
                                range: 0...99,
                                accessibilityIdentifier:
                                    "p9-mixed-amplitude-release"
                            )
                        }
                        group("Velocity Sensitivity") {
                            numberRow(
                                "Loudness",
                                \.velocitySensitivity.loudness,
                                range: 0...99
                            )
                            numberRow(
                                "Attack",
                                \.velocitySensitivity.attack,
                                range: 0...99
                            )
                            numberRow(
                                "Filter",
                                \.velocitySensitivity.filter,
                                range: 0...99
                            )
                            numberRow(
                                "Release",
                                \.velocitySensitivity.release,
                                range: -50...50
                            )
                            choiceRow(
                                "Release from Note On",
                                keyPath: \.releaseVelocityFromNoteOn
                            )
                        }
                        loudSampleGroup
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .controlSize(.small)
            .padding(12)
        }
        .background(Color.suiteBackground)
    }

    private var playbackGroup: some View {
        group("Playback and Routing") {
            choiceRow("Constant pitch", keyPath: \.constantPitch)
            choiceRow("One-shot", keyPath: \.oneShot)
            numberRow("LFO depth", \.lfoDepth, range: 0...99)
            optionalPickerRow(
                "MIDI channel",
                value: common(\.midiChannelOffset).map { $0 + 1 },
                choices: Array(1...16),
                label: { "\($0)" }
            ) { value in
                apply(\.midiChannelOffset, value: value - 1, name: "Set MIDI Channel")
            }
            optionalPickerRow(
                "Output",
                value: common(\.output),
                choices: P9Output.standardChoices,
                label: \.displayName
            ) { value in
                apply(\.output, value: value, name: "Set Output")
            }
        }
    }

    private var loudSampleGroup: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $loudSampleExpanded) {
                sampleRows(
                    name: \.loudSampleName,
                    loudness: \.loudLoudness,
                    filter: \.loudFilter,
                    transpose: \.loudTuning.transpose,
                    fine: \.loudTuning.fine
                )
                .padding(.top, 8)
            } label: {
                Text("Loud Sample").fontWeight(.medium)
            }
            .padding(6)
        }
    }

    private func sampleGroup(
        _ title: String,
        name: WritableKeyPath<P9Keygroup, String>,
        loudness: WritableKeyPath<P9Keygroup, Int>,
        filter: WritableKeyPath<P9Keygroup, Int>,
        transpose: WritableKeyPath<P9Keygroup, Int>,
        fine: WritableKeyPath<P9Keygroup, Int>
    ) -> some View {
        group(title) {
            sampleRows(
                name: name,
                loudness: loudness,
                filter: filter,
                transpose: transpose,
                fine: fine
            )
        }
    }

    @ViewBuilder
    private func sampleRows(
        name: WritableKeyPath<P9Keygroup, String>,
        loudness: WritableKeyPath<P9Keygroup, Int>,
        filter: WritableKeyPath<P9Keygroup, Int>,
        transpose: WritableKeyPath<P9Keygroup, Int>,
        fine: WritableKeyPath<P9Keygroup, Int>
    ) -> some View {
        optionalPickerRow(
            "Sample",
            value: common(name),
            choices: [""] + availableSampleNames,
            label: { $0.isEmpty ? "No sample" : $0 }
        ) { value in
            apply(name, value: value, name: "Assign Sample")
        }
        numberRow("Loudness", loudness, range: -50...50)
        numberRow("Filter", filter, range: 0...99)
        numberRow("Transpose", transpose, range: P9Tuning.transposeRange)
        numberRow("Fine", fine, range: P9Tuning.fineRange)
    }

    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox(title) {
            VStack(spacing: 7) { content() }
                .padding(6)
        }
    }

    private func numberRow(
        _ title: String,
        _ keyPath: WritableKeyPath<P9Keygroup, Int>,
        range: ClosedRange<Int>,
        accessibilityIdentifier: String? = nil
    ) -> some View {
        let commonValue = common(keyPath)
        let primaryValue = primaryKeygroup?[keyPath: keyPath]
            ?? commonValue
            ?? range.lowerBound
        return HStack(spacing: 8) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            P9MixedBoundedNumberField(
                value: commonValue,
                primaryValue: primaryValue,
                range: range,
                accessibilityIdentifier: accessibilityIdentifier,
                onBegin: { document.beginContinuousEdit(actionName: "Set \(title)") },
                onChange: { apply(keyPath, value: $0, name: "Set \(title)") },
                onEnd: document.endContinuousEdit
            )
            Stepper(
                "",
                value: Binding(
                    get: { primaryValue },
                    set: { apply(keyPath, value: $0, name: "Set \(title)") }
                ),
                in: range
            )
            .labelsHidden()
        }
    }

    private func choiceRow(
        _ title: String,
        keyPath: WritableKeyPath<P9Keygroup, Bool>
    ) -> some View {
        optionalPickerRow(
            title,
            value: common(keyPath),
            choices: [false, true],
            label: { $0 ? "On" : "Off" }
        ) { value in
            apply(keyPath, value: value, name: "Set \(title)")
        }
    }

    private func optionalPickerRow<Value: Hashable>(
        _ title: String,
        value: Value?,
        choices: [Value],
        label: @escaping (Value) -> String,
        onSet: @escaping (Value) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker(
                "",
                selection: Binding<Value?>(
                    get: { value },
                    set: { if let value = $0 { onSet(value) } }
                )
            ) {
                if value == nil { Text("Mixed").tag(Value?.none) }
                ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                    Text(label(choice)).tag(Optional(choice))
                }
            }
            .labelsHidden()
            .frame(width: 190)
        }
    }

    private func common<Value: Equatable>(
        _ keyPath: KeyPath<P9Keygroup, Value>
    ) -> Value? {
        P9SelectionValues.mixedValue(in: keygroups, keyPath).commonValue
    }

    private func apply<Value>(
        _ keyPath: WritableKeyPath<P9Keygroup, Value>,
        value: Value,
        name: String
    ) {
        do {
            try document.performEdit(actionName: name) { program in
                guard selection.allSatisfy(program.keygroups.indices.contains) else {
                    throw P9ProgramError.invalidKeygroup(
                        selection.first(where: {
                            !program.keygroups.indices.contains($0)
                        }) ?? -1
                    )
                }
                for index in selection.sorted() {
                    program.keygroups[index][keyPath: keyPath] = value
                }
            }
        } catch {
            NSSound.beep()
        }
    }
}

private struct P9MixedBoundedNumberField: View {
    let value: Int?
    let primaryValue: Int
    let range: ClosedRange<Int>
    var accessibilityIdentifier: String? = nil
    let onBegin: () -> Void
    let onChange: (Int) -> Void
    let onEnd: () -> Void

    var body: some View {
        P9MixedDraggableNumberTextField(
            value: value,
            primaryValue: primaryValue,
            range: range,
            accessibilityIdentifier: accessibilityIdentifier,
            onBegin: onBegin,
            onChange: onChange,
            onEnd: onEnd
        )
        .frame(width: 58)
        .help(
            "Type or use arrow keys for exact edits; drag from the primary "
                + "keygroup value. Shift drags finely and Option adjusts coarsely."
        )
    }
}

private struct P9MixedDraggableNumberTextField: NSViewRepresentable {
    let value: Int?
    let primaryValue: Int
    let range: ClosedRange<Int>
    let accessibilityIdentifier: String?
    let onBegin: () -> Void
    let onChange: (Int) -> Void
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.alignment = .right
        field.controlSize = .small
        field.font = NSFont(name: "JetBrainsMono-Regular", size: 11)
        field.placeholderString = "Mixed"
        if let accessibilityIdentifier {
            field.setAccessibilityIdentifier(accessibilityIdentifier)
        }
        field.delegate = context.coordinator
        context.coordinator.field = field
        let pan = NSPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.dragged(_:))
        )
        pan.buttonMask = 0x1
        field.addGestureRecognizer(pan)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        guard !context.coordinator.isEditing,
              context.coordinator.dragStartValue == nil
        else { return }
        field.stringValue = value.map(String.init) ?? ""
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: P9MixedDraggableNumberTextField
        weak var field: NSTextField?
        var dragStartValue: Int?
        var isEditing = false
        var editingStartValue: Int?

        init(parent: P9MixedDraggableNumberTextField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
            editingStartValue = parent.value
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            defer {
                isEditing = false
                editingStartValue = nil
                field?.stringValue = parent.value.map(String.init) ?? ""
            }
            guard let field,
                  let value = P9NumericInput.boundedValue(
                    field.stringValue,
                    range: parent.range
                  )
            else { return }
            parent.onChange(value)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                field?.stringValue = editingStartValue.map(String.init) ?? ""
                field?.window?.makeFirstResponder(nil)
                return true
            }
            let direction: Int
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                direction = 1
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                direction = -1
            } else {
                return false
            }
            guard let field else { return true }
            let current = P9NumericInput.boundedValue(
                field.stringValue,
                range: parent.range
            ) ?? parent.value ?? parent.primaryValue
            let modifiers = NSApp.currentEvent?.modifierFlags
                .intersection(.deviceIndependentFlagsMask) ?? []
            let updated = P9NumericInput.incrementedValue(
                from: current,
                direction: direction,
                range: parent.range,
                coarse: modifiers.contains(.option)
            )
            field.stringValue = String(updated)
            editingStartValue = updated
            parent.onChange(updated)
            field.currentEditor()?.selectAll(nil)
            return true
        }

        @objc func dragged(_ recognizer: NSPanGestureRecognizer) {
            guard let field else { return }
            switch recognizer.state {
            case .began:
                dragStartValue = parent.primaryValue
                parent.onBegin()
                field.window?.makeFirstResponder(nil)
            case .changed:
                let modifiers = NSApp.currentEvent?.modifierFlags
                    .intersection(.deviceIndependentFlagsMask) ?? []
                let updated = P9NumericInput.draggedValue(
                    from: dragStartValue ?? parent.primaryValue,
                    verticalTranslation: -recognizer.translation(in: field).y,
                    range: parent.range,
                    pointsPerStep: modifiers.contains(.shift) ? 8 : 2,
                    stepMultiplier: modifiers.contains(.option) ? 10 : 1
                )
                parent.onChange(updated)
                field.stringValue = String(updated)
            case .ended, .cancelled, .failed:
                dragStartValue = nil
                parent.onEnd()
                field.stringValue = parent.value.map(String.init) ?? ""
            default:
                break
            }
        }
    }
}

private struct P9BoundedNumberField: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var accessibilityIdentifier: String? = nil

    var body: some View {
        P9DraggableNumberTextField(
            value: $value,
            range: range,
            accessibilityIdentifier: accessibilityIdentifier
        )
            .frame(width: 58)
            .help("Type a value, drag up or down, or use the arrow buttons")
    }
}

private struct P9DraggableNumberTextField: NSViewRepresentable {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let accessibilityIdentifier: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: String(value))
        field.alignment = .right
        field.controlSize = .small
        field.font = NSFont(name: "JetBrainsMono-Regular", size: 11)
        field.delegate = context.coordinator
        context.coordinator.field = field
        if let accessibilityIdentifier {
            field.setAccessibilityIdentifier(accessibilityIdentifier)
        }

        let pan = NSPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.dragged(_:))
        )
        pan.buttonMask = 0x1
        field.addGestureRecognizer(pan)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        guard !context.coordinator.isEditing,
              context.coordinator.dragStartValue == nil
        else { return }
        let normalized = String(value)
        if field.stringValue != normalized {
            field.stringValue = normalized
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: P9DraggableNumberTextField
        weak var field: NSTextField?
        var dragStartValue: Int?
        var isEditing = false

        init(parent: P9DraggableNumberTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field,
                  let bounded = P9NumericInput.boundedValue(
                    field.stringValue,
                    range: parent.range
                  )
            else { return }
            if parent.value != bounded {
                parent.value = bounded
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isEditing = false
            field?.stringValue = String(parent.value)
        }

        @objc func dragged(_ recognizer: NSPanGestureRecognizer) {
            guard let field else { return }
            switch recognizer.state {
            case .began:
                dragStartValue = parent.value
                field.window?.makeFirstResponder(nil)
            case .changed:
                let startingValue = dragStartValue ?? parent.value
                let updatedValue = P9NumericInput.draggedValue(
                    from: startingValue,
                    verticalTranslation: -recognizer.translation(in: field).y,
                    range: parent.range
                )
                if parent.value != updatedValue {
                    parent.value = updatedValue
                    field.stringValue = String(updatedValue)
                }
            case .ended, .cancelled, .failed:
                dragStartValue = nil
                field.stringValue = String(parent.value)
            default:
                break
            }
        }
    }
}
