import SwiftUI

struct SettingsView: View {
    enum Tab: Hashable {
        case general
        case safety
        case tags
    }

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var preferences: SuitePreferences
    @State private var selectedTab: Tab
    @State private var customCleanupName = ""
    @State private var cleanupException = ""
    @State private var cleanupError: String?

    init(initialTab: Tab = .general) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Form {
                Section("Appearance") {
                    Picker("Table density", selection: $preferences.density) {
                        ForEach(SuiteDensity.allCases) { density in
                            Text(density.title).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("Display zoom", selection: $preferences.zoom) {
                        ForEach(SuiteZoomLevel.allCases) { zoom in
                            Text(zoom.title).tag(zoom)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Show inspector", isOn: $preferences.inspectorVisible)
                }
                Section("AKAI Util") {
                    LabeledContent("Bundled helper", value: "AKAI Util 4.6.7 (Universal)")
                    LabeledContent("Detected", value: settings.detectedVersion)
                    Button("Validate Again") {
                        Task { await settings.validateExecutable() }
                    }
                }
                Section("S950 Import Defaults") {
                    Toggle("Convert WAV files to mono", isOn: $settings.defaultMono)
                    Toggle("Preserve compatible sample rates", isOn: $settings.preserveSampleRate)
                    Toggle("Compress S950 samples", isOn: $settings.compressedS900)
                }
                Section("External Audio Editor") {
                    HStack {
                        TextField(
                            "Application",
                            text: $settings.audioEditorPath,
                            prompt: Text("Choose an audio editor application")
                        )
                        Button("Choose…") { settings.chooseAudioEditor() }
                    }
                    Text(
                        "A selected S950 sample can be exported as WAV, opened in this editor, then safely converted and returned to its IMG."
                    )
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(Tab.general)

            Form {
                Section("Data Protection") {
                    Toggle("Back up before destructive operations", isOn: $settings.backupBeforeDestructive)
                    LabeledContent("Default IMG backup folder") {
                        HStack {
                            Text(
                                settings.backupFolderPath.isEmpty
                                    ? "Beside each IMG"
                                    : settings.backupFolderPath
                            )
                            .lineLimit(1)
                            .truncationMode(.middle)
                            Button("Choose…") { settings.chooseBackupFolder() }
                            if !settings.backupFolderPath.isEmpty {
                                Button("Use IMG Folder") {
                                    settings.clearBackupFolder()
                                }
                            }
                        }
                    }
                    Toggle(
                        "Open destination folder after export",
                        isOn: $settings.openExportDestination
                    )
                    Toggle("Open diagnostic log when an error occurs", isOn: $settings.autoOpenLogOnError)
                }
                Section("Safe Eject") {
                    Toggle("Clean and eject after a verified USB copy", isOn: $settings.ejectAfterUSBCopy)
                    Text("EDIT950 removes only the enabled metadata rules, including AppleDouble ._* sidecars, verifies none remain, then asks macOS to safely unmount and eject the volume. Every cleanup is previewed first. Full Disk Access is required to remove protected .Spotlight-V100 data.")
                        .font(SuiteFont.regular(10))
                        .foregroundStyle(Color.suiteUnit)
                    Button("Open Full Disk Access Settings") {
                        AppSettings.openFullDiskAccessSettings()
                    }

                    Text("Default metadata rules")
                        .font(SuiteFont.medium(11))
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        alignment: .leading,
                        spacing: 7
                    ) {
                        ForEach(
                            RemovableMediaCleanupPolicy.defaultNames,
                            id: \.self
                        ) { name in
                            Toggle(name, isOn: Binding(
                                get: {
                                    settings.mediaCleanupPolicy
                                        .isDefaultEnabled(name)
                                },
                                set: {
                                    settings.setDefaultCleanupName(
                                        name,
                                        enabled: $0
                                    )
                                }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }

                    LabeledContent("Custom exact names") {
                        VStack(alignment: .trailing, spacing: 7) {
                            ForEach(
                                settings.mediaCleanupPolicy.customNames,
                                id: \.self
                            ) { name in
                                HStack {
                                    Text(name).textSelection(.enabled)
                                    Button {
                                        settings.removeCustomCleanupName(name)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.plain)
                                    .help("REMOVE CUSTOM CLEANUP NAME")
                                }
                            }
                            HStack {
                                TextField(
                                    "e.g. .MySamplerCache",
                                    text: $customCleanupName
                                )
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addCustomCleanupName)
                                Button("Add") { addCustomCleanupName() }
                                    .disabled(customCleanupName
                                        .trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                        ).isEmpty)
                            }
                        }
                        .frame(maxWidth: 390, alignment: .trailing)
                    }

                    LabeledContent("Exceptions") {
                        VStack(alignment: .trailing, spacing: 7) {
                            ForEach(
                                settings.mediaCleanupPolicy.exceptions,
                                id: \.self
                            ) { exception in
                                HStack {
                                    Text(exception).textSelection(.enabled)
                                    Button {
                                        settings.removeCleanupException(exception)
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.plain)
                                    .help("REMOVE CLEANUP EXCEPTION")
                                }
                            }
                            HStack {
                                TextField(
                                    "e.g. Samples/Thumbs.db",
                                    text: $cleanupException
                                )
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addCleanupException)
                                Button("Add") { addCleanupException() }
                                    .disabled(cleanupException
                                        .trimmingCharacters(
                                            in: .whitespacesAndNewlines
                                        ).isEmpty)
                            }
                        }
                        .frame(maxWidth: 390, alignment: .trailing)
                    }
                }
                Section {
                    Button("Restore Defaults", role: .destructive) { settings.restoreDefaults() }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Safety", systemImage: "lock.shield") }
            .tag(Tab.safety)

            Form {
                Section("Shared Tag Index") {
                    LabeledContent("Current file") {
                        Text(model.tagLibraryFileURL.path)
                            .foregroundStyle(Color.suiteUnit)
                            .lineLimit(3)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: 390, alignment: .trailing)
                    }
                    HStack {
                        Button("Show in Finder") { model.revealTagIndex() }
                        Spacer()
                        Button("Reset to Default") { model.resetTagLibraryDirectory() }
                            .disabled(model.isUsingDefaultTagLibraryDirectory)
                        Button("Choose Location…") { model.chooseTagLibraryDirectory() }
                    }
                    HStack {
                        Spacer()
                        Button("Export Copy…") { model.exportTagIndex() }
                    }
                    Text("The versioned JSON index contains tag names, colours and IMG/P9/S9 assignments. EDIT950 and FIND950 use the same selected location. Relocating it leaves the previous copy in place as a backup; tags are never written into sampler files. Synced folders can be used, but avoid editing tags on multiple Macs simultaneously.")
                        .font(SuiteFont.regular(10))
                        .foregroundStyle(Color.suiteUnit)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Tags", systemImage: "tag") }
            .tag(Tab.tags)
        }
        .padding(12)
        .background(Color.suiteBackground)
        .alert("Safe Eject Settings", isPresented: Binding(
            get: { cleanupError != nil },
            set: { if !$0 { cleanupError = nil } }
        )) {
            Button("OK", role: .cancel) { cleanupError = nil }
        } message: {
            Text(cleanupError ?? "Unknown error")
        }
    }

    private func addCustomCleanupName() {
        do {
            try settings.addCustomCleanupName(customCleanupName)
            customCleanupName = ""
        } catch {
            cleanupError = error.localizedDescription
        }
    }

    private func addCleanupException() {
        do {
            try settings.addCleanupException(cleanupException)
            cleanupException = ""
        } catch {
            cleanupError = error.localizedDescription
        }
    }
}
