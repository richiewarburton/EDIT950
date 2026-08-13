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

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let root = MainView()
            .environmentObject(model)
            .environmentObject(settings)
            .environmentObject(suitePreferences)
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

        do {
            try await model.openImage(imageURL, readOnly: true)
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
            if let firstFile = model.snapshot.files.first {
                model.selection = [firstFile.id]
            }
            try await Task.sleep(nanoseconds: 900_000_000)
            hostingView.layoutSubtreeIfNeeded()
            let bounds = hostingView.bounds
            guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: bounds) else {
                throw VisualSmokeFailure.capture
            }
            hostingView.cacheDisplay(in: bounds, to: bitmap)
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
}
