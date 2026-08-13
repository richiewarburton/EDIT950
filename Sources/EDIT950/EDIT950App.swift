import AppKit
import SwiftUI

@main
struct EDIT950App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var model: AppModel
    @StateObject private var suitePreferences: SuitePreferences
    @StateObject private var undoHistory: SuiteUndoCoordinator
    @State private var showAbout = false

    init() {
        Self.migrateLegacyDefaults()
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: AppModel(settings: settings))
        _suitePreferences = StateObject(wrappedValue: SuitePreferences(
            app: .edit,
            defaultInspectorVisible: false
        ))
        _undoHistory = StateObject(wrappedValue: SuiteUndoCoordinator())
        SuiteFontGate.validateBundle()
    }

    private static func migrateLegacyDefaults() {
        guard let legacy = UserDefaults(suiteName: "com.local.AKAIImageManager") else { return }
        let current = UserDefaults.standard
        for (key, value) in legacy.dictionaryRepresentation()
        where current.object(forKey: key) == nil {
            current.set(value, forKey: key)
        }
    }

    var body: some Scene {
        Window("EDIT950", id: "main") {
            SuiteZoomContainer {
                MainView()
            }
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(suitePreferences)
                .onAppear { model.undoManager = undoHistory.manager }
                .suiteSurface()
                .frame(minWidth: 880, minHeight: 520)
                .onOpenURL { model.handleOpenURLs([$0]) }
                .onAppear { appDelegate.model = model }
                .task { await settings.validateExecutable() }
                .sheet(isPresented: $showAbout) {
                    SuiteAboutView(
                        product: "EDIT950",
                        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "DEV"
                    )
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button(undoHistory.undoTitle) { undoHistory.undo() }
                    .keyboardShortcut("z")
                    .disabled(!undoHistory.canUndo)
                Button(undoHistory.redoTitle) { undoHistory.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!undoHistory.canRedo)
            }
            CommandGroup(replacing: .appInfo) {
                Button("ABOUT EDIT950…") { showAbout = true }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Image…") { model.openPanel() }
                    .keyboardShortcut("o")
                Menu("Open Recent") {
                    if model.recentImages.isEmpty {
                        Text("No Recent Images")
                    } else {
                        ForEach(model.recentImages, id: \.path) { url in
                            Button(url.lastPathComponent) {
                                model.openRecent(url)
                            }
                        }
                    }
                }
                Toggle(
                    "Open Images Read-Only",
                    isOn: $model.currentReadOnlyChoice
                )
                Divider()
                Button("Open S950 P9 Program…") { model.openP9EditorPanel() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("New or Format Image…") { model.showFormatSheet = true }
                    .keyboardShortcut("n")
                Button("Close Image") { model.closeImage() }
                    .keyboardShortcut("w")
                    .disabled(model.session == nil)
            }
            CommandMenu("Image") {
                Button("Import WAV Files…") { model.importPanel() }
                    .keyboardShortcut("i")
                    .disabled(!model.canImport)
                Button("Export Selected…") { model.exportSelected() }
                    .keyboardShortcut("e")
                    .disabled(!model.canExport)
                Button("Copy Original S9/P9 Files…") { model.copySelectedNativeFiles() }
                    .keyboardShortcut("e", modifiers: [.command, .option])
                    .disabled(!model.canCopyNativeFiles)
                Button("Export Selected P9 as Ableton Drum Rack…") {
                    model.exportSelectedP9ToAbleton()
                }
                .disabled(!model.canExportSelectedP9ToAbleton)
                Button("Edit Selected P9 Keygroups…") { model.editSelectedP9() }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                    .disabled(!model.canEditSelectedP9)
                Button("Edit Selected Sample…") {
                    model.editSelectedSampleInAudioEditor()
                }
                .disabled(!model.canEditSelectedS9Sample)
                Button(
                    model.auditioningSampleID == nil
                        ? "Audition Selected Sample"
                        : "Stop Sample Audition"
                ) {
                    if model.auditioningSampleID == nil {
                        model.auditionSelectedSample()
                    } else {
                        model.stopSampleAudition()
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(
                    model.auditioningSampleID == nil
                        && !model.canAuditionSelectedSample
                )
                Button("Rename Selected S9/P9…") {
                    model.renameSelectedNativeFile()
                }
                .disabled(!model.canRenameSelectedNativeFile)
                Button("Selected File Information…") {
                    model.showSelectedFileInformation()
                }
                .disabled(!model.canShowSelectedFileInformation)
                Divider()
                Button("New S950 Program…") {
                    model.createP9Program()
                }
                .disabled(!model.canCreateP9Program)
                Button("New Program from Copied Keygroups…") {
                    model.createP9FromCopiedKeygroups()
                }
                .disabled(!model.canCreateP9FromCopiedKeygroups)
                Button("Export All Samples…") { model.exportAllSamples() }
                    .disabled(model.session == nil || model.isBusy)
                Divider()
                Button("Refresh") { model.refreshAction() }
                    .keyboardShortcut("r")
                    .disabled(model.session == nil || model.isBusy)
                Button("Disk Information") { model.showDiskInfo = true }
                    .disabled(model.session == nil)
                Button("Create Backup") { model.backupImage() }
                    .disabled(model.session == nil || model.isBusy)
                Divider()
                Button("Delete Selected…") { model.requestDeleteSelected() }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(!model.canMutate || model.selectedFiles.isEmpty)
            }
            CommandMenu("Display") {
                Button("Zoom Out") { suitePreferences.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(suitePreferences.zoom == .fifty)
                Button("Actual Size") { suitePreferences.zoom = .oneHundred }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Zoom In") { suitePreferences.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(suitePreferences.zoom == .twoHundred)
                Divider()
                ForEach(SuiteZoomLevel.allCases) { zoom in
                    Button {
                        suitePreferences.zoom = zoom
                    } label: {
                        if suitePreferences.zoom == zoom {
                            Label(zoom.title, systemImage: "checkmark")
                        } else {
                            Text(zoom.title)
                        }
                    }
                }
            }
            CommandMenu("Diagnostics") {
                Toggle("Diagnostic Log", isOn: $model.isLogVisible)
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Divider()
                Button("Build PLAY950 Filter/Envelope Fixture…") {
                    model.buildPLAY950Fixture()
                }
                .disabled(!model.canBuildPLAY950Fixture)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(model)
                .environmentObject(suitePreferences)
                .suiteSurface()
                .frame(width: 620, height: 560)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel? {
        didSet {
            guard let model, !pendingOpenURLs.isEmpty else { return }
            let urls = pendingOpenURLs
            pendingOpenURLs.removeAll()
            model.handleOpenURLs(urls)
        }
    }
    private var pendingOpenURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        if let model {
            model.handleOpenURLs(urls)
        } else {
            pendingOpenURLs.append(contentsOf: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
