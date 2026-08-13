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
                Section("USBclean") {
                    HStack {
                        TextField("Application", text: $settings.usbCleanPath)
                        Button("Choose…") { settings.chooseUSBclean() }
                    }
                    Toggle("Clean and eject after a verified USB copy", isOn: $settings.ejectAfterUSBCopy)
                    Text("Ejection only happens after an explicit Clean Eject action, or after a confirmed USB copy when this preference is enabled.")
                        .font(SuiteFont.regular(10))
                        .foregroundStyle(Color.suiteUnit)
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
    }
}
