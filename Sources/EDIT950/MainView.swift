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
            FileBrowser()
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

            Button {
                preferences.inspectorVisible.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help("Show or hide the inspector")
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

private struct BrowserHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: SuiteBrandAsset.image(named: "EDIT950-brand-mark"))
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("EDIT950")
                    .font(SuiteFont.bold(15))
                    .tracking(4.1)
                Text("CREATE · EDIT · VERIFY")
                    .font(SuiteFont.regular(9))
                    .tracking(1.4)
                    .foregroundStyle(Color.suiteUnit)
            }
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
        .padding(.horizontal, 16)
        .frame(height: 64)
        .background(Color.suiteBackground)
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
                SuiteEmptyState(
                    systemImage: "opticaldiscdrive",
                    title: "OPEN AN AKAI IMAGE",
                    message: "Browse, import, export, back up and safely eject S900 and S950 disk images.",
                    actionTitle: "OPEN IMAGE…",
                    action: model.openPanel
                )
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
        VStack(spacing: 0) {
            HStack {
                Label("Diagnostic Log", systemImage: "terminal")
                    .font(SuiteFont.medium(10))
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.diagnosticLog, forType: .string)
                }
                .buttonStyle(.borderless)
                Button {
                    model.isLogVisible = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Hide diagnostic log")
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            Divider()
            ScrollView {
                Text(model.diagnosticLog.isEmpty ? "Commands and cleaned AKAI Util output will appear here." : model.diagnosticLog)
                    .font(SuiteFont.regular(10))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(10)
            }
            .background(Color.suiteBackground)
        }
    }
}
