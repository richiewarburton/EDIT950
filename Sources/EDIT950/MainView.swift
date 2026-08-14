import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var preferences: SuitePreferences

    var body: some View {
        VStack(spacing: 0) {
            BrowserHeader()
            Divider()
            SuiteZoomContainer {
                FileBrowser()
            }
            Divider()
            StatusBar()
            if model.isLogVisible {
                Divider()
                DiagnosticLogView()
                    .frame(minHeight: 120, idealHeight: 190, maxHeight: 260)
            }
        }
        .background(Color.suiteBackground)
        .environment(\.defaultMinListRowHeight, preferences.density.rowHeight)
        .navigationTitle(model.session?.imageURL.lastPathComponent ?? "EDIT950")
        .toolbar { toolbar }
        .inspector(isPresented: $preferences.inspectorVisible) {
            EditInspector()
                .environmentObject(model)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.handleDroppedURLs(urls)
            return !urls.isEmpty
        } isTargeted: { _ in }
        .sheet(isPresented: $model.showImportSheet) {
            ImportOptionsSheet()
                .environmentObject(model)
                .environmentObject(settings)
        }
        .sheet(isPresented: $model.showFormatSheet) {
            FormatImageSheet()
                .environmentObject(model)
                .environmentObject(settings)
        }
        .sheet(isPresented: $model.showDiskInfo) {
            DiskInfoSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showTagManager) {
            TagManagerView()
                .environmentObject(model)
        }
        .sheet(item: $model.fileInformation) { information in
            AkaiFileInformationSheet(information: information)
        }
        .sheet(item: $model.focusedExportPresentation) { presentation in
            FocusedExportSheet(
                presentation: presentation,
                onExport: { destination, openInPLAY950 in
                    model.beginFocusedExport(
                        destination,
                        openInPLAY950: openInPLAY950
                    )
                },
                onCancel: model.cancelFocusedExport
            )
            .environmentObject(model)
        }
        .sheet(item: $model.collectionExportPresentation) { presentation in
            CollectionExportSheet(
                presentation: presentation,
                onExport: { url, preset in
                    model.beginCollectionExport(url, preset: preset)
                },
                onCancel: model.cancelCollectionExport
            )
        }
        .sheet(item: $model.p9EditorDocument) { document in
            P9EditorSheet(
                document: document,
                keygroupTransfer: model.keygroupTransfer,
                availableSampleNames: model.availableSampleNames,
                onCopyKeygroups: { program, indexes, source in
                    model.copyKeygroups(
                        from: program,
                        indexes: indexes,
                        source: source
                    )
                },
                onPasteKeygroups: { destination in
                    model.pasteKeygroups(into: destination)
                },
                onOverwriteP9: { document, createBackup in
                    model.overwriteP9InImage(
                        document,
                        createBackup: createBackup
                    )
                },
                onCreateP9InImage: { document in
                    model.createP9InImage(document)
                },
                onChooseAbletonDrumRack: { document in
                    model.chooseAbletonDrumRack(for: document)
                },
                onImportAbletonDrumRack: { draft, document in
                    model.importAbletonDrumRack(draft, into: document)
                }
            )
        }
        .sheet(item: $model.externalSampleEditSession) { editSession in
            ExternalSampleEditSheet(editSession: editSession)
                .environmentObject(model)
                .environmentObject(settings)
        }
        .alert(item: Binding(
            get: { model.report?.isError == true ? model.report : nil },
            set: { model.report = $0 }
        )) { report in
            let message = report.lines.joined(separator: "\n")
            if message.localizedCaseInsensitiveContains("Full Disk Access") {
                return Alert(
                    title: Text(report.title),
                    message: Text(message),
                    primaryButton: .default(Text("Open Full Disk Access")) {
                        model.dismissReport()
                        AppSettings.openFullDiskAccessSettings()
                    },
                    secondaryButton: .cancel(Text("OK")) {
                        model.dismissReport()
                    }
                )
            } else {
                return Alert(
                    title: Text(report.title),
                    message: Text(message),
                    dismissButton: .default(Text("OK")) {
                        model.dismissReport()
                    }
                )
            }
        }
        .alert("Delete selected files permanently?", isPresented: $model.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                model.showDeleteConfirmation = false
            }
            Button("Delete", role: .destructive) { model.deleteSelected() }
        } message: {
            Text(model.selectedFiles.map { "\($0.index). \($0.name)" }.joined(separator: "\n")
                 + "\n\nEDIT950 creates a verified timestamped backup. Undo restores the image and its shared tags.")
        }
        .sheet(isPresented: $model.showDeleteAllConfirmation) {
            DeleteAllSheet()
                .environmentObject(model)
                .environmentObject(settings)
        }
        .alert("Formatting did not complete", isPresented: Binding(
            get: { model.incompleteImageURL != nil },
            set: { if !$0 { model.incompleteImageURL = nil } }
        )) {
            Button("Keep File", role: .cancel) { model.incompleteImageURL = nil }
            Button("Delete Incomplete Image", role: .destructive) { model.removeIncompleteImage() }
        } message: {
            Text("The newly created image could not be verified. Delete \(model.incompleteImageURL?.lastPathComponent ?? "it")?")
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            model.reloadSharedTags()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: model.openPanel) {
                Label("OPEN", systemImage: "folder")
            }
            .help("Open an AKAI disk image (⌘O)")

            Button { model.showFormatSheet = true } label: {
                Label("NEW", systemImage: "plus.rectangle.on.rectangle")
            }
            .help("Create or format an image")

            Button(action: model.importPanel) {
                Label("IMPORT", systemImage: "square.and.arrow.down")
            }
            .disabled(!model.canImport)
            .help("Import WAV, S9 or P9 files")

            Button(action: model.exportSelected) {
                Label("EXPORT", systemImage: "square.and.arrow.up")
            }
            .disabled(!model.canExport)
            .help("Export selected samples to WAV, or selected P9 programs as native files")

        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: model.editSelectedP9) {
                Label("Edit P9", systemImage: "slider.horizontal.3")
            }
            .disabled(!model.canEditSelectedP9)
            .help("Open the selected P9 in the safe keygroup editor")

            Button(action: model.createP9Program) {
                Label("New Program", systemImage: "doc.badge.plus")
            }
            .disabled(!model.canCreateP9Program)
            .help("Create a new S950 program with one blank keygroup")

            Button(action: model.editSelectedSampleInAudioEditor) {
                Label("Edit Sample", systemImage: "waveform.badge.pencil")
            }
            .disabled(!model.canEditSelectedS9Sample)
            .help("Edit one selected S950 sample and optionally open its WAV in an audio editor")

        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: model.refreshAction) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.session == nil || model.isBusy)
            .help("Refresh disks, volumes and files (⌘R)")

            Button {
                model.showDiskInfo = true
            } label: {
                Label("Disk Info", systemImage: "info.circle")
            }
            .disabled(model.session == nil || model.isBusy)
            .help("Show parsed disk information and diagnostics")

            Button(action: model.backupImage) {
                Label("Backup", systemImage: "externaldrive.badge.timemachine")
            }
            .disabled(model.session == nil || model.isBusy)
            .help("Create a verified timestamped backup of the open image")

            Button(action: model.cleanEject) {
                Label("Safe Eject", systemImage: "eject")
            }
            .disabled(
                model.session?.isRemovable != true
                    || model.isBusy
            )
            .help("Clean metadata, then safely eject the mounted removable volume")

            Button {
                model.showTagManager = true
            } label: {
                Label("Tags", systemImage: "tag")
            }
            .help("Create and edit tags shared with FIND950")

            EditToolbarVisibilityButton(
                title: preferences.inspectorVisible
                    ? "Hide Inspector" : "Show Inspector",
                symbol: "sidebar.right",
                isSelected: preferences.inspectorVisible
            ) {
                preferences.inspectorVisible.toggle()
            }
        }

        if model.canMutate, !model.selectedFiles.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                Button(action: model.requestDeleteSelected) {
                    Label("Delete", systemImage: "trash")
                        .foregroundStyle(Color.suiteRed)
                }
                .help("Permanently delete selected files")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("New S950 Program…") {
                    model.createP9Program()
                }
                .disabled(!model.canCreateP9Program)
                Button("New Program from Copied Keygroups…") {
                    model.createP9FromCopiedKeygroups()
                }
                .disabled(!model.canCreateP9FromCopiedKeygroups)
                Divider()
                Button("Disk Information…") { model.showDiskInfo = true }
                Button("Create Timestamped Backup") { model.backupImage() }
                    .disabled(model.session == nil)
                Divider()
                Button("Repair Selected Internal Sample Names") { model.fixSelectedRAMNames() }
                    .disabled(!model.canMutate || model.selectedFiles.isEmpty)
                Button("Repair All Internal Sample Names") { model.fixAllRAMNames() }
                    .disabled(!model.canMutate)
                Divider()
                Button("Delete All Files in Volume…", role: .destructive) {
                    model.showDeleteAllConfirmation = true
                }
                .disabled(!model.canMutate || model.snapshot.files.isEmpty)
                Divider()
                if model.session?.isRemovable == true {
                    Button("Clean and Safely Eject") { model.cleanEject() }
                }
                if let destination = model.usbCopyDestination {
                    Button("Copy to \(destination.deletingLastPathComponent().lastPathComponent) and Eject…") {
                        confirmUSBCopy(destination)
                    }
                }
                Toggle("Diagnostic Log", isOn: $model.isLogVisible)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .disabled(model.session == nil && !model.isLogVisible)
            .help("More image, repair, deletion and diagnostic actions")
        }
    }

    private func confirmUSBCopy(_ destination: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Replace the USB image?"
        alert.informativeText = "Source:\n\(model.session?.imageURL.path ?? "")\n\nDestination:\n\(destination.path)\n\nAKAI Util will close before the verified copy begins."
        alert.addButton(withTitle: "Copy and Replace")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { model.copyToUSBAndEject() }
    }
}

private struct EditToolbarVisibilityButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title.uppercased(), systemImage: symbol)
                .font(SuiteFont.regular(11))
                .tracking(1.2)
                .foregroundStyle(Color.suiteInk)
                .padding(.horizontal, 8)
                .frame(minHeight: 30)
                .background(buttonBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.suiteYellow : Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(title)
    }

    private var buttonBackground: Color {
        if hovering { return Color.suiteSlab2 }
        if isSelected { return Color.suiteYellow.opacity(0.2) }
        return Color.suiteSlab
    }
}

private struct BrowserHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: SuiteBrandAsset.image(named: "EDIT950-brand-mark"))
                .resizable()
                .interpolation(.high)
                .frame(width: 42, height: 42)
                .fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                Text("EDIT950")
                    .font(SuiteFont.bold(17))
                    .tracking(4.1)
                Text("CREATE · EDIT · VERIFY")
                    .font(SuiteFont.regular(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.suiteUnit)
            }
            .fixedSize(horizontal: true, vertical: true)
            .layoutPriority(2)
            if let notice = model.headerNotice {
                Divider().frame(height: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Label(notice.title, systemImage: notice.systemImage)
                        .font(SuiteFont.medium(11))
                        .foregroundStyle(Color.suiteGreen)
                        .lineLimit(1)
                    Text(notice.detail)
                        .font(SuiteFont.regular(9))
                        .foregroundStyle(Color.suiteUnit)
                        .lineLimit(1)
                }
            }
            Spacer()
            if model.session != nil {
                if model.snapshot.volumes.count > 1 {
                    Menu {
                        ForEach(model.snapshot.volumes) { volume in
                            Button {
                                model.navigate(to: volume)
                            } label: {
                                if model.snapshot.currentPath == volume.path {
                                    Label(volume.name, systemImage: "checkmark")
                                } else {
                                    Text(volume.name)
                                }
                            }
                        }
                    } label: {
                        SuiteMenuLabel(title: currentVolumeName, systemImage: "folder")
                    }
                    .menuStyle(.borderlessButton)
                    .help("Choose an S950 volume")
                }
                Menu {
                    ImageTagMenuContent()
                } label: {
                    SuiteMenuLabel(title: "TAGS", systemImage: "tag")
                }
                .menuStyle(.borderlessButton)
                .help("Tag this IMG in EDIT950 and FIND950")
                Button(action: model.closeImage) {
                    Label("CLOSE IMG", systemImage: "xmark.circle")
                }
                .buttonStyle(SuiteSecondaryButtonStyle())
                .disabled(model.isBusy)
                .help("Close the current IMG (⌘W)")
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(model.snapshot.fileCount) FILES")
                        .font(SuiteFont.medium(19))
                        .monospacedDigit()
                    Text("\(model.snapshot.freeBytes.formattedByteCount.uppercased()) FREE")
                        .font(SuiteFont.regular(10))
                        .tracking(1.4)
                        .foregroundStyle(Color.suiteUnit)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 72)
        .background(Color.suitePanel)
    }

    private var currentVolumeName: String {
        model.snapshot.volumes.first {
            $0.path == model.snapshot.currentPath
        }?.name ?? "Choose Volume"
    }
}

private struct FileBrowser: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("EDIT950.table.columns") private var columnCustomization = TableColumnCustomization<AkaiFile>()

    var body: some View {
        Group {
            if model.session == nil {
                RecentImagesDashboard()
            } else if model.snapshot.files.isEmpty {
                if model.session?.readOnly == true {
                    SuiteEmptyState(
                        systemImage: "waveform.badge.plus",
                        title: "THIS VOLUME IS EMPTY",
                        message: "The image is open read-only.",
                        actionTitle: nil,
                        action: nil
                    )
                } else {
                    SuiteEmptyState(
                        systemImage: "waveform.badge.plus",
                        title: "THIS VOLUME IS EMPTY",
                        message: "Drop WAV, S9 or P9 files here, or import samples and programs.",
                        actionTitle: "IMPORT SAMPLES…",
                        action: { model.importPanel() }
                    )
                }
            } else {
                Table(
                    model.displayedFiles,
                    selection: $model.selection,
                    sortOrder: $model.fileSortOrder,
                    columnCustomization: $columnCustomization
                ) {
                    identityColumns
                    metadataColumns
                    storageColumns
                }
                .background(Color.suiteBackground)
                .tint(Color.suiteYellow)
                .accentColor(Color.suiteYellow)
                .background(
                    NativeTableKeyboardMonitor {
                        model.handleSpaceForFileTable()
                    }
                )
                .background(
                    NativeTableDoubleClickMonitor { row in
                        guard model.displayedFiles.indices.contains(row) else {
                            return
                        }
                        model.openEditor(for: model.displayedFiles[row])
                    }
                )
                .contextMenu(forSelectionType: AkaiFile.ID.self) { selection in
                    let selectedFiles = model.snapshot.files.filter {
                        selection.contains($0.id)
                    }
                    Menu("TAGS", systemImage: "tag") {
                        FileTagMenuContent(files: selectedFiles)
                    }
                    .disabled(selectedFiles.isEmpty)
                    Divider()
                    Button(
                        model.auditioningSampleID != nil
                            ? "STOP SAMPLE AUDITION"
                            : "AUDITION SAMPLE"
                    ) {
                        model.auditionSample(withIDs: selection)
                    }
                    .disabled(
                        selection.count != 1
                            || !model.snapshot.files.contains {
                                selection.contains($0.id) && $0.isSample
                            }
                            || model.session == nil
                            || model.isBusy
                    )
                    Button("EDIT P9 KEYGROUPS…") {
                        model.editP9(withIDs: selection)
                    }
                    .disabled(!model.containsSingleP9(withIDs: selection))
                    Button("EDIT SAMPLE…") {
                        model.editSelectedSampleInAudioEditor()
                    }
                    .disabled(
                        selection.count != 1
                            || !model.canEditSelectedS9Sample
                    )
                    Button("EXPORT SELECTED…") {
                        model.exportSelected(withIDs: selection)
                    }
                    .disabled(!model.snapshot.files.contains {
                        selection.contains($0.id)
                            && ($0.isSample
                                || ($0.name as NSString).pathExtension.uppercased()
                                    == "P9")
                    })
                    Button("EXPORT P9 AS ABLETON DRUM RACK…") {
                        model.exportP9ToAbleton(withIDs: selection)
                    }
                    .disabled(
                        !model.canExportP9ToAbleton(withIDs: selection)
                    )
                    Button("COPY ORIGINAL S9/P9 FILES…") {
                        model.copyNativeFiles(withIDs: selection)
                    }
                    .disabled(!model.containsNativeFile(withIDs: selection))
                    Button("FILE INFORMATION…") {
                        model.showFileInformation(withIDs: selection)
                    }
                    .disabled(!model.containsSingleFile(withIDs: selection))
                    Button("RENAME S9/P9…") {
                        model.renameNativeFile(withIDs: selection)
                    }
                    .disabled(
                        !model.containsSingleRenameableNativeFile(
                            withIDs: selection
                        )
                    )
                    Button("REPAIR INTERNAL SAMPLE NAME") { model.fixSelectedRAMNames() }
                        .disabled(selection.isEmpty || !model.canMutate)
                    Divider()
                    Button("DELETE…", role: .destructive) { model.requestDeleteSelected() }
                        .disabled(selection.isEmpty || !model.canMutate)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @TableColumnBuilder<AkaiFile, KeyPathComparator<AkaiFile>>
    private var identityColumns: some TableColumnContent<AkaiFile, KeyPathComparator<AkaiFile>> {
        TableColumn("#", value: \.index) { file in
            tableCell(file) {
                Text(file.index.formatted())
                    .monospacedDigit()
                    .foregroundStyle(
                        model.selection.contains(file.id)
                            ? Color.suiteOnYellow : Color.suiteUnit
                    )
            }
        }
        .width(min: 38, ideal: 46, max: 58)
        .customizationID("index")
        TableColumn("") { file in
            tableCell(file, alignment: .center) {
                EditAuditionCell(file: file, model: model)
            }
        }
            .width(min: 30, ideal: 34, max: 38)
            .customizationID("audition")
        TableColumn("") { file in
            tableCell(file, alignment: .center) {
                EditTypeGlyph(file: file).frame(maxWidth: .infinity)
            }
        }
            .width(min: 24, ideal: 24, max: 24)
            .customizationID("type-icon")
        TableColumn("Name", value: \.name) { file in
            tableCell(file) {
                FileNameCell(
                    file: file,
                    selected: model.selection.contains(file.id)
                )
            }
        }
            .width(min: 100, ideal: 260, max: 640)
            .customizationID("name")
    }

    @TableColumnBuilder<AkaiFile, KeyPathComparator<AkaiFile>>
    private var metadataColumns: some TableColumnContent<AkaiFile, KeyPathComparator<AkaiFile>> {
        TableColumn("Tags") { file in
            tableCell(file) {
                HStack(spacing: 6) {
                    TagChipsView(tags: model.tags(for: file))
                    Spacer(minLength: 2)
                    Menu("Tags", systemImage: "tag") { FileTagMenuContent(files: [file]) }
                        .labelStyle(.iconOnly).menuStyle(.borderlessButton)
                }
            }
        }
        .width(min: 90, ideal: 180, max: 360)
        .customizationID("tags")
        TableColumn("Type", value: \.type) { file in
            tableCell(file) {
                Text(file.type.uppercased())
                    .font(SuiteFont.regular(10))
                    .tracking(1.4)
                    .foregroundStyle(
                        model.selection.contains(file.id)
                            ? Color.suiteOnYellow : Color.suiteUnit
                    )
            }
        }
        .width(min: 64, ideal: 96, max: 180)
        .customizationID("type")
        TableColumn("S9 Rate", value: \.sampleRateSortValue) { file in
            tableCell(file) {
                EditSampleRateCell(
                    file: file,
                    selected: model.selection.contains(file.id)
                )
            }
        }
            .width(min: 72, ideal: 104, max: 180)
            .customizationID("sample-rate")
        TableColumn("Size", value: \.byteSize) { file in
            tableCell(file) {
                Text(file.byteSize.formattedByteCount).monospacedDigit()
            }
        }
            .width(min: 68, ideal: 96, max: 180)
            .customizationID("size")
    }

    @TableColumnBuilder<AkaiFile, KeyPathComparator<AkaiFile>>
    private var storageColumns: some TableColumnContent<AkaiFile, KeyPathComparator<AkaiFile>> {
        TableColumn("Start Block", value: \.startBlockSortValue) { file in
            tableCell(file) {
                EditStartBlockCell(
                    file: file,
                    selected: model.selection.contains(file.id)
                )
            }
        }
            .width(min: 76, ideal: 108, max: 200)
            .customizationID("start-block")
        TableColumn("Compression", value: \.compressionSortValue) { file in
            tableCell(file) { EditCompressionCell(file: file) }
        }
            .width(min: 78, ideal: 116, max: 220)
            .customizationID("compression")
        TableColumn("") { file in
            tableCell(file, alignment: .center) {
                NativeFileDragCell(
                    file: file,
                    model: model,
                    selected: model.selection.contains(file.id)
                )
            }
        }
            .width(min: 32, ideal: 32, max: 32)
            .customizationID("native-drag")
    }

    private func tableCell<Content: View>(
        _ file: AkaiFile,
        alignment: Alignment = .leading,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        SuiteTableCell(
            selected: model.selection.contains(file.id),
            alignment: alignment,
            content: content
        )
    }
}

private struct RecentImageRow: Identifiable, Hashable {
    let url: URL
    let modifiedAt: Date?
    let byteSize: Int64?

    var id: String { url.standardizedFileURL.path }
    var name: String { url.lastPathComponent }
    var location: String { url.deletingLastPathComponent().path }

    init(url: URL) {
        self.url = url
        let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey
        ])
        modifiedAt = values?.contentModificationDate
        byteSize = values?.fileSize.map(Int64.init)
    }
}

private struct RecentImagesDashboard: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedID: RecentImageRow.ID?
    @State private var hintIndex = 0
    @State private var didChooseOpeningHint = false

    private var rows: [RecentImageRow] {
        model.recentImages.map(RecentImageRow.init)
    }

    private var selectedURL: URL? {
        rows.first { $0.id == selectedID }?.url
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                welcome
                recentTable
                actions
                hintCard
            }
            .frame(maxWidth: 1120)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Color.suiteBackground)
        .onAppear {
            selectFirstAvailableRow()
            chooseOpeningHintIfNeeded()
        }
        .onChange(of: rows.map(\.id)) { _, _ in
            selectFirstAvailableRow()
        }
    }

    private var welcome: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.suiteSlab)
                Image(systemName: "opticaldiscdrive.fill")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(Color.suiteBlue)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text("WELCOME TO EDIT950")
                    .font(SuiteFont.medium(18))
                    .tracking(3.1)
                Text("Choose a recent AKAI image, open another one, or create a fresh working disk.")
                    .font(SuiteFont.regular(11))
                    .foregroundStyle(Color.suiteUnit)
            }
            Spacer(minLength: 20)
            Button("LOAD ANOTHER IMG…", action: model.openPanel)
                .buttonStyle(SuitePrimaryButtonStyle(role: .neutral))
        }
    }

    private var recentTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RECENTLY LOADED IMAGES")
                    .font(SuiteFont.medium(11))
                    .tracking(2.2)
                    .foregroundStyle(Color.suiteLabel)
                Spacer()
                Text("\(rows.count) RECENT")
                    .font(SuiteFont.regular(9))
                    .tracking(1.2)
                    .foregroundStyle(Color.suiteUnit)
            }

            Table(rows, selection: $selectedID) {
                TableColumn("IMG") { row in
                    HStack(spacing: 8) {
                        Image(systemName: "opticaldisc")
                            .foregroundStyle(Color.suiteBlue)
                        Text(row.name)
                            .font(SuiteFont.medium(11))
                            .lineLimit(1)
                    }
                }
                .width(min: 170, ideal: 260)

                TableColumn("LOCATION") { row in
                    Text(row.location)
                        .font(SuiteFont.regular(10))
                        .foregroundStyle(Color.suiteUnit)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .width(min: 230, ideal: 480)

                TableColumn("MODIFIED") { row in
                    Text(modifiedText(for: row))
                        .font(SuiteFont.regular(10))
                        .foregroundStyle(Color.suiteLabel)
                        .monospacedDigit()
                }
                .width(min: 135, ideal: 155, max: 180)

                TableColumn("SIZE") { row in
                    Text(row.byteSize?.formattedByteCount ?? "—")
                        .font(SuiteFont.regular(10))
                        .foregroundStyle(Color.suiteLabel)
                        .monospacedDigit()
                }
                .width(min: 72, ideal: 90, max: 120)
            }
            .background(
                NativeTableDoubleClickMonitor { row in
                    guard rows.indices.contains(row) else { return }
                    model.openRecent(rows[row].url)
                }
            )
            .frame(minHeight: 160, idealHeight: 220, maxHeight: 250)
            .overlay {
                if rows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 24))
                        Text("NO RECENT IMAGES YET")
                            .font(SuiteFont.medium(11))
                            .tracking(1.8)
                        Text("Load an IMG and it will appear here next time.")
                            .font(SuiteFont.regular(10))
                            .foregroundStyle(Color.suiteUnit)
                    }
                }
            }
            .background(Color.suitePanel)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.suiteRule2, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 9) {
                contextualActionButtons
                Spacer(minLength: 0)
                createNewButton
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    contextualActionButtons
                    Spacer(minLength: 0)
                }
                HStack {
                    Spacer()
                    createNewButton
                }
            }
        }
    }

    @ViewBuilder
    private var contextualActionButtons: some View {
        Group {
            Button {
                if let selectedURL { model.openRecent(selectedURL) }
            } label: {
                Label("LOAD", systemImage: "folder.fill")
            }
            .buttonStyle(SuitePrimaryButtonStyle(role: .sample))
            .disabled(selectedURL == nil || model.isBusy)

            Button {
                if let selectedURL { model.createCopyAndOpen(selectedURL) }
            } label: {
                Label("CREATE COPY AND LOAD", systemImage: "doc.on.doc")
            }
            .buttonStyle(SuiteSecondaryButtonStyle())
            .disabled(selectedURL == nil || model.isBusy)

            Button {
                if let selectedURL { model.openInFIND950(selectedURL) }
            } label: {
                SuiteLauncherLabel(target: .find, title: "OPEN IN FIND")
            }
            .buttonStyle(SuiteSecondaryButtonStyle())
            .disabled(selectedURL == nil || model.isBusy)

            Button {
                if let selectedURL { model.sendToPLAY950(selectedURL) }
            } label: {
                SuiteLauncherLabel(target: .play, title: "SEND TO PLAY")
            }
            .buttonStyle(SuiteSecondaryButtonStyle())
            .disabled(selectedURL == nil || model.isBusy)
        }
    }

    private var createNewButton: some View {
        Button {
            model.showFormatSheet = true
        } label: {
            Label("CREATE NEW", systemImage: "plus.rectangle.on.rectangle")
        }
        .buttonStyle(SuitePrimaryButtonStyle(role: .neutral))
        .disabled(model.isBusy)
    }

    private var hintCard: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.suiteAmber)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 5) {
                Text("EDIT950 HINT · \(hintIndex + 1) OF \(Edit950HintStore.hints.count)")
                    .font(SuiteFont.medium(9))
                    .tracking(1.5)
                    .foregroundStyle(Color.suiteAmber)
                Text(Edit950HintStore.hints[hintIndex])
                    .font(SuiteFont.regular(11))
                    .foregroundStyle(Color.suiteLabel)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                hintButton(systemImage: "chevron.left", delta: -1, label: "Previous hint")
                hintButton(systemImage: "chevron.right", delta: 1, label: "Next hint")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(Color.suiteSlab)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.suiteRule, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func hintButton(
        systemImage: String,
        delta: Int,
        label: String
    ) -> some View {
        Button {
            showHint(offsetBy: delta)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(SuiteSecondaryButtonStyle())
        .accessibilityLabel(label)
    }

    private func selectFirstAvailableRow() {
        guard selectedID == nil || !rows.contains(where: { $0.id == selectedID }) else {
            return
        }
        selectedID = rows.first?.id
    }

    private func chooseOpeningHintIfNeeded() {
        guard !didChooseOpeningHint else { return }
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: Edit950HintStore.defaultsKey) as? Int ?? -1
        hintIndex = Edit950HintStore.normalized(previous + 1)
        defaults.set(hintIndex, forKey: Edit950HintStore.defaultsKey)
        didChooseOpeningHint = true
    }

    private func showHint(offsetBy offset: Int) {
        hintIndex = Edit950HintStore.normalized(hintIndex + offset)
        UserDefaults.standard.set(hintIndex, forKey: Edit950HintStore.defaultsKey)
    }

    private func modifiedText(for row: RecentImageRow) -> String {
        guard let date = row.modifiedAt else { return "—" }
        return date.formatted(
            .dateTime
                .year()
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
    }
}

private enum Edit950HintStore {
    static let defaultsKey = "EDIT950.welcomeHintIndex"

    static let hints: [String] = {
        let groups: [[String]] = [
            [
                "Open archival IMGs read-only when you only need to browse, audition or export.",
                "Create a working copy before experimenting with an irreplaceable sampler disk.",
                "EDIT950 never formats a physical floppy drive; it works with image files instead.",
                "Standard S900 and S950 IMG files are the best starting point for an editing session.",
                "Convert HFE, SCP and raw flux captures to a supported IMG before opening them here.",
                "A recent IMG is only listed while its file still exists at the remembered location.",
                "Use Create Copy and Load when the archive should remain untouched.",
                "The read-only choice applies to both the Open panel and the recent-image Load button.",
                "Drag a supported IMG onto the window to open it without using the Open panel.",
                "Close the current IMG to return to this recent-images launch screen."
            ],
            [
                "The volume menu in the header moves between volumes on a multi-volume image.",
                "Click a table heading to sort files by name, type, size or stored metadata.",
                "Use the Inspector for contextual actions and details about the current selection.",
                "The Disk Information sheet shows parsed disk, partition and volume diagnostics.",
                "Refresh rereads the current image after an external change.",
                "The status bar reports the current operation and offers cancellation when supported.",
                "Comfortable table density gives each file more vertical space; Dense shows more rows.",
                "Display zoom changes the IMG browser while the app header remains stable and readable.",
                "The current volume name appears in the header when an image contains several volumes.",
                "The header always shows the file count and remaining image capacity for an open IMG."
            ],
            [
                "Press Space with one S9 selected to start or stop its audition.",
                "The play icon beside an S9 gives quick one-shot audition from the file table.",
                "Sample auditions use temporary, session-scoped WAV exports and do not change the IMG.",
                "Looping auditions follow the S9 playback mode and its valid stored loop points.",
                "The sample editor can audition root pitch, direction, mode and bandwidth together.",
                "Only one sample audition plays at a time; starting another replaces the current one.",
                "If an edited sample sounds stale, Refresh rebuilds the session audition cache.",
                "A cache failure never rolls back a native IMG edit that has already been verified.",
                "Reverse playback can be auditioned before committing the S9 replacement.",
                "Alternating-loop audition reverses direction at each loop boundary."
            ],
            [
                "Exported S9 audio is written as WAV while the native sample remains in the IMG.",
                "Valid native loop positions are preserved as labelled markers in exported WAV files.",
                "Select several S9 files to export a group of samples in one operation.",
                "Copy Original S9 preserves the sampler-native file instead of converting it to WAV.",
                "Use File Information to inspect an S9 before deciding how to export it.",
                "Export destinations can be revealed automatically when that preference is enabled.",
                "An exported WAV is a convenient safety reference before editing a native sample.",
                "The sample rate column helps identify mixed-rate material before batch export.",
                "Native S9 exports keep their exact sampler-visible filename casing.",
                "Drag the native-file handle to promise selected S9 or P9 files directly to Finder."
            ],
            [
                "The sample editor can change root note without changing the sample duration.",
                "Forward and Reverse control the native S9 playback direction.",
                "One-shot, Loop and Alternating loop map to the S950's native playback modes.",
                "Use the zero-crossing arrows to move loop boundaries away from audible clicks.",
                "The loop-point arrow buttons have a larger hit area than their visible chevrons.",
                "You can type exact sample positions or use the numeric steppers for fine adjustment.",
                "Refresh Loop Points rereads marker edits saved by your external WAV editor.",
                "Save over the temporary WAV in the external editor; do not move it or use Save As.",
                "Replacement keeps the original sampler-visible sample name so P9 references survive.",
                "Audition Current Settings lets you check a proposed S9 edit before replacement."
            ],
            [
                "S950 Audio Bandwidth is not the same number as the actual sample rate.",
                "Actual sample rate equals the S950 bandwidth value multiplied by 2.5.",
                "A bandwidth of 3,000 corresponds to an actual sample rate of 7,500 samples per second.",
                "A bandwidth of 19,200 corresponds to an actual sample rate of 48,000 samples per second.",
                "Clean bandwidth conversion removes frequencies that cannot survive the lower rate.",
                "Raw bandwidth conversion omits the anti-alias filter for deliberate grit and aliasing.",
                "Bandwidth conversion preserves pitch and duration by genuinely resampling the audio.",
                "The sample editor estimates IMG memory savings before you replace the S9.",
                "Stored loop positions are scaled when bandwidth conversion changes sample length.",
                "Audition both Clean and Raw conversion when choosing character matters more than size."
            ],
            [
                "A P9 program describes keygroups and points them at native S9 sample names.",
                "Double-click a P9 row to open its keygroup editor.",
                "Open a standalone P9 from Finder when you want to inspect it outside an IMG.",
                "The P9 editor shows Soft and Loud layers, ranges, tuning, filter and envelopes.",
                "A blank S950 program begins with one keygroup ready for assignment.",
                "Overwrite P9 writes a verified edited program back into its source IMG.",
                "Create P9 in Image adds a standalone edited program to the open writable volume.",
                "Copy Original P9 exports the native program without translating its structure.",
                "File Information can reveal useful native details before a P9 edit.",
                "Send a selected P9 to PLAY950 to hear it with all of its linked S9 samples."
            ],
            [
                "A keygroup maps a keyboard and velocity range to Soft and Loud sample layers.",
                "Soft and Loud sample names must match sampler-visible S9 names in the image.",
                "Velocity ranges decide when a keygroup switches between its Soft and Loud layers.",
                "Key ranges decide which MIDI notes can trigger a keygroup.",
                "The MIDI monitor highlights matching keygroups but sends no MIDI and produces no audio.",
                "Copy keygroups to move a carefully programmed zone into another writable image.",
                "Linked samples can travel with copied keygroups when the destination needs them.",
                "A keygroup output assignment routes that zone to the selected S950 output.",
                "Filter and envelope values can be inspected without translating the P9 to another format.",
                "Check both sample layers when a program behaves differently at higher velocity."
            ],
            [
                "Select several keygroups before applying the same controlled edit to all of them.",
                "Bulk tuning changes are useful for retuning a layered instrument consistently.",
                "Bulk release changes can lengthen or shorten the tail of a whole program.",
                "Bulk filter changes can make several zones brighter or darker together.",
                "Bulk output changes can route a group of keygroups to another S950 output.",
                "Chromatic spread assigns samples across consecutive notes with tuning compensation.",
                "Review the selected keygroup count before committing a broad edit.",
                "Copy only the keygroups you need when building a smaller performance disk.",
                "A controlled bulk edit preserves fields that the chosen operation does not own.",
                "Use Undo after a verified native edit when you need the previous IMG state back."
            ],
            [
                "Import accepts compatible WAV, native S9 and native P9 files on a writable S950 volume.",
                "A WAV can be converted to mono during import when the source contains two channels.",
                "Preserve Sample Rate keeps a compatible WAV's rate instead of choosing another one.",
                "Create Unique Name avoids replacing an existing sampler-visible name during import.",
                "Skip leaves an existing same-name file untouched during a batch import.",
                "Replace should be used only when you intend to overwrite a same-name native file.",
                "Import is disabled for read-only images and when no writable S950 volume is selected.",
                "Drop WAV, S9 or P9 files onto an open writable image to begin importing them.",
                "Paths containing spaces are staged safely because AKAI Util cannot quote them itself.",
                "Check remaining IMG capacity before importing a large group of samples."
            ],
            [
                "Import a suitable Ableton Drum Rack to build native S9 samples and a P9 program.",
                "Ableton import supports one distinct sample zone per occupied Sampler or Drum Rack pad.",
                "Export P9 as Ableton Drum Rack uses the program's Soft sample layer.",
                "A ranged P9 keygroup maps to its Low note during Ableton Drum Rack export.",
                "The exported Ableton rack targets Live 12.4.3 Sampler compatibility.",
                "Review pad and sample mappings before importing an Ableton rack into an IMG.",
                "Ableton export gathers the linked Soft samples needed by the P9.",
                "A focused export can build a smaller verified IMG for one chosen program.",
                "A collection export can gather selected programs and dependencies into a working image.",
                "Open a verified focused export in PLAY950 immediately when the export sheet offers it."
            ],
            [
                "Tags are stored outside the IMG, so they do not consume sampler disk space.",
                "EDIT950 and FIND950 can share the same versioned tag index.",
                "Tag the open IMG from the header's Tags menu.",
                "Apply one tag to several selected native files in a single step.",
                "P9 and S9 tag chips appear in their dedicated file-table column.",
                "A verified native rename moves the matching shared tag assignment with the file.",
                "Deleting a native file removes its obsolete tag assignment after verification.",
                "Export the shared tag index when you want a portable JSON backup.",
                "The shared tag location can live in a synced folder, but avoid simultaneous edits on two Macs.",
                "Tags help FIND950 locate related disks, programs and samples across a large archive."
            ],
            [
                "Create Backup writes a timestamped, checksum-verified copy of the open IMG.",
                "Verified native mutations are serialized so two writes cannot overlap.",
                "Supported replacements are staged before the original IMG is changed.",
                "When a verified operation fails, EDIT950 restores its backup when one is available.",
                "Rename and focused-export workflows create and verify complete backups.",
                "Supported native edits are re-exported and byte-compared after writing.",
                "Delete All requires typing DELETE ALL and offers a full backup first.",
                "The source IMG remains unchanged until a focused export's final publication step.",
                "A checksum-matched copy is safer than duplicating an IMG during another write operation.",
                "Keep archival masters read-only and use clearly named working copies for experiments."
            ],
            [
                "Use a verified working IMG with a Gotek or compatible USB floppy emulator.",
                "Safe Eject is enabled only when the open IMG belongs to mounted removable media.",
                "Safe Eject cleans configured metadata and asks macOS to unmount the volume.",
                "Wait for the success message before unplugging removable media.",
                "A 1.6 MB image offers more working capacity than an 800 KB image.",
                "Create New can prepare a focused disk for one live set or song.",
                "A smaller working disk can make a hardware library easier to navigate on stage.",
                "Keep the original capture separate from any IMG copied to removable media.",
                "EDIT950 intentionally does not expose physical-drive formatting commands.",
                "Use the exact mounted USB destination check before replacing an emulator image."
            ],
            [
                "FIND950 is the quickest place to search a large collection before editing an IMG.",
                "Open in FIND hands the selected recent image to the companion library browser.",
                "Send to PLAY asks an open PLAY950 plug-in window to load every P9 in the selected IMG.",
                "Keep the PLAY950 editor window open so it can receive a distributed load request.",
                "PLAY950 presents a program chooser when an IMG contains several P9 programs.",
                "FIND950 reads and indexes IMGs without making native changes to them.",
                "Use FIND950 to locate a sound, EDIT950 to modify it, and PLAY950 to perform it.",
                "Shared tags make the same musical categories visible in EDIT950 and FIND950.",
                "A selected P9 can be sent directly to PLAY950 from the open-image browser.",
                "The recent-image dashboard is a quick bridge between the three 950TOOLS apps."
            ],
            [
                "If an IMG will not open, show the Diagnostic Log and inspect the AKAI Util response.",
                "A greyed Import button usually means the image is read-only or no S950 volume is selected.",
                "If Safe Eject is unavailable, confirm that the IMG is on mounted removable media.",
                "Grant Full Disk Access when protected macOS metadata prevents verified media cleanup.",
                "If a P9 is silent, check that its Soft and Loud sample names still exist in the IMG.",
                "If a WAV will not import, inspect its channel count, PCM format and sample rate.",
                "If a recent row disappears, confirm that the IMG was not moved or renamed in Finder.",
                "Refresh after another application changes the currently open IMG.",
                "Use File Information when a native name or type looks unexpected.",
                "A detailed error report is safer than retrying a failed mutation blindly."
            ],
            [
                "S950 filenames are short and sampler-visible, so choose distinctive names.",
                "Renaming an S9 can update matching Soft and Loud references in every P9.",
                "Keep a sample's visible name stable during external WAV replacement.",
                "Create Unique Name prevents two imported files from fighting for one sampler name.",
                "Native filename casing is preserved when copying original S9 and P9 files.",
                "A P9 reference points to a sample name, not to a modern filesystem identifier.",
                "Check for truncated or colliding names before importing a large modern sample pack.",
                "Repair Internal Sample Name is for an S9 whose stored name disagrees with its directory entry.",
                "Use verified Rename instead of renaming native files outside the IMG.",
                "Tags can carry descriptive detail that does not fit in an S950 filename."
            ],
            [
                "The header's FREE value updates after imports, deletions and verified replacements.",
                "Lower bandwidth can reduce an S9's memory use while preserving pitch and duration.",
                "Estimated IMG after replacement helps catch a sample that will not fit.",
                "Delete unused material from a working copy when you need space for another program.",
                "Compression and sample rate columns help explain why similarly long samples use different space.",
                "A P9 is small, but its linked S9 samples determine most of a program's storage cost.",
                "Focused export gathers only the selected program and required dependencies.",
                "A collection export reports the programs and sample sources included in the result.",
                "Capacity checks happen before supported replacements mutate the IMG.",
                "Keep some free blocks available when building a disk that will be edited on hardware."
            ],
            [
                "Command-O opens an AKAI image.",
                "Command-Shift-O opens a standalone S950 P9 program.",
                "Command-N opens the New or Format Image sheet.",
                "Command-W closes the current IMG and returns to recent images.",
                "Command-R refreshes the open IMG.",
                "Command-I opens Import when the current volume is writable.",
                "Command-E exports the current supported selection.",
                "Command-Option-E copies selected original S9 or P9 files.",
                "Command-0 restores Actual Size for the zoomed IMG browser.",
                "Command-minus and Command-plus step through the available browser zoom levels."
            ],
            [
                "EDIT950 bundles AKAI Util 4.6.7, so a separate helper installation is not required.",
                "Both EDIT950 and its bundled AKAI Util helper are Universal arm64 and x86_64 binaries.",
                "AKAI Util commands run one at a time through a serialized controller.",
                "Temporary audition and staging workspaces are removed after their session ends.",
                "The app preserves unknown native bytes unless a documented edit owns them.",
                "Source WAV, S9 and P9 files are never modified in place during import.",
                "The diagnostic log records helper commands and cleaned output for troubleshooting.",
                "Display settings are shared consistently across the 950TOOLS visual system.",
                "The app uses JetBrains Mono to keep technical values aligned and readable.",
                "Create, edit and verify is the guiding workflow for every writable IMG operation."
            ]
        ]
        let result = groups.flatMap { $0 }
        precondition(result.count == 200, "EDIT950 must ship exactly 200 welcome hints.")
        return result
    }()

    static func normalized(_ index: Int) -> Int {
        let count = hints.count
        return ((index % count) + count) % count
    }
}

private struct NativeTableKeyboardMonitor: NSViewRepresentable {
    let onSpace: @MainActor () -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(onSpace: onSpace) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.hostView = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.onSpace = onSpace
        context.coordinator.applySelectionStyleSoon()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        weak var hostView: NSView?
        var onSpace: @MainActor () -> Bool
        private var monitor: Any?
        private var observers: [NSObjectProtocol] = []
        private let selectedColor = NSColor(
            calibratedRed: 1,
            green: 196.0 / 255.0,
            blue: 0,
            alpha: 1
        )

        init(onSpace: @escaping @MainActor () -> Bool) {
            self.onSpace = onSpace
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard let self,
                      event.keyCode == 49,
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                      let window = hostView?.window,
                      event.window === window,
                      Self.tableAncestor(of: window.firstResponder as? NSView) != nil
                else { return event }
                return onSpace() ? nil : event
            }
            observers = [
                NotificationCenter.default.addObserver(
                    forName: NSTableView.selectionDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let coordinator = self else { return }
                    Task { @MainActor in
                        guard let changedTable = notification.object as? NSTableView,
                              changedTable.numberOfColumns >= 6,
                              changedTable.window === coordinator.hostView?.window
                        else { return }
                        coordinator.applySelectionStyleSoon()
                    }
                },
                NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    guard let coordinator = self else { return }
                    Task { @MainActor in coordinator.applySelectionStyleSoon() }
                }
            ]
            applySelectionStyleSoon()
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }

        func applySelectionStyleSoon() {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.applySelectionStyle()
            }
        }

        private func applySelectionStyle() {
            guard let contentView = hostView?.window?.contentView,
                  let table = NativeFileTableLocator.first(in: contentView)
            else { return }
            table.focusRingType = .none
            table.enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
            for rowIndex in 0..<table.numberOfRows {
                guard let row = table.rowView(
                    atRow: rowIndex,
                    makeIfNecessary: false
                ) else { continue }
                let selected = table.selectedRowIndexes.contains(rowIndex)
                row.selectionHighlightStyle = .none
                row.backgroundColor = selected ? selectedColor : .clear
                row.wantsLayer = true
                row.layer?.backgroundColor = selected ? selectedColor.cgColor : nil
                for cell in row.subviews {
                    cell.wantsLayer = true
                    cell.layer?.backgroundColor = selected
                        ? selectedColor.cgColor : nil
                }
            }
        }

        private static func tableAncestor(of view: NSView?) -> NSTableView? {
            var candidate = view
            while let current = candidate {
                if let table = current as? NSTableView { return table }
                candidate = current.superview
            }
            return nil
        }
    }
}

private struct EditAuditionCell: View {
    let file: AkaiFile
    let model: AppModel

    var body: some View {
        if file.isSample {
            if model.isSampleCacheLoading(file) {
                ProgressView().controlSize(.small).help("PREPARING AUDITION WAV")
            } else if let error = model.sampleCacheError(for: file) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Color.suiteAmber).help("AUDITION UNAVAILABLE: \(error)")
            } else {
                Button { model.auditionSample(withIDs: Set([file.id])) } label: {
                    Image(systemName: model.auditioningSampleID == file.id ? "stop.fill" : "play.fill")
                        .foregroundStyle(Color.suiteBlue)
                }
                .buttonStyle(.plain)
                .disabled(!model.isSampleCached(file) || model.isBusy)
                .help(model.auditioningSampleID == file.id ? "STOP SAMPLE AUDITION" : "PLAY SAMPLE ONCE")
            }
        }
    }
}

private struct EditSampleRateCell: View {
    let file: AkaiFile
    let selected: Bool
    var body: some View {
        Text(displayValue)
            .monospacedDigit()
            .foregroundStyle(
                selected
                    ? Color.suiteOnYellow
                    : file.sampleRate == nil ? Color.suiteUnit : Color.suiteInk
            )
    }
    private var displayValue: String {
        guard let sampleRate = file.sampleRate else { return "—" }
        return "\(sampleRate) Hz"
    }
}

private struct EditStartBlockCell: View {
    let file: AkaiFile
    let selected: Bool
    var body: some View {
        Text(displayValue)
            .monospaced()
            .foregroundStyle(
                selected
                    ? Color.suiteOnYellow
                    : file.startBlock == nil
                        ? Color.suiteUnit.opacity(0.65) : Color.suiteInk
            )
    }
    private var displayValue: String {
        guard let startBlock = file.startBlock else { return "—" }
        return String(format: "0x%04X", startBlock)
    }
}

private struct EditCompressionCell: View {
    let file: AkaiFile
    var body: some View { Text(file.compression ?? "—") }
}

private struct NativeFileDragCell: View {
    let file: AkaiFile
    let model: AppModel
    let selected: Bool

    var body: some View {
        if model.isNativeAkaiFile(file) {
            ZStack {
                Color.clear
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(
                        selected ? Color.suiteOnYellow : Color.suiteUnit
                    )
                NativeFileDragSource(file: file, model: model)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .help("Drag selected original S9/P9 files to Finder")
        }
    }
}

@MainActor
enum NativeFileTableSelection {
    static func select(
        _ file: AkaiFile,
        modifiers: NSEvent.ModifierFlags,
        model: AppModel,
        window: NSWindow?
    ) {
        model.selectFile(file, modifiers: modifiers)
        guard let window,
              let contentView = window.contentView,
              let table = NativeFileTableLocator.first(in: contentView)
        else { return }
        let selectedRows = IndexSet(
            model.displayedFiles.indices.filter {
                model.selection.contains(model.displayedFiles[$0].id)
            }
        )
        table.selectRowIndexes(selectedRows, byExtendingSelection: false)
        window.makeFirstResponder(table)
    }
}

private struct NativeTableDoubleClickMonitor: NSViewRepresentable {
    let onDoubleClick: @MainActor (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDoubleClick: onDoubleClick)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.hostView = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.onDoubleClick = onDoubleClick
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        weak var hostView: NSView?
        var onDoubleClick: @MainActor (Int) -> Void
        private var eventMonitor: Any?

        init(onDoubleClick: @escaping @MainActor (Int) -> Void) {
            self.onDoubleClick = onDoubleClick
        }

        func install() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .leftMouseDown
            ) { [weak self] event in
                guard event.clickCount == 2,
                      let self,
                      let window = self.hostView?.window,
                      event.window === window,
                      let contentView = window.contentView,
                      let table = NativeFileTableLocator.fileTable(
                        at: event.locationInWindow,
                        inside: contentView
                      )
                else { return event }
                let point = table.convert(event.locationInWindow, from: nil)
                let row = table.row(at: point)
                guard row >= 0 else { return event }
                Task { @MainActor in
                    self.onDoubleClick(row)
                }
                return event
            }
        }

        func uninstall() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }

    }
}

enum NativeFileTableLocator {
    static func first(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView,
           table.numberOfColumns >= 6 {
            return table
        }
        for subview in view.subviews {
            if let table = first(in: subview) {
                return table
            }
        }
        return nil
    }

    static func fileTable(
        at windowPoint: NSPoint,
        inside view: NSView
    ) -> NSTableView? {
        if let table = view as? NSTableView,
           table.numberOfColumns >= 6 {
            let localPoint = table.convert(windowPoint, from: nil)
            if table.visibleRect.contains(localPoint) {
                return table
            }
        }
        for subview in view.subviews {
            if let table = fileTable(at: windowPoint, inside: subview) {
                return table
            }
        }
        return nil
    }
}

@MainActor
private struct NativeFileDragSource: NSViewRepresentable {
    let file: AkaiFile
    let model: AppModel

    func makeNSView(context: Context) -> NativeFileDragSourceView {
        NativeFileDragSourceView()
    }

    func updateNSView(
        _ nsView: NativeFileDragSourceView,
        context: Context
    ) {
        nsView.onMouseDown = {
            _ = model.nativeFilesForDrag(startingWith: file)
        }
        nsView.prepareDrag = {
            let files = model.nativeFilesForDrag(startingWith: file)
            guard !files.isEmpty, !model.isBusy else { return nil }
            return NativeFilePromiseCoordinator(files: files, model: model)
        }
    }
}

@MainActor
private final class NativeFileDragSourceView: NSView, NSDraggingSource {
    var onMouseDown: (() -> Void)?
    var prepareDrag: (() -> NativeFilePromiseCoordinator?)?
    private var startingPoint: NSPoint?
    private var startedDragging = false
    private var activeCoordinator: NativeFilePromiseCoordinator?

    override func mouseDown(with event: NSEvent) {
        startingPoint = convert(event.locationInWindow, from: nil)
        startedDragging = false
        onMouseDown?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !startedDragging,
              let startingPoint
        else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - startingPoint.x, point.y - startingPoint.y) >= 3
        else { return }
        guard let coordinator = prepareDrag?() else { return }

        startedDragging = true
        activeCoordinator = coordinator
        coordinator.onComplete = { [weak self, weak coordinator] in
            guard self?.activeCoordinator === coordinator else { return }
            self?.activeCoordinator = nil
        }
        let items = coordinator.draggingItems(in: bounds)
        guard !items.isEmpty else {
            activeCoordinator = nil
            return
        }
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        startingPoint = nil
        startedDragging = false
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        startingPoint = nil
        startedDragging = false
        if operation.isEmpty {
            activeCoordinator = nil
        }
    }
}

private final class NativeFilePromiseCoordinator:
    NSObject,
    NSFilePromiseProviderDelegate
{
    let files: [AkaiFile]
    let model: AppModel
    var onComplete: (() -> Void)?
    private var providers: [NSFilePromiseProvider] = []
    private var exportTask: Task<[AkaiFile.ID: URL], Error>?
    private var completedPromises = Set<AkaiFile.ID>()

    init(files: [AkaiFile], model: AppModel) {
        self.files = files
        self.model = model
    }

    @MainActor
    func draggingItems(in bounds: NSRect) -> [NSDraggingItem] {
        providers = files.map { file in
            let type = UTType(
                filenameExtension: (file.name as NSString).pathExtension
            ) ?? .data
            let provider = NSFilePromiseProvider(
                fileType: type.identifier,
                delegate: self
            )
            provider.userInfo = file.id
            return provider
        }

        let icon = NSImage(
            systemSymbolName: files.count > 1 ? "doc.on.doc" : "doc",
            accessibilityDescription: "AKAI file"
        ) ?? NSImage()
        let size = NSSize(width: 28, height: 28)
        return providers.enumerated().map { offset, provider in
            let item = NSDraggingItem(pasteboardWriter: provider)
            let shift = CGFloat(min(offset, 4)) * 2
            item.setDraggingFrame(
                NSRect(
                    x: max(0, bounds.midX - size.width / 2 + shift),
                    y: max(0, bounds.midY - size.height / 2 - shift),
                    width: size.width,
                    height: size.height
                ),
                contents: icon
            )
            return item
        }
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        file(for: filePromiseProvider)?.name ?? "AKAI-File.S9"
    }

    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let file = file(for: filePromiseProvider) else {
            completionHandler(
                AppError.verificationFailed("The dragged AKAI file is unavailable.")
            )
            return
        }
        Task { @MainActor [weak self] in
            guard let self else {
                completionHandler(CocoaError(.userCancelled))
                return
            }
            do {
                let exports = try await exportedFiles()
                guard let source = exports[file.id] else {
                    throw AppError.verificationFailed(
                        "AKAI Util did not create \(file.name)."
                    )
                }
                try FileManager.default.copyItem(at: source, to: url)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
            completedPromises.insert(file.id)
            if completedPromises.count == files.count {
                onComplete?()
            }
        }
    }

    @MainActor
    private func exportedFiles() async throws -> [AkaiFile.ID: URL] {
        if let exportTask {
            return try await exportTask.value
        }
        let task = Task { @MainActor [files, model] in
            try await model.exportNativeFilesForDrag(files)
        }
        exportTask = task
        return try await task.value
    }

    private func file(
        for provider: NSFilePromiseProvider
    ) -> AkaiFile? {
        guard let id = provider.userInfo as? AkaiFile.ID else { return nil }
        return files.first { $0.id == id }
    }
}

private struct FileNameCell: View {
    let file: AkaiFile
    let selected: Bool

    var body: some View {
        Text(file.name)
            .font(SuiteFont.regular(12))
            .foregroundStyle(
                file.name.uppercased().hasSuffix(".P9")
                    ? Color.suiteRed
                    : selected ? Color.suiteOnYellow : Color.suiteInk
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        .help(
            file.name.uppercased().hasSuffix(".P9")
                ? "Double-click to edit this P9 program"
                : file.isSample
                    ? "Double-click to edit this sample; audio-editor launch is optional"
                    : ""
        )
    }
}

private struct EditTypeGlyph: View {
    let file: AkaiFile

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(colour)
            .font(SuiteFont.regular(12))
    }

    private var symbol: String {
        switch file.type.uppercased() {
        case "PROGRAM": "pianokeys"
        case "SAMPLE": "waveform"
        case "EFFECTS": "dial.medium"
        case "DRUM SET": "square.grid.3x3"
        case "CUE LIST": "list.bullet"
        case "MULTI": "square.stack.3d.up"
        default: "doc"
        }
    }

    private var colour: Color {
        file.type.caseInsensitiveCompare("Program") == .orderedSame
            ? .suiteRed
            : file.isSample ? .suiteBlue : .suiteUnit
    }
}

private struct EditInspector: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            if model.selectedFiles.count == 1, let file = model.selectedFiles.first {
                fileInspector(file)
            } else if model.selectedFiles.count > 1 {
                multiInspector
            } else if model.session != nil {
                diskInspector
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .font(SuiteFont.regular(34))
                        .opacity(0.4)
                    Text("SELECT A FILE TO INSPECT")
                        .font(SuiteFont.regular(10))
                        .tracking(1.4)
                        .foregroundStyle(Color.suiteUnit)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            }
        }
        .padding(16)
        .background(Color.suitePanel)
    }

    private func fileInspector(_ file: AkaiFile) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 10) {
                EditTypeGlyph(file: file).font(SuiteFont.regular(20))
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name).font(SuiteFont.regular(12))
                    Text(file.type.uppercased()).font(SuiteFont.regular(10)).tracking(1.4).foregroundStyle(Color.suiteUnit)
                }
            }
            section("METADATA") {
                metadata("SIZE", file.byteSize.formattedByteCount.uppercased())
                metadata("INDEX", file.index.formatted())
                metadata("START BLOCK", file.startBlock.map { String(format: "0x%04X", $0) } ?? "—")
                metadata("COMPRESSION", file.compression?.uppercased() ?? "—")
                metadata("S9 RATE", file.sampleRate.map { "\($0.formatted()) HZ" } ?? "—")
            }
            section("TAGS") { TagChipsView(tags: model.tags(for: file)) }
            section("ACTIONS") { actions(file) }
            section("LOCATION") {
                Text(model.snapshot.currentPath).font(SuiteFont.regular(10)).foregroundStyle(Color.suiteUnit)
                Button("SHOW IN FINDER") {
                    if let url = model.session?.imageURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }.buttonStyle(SuiteSecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private func actions(_ file: AkaiFile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if file.isSample {
                Button(model.auditioningSampleID == file.id ? "STOP AUDITION" : "AUDITION") {
                    if model.auditioningSampleID == nil { model.auditionSelectedSample() } else { model.stopSampleAudition() }
                }.buttonStyle(SuitePrimaryButtonStyle(role: .sample)).disabled(!model.canAuditionSelectedSample && model.auditioningSampleID == nil)
                Button("EDIT SAMPLE…") { model.editSelectedSampleInAudioEditor() }.buttonStyle(SuiteSecondaryButtonStyle()).disabled(!model.canEditSelectedS9Sample)
                Button("EXPORT AS WAV…") { model.exportSelected() }.buttonStyle(SuiteSecondaryButtonStyle()).disabled(!model.canExport)
                Button("COPY ORIGINAL S9…") { model.copySelectedNativeFiles() }.buttonStyle(SuiteSecondaryButtonStyle()).disabled(!model.canCopyNativeFiles)
                Button("RENAME S9…") { model.renameSelectedNativeFile() }.buttonStyle(SuiteSecondaryButtonStyle()).disabled(!model.canRenameSelectedNativeFile)
                Button("REPAIR INTERNAL SAMPLE NAME") { model.fixSelectedRAMNames() }.buttonStyle(SuiteSecondaryButtonStyle()).disabled(!model.canMutate)
            } else if (file.name as NSString).pathExtension.uppercased() == "P9" {
                Button { model.openSelectedProgramInPLAY950() } label: {
                    SuiteLauncherLabel(target: .play, title: "OPEN IN PLAY950")
                }.buttonStyle(SuitePrimaryButtonStyle(role: .program))
                Button("EDIT P9 KEYGROUPS…") { model.editSelectedP9() }.buttonStyle(SuiteSecondaryButtonStyle()).disabled(!model.canEditSelectedP9)
                Button("EXPORT PROGRAM…") { model.exportSelected() }.buttonStyle(SuiteSecondaryButtonStyle()).disabled(!model.canExport)
                Button("EXPORT AS ABLETON DRUM RACK…") { model.exportSelectedP9ToAbleton() }.buttonStyle(SuiteSecondaryButtonStyle()).disabled(!model.canExportSelectedP9ToAbleton)
                Button("COPY ORIGINAL P9…") { model.copySelectedNativeFiles() }.buttonStyle(SuiteSecondaryButtonStyle()).disabled(!model.canCopyNativeFiles)
                Button("RENAME P9…") { model.renameSelectedNativeFile() }.buttonStyle(SuiteSecondaryButtonStyle()).disabled(!model.canRenameSelectedNativeFile)
            } else {
                Button("COPY ORIGINAL FILE…") { model.copySelectedNativeFiles() }.buttonStyle(SuiteSecondaryButtonStyle()).disabled(!model.canCopyNativeFiles)
            }
            Menu { FileTagMenuContent(files: [file]) } label: { SuiteMenuLabel(title: "TAGS", systemImage: "tag") }.menuStyle(.borderlessButton)
            Button("FILE INFORMATION…") { model.showSelectedFileInformation() }.buttonStyle(SuiteSecondaryButtonStyle()).disabled(!model.canShowSelectedFileInformation)
            if model.canMutate {
                Button("DELETE…") { model.requestDeleteSelected() }.buttonStyle(SuitePrimaryButtonStyle(role: .destructive))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var multiInspector: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("\(model.selectedFiles.count) FILES SELECTED").font(SuiteFont.medium(15)).tracking(2.4).monospacedDigit()
            section("METADATA") {
                metadata("TOTAL SIZE", model.selectedFiles.reduce(Int64(0)) { $0 + $1.byteSize }.formattedByteCount.uppercased())
                metadata("LOCATION", model.snapshot.currentPath)
            }
            section("TAGS") { Menu { FileTagMenuContent(files: model.selectedFiles) } label: { SuiteMenuLabel(title: "TAGS", systemImage: "tag") }.menuStyle(.borderlessButton) }
            section("ACTIONS") {
                VStack(alignment: .leading, spacing: 8) {
                    Button("EXPORT SELECTED…") { model.exportSelected() }.buttonStyle(SuiteSecondaryButtonStyle()).disabled(!model.canExport)
                    Button("COPY ORIGINAL FILES…") { model.copySelectedNativeFiles() }.buttonStyle(SuiteSecondaryButtonStyle()).disabled(!model.canCopyNativeFiles)
                    if model.canMutate { Button("DELETE…") { model.requestDeleteSelected() }.buttonStyle(SuitePrimaryButtonStyle(role: .destructive)) }
                }
            }
        }
    }

    private var diskInspector: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "opticaldiscdrive").font(SuiteFont.regular(20)).foregroundStyle(Color.suiteUnit)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.session?.imageURL.lastPathComponent ?? "AKAI IMAGE").font(SuiteFont.regular(12))
                    Text("DISK IMAGE").font(SuiteFont.regular(10)).foregroundStyle(Color.suiteUnit)
                }
            }
            section("METADATA") {
                metadata("FILES", model.snapshot.fileCount.formatted())
                metadata("VOLUMES", model.snapshot.volumes.count.formatted())
                metadata("FREE", model.snapshot.freeBytes.formattedByteCount.uppercased())
            }
            section("TAGS") { TagChipsView(tags: model.tagsForCurrentImage()) }
            section("ACTIONS") {
                VStack(alignment: .leading, spacing: 8) {
                    Menu { ImageTagMenuContent() } label: { SuiteMenuLabel(title: "TAGS", systemImage: "tag") }.menuStyle(.borderlessButton)
                    Button("DISK INFORMATION…") { model.showDiskInfo = true }.buttonStyle(SuiteSecondaryButtonStyle())
                    Button("BACKUP") { model.backupImage() }.buttonStyle(SuiteSecondaryButtonStyle()).disabled(model.isBusy)
                    if model.session?.isRemovable == true { Button("SAFE EJECT") { model.cleanEject() }.buttonStyle(SuiteSecondaryButtonStyle()).disabled(model.isBusy) }
                    Button("SHOW IN FINDER") { if let url = model.session?.imageURL { NSWorkspace.shared.activateFileViewerSelecting([url]) } }.buttonStyle(SuiteSecondaryButtonStyle())
                }
            }
            section("LOCATION") { Text(model.session?.imageURL.path ?? "").font(SuiteFont.regular(10)).foregroundStyle(Color.suiteUnit).textSelection(.enabled) }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { SuiteSectionHeader(title: title); content() }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func metadata(_ title: String, _ value: String) -> some View {
        HStack { Text(title).font(SuiteFont.regular(10)).tracking(1.2).foregroundStyle(Color.suiteLabel); Spacer(); Text(value).font(SuiteFont.regular(12)).monospacedDigit() }
    }
}

private struct StatusBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            if let progress = model.progress {
                SuiteProgressBar(value: progress.fraction)
                    .frame(width: 140)
                Text(progress.kind.rawValue.uppercased())
                    .font(SuiteFont.medium(10))
                Text(progress.detail)
                    .foregroundStyle(Color.suiteUnit)
                    .lineLimit(1)
                Spacer()
                Button("Cancel") { model.cancelOperation() }
            } else if model.session != nil {
                Label(
                    model.session?.readOnly == true ? "READ-ONLY" : "READY",
                    systemImage: model.session?.readOnly == true ? "lock.fill" : "circle.fill"
                )
                .foregroundStyle(model.session?.readOnly == true ? Color.suiteAmber : Color.suiteUnit)
                Text(model.snapshot.currentPath)
                    .foregroundStyle(Color.suiteUnit)
                    .lineLimit(1)
                Spacer()
                SpaceGauge()
            } else {
                Text("READY")
                    .foregroundStyle(Color.suiteUnit)
                Spacer()
            }
        }
        .font(SuiteFont.regular(10))
        .tracking(1.4)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color.suitePanel)
        .overlay(alignment: .top) { Rectangle().fill(Color.suiteRule).frame(height: 1) }
    }
}

private struct SpaceGauge: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 7) {
            SuiteProgressBar(value: usedFraction, alertAt: 0.9)
                .frame(width: 90)
            Text("\(model.snapshot.usedBytes.formattedByteCount.uppercased()) USED · \(model.snapshot.freeBytes.formattedByteCount.uppercased()) FREE")
                .monospacedDigit()
        }
    }

    private var usedFraction: Double {
        guard model.snapshot.totalBytes > 0 else { return 0 }
        return Double(model.snapshot.usedBytes) / Double(model.snapshot.totalBytes)
    }
}

private struct DiagnosticLogView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        DiagnosticLogContents(
            diagnostics: model.diagnostics,
            onCopy: model.copyDiagnosticLog,
            onSave: model.saveDiagnosticLog,
            onReveal: model.revealDiagnosticLog,
            onClear: model.clearDiagnosticLog,
            onClose: { model.isLogVisible = false }
        )
    }
}

private struct DiagnosticLogContents: View {
    @ObservedObject var diagnostics: DiagnosticLogStore
    let onCopy: () -> Void
    let onSave: () -> Void
    let onReveal: () -> Void
    let onClear: () -> Void
    let onClose: () -> Void

    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Diagnostic Activity Log", systemImage: "waveform.path.ecg")
                    .font(SuiteFont.medium(10))
                Text("ROLLING · \(diagnostics.text.utf8.count.formatted()) BYTES")
                    .font(SuiteFont.regular(9))
                    .foregroundStyle(Color.suiteUnit)
                Spacer()
                Button("Copy", action: onCopy)
                    .buttonStyle(.borderless)
                    .help("Copy the visible diagnostic timeline")
                Button("Save…", action: onSave)
                    .buttonStyle(.borderless)
                    .help("Save a readable copy for a bug report")
                Button("Reveal", action: onReveal)
                    .buttonStyle(.borderless)
                    .help("Reveal the live rolling log in Finder")
                Button("Clear") { confirmClear = true }
                    .buttonStyle(.borderless)
                    .help("Clear earlier diagnostic entries")
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Hide diagnostic log")
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            Divider()
            if let warning = diagnostics.storageWarning {
                Label(
                    "The activity is visible here, but the rolling file could not be updated: \(warning)",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(SuiteFont.regular(9))
                .foregroundStyle(Color.suiteAmber)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(
                        diagnostics.text.isEmpty
                            ? "Activity, dialogue state, IMG operations, sample edits, errors and cleaned AKAI Util output will appear here."
                            : diagnostics.text
                    )
                    .font(SuiteFont.regular(10))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
                    Color.clear.frame(height: 1).id("diagnostic-log-end")
                }
                .onAppear { proxy.scrollTo("diagnostic-log-end", anchor: .bottom) }
                .onChange(of: diagnostics.text) { _, _ in
                    proxy.scrollTo("diagnostic-log-end", anchor: .bottom)
                }
            }
            .background(Color.suiteBackground)
        }
        .alert("Clear the diagnostic log?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Log", role: .destructive, action: onClear)
        } message: {
            Text("Earlier entries will be removed. EDIT950 will immediately continue recording new activity.")
        }
    }
}
