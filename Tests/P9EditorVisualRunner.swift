import AppKit
import SwiftUI

@main
@MainActor
struct P9EditorVisualRunner {
    static func main() {
        guard (3...4).contains(CommandLine.arguments.count) else {
            fputs("usage: P9EditorVisualRunner <program.p9> <screenshot.png> [--all|--spread|--image|--overwrite]\n", stderr)
            exit(2)
        }
        let programURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let screenshotURL = URL(fileURLWithPath: CommandLine.arguments[2])

        do {
            let sourceData = try Data(contentsOf: programURL)
            let mode = CommandLine.arguments.count == 4 ? CommandLine.arguments[3] : ""
            let document = try P9EditorDocument(
                data: sourceData,
                source: mode == "--overwrite" || mode == "--image"
                    ? .image(
                        filename: programURL.lastPathComponent,
                        imageURL: URL(fileURLWithPath: "/tmp/VISUAL.img"),
                        volumePath: "/"
                    )
                    : .local(programURL)
            )
            guard try document.program.encoded() == sourceData, !document.hasChanges else {
                throw P9EditorVisualFailure.roundTrip
            }
            if (mode == "--overwrite" || mode == "--image"),
               !document.program.keygroups.isEmpty {
                var program = document.program
                program.keygroups[0].softLoudness += 1
                document.program = program
            }
            NSApplication.shared.setActivationPolicy(.regular)
            let appearanceName: NSAppearance.Name =
                ProcessInfo.processInfo.environment["EDIT950_SMOKE_APPEARANCE"]
                    == "light" ? .aqua : .darkAqua
            NSApplication.shared.appearance = NSAppearance(named: appearanceName)
            NSApplication.shared.finishLaunching()
            let preferenceDomain = "EDIT950.P9VisualSmoke.\(UUID().uuidString)"
            guard let preferenceDefaults = UserDefaults(
                suiteName: preferenceDomain
            ) else {
                throw P9EditorVisualFailure.preferences
            }
            preferenceDefaults.removePersistentDomain(forName: preferenceDomain)
            defer {
                preferenceDefaults.removePersistentDomain(
                    forName: preferenceDomain
                )
            }
            let suitePreferences = SuitePreferences(
                app: .edit,
                defaultInspectorVisible: false,
                defaults: preferenceDefaults
            )
            if let zoomValue = ProcessInfo.processInfo.environment[
                "EDIT950_SMOKE_ZOOM"
            ], let rawZoom = Double(zoomValue),
               let zoom = SuiteZoomLevel(rawValue: rawZoom) {
                suitePreferences.zoom = zoom
            }
            let contentSize: NSSize
            let root: AnyView
            if mode == "--spread" {
                contentSize = P9EditorSheet.presentationSize(
                    for: suitePreferences.zoom
                )
                root = AnyView(
                    P9EditorSheet(
                        document: document,
                        initialSelection: Set(document.program.keygroups.indices),
                        showSpreadInitially: true
                    )
                    .environmentObject(suitePreferences)
                    .frame(width: contentSize.width, height: contentSize.height)
                )
            } else {
                contentSize = P9EditorSheet.presentationSize(
                    for: suitePreferences.zoom
                )
                let initialSelection = mode == "--all"
                    ? Set(document.program.keygroups.indices)
                    : nil
                root = AnyView(
                    P9EditorSheet(
                        document: document,
                        initialSelection: initialSelection,
                        showOverwriteConfirmationInitially: mode == "--overwrite",
                        onOverwriteP9:
                            mode == "--overwrite" || mode == "--image"
                                ? { _, _ in } : nil,
                        onSaveP9AsNewInImage:
                            mode == "--overwrite" || mode == "--image"
                                ? { _, _ in } : nil
                    )
                        .environmentObject(suitePreferences)
                        .frame(width: contentSize.width, height: contentSize.height)
                )
            }
            let hostingView = NSHostingView(rootView: root)
            let window = NSWindow(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: contentSize.width,
                    height: contentSize.height
                ),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.appearance = NSAppearance(named: appearanceName)
            window.title = "P9 Keygroup Editor — Visual Smoke Test"
            window.contentView = hostingView
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            hostingView.layoutSubtreeIfNeeded()
            let holdSeconds = ProcessInfo.processInfo.environment[
                "EDIT950_VISUAL_HOLD_SECONDS"
            ].flatMap(Double.init) ?? 0.5
            RunLoop.current.run(until: Date(timeIntervalSinceNow: holdSeconds))
            hostingView.layoutSubtreeIfNeeded()
            window.attachedSheet?.appearance = NSAppearance(named: appearanceName)
            window.attachedSheet?.contentView?.appearance = NSAppearance(named: appearanceName)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

            let captureWindow = mode == "--spread" || mode == "--overwrite"
                ? window.attachedSheet ?? window
                : window
            guard let capturedImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                CGWindowID(captureWindow.windowNumber),
                [.boundsIgnoreFraming]
            ) else {
                throw P9EditorVisualFailure.capture
            }
            let bitmap = NSBitmapImageRep(cgImage: capturedImage)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw P9EditorVisualFailure.capture
            }
            try data.write(to: screenshotURL)
            print("P9 editor smoke screenshot: \(screenshotURL.path)")
            window.orderOut(nil)
        } catch {
            fputs("P9 editor visual smoke test failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private enum P9EditorVisualFailure: Error {
    case capture
    case preferences
    case roundTrip
}
