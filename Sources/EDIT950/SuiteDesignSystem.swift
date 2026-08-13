import AppKit
import CoreText
import SwiftUI

@MainActor
final class SuiteUndoCoordinator: ObservableObject {
    let manager = UndoManager()
    private var observers: [NSObjectProtocol] = []

    init() {
        manager.levelsOfUndo = 50
        manager.groupsByEvent = false
        let names = [
            "NSUndoManagerCheckpointNotification",
            "NSUndoManagerDidOpenUndoGroupNotification",
            "NSUndoManagerWillCloseUndoGroupNotification",
            "NSUndoManagerDidUndoChangeNotification",
            "NSUndoManagerDidRedoChangeNotification"
        ].map { Notification.Name($0) }
        observers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: manager,
                queue: .main
            ) { [weak self] _ in
                guard let coordinator = self else { return }
                Task { @MainActor in
                    coordinator.objectWillChange.send()
                }
            }
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var canUndo: Bool { manager.canUndo }
    var canRedo: Bool { manager.canRedo }
    var undoTitle: String {
        manager.undoActionName.isEmpty ? "Undo" : "Undo \(manager.undoActionName)"
    }
    var redoTitle: String {
        manager.redoActionName.isEmpty ? "Redo" : "Redo \(manager.redoActionName)"
    }

    func undo() {
        manager.undo()
        objectWillChange.send()
    }

    func redo() {
        manager.redo()
        objectWillChange.send()
    }
}

@MainActor
extension UndoManager {
    func registerSuiteUndo<Target: AnyObject>(
        withTarget target: Target,
        actionName: String,
        handler: @escaping (Target) -> Void
    ) {
        let opensGroup = groupingLevel == 0
        if opensGroup { beginUndoGrouping() }
        registerUndo(withTarget: target, handler: handler)
        setActionName(actionName)
        if opensGroup { endUndoGrouping() }
    }
}

enum SuiteApp: String { case find = "find"; case edit = "edit" }

enum SuiteDensity: String, CaseIterable, Identifiable {
    case dense
    case standard = "default"
    case comfortable
    var id: String { rawValue }
    var rowHeight: CGFloat { self == .dense ? 28 : self == .comfortable ? 40 : 32 }
    var title: String { rawValue.uppercased() }
}

enum SuiteZoomLevel: Double, CaseIterable, Identifiable {
    case fifty = 0.5
    case oneHundred = 1.0
    case oneHundredFifty = 1.5
    case twoHundred = 2.0

    var id: Double { rawValue }
    var title: String { "\(Int(rawValue * 100))%" }
}

@MainActor
final class SuitePreferences: ObservableObject {
    static let notification = Notification.Name("com.e45recordings.950tools.preferences.changed")
    @Published var density: SuiteDensity { didSet { persist("suite.density", density.rawValue) } }
    @Published var inspectorVisible: Bool { didSet { persist("suite.inspector.visible.\(app.rawValue)", inspectorVisible) } }
    @Published var zoom: SuiteZoomLevel {
        didSet { persist("suite.zoom.\(app.rawValue)", zoom.rawValue) }
    }
    let app: SuiteApp
    private let defaults: UserDefaults
    private let defaultInspectorVisible: Bool
    private var observer: NSObjectProtocol?
    private var isReloading = false

    init(
        app: SuiteApp,
        defaultInspectorVisible: Bool,
        defaults suppliedDefaults: UserDefaults? = nil
    ) {
        self.app = app
        self.defaultInspectorVisible = defaultInspectorVisible
        defaults = suppliedDefaults
            ?? UserDefaults(suiteName: "group.com.e45recordings.950tools")
            ?? .standard
        density = SuiteDensity(rawValue: defaults.string(forKey: "suite.density") ?? "") ?? .standard
        let key = "suite.inspector.visible.\(app.rawValue)"
        inspectorVisible = defaults.object(forKey: key) == nil ? defaultInspectorVisible : defaults.bool(forKey: key)
        zoom = SuiteZoomLevel(
            rawValue: defaults.double(forKey: "suite.zoom.\(app.rawValue)")
        ) ?? .oneHundred
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let preferences = self else { return }
            Task { @MainActor in preferences.reload() }
        }
    }
    deinit { if let observer { DistributedNotificationCenter.default().removeObserver(observer) } }
    private func persist(_ key: String, _ value: Any) {
        guard !isReloading else { return }
        defaults.set(value, forKey: key)
        DistributedNotificationCenter.default().postNotificationName(Self.notification, object: app.rawValue, deliverImmediately: true)
    }
    private func reload() {
        isReloading = true
        density = SuiteDensity(rawValue: defaults.string(forKey: "suite.density") ?? "") ?? .standard
        let key = "suite.inspector.visible.\(app.rawValue)"
        inspectorVisible = defaults.object(forKey: key) == nil ? defaultInspectorVisible : defaults.bool(forKey: key)
        zoom = SuiteZoomLevel(
            rawValue: defaults.double(forKey: "suite.zoom.\(app.rawValue)")
        ) ?? .oneHundred
        isReloading = false
    }

    func zoomIn() {
        guard let index = Self.zoomOrder.firstIndex(of: zoom),
              Self.zoomOrder.indices.contains(index + 1)
        else { return }
        zoom = Self.zoomOrder[index + 1]
    }

    func zoomOut() {
        guard let index = Self.zoomOrder.firstIndex(of: zoom), index > 0
        else { return }
        zoom = Self.zoomOrder[index - 1]
    }

    private static let zoomOrder = SuiteZoomLevel.allCases.sorted {
        $0.rawValue < $1.rawValue
    }
}

struct SuiteZoomContainer<Content: View>: View {
    @EnvironmentObject private var preferences: SuitePreferences
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = preferences.zoom.rawValue
            content
                .frame(
                    width: max(1, geometry.size.width / scale),
                    height: max(1, geometry.size.height / scale),
                    alignment: .topLeading
                )
                .scaleEffect(scale, anchor: .topLeading)
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: .topLeading
                )
                .clipped()
        }
    }
}

private extension NSColor {
    static func suite(hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
    static func suiteDynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .suite(hex: dark) : .suite(hex: light) }
    }
    static func suiteDynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
}

extension Color {
    static let suiteRed = Color(nsColor: .suiteDynamic(light: 0xE8140A, dark: 0xFF2010))
    static let suiteBlue = Color(nsColor: .suiteDynamic(light: 0x1E22E8, dark: 0x3A53FF))
    static let suiteYellow = Color(nsColor: .suiteDynamic(light: 0xFFC400, dark: 0xFFC400))
    static let suiteAmber = Color(nsColor: .suiteDynamic(light: 0xB25A00, dark: 0xFFA340))
    static let suiteGreen = Color(nsColor: .suiteDynamic(light: 0x087F5B, dark: 0x39D98A))
    static let suiteOnRed = Color.white
    static let suiteOnBlue = Color.white
    static let suiteOnYellow = Color(nsColor: .suite(hex: 0x101114))
    static let suitePage = Color(nsColor: .suiteDynamic(light: 0xDCDBD4, dark: 0x000000))
    static let suiteBackground = Color(nsColor: .suiteDynamic(light: 0xF7F6F2, dark: 0x0A0A0C))
    static let suitePanel = Color(nsColor: .suiteDynamic(light: 0xFFFFFF, dark: 0x0E0E11))
    static let suiteSlab = Color(nsColor: .suiteDynamic(light: 0xEAE9E3, dark: 0x17171C))
    static let suiteSlab2 = Color(nsColor: .suiteDynamic(light: 0xE0DFD8, dark: 0x202027))
    static let suiteSlab3 = Color(nsColor: .suiteDynamic(light: 0xFFFFFF, dark: 0x2A2A32))
    static let suiteInk = Color(nsColor: .suiteDynamic(light: 0x101114, dark: 0xF1F1F5))
    static let suiteLabel = Color(nsColor: .suiteDynamic(light: 0x5F636B, dark: 0x8D939D))
    static let suiteUnit = Color(nsColor: .suiteDynamic(light: 0x9095A0, dark: 0x5E636D))
    static let suiteRule = Color(nsColor: .suiteDynamic(light: NSColor(white: 0, alpha: 0.11), dark: NSColor(white: 1, alpha: 0.09)))
    static let suiteRule2 = Color(nsColor: .suiteDynamic(light: NSColor(white: 0, alpha: 0.24), dark: NSColor(white: 1, alpha: 0.18)))
    static let suiteTrack = Color(nsColor: .suiteDynamic(light: NSColor(white: 0, alpha: 0.13), dark: NSColor(white: 1, alpha: 0.09)))
}

enum SuiteFont {
    static func regular(_ size: CGFloat) -> Font { .custom("JetBrainsMono-Regular", fixedSize: size) }
    static func medium(_ size: CGFloat) -> Font { .custom("JetBrainsMono-Medium", fixedSize: size) }
    static func bold(_ size: CGFloat) -> Font { .custom("JetBrainsMono-Bold", fixedSize: size) }
}

enum SuiteTagPalette {
    static let groups: [(title: String, colours: [String])] = [
        ("PRIMARY", ["#FF0000", "#FF7A00", "#FFD500", "#00C853", "#00A3FF", "#003CFF", "#7A00FF", "#FF00A8"]),
        ("NEON", ["#FF3131", "#FF5F1F", "#FFF01F", "#CCFF00", "#39FF14", "#00FFD5", "#00E5FF", "#1F51FF", "#BC13FE", "#FF10F0"]),
        ("BRIGHT", ["#E30402", "#FF3B30", "#FF9500", "#FFCC02", "#34C759", "#00C7BE", "#001FD7", "#0A84FF", "#5856D6", "#AF52DE"]),
        ("PASTEL", ["#FFB3BA", "#FFDFBA", "#FFFFBA", "#BAFFC9", "#BAE1FF", "#C7CEEA", "#E2C6FF", "#FFC6E7", "#D7F9F1", "#F6E4D6"]),
        ("MUTED", ["#6E7581", "#7A3E7A", "#2F6E70", "#8A7A3A", "#8A4A34", "#4A6B3A", "#6B5B53", "#596A86", "#8B6F47", "#786F89"]),
        ("NEUTRAL", ["#FFFFFF", "#E5E7EB", "#9CA3AF", "#6B7280", "#374151", "#111827", "#000000"])
    ]

    static let allHex = groups.flatMap(\.colours)

    static func colour(for storedHex: String) -> Color {
        let clean = storedHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let value = UInt32(clean, radix: 16), clean.count == 6 else { return .suiteRule2 }
        return Color(nsColor: .suite(hex: value))
    }
}

enum SuiteBrandAsset {
    static func image(named name: String) -> NSImage {
        for url in candidateURLs(named: name) {
            if let image = NSImage(contentsOf: url) { return image }
        }
        return NSImage()
    }

    private static func candidateURLs(named name: String) -> [URL] {
        var urls: [URL] = []
        if let root = Bundle.main.resourceURL {
            urls.append(root.appendingPathComponent("BrandAssets/\(name).png"))
        }
        urls.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/BrandAssets/\(name).png"))
        return urls
    }
}

enum SuiteLauncherTarget: String {
    case edit = "EDIT950"
    case find = "FIND950"
    case play = "PLAY950"
}

struct SuiteLauncherLabel: View {
    let target: SuiteLauncherTarget
    let title: String
    var iconSize: CGFloat = 22

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: SuiteBrandAsset.image(named: "launcher-\(target.rawValue)"))
                .resizable().interpolation(.high)
                .frame(width: iconSize, height: iconSize)
            Text(title.uppercased()).lineLimit(1)
        }
    }
}

struct SuiteBrandHeader: View {
    let product: String
    let purpose: String

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: SuiteBrandAsset.image(named: "\(product)-brand-mark"))
                .resizable().interpolation(.high)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(product).font(SuiteFont.bold(15)).tracking(4.1)
                Text(purpose.uppercased()).font(SuiteFont.regular(9)).tracking(1.4)
                    .foregroundStyle(Color.suiteUnit)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color.suitePanel)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.suiteRule).frame(height: 1) }
    }
}

enum SuiteFontGate {
    private static let smokeFontDirectoryEnvironmentKey =
        "EDIT950_TEST_FONT_DIRECTORY"
    private static let fontFiles = [
        "JetBrainsMono-Regular.ttf",
        "JetBrainsMono-Medium.ttf",
        "JetBrainsMono-Bold.ttf"
    ]
    static let names = ["JetBrainsMono-Regular", "JetBrainsMono-Medium", "JetBrainsMono-Bold"]
    static func validateBundle() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let required = [
            "Fonts/JetBrainsMono-Regular.ttf",
            "Fonts/JetBrainsMono-Medium.ttf",
            "Fonts/JetBrainsMono-Bold.ttf",
            "Fonts/fonts.sha256",
            "Licenses/JetBrainsMono-OFL-1.1.txt",
            "BrandAssets/EDIT950-brand-mark.png",
            "BrandAssets/launcher-FIND950.png",
            "BrandAssets/launcher-PLAY950.png"
        ]
        precondition(required.allSatisfy { path in
            guard let root = Bundle.main.resourceURL else { return false }
            return FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
        }, "The JetBrains Mono package is incomplete.")
        precondition(names.allSatisfy { NSFont(name: $0, size: 12) != nil }, "JetBrains Mono failed to register.")
    }
    static func registerFontsForSmokeTests() throws {
        guard let directoryPath = ProcessInfo.processInfo.environment[
            smokeFontDirectoryEnvironmentKey
        ], !directoryPath.isEmpty else {
            throw SuiteFontGateError.missingEnvironment(
                smokeFontDirectoryEnvironmentKey
            )
        }
        let root = URL(fileURLWithPath: directoryPath, isDirectory: true)
            .standardizedFileURL
        let missing = fontFiles.filter {
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent($0).path
            )
        }
        guard missing.isEmpty else {
            throw SuiteFontGateError.missingFiles(missing, root)
        }

        var registrationErrors: [String] = []
        for file in fontFiles {
            let url = root.appendingPathComponent(file) as CFURL
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url, .process, &error),
               let error {
                registrationErrors.append(
                    "\(file): \(error.takeRetainedValue())"
                )
            }
        }
        let unresolved = names.filter { NSFont(name: $0, size: 12) == nil }
        guard unresolved.isEmpty else {
            throw SuiteFontGateError.unresolvedFonts(
                unresolved,
                root,
                registrationErrors
            )
        }
    }
    static func showLicence() {
        guard let root = Bundle.main.resourceURL else { return }
        let url = root.appendingPathComponent("Licenses/JetBrainsMono-OFL-1.1.txt")
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
    }
}

private enum SuiteFontGateError: LocalizedError {
    case missingEnvironment(String)
    case missingFiles([String], URL)
    case unresolvedFonts([String], URL, [String])

    var errorDescription: String? {
        switch self {
        case .missingEnvironment(let key):
            return "Set \(key) to the test font directory."
        case .missingFiles(let files, let directory):
            return "Missing test fonts in \(directory.path): \(files.joined(separator: ", "))."
        case .unresolvedFonts(let names, let directory, let registrationErrors):
            let diagnostics = registrationErrors.isEmpty
                ? "No CoreText registration error was returned."
                : registrationErrors.joined(separator: "; ")
            return "Could not resolve \(names.joined(separator: ", ")) from \(directory.path). \(diagnostics)"
        }
    }
}

struct SuiteSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(SuiteFont.regular(11)).tracking(1.98).textCase(.uppercase)
            .foregroundStyle(configuration.isPressed ? Color.suiteInk : Color.suiteLabel)
            .padding(.horizontal, 12).frame(minHeight: 30)
            .background(configuration.isPressed ? Color.suiteSlab2 : Color.suiteSlab)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.suiteRule2, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

enum SuitePrimaryRole { case neutral, sample, program, destructive }
struct SuitePrimaryButtonStyle: ButtonStyle {
    let role: SuitePrimaryRole
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(SuiteFont.medium(11)).tracking(1.98).textCase(.uppercase).foregroundStyle(foreground)
            .padding(.horizontal, 14).frame(minHeight: 32).background(background)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(role == .neutral ? Color.suiteRule2 : foreground.opacity(configuration.isPressed ? 0.45 : 0), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6)).opacity(configuration.isPressed ? 0.9 : 1)
    }
    private var background: Color { role == .sample ? .suiteBlue : role == .program ? .suiteRed : role == .destructive ? .suiteRed : .suiteSlab3 }
    private var foreground: Color { role == .sample ? .suiteOnBlue : role == .program ? .suiteOnRed : role == .destructive ? .suiteOnRed : .suiteInk }
}

struct SuiteMenuLabel: View {
    let title: String
    var systemImage: String? = nil
    var badge: Int? = nil
    var body: some View {
        HStack(spacing: 7) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title.uppercased()).lineLimit(1)
            if let badge, badge > 0 { Text(badge.formatted()).font(SuiteFont.regular(9)).padding(.horizontal, 4).background(Color.suiteSlab3, in: RoundedRectangle(cornerRadius: 3)) }
            Image(systemName: "chevron.down").font(SuiteFont.regular(9)).frame(width: 22).padding(.vertical, 7).background(Color.suiteSlab2)
        }
        .font(SuiteFont.regular(11)).tracking(1.4).foregroundStyle(Color.suiteInk).padding(.leading, 10)
        .background(Color.suiteSlab).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct SuiteSectionHeader: View {
    let title: String
    var accent: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(SuiteFont.medium(11)).tracking(2.64).foregroundStyle(Color.suiteLabel)
            Rectangle().fill(accent ?? Color.suiteRule).frame(height: accent == nil ? 1 : 3)
        }
    }
}

struct SuiteProgressBar: View {
    let value: Double?
    var alertAt: Double? = nil
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.suiteTrack)
                RoundedRectangle(cornerRadius: 3).fill(value != nil && alertAt != nil && value! >= alertAt! ? Color.suiteRed : Color.suiteUnit)
                    .frame(width: geometry.size.width * (value.map { min(max($0, 0), 1) } ?? 0.32))
            }
        }.frame(height: 4).clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct SuiteEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage).font(SuiteFont.regular(34)).foregroundStyle(Color.suiteUnit.opacity(0.65))
            Text(title.uppercased()).font(SuiteFont.medium(15)).tracking(2.4)
            Text(message).font(SuiteFont.regular(11)).foregroundStyle(Color.suiteUnit).multilineTextAlignment(.center).frame(maxWidth: 420)
            if let actionTitle, let action { Button(actionTitle.uppercased(), action: action).buttonStyle(SuitePrimaryButtonStyle(role: .neutral)) }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.suiteBackground)
    }
}

struct SuiteAboutView: View {
    @Environment(\.dismiss) private var dismiss
    let product: String
    let version: String
    var body: some View {
        VStack(spacing: 18) {
            Text(product.uppercased()).font(SuiteFont.bold(15)).tracking(5.1)
            Text("VERSION \(version)").font(SuiteFont.regular(10)).tracking(1.4).foregroundStyle(Color.suiteUnit)
            Divider().overlay(Color.suiteRule)
            Text("AKAI UTIL 4.6.7 INCLUDED").font(SuiteFont.medium(10)).tracking(1.2)
            Text("READ/WRITE IMG ACCESS · NO SEPARATE INSTALL")
                .font(SuiteFont.regular(9)).tracking(0.8).foregroundStyle(Color.suiteUnit)
            Text("SAFE EJECT USES NATIVE EDIT950 CODE")
                .font(SuiteFont.regular(9)).tracking(0.8).foregroundStyle(Color.suiteUnit)
            Text("JETBRAINS MONO — SIL OFL 1.1").font(SuiteFont.regular(10)).tracking(1.4).foregroundStyle(Color.suiteUnit)
            Button("VIEW LICENCE…", action: SuiteFontGate.showLicence).buttonStyle(SuiteSecondaryButtonStyle())
            Button("DONE") { dismiss() }
                .buttonStyle(SuitePrimaryButtonStyle(role: .neutral))
                .keyboardShortcut(.cancelAction)
        }.padding(24).frame(width: 390, height: 370).foregroundStyle(Color.suiteInk).background(Color.suitePanel)
            .onExitCommand { dismiss() }
            .background(SuiteEscapeDismissBridge { dismiss() })
    }
}

private struct SuiteEscapeDismissBridge: NSViewRepresentable {
    let onEscape: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEscape: onEscape) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.hostView = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        weak var hostView: NSView?
        var onEscape: @MainActor () -> Void
        private var monitor: Any?

        init(onEscape: @escaping @MainActor () -> Void) {
            self.onEscape = onEscape
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard let self,
                      event.keyCode == 53,
                      let window = hostView?.window,
                      event.window === window
                else { return event }
                onEscape()
                return nil
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

private struct SuiteSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View { content.font(SuiteFont.regular(11)).foregroundStyle(Color.suiteInk).background(Color.suiteBackground) }
}
extension View { func suiteSurface() -> some View { modifier(SuiteSurfaceModifier()) } }
