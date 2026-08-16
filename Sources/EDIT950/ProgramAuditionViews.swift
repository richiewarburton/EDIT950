import AppKit
import SwiftUI

struct ProgramAuditionControlStrip: View {
    @ObservedObject var controller: ProgramAuditionController
    var indicatedSampleNames: [String] = []
    var availablePrograms: [AkaiFile] = []
    var selectedProgramID: Binding<AkaiFile.ID?>? = nil

    var body: some View {
        HStack(spacing: 0) {
            inputGroup
                .padding(.trailing, 14)

            stripDivider

            routingGroup
                .padding(.horizontal, 14)

            stripDivider

            computerKeysGroup
                .padding(.horizontal, 14)

            stripDivider

            activityGroup
                .padding(.leading, 14)
        }
        .font(SuiteFont.medium(12))
        .tracking(0.45)
        .padding(.horizontal, 14)
        .frame(minHeight: 78)
        .background(Color.suiteSlab2)
    }

    private var inputGroup: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel("INPUT")
            Toggle(
                "MIDI AUDITION",
                isOn: Binding(
                    get: { controller.hardwareMIDIEnabled },
                    set: controller.setHardwareMIDIEnabled
                )
            )
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("program-midi-audition-toggle")

            Toggle(
                "COMPUTER MIDI KEYBOARD",
                isOn: Binding(
                    get: { controller.computerKeyboardEnabled },
                    set: controller.setComputerKeyboardEnabled
                )
            )
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("computer-midi-keyboard-toggle")
        }
        .font(SuiteFont.medium(10))
        .frame(minWidth: 206, alignment: .leading)
    }

    private var routingGroup: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel("AUDITION ROUTING")
            HStack(spacing: 8) {
                if let selectedProgramID {
                    programMenu(selection: selectedProgramID)
                }
                channelMenu
            }
        }
    }

    private func programMenu(selection: Binding<AkaiFile.ID?>) -> some View {
        Menu {
            Button {
                selection.wrappedValue = nil
            } label: {
                if selection.wrappedValue == nil {
                    Label("SELECT P9", systemImage: "checkmark")
                } else {
                    Text("SELECT P9")
                }
            }
            Divider()
            ForEach(availablePrograms) { program in
                Button {
                    selection.wrappedValue = program.id
                } label: {
                    let title = (program.name as NSString).deletingPathExtension
                    if selection.wrappedValue == program.id {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            auditionMenuLabel(title: selectedProgramTitle, width: 156)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(availablePrograms.isEmpty)
        .accessibilityLabel("Audition program")
        .accessibilityIdentifier("main-program-audition-picker")
        .help(
            "Choose the P9 played by MIDI and the computer keyboard. "
                + "This choice is independent of file-table selection."
        )
    }

    private var channelMenu: some View {
        Menu {
            Button {
                controller.setMIDIChannelSelection(-1)
            } label: {
                if controller.omni {
                    Label("OMNI", systemImage: "checkmark")
                } else {
                    Text("OMNI")
                }
            }
            Divider()
            ForEach(0..<16, id: \.self) { channel in
                Button {
                    controller.setMIDIChannelSelection(channel)
                } label: {
                    if !controller.omni, controller.selectedMIDIChannel == channel {
                        Label("KG CH \(channel + 1)", systemImage: "checkmark")
                    } else {
                        Text("KG CH \(channel + 1)")
                    }
                }
            }
        } label: {
            auditionMenuLabel(title: selectedChannelTitle, width: 110)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(!controller.inputEnabled)
        .accessibilityLabel("Audition keygroup channel")
        .accessibilityIdentifier("program-midi-channel-picker")
        .help(
            "Choose the P9 keygroup MIDI channel to audition. Physical MIDI "
                + "input and computer keys are routed to that channel; Omni ignores "
                + "the keygroup channel."
        )
    }

    private var computerKeysGroup: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel("COMPUTER KEYS")
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("OCT \(signed(controller.computerOctave)) · VEL \(controller.computerVelocity)")
                        .font(SuiteFont.medium(11))
                        .monospacedDigit()
                    Text("Z/X OCT · C/V VEL")
                        .font(SuiteFont.regular(9))
                        .foregroundStyle(Color.suiteLabel)
                }
                .opacity(controller.computerKeyboardEnabled ? 1 : 0.48)

                Button("PANIC", action: controller.panic)
                    .buttonStyle(SuiteSecondaryButtonStyle())
                    .controlSize(.small)
                    .disabled(!controller.inputEnabled)
                    .accessibilityIdentifier("program-midi-panic-button")
                    .help("Stop every audition voice and clear all held input notes.")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var activityGroup: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("ACTIVITY")
                Text(controller.status)
                    .font(SuiteFont.medium(10))
                    .tracking(0.35)
                    .foregroundStyle(
                        controller.errorMessage == nil ? Color.suiteLabel : Color.suiteRed
                    )
                    .lineLimit(1)
                    .accessibilityIdentifier("program-audition-status")

                HStack(spacing: 4) {
                    if controller.visibleNotes.isEmpty {
                        Text("NO KEYS HELD")
                            .font(SuiteFont.regular(10))
                            .foregroundStyle(Color.suiteLabel)
                    } else {
                        ForEach(Array(controller.visibleNotes.prefix(3))) { note in
                            ProgramAuditionNoteChip(note: note)
                        }
                        if controller.visibleNotes.count > 3 {
                            Text("+\(controller.visibleNotes.count - 3)")
                                .font(SuiteFont.medium(10))
                                .foregroundStyle(Color.suiteBlue)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !indicatedSampleNames.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("TRIGGERED S9")
                        .font(SuiteFont.medium(9))
                        .foregroundStyle(Color.suiteLabel)
                    Text(indicatedSampleNames.joined(separator: " · "))
                        .font(SuiteFont.medium(10))
                        .foregroundStyle(Color.suiteYellow)
                        .lineLimit(2)
                        .accessibilityLabel(
                            "Triggered samples: \(indicatedSampleNames.joined(separator: ", "))"
                        )
                }
                .frame(maxWidth: 170, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(Color.suiteRule)
            .frame(width: 1, height: 50)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(SuiteFont.medium(8))
            .tracking(1.45)
            .foregroundStyle(Color.suiteUnit)
    }

    private func auditionMenuLabel(title: String, width: CGFloat) -> some View {
        HStack(spacing: 7) {
            Text(title.uppercased())
                .font(SuiteFont.medium(10))
                .tracking(0.7)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.suiteLabel)
        }
        .foregroundStyle(Color.suiteInk)
        .padding(.horizontal, 10)
        .frame(width: width, height: 32)
        .background(Color.suiteSlab)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.suiteRule2, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private var selectedProgramTitle: String {
        guard let selectedProgramID,
              let selectedID = selectedProgramID.wrappedValue,
              let program = availablePrograms.first(where: { $0.id == selectedID })
        else { return "SELECT P9" }
        return (program.name as NSString).deletingPathExtension
    }

    private var selectedChannelTitle: String {
        controller.omni ? "OMNI" : "KG CH \(controller.selectedMIDIChannel + 1)"
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : String(value)
    }
}

private struct ProgramAuditionNoteChip: View {
    let note: ProgramAuditionHeldNote

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: note.source == .externalMIDI ? "pianokeys" : "keyboard")
            Text("\(sourceLabel) · \(note.summary)")
                .lineLimit(1)
        }
        .font(SuiteFont.medium(10))
        .foregroundStyle(note.playableSample ? Color.suiteBlue : Color.suiteAmber)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(note.playableSample ? Color.suiteBlue.opacity(0.12) : Color.suiteAmber.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(note.playableSample ? Color.suiteBlue.opacity(0.45) : Color.suiteAmber)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(note.source.title), \(note.summary)"
        )
        .help("\(note.source.title) · \(note.summary)")
    }

    private var sourceLabel: String {
        note.source == .externalMIDI ? "MIDI" : "KEYBOARD"
    }
}

struct ComputerMIDIKeyboardMonitor: NSViewRepresentable {
    @ObservedObject var controller: ProgramAuditionController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.hostView = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
        context.coordinator.controller = controller
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        weak var hostView: NSView?
        var controller: ProgramAuditionController
        private var keyDownMonitor: Any?
        private var keyUpMonitor: Any?
        private var observers: [NSObjectProtocol] = []

        init(controller: ProgramAuditionController) {
            self.controller = controller
        }

        func install() {
            guard keyDownMonitor == nil, keyUpMonitor == nil else { return }
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                guard let self, accepts(event), !isEditingText(in: event.window) else {
                    return event
                }
                return controller.handleComputerKeyDown(event) ? nil : event
            }
            keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) {
                [weak self] event in
                guard let self, accepts(event) else { return event }
                return controller.handleComputerKeyUp(event) ? nil : event
            }
            observers = [
                NotificationCenter.default.addObserver(
                    forName: NSApplication.didResignActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.controller.focusWasLost() }
                },
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didResignKeyNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    Task { @MainActor in
                        guard let self,
                              let window = notification.object as? NSWindow,
                              self.belongs(window, to: self.hostView?.window)
                        else { return }
                        self.controller.focusWasLost()
                    }
                }
            ]
        }

        func uninstall() {
            if let keyDownMonitor { NSEvent.removeMonitor(keyDownMonitor) }
            if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
            keyDownMonitor = nil
            keyUpMonitor = nil
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
            controller.focusWasLost()
        }

        private func accepts(_ event: NSEvent) -> Bool {
            belongs(event.window, to: hostView?.window)
        }

        private func belongs(_ candidate: NSWindow?, to host: NSWindow?) -> Bool {
            guard let candidate, let host else { return false }
            return candidate === host
                || candidate.sheetParent === host
                || host.attachedSheet === candidate
        }

        private func isEditingText(in window: NSWindow?) -> Bool {
            guard let textView = window?.firstResponder as? NSTextView else { return false }
            return textView.isFieldEditor || textView.isEditable
        }
    }
}
