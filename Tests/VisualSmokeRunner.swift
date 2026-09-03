import AppKit
import SwiftUI

@main
@MainActor
struct VisualSmokeRunner {
    static func main() async {
        do {
            try SuiteFontGate.registerFontsForSmokeTests()
        } catch {
            fputs("Visual smoke setup failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        guard (3...4).contains(CommandLine.arguments.count) else {
            fputs("usage: VisualSmokeRunner <image.img> <screenshot.png> [akaiutil]\n", stderr)
            exit(2)
        }
        let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let screenshotURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let settings = AppSettings()
        if CommandLine.arguments.count == 4 {
            settings.executablePath = CommandLine.arguments[3]
        }
        let tagDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("visual-smoke-tags-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tagDirectory) }
        let model = AppModel(
            settings: settings,
            tagLibraryDirectoryOverride: tagDirectory
        )
        let preferenceDomain = "EDIT950.VisualSmoke.\(UUID().uuidString)"
        guard let preferenceDefaults = UserDefaults(suiteName: preferenceDomain) else {
            fputs("Visual smoke setup failed: Could not create isolated preferences.\n", stderr)
            exit(1)
        }
        preferenceDefaults.removePersistentDomain(forName: preferenceDomain)
        defer {
            preferenceDefaults.removePersistentDomain(forName: preferenceDomain)
        }
        let suitePreferences = SuitePreferences(
            app: .edit,
            defaultInspectorVisible: false,
            defaults: preferenceDefaults
        )
        if ProcessInfo.processInfo.environment["EDIT950_SMOKE_APPEARANCE"] == "light" {
            suitePreferences.appearance = .light
        }
        if let zoomValue = ProcessInfo.processInfo.environment["EDIT950_SMOKE_ZOOM"],
           let rawZoom = Double(zoomValue),
           let zoom = SuiteZoomLevel(rawValue: rawZoom) {
            suitePreferences.zoom = zoom
        }
        if ProcessInfo.processInfo.environment["EDIT950_SMOKE_INSPECTOR"] == "1" {
            suitePreferences.inspectorVisible = true
        }

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let root = MainView()
            .environmentObject(model)
            .environmentObject(settings)
            .environmentObject(suitePreferences)
            .preferredColorScheme(suitePreferences.appearance.colorScheme)
            .frame(width: 1180, height: 760)
        let hostingView = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "EDIT950 — Visual Smoke Test"
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        var captureView: NSView = hostingView

        do {
            let showsSampleKeyboard = ProcessInfo.processInfo.environment[
                "EDIT950_SHOW_SAMPLE_KEYBOARD"
            ] == "1"
            let opensWritable = ProcessInfo.processInfo.environment[
                "EDIT950_SMOKE_WRITABLE"
            ] == "1"
            try await model.openImage(
                imageURL,
                readOnly: !showsSampleKeyboard && !opensWritable
            )
            if showsSampleKeyboard {
                guard let sample = model.snapshot.files.first(where: \.isSample) else {
                    throw VisualSmokeFailure.sampleUnavailable
                }
                model.selection = [sample.id]
                model.editSelectedSampleInAudioEditor()
                for _ in 0..<60 where model.externalSampleEditSession == nil {
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                guard let editSession = model.externalSampleEditSession else {
                    throw VisualSmokeFailure.sampleUnavailable
                }
                let pageIndex = Int(ProcessInfo.processInfo.environment[
                    "EDIT950_SAMPLE_WORKFLOW_PAGE"
                ] ?? "0") ?? 0
                let editorRoot = ExternalSampleEditSheet(
                    editSession: editSession,
                    initialWorkflowPageIndex: pageIndex,
                    initialSaveAsNewPromptVisible:
                        ProcessInfo.processInfo.environment[
                            "EDIT950_SHOW_SAVE_AS_NEW_PROMPT"
                        ] == "1"
                )
                    .environmentObject(model)
                    .environmentObject(settings)
                    .environmentObject(suitePreferences)
                    .preferredColorScheme(suitePreferences.appearance.colorScheme)
                let editorHost = NSHostingView(rootView: editorRoot)
                window.setContentSize(
                    ExternalSampleEditSheet.presentationSize(
                        for: suitePreferences.zoom
                    )
                )
                window.contentView = editorHost
                captureView = editorHost
            } else {
                model.addTag()
                if let created = model.tags.last {
                    model.updateTag(created, name: "Archive", colorHex: "#D97706")
                    if let archiveTag = model.tags.first(where: { $0.id == created.id }) {
                        model.toggleImageTag(archiveTag)
                    }
                }
                model.addTag()
                if let created = model.tags.last {
                    model.updateTag(created, name: "Favourite", colorHex: "#2563EB")
                    if let favourite = model.tags.first(where: { $0.id == created.id }) {
                        model.toggleTag(
                            favourite,
                            for: Array(model.snapshot.files.filter {
                                model.isNativeAkaiFile($0)
                            }.prefix(2))
                        )
                    }
                }
                let showsDiskInspector = ProcessInfo.processInfo.environment[
                    "EDIT950_SMOKE_DISK_INSPECTOR"
                ] == "1"
                let showsFileInspector = ProcessInfo.processInfo.environment[
                    "EDIT950_SMOKE_FILE_INSPECTOR"
                ] == "1"
                if !showsDiskInspector, let firstFile = model.snapshot.files.first {
                    model.selection = [firstFile.id]
                }
                if showsDiskInspector || showsFileInspector {
                    let inspectorRoot = EditInspector()
                        .environmentObject(model)
                        .preferredColorScheme(suitePreferences.appearance.colorScheme)
                        .frame(width: 520, height: 760)
                    let inspectorHost = NSHostingView(rootView: inspectorRoot)
                    window.setContentSize(CGSize(width: 520, height: 760))
                    window.contentView = inspectorHost
                    captureView = inspectorHost
                }
                if ProcessInfo.processInfo.environment[
                    "EDIT950_SHOW_DIAGNOSTIC_LOG"
                ] == "1" {
                    model.diagnostics.record(
                        .warning,
                        category: "visual-test",
                        message: "Visible diagnostic timeline example",
                        fields: [
                            "image": imageURL.path,
                            "state": "Viewer is readable and selectable"
                        ]
                    )
                    model.isLogVisible = true
                }
            }
            try await Task.sleep(nanoseconds: 900_000_000)
            captureView.layoutSubtreeIfNeeded()
            let bounds = captureView.bounds
            guard let bitmap = captureView.bitmapImageRepForCachingDisplay(in: bounds) else {
                throw VisualSmokeFailure.capture
            }
            captureView.cacheDisplay(in: bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw VisualSmokeFailure.capture
            }
            try data.write(to: screenshotURL)
            print("Visual smoke screenshot: \(screenshotURL.path)")
            model.closeImage()
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            fputs("Visual smoke test failed: \(error)\n", stderr)
            exit(1)
        }
    }
}

enum VisualSmokeFailure: Error {
    case capture
    case sampleUnavailable
}
