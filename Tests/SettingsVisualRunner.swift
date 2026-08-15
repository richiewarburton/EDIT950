import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var isLogVisible = false
    let tagLibraryFileURL = URL(
        fileURLWithPath: "/Users/example/Dropbox/950TOOLS Shared Tags/tags-v2.json"
    )
    let isUsingDefaultTagLibraryDirectory = false

    func revealTagIndex() {}
    func resetTagLibraryDirectory() {}
    func chooseTagLibraryDirectory() {}
    func exportTagIndex() {}
    func saveDiagnosticLog() {}
    func revealDiagnosticLog() {}
}

@main
@MainActor
struct SettingsVisualRunner {
    static func main() {
        do {
            try SuiteFontGate.registerFontsForSmokeTests()
        } catch {
            fputs("Settings smoke setup failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: SettingsVisualRunner <screenshot.png>\n", stderr)
            exit(2)
        }
        let screenshotURL = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let defaults = UserDefaults(
            suiteName: "EDIT950.SettingsVisual.\(UUID().uuidString)"
        ) else {
            fputs("Could not create isolated settings.\n", stderr)
            exit(1)
        }
        let settings = AppSettings(defaults: defaults)
        settings.backupFolderPath =
            "/Users/example/Music/EDIT950 Backups"
        settings.openExportDestination = true
        let model = AppModel()
        let suitePreferences = SuitePreferences(
            app: .edit,
            defaultInspectorVisible: false,
            defaults: defaults
        )
        let usesLightAppearance =
            ProcessInfo.processInfo.environment["EDIT950_SMOKE_APPEARANCE"]
                == "light"
        if usesLightAppearance {
            suitePreferences.appearance = .light
        }
        let initialTab: SettingsView.Tab = switch ProcessInfo.processInfo.environment[
            "EDIT950_SETTINGS_TAB"
        ] {
        case "general": .general
        case "safety": .safety
        default: .tags
        }

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.appearance = NSAppearance(
            named: usesLightAppearance ? .aqua : .darkAqua
        )
        NSApplication.shared.finishLaunching()
        let root = SettingsView(initialTab: initialTab)
            .environmentObject(settings)
            .environmentObject(model)
            .environmentObject(suitePreferences)
            .preferredColorScheme(suitePreferences.appearance.colorScheme)
            .frame(width: 620, height: 560)
        let hostingView = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "EDIT950 Settings — Visual Smoke Test"
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
        hostingView.layoutSubtreeIfNeeded()

        let bounds = hostingView.bounds
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(
            in: bounds
        ) else {
            fputs("Could not capture Settings.\n", stderr)
            exit(1)
        }
        hostingView.cacheDisplay(in: bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:])
        else {
            fputs("Could not encode Settings screenshot.\n", stderr)
            exit(1)
        }
        do {
            try data.write(to: screenshotURL)
            print("Settings smoke screenshot: \(screenshotURL.path)")
        } catch {
            fputs("Settings visual smoke failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        window.orderOut(nil)
    }
}
