import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SampleLoopAuditionController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var playerAttached = false
    private var activeBuffer: AVAudioPCMBuffer?
    private var activeMode: S9PlaybackMode = .oneShot
    private var activeDirection: S9PlaybackDirection = .normal
    private var playbackGeneration = UUID()
    var onPlaybackEnded: (() -> Void)?

    func toggle(url: URL, start: Int, end: Int) {
        toggle(
            url: url,
            mode: .loop,
            direction: .normal,
            start: start,
            end: end
        )
    }

    func toggle(
        url: URL,
        mode: S9PlaybackMode,
        direction: S9PlaybackDirection,
        start: Int,
        end: Int
    ) {
        if isPlaying {
            stop()
        } else {
            play(
                url: url,
                mode: mode,
                direction: direction,
                start: start,
                end: end
            )
        }
    }

    func updateIfPlaying(url: URL, start: Int, end: Int) {
        guard isPlaying else { return }
        play(
            url: url,
            mode: activeMode,
            direction: activeDirection,
            start: start,
            end: end
        )
    }

    func updateIfPlaying(
        url: URL,
        mode: S9PlaybackMode,
        direction: S9PlaybackDirection,
        start: Int,
        end: Int
    ) {
        guard isPlaying else { return }
        play(
            url: url,
            mode: mode,
            direction: direction,
            start: start,
            end: end
        )
    }

    func toggleOneShot(url: URL) {
        if isPlaying {
            stop()
        } else {
            playOneShot(url: url)
        }
    }

    func playOneShot(url: URL) {
        play(
            url: url,
            mode: .oneShot,
            direction: .normal,
            start: 0,
            end: 0
        )
    }

    func play(url: URL, start: Int, end: Int) {
        play(
            url: url,
            mode: .loop,
            direction: .normal,
            start: start,
            end: end
        )
    }

    func play(
        url: URL,
        mode: S9PlaybackMode,
        direction: S9PlaybackDirection,
        start: Int,
        end: Int
    ) {
        do {
            let file = try AVAudioFile(forReading: url)
            guard file.length > 0 else {
                throw AppError.verificationFailed(
                    "The temporary WAV contains no audio to audition."
                )
            }
            let regionStart = mode == .oneShot ? 0 : start
            let regionEnd = mode == .oneShot ? Int(file.length) : end
            guard regionStart >= 0, regionStart < regionEnd else {
                throw AppError.verificationFailed(
                    "Loop start must be before loop end for audition."
                )
            }
            guard AVAudioFramePosition(regionEnd) <= file.length else {
                throw AppError.verificationFailed(
                    "The audition loop extends beyond the temporary WAV."
                )
            }
            let forward = try readBuffer(
                file: file,
                start: AVAudioFramePosition(regionStart),
                frameCount: AVAudioFrameCount(regionEnd - regionStart)
            )
            let playable: AVAudioPCMBuffer
            switch (mode, direction) {
            case (.alternatingLoop, .normal):
                playable = try alternatingBuffer(
                    forward: forward,
                    startsReversed: false
                )
            case (.alternatingLoop, .reverse):
                playable = try alternatingBuffer(
                    forward: forward,
                    startsReversed: true
                )
            case (_, .reverse):
                playable = try reversedBuffer(forward)
            default:
                playable = forward
            }

            try preparePlayback(format: playable.format)
            activeBuffer = playable
            activeMode = mode
            activeDirection = direction
            playbackGeneration = UUID()
            let generation = playbackGeneration
            errorMessage = nil
            isPlaying = true
            if mode == .oneShot {
                player.scheduleBuffer(
                    playable,
                    at: nil,
                    options: [],
                    completionCallbackType: .dataPlayedBack
                ) { [weak self] _ in
                    Task { @MainActor in
                        guard let self,
                              self.playbackGeneration == generation
                        else { return }
                        self.finishPlayback()
                    }
                }
            } else {
                player.scheduleBuffer(playable, at: nil, options: [.loops])
            }
            player.play()
        } catch {
            stop()
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    func stop() {
        playbackGeneration = UUID()
        player.stop()
        engine.stop()
        activeBuffer = nil
        isPlaying = false
    }

    private func preparePlayback(format: AVAudioFormat) throws {
        player.stop()
        engine.stop()
        if playerAttached {
            engine.disconnectNodeOutput(player)
        } else {
            engine.attach(player)
            playerAttached = true
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
    }

    private func finishPlayback() {
        player.stop()
        engine.stop()
        activeBuffer = nil
        isPlaying = false
        onPlaybackEnded?()
    }

    private func readBuffer(
        file: AVAudioFile,
        start: AVAudioFramePosition,
        frameCount: AVAudioFrameCount
    ) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ) else {
            throw AppError.verificationFailed(
                "The audition buffer could not be created."
            )
        }
        file.framePosition = start
        try file.read(into: buffer, frameCount: frameCount)
        return buffer
    }

    private func reversedBuffer(
        _ source: AVAudioPCMBuffer
    ) throws -> AVAudioPCMBuffer {
        guard let result = AVAudioPCMBuffer(
            pcmFormat: source.format,
            frameCapacity: source.frameLength
        ), let sourceChannels = source.floatChannelData,
           let resultChannels = result.floatChannelData
        else {
            throw AppError.verificationFailed(
                "The audition format cannot be reversed safely."
            )
        }
        result.frameLength = source.frameLength
        let count = Int(source.frameLength)
        for channel in 0..<Int(source.format.channelCount) {
            for frame in 0..<count {
                resultChannels[channel][frame] =
                    sourceChannels[channel][count - 1 - frame]
            }
        }
        return result
    }

    private func alternatingBuffer(
        forward: AVAudioPCMBuffer,
        startsReversed: Bool
    ) throws -> AVAudioPCMBuffer {
        let count = Int(forward.frameLength)
        guard count <= Int(AVAudioFrameCount.max) / 2,
              let result = AVAudioPCMBuffer(
                pcmFormat: forward.format,
                frameCapacity: AVAudioFrameCount(count * 2)
              ), let sourceChannels = forward.floatChannelData,
              let resultChannels = result.floatChannelData
        else {
            throw AppError.verificationFailed(
                "The alternating-loop audition buffer could not be created."
            )
        }
        result.frameLength = AVAudioFrameCount(count * 2)
        for channel in 0..<Int(forward.format.channelCount) {
            for frame in 0..<count {
                let ordinary = sourceChannels[channel][frame]
                let reversed = sourceChannels[channel][count - 1 - frame]
                resultChannels[channel][frame] =
                    startsReversed ? reversed : ordinary
                resultChannels[channel][count + frame] =
                    startsReversed ? ordinary : reversed
            }
        }
        return result
    }
}

struct AkaiFileInformationSheet: View {
    let information: AkaiFileInformation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.suiteUnit)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AKAI File Information")
                        .font(SuiteFont.medium(15)).tracking(2.4)
                    Text(information.filename)
                        .foregroundStyle(Color.suiteUnit)
                }
            }

            ScrollView([.vertical, .horizontal]) {
                Text(information.details)
                    .font(SuiteFont.regular(11))
                    .textSelection(.enabled)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .topLeading
                    )
                    .padding(12)
            }
            .background(
                Color.suiteBackground,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.suiteRule, lineWidth: 1)
            }

            HStack {
                Text(
                    "Values are reported directly by AKAI Util from the native file."
                )
                .font(SuiteFont.regular(10))
                .foregroundStyle(Color.suiteUnit)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 640, height: 560)
    }
}

struct ImportOptionsSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var options = ImportOptions()
    @State private var inspections: [WAVInspection] = []
    @State private var inspectionError: String?
    @State private var sampleNames: [String: String] = [:]
    @FocusState private var focusedSamplePath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.suiteBlue)
                VStack(alignment: .leading) {
                    Text("Import WAV Samples")
                        .font(SuiteFont.medium(15)).tracking(2.4)
                    Text("\(model.pendingImportURLs.count) file\(model.pendingImportURLs.count == 1 ? "" : "s") into \(model.snapshot.currentPath)")
                        .foregroundStyle(Color.suiteUnit)
                }
            }

            Form {
                LabeledContent("Target sampler", value: "S950")
                Toggle("Create compressed S950 samples", isOn: $options.compressedS900)
                Toggle("Convert to mono", isOn: $options.convertToMono)
                Toggle("Preserve compatible sample rates", isOn: $options.preserveSampleRate)
                Picker("If a name exists", selection: $options.collisionPolicy) {
                    ForEach(CollisionPolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
            }
            .formStyle(.grouped)

            GroupBox("Filename and repair preview") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(model.pendingImportURLs, id: \.path) { url in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(url.lastPathComponent)
                                        .lineLimit(1)
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(Color.suiteUnit.opacity(0.65))
                                    HStack(spacing: 3) {
                                        TextField(
                                            "S950 name",
                                            text: sampleNameBinding(for: url)
                                        )
                                        .textFieldStyle(.roundedBorder)
                                        .font(SuiteFont.medium(11))
                                        .frame(width: 145)
                                        .focused(
                                            $focusedSamplePath,
                                            equals: url.standardizedFileURL.path
                                        )
                                        .onSubmit { normalizeName(for: url) }
                                        Text(".S9")
                                            .font(SuiteFont.medium(11))
                                    }
                                    Spacer()
                                    if let inspection = inspections.first(where: { $0.url == url }) {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(inspection.needsRepair ? "Repair needed" : "Compatible")
                                                .foregroundStyle(inspection.needsRepair ? .orange : .green)
                                            if inspection.cueSampleOffsets.count == 2 {
                                                Text("2 loop markers")
                                                    .font(SuiteFont.regular(10))
                                                    .foregroundStyle(Color.suiteUnit)
                                            }
                                        }
                                    }
                                }
                                if let error = filenameValidationError(for: url) {
                                    Text(error)
                                        .font(SuiteFont.regular(10))
                                        .foregroundStyle(Color.suiteRed)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: 120)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated input: \(estimatedSize.formattedByteCount)")
                    Text("Available in image: \(model.snapshot.freeBytes.formattedByteCount)")
                        .foregroundStyle(estimatedSize > model.snapshot.freeBytes && model.snapshot.freeBytes > 0 ? .red : .secondary)
                }
                .font(SuiteFont.regular(10))
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") {
                    model.performImport(
                        options: options,
                        requestedNames: normalizedRequestedNames
                    )
                }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(SuitePrimaryButtonStyle(role: .neutral))
                    .disabled(
                        model.pendingImportURLs.isEmpty
                            || hasInvalidSampleNames
                            || (estimatedSize > model.snapshot.freeBytes
                                && model.snapshot.freeBytes > 0)
                    )
            }
        }
        .padding(22)
        .frame(width: 700, height: 590)
        .onAppear {
            options = settings.defaultImportOptions
            initializeSampleNames()
            inspect()
        }
        .onChange(of: options) { inspect() }
        .onChange(of: focusedSamplePath) { oldValue, _ in
            guard let oldValue,
                  let url = model.pendingImportURLs.first(where: {
                      $0.standardizedFileURL.path == oldValue
                  })
            else { return }
            normalizeName(for: url)
        }
    }

    private var estimatedSize: Int64 {
        model.pendingImportURLs.reduce(0) {
            $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private func inspect() {
        inspections = model.pendingImportURLs.compactMap { try? WAVService.inspect($0, options: options) }
        inspectionError = nil
    }

    private func initializeSampleNames() {
        for url in model.pendingImportURLs {
            let path = url.standardizedFileURL.path
            if sampleNames[path] == nil {
                sampleNames[path] = AkaiFilename.sanitizedBase(
                    url.lastPathComponent,
                    family: .s900
                )
            }
        }
    }

    private func sampleNameBinding(for url: URL) -> Binding<String> {
        let path = url.standardizedFileURL.path
        return Binding(
            get: {
                sampleNames[path] ?? AkaiFilename.sanitizedBase(
                    url.lastPathComponent,
                    family: .s900
                )
            },
            set: { sampleNames[path] = $0 }
        )
    }

    private func normalizeName(for url: URL) {
        let path = url.standardizedFileURL.path
        sampleNames[path] = AkaiFilename.normalizedS950Base(
            sampleNames[path] ?? ""
        )
    }

    private var normalizedRequestedNames: [String: String] {
        Dictionary(uniqueKeysWithValues: model.pendingImportURLs.map { url in
            let path = url.standardizedFileURL.path
            return (
                path,
                AkaiFilename.normalizedS950Base(
                    sampleNames[path]
                        ?? AkaiFilename.sanitizedBase(
                            url.lastPathComponent,
                            family: .s900
                        )
                )
            )
        })
    }

    private var duplicateSampleNames: Set<String> {
        let names = normalizedRequestedNames.values
        let counts = Dictionary(grouping: names, by: { $0 }).mapValues(\.count)
        return Set(counts.filter { $0.value > 1 }.map(\.key))
    }

    private func filenameValidationError(for url: URL) -> String? {
        let path = url.standardizedFileURL.path
        let name = sampleNames[path]
            ?? AkaiFilename.sanitizedBase(url.lastPathComponent, family: .s900)
        if let error = AkaiFilename.s950BaseValidationError(name) {
            return error
        }
        if duplicateSampleNames.contains(
            AkaiFilename.normalizedS950Base(name)
        ) {
            return "Enter a unique name for each imported sample."
        }
        return nil
    }

    private var hasInvalidSampleNames: Bool {
        model.pendingImportURLs.contains {
            filenameValidationError(for: $0) != nil
        }
    }
}

struct ExternalSampleEditSheet: View {
    @ObservedObject var editSession: ExternalSampleEditSession
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var compressed = false
    @State private var createBackup = true
    @State private var editAttributes: S9SampleEditSettings
    @State private var markerSummary: String?
    @State private var loopStart: Int
    @State private var loopEnd: Int
    @State private var loopPointsManuallyEdited = false
    @State private var zeroCrossingMap: WAVZeroCrossingMap?
    @State private var zeroCrossingError: String?
    @State private var bandwidth: Int
    @State private var resamplingMode: S950ResamplingMode = .antiAliased
    @State private var convertedPreviewURL: URL?
    @State private var isPreparingPreview = false
    @State private var previewError: String?
    @StateObject private var audition = SampleLoopAuditionController()

    init(editSession: ExternalSampleEditSession) {
        self.editSession = editSession
        _editAttributes = State(
            initialValue: S9SampleEditSettings(
                attributes: editSession.originalAttributes
            )
        )
        let attributes = editSession.originalAttributes
        _loopStart = State(initialValue: Int(attributes.loopStart ?? 0))
        _loopEnd = State(
            initialValue: Int(
                attributes.loopStart == nil
                    ? attributes.sampleLength
                    : attributes.playbackEnd
            )
        )
        _bandwidth = State(initialValue: S950BandwidthConversion.bandwidth(
            forSampleRate: Int(editSession.originalInspection.sampleRate.rounded())
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "waveform.badge.pencil")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.suiteBlue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Edit \(editSession.sourceFile.name)")
                        .font(SuiteFont.medium(15)).tracking(2.4)
                    Text("Edit native attributes, or open the WAV in your audio editor")
                    .foregroundStyle(Color.suiteUnit)
                }
            }

            GroupBox("Round-trip WAV") {
                VStack(alignment: .leading, spacing: 9) {
                    LabeledContent("Temporary file") {
                        Text(editSession.wavURL.lastPathComponent)
                            .font(SuiteFont.regular(11))
                    }
                    LabeledContent(
                        "Exported format",
                        value:
                            "\(Int(editSession.originalInspection.sampleRate)) Hz · "
                            + "\(editSession.originalInspection.bitDepth)-bit · "
                            + "\(editSession.originalInspection.channelCount) channel"
                            + "\(editSession.originalInspection.channelCount == 1 ? "" : "s")"
                    )
                    Text(
                        editSession.editorURL == nil
                            ? "Native attributes can be changed without an audio editor. Configure one in Settings only if audio editing is required."
                            : "Open the WAV below only when audio editing is required. Save over it; do not use Save As or change its location."
                    )
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
                    HStack {
                        Button(
                            "Open WAV in "
                                + (editSession.editorURL?
                                    .deletingPathExtension().lastPathComponent
                                    ?? "Audio Editor")
                        ) {
                            openWAVInEditor()
                        }
                        .buttonStyle(SuiteSecondaryButtonStyle())
                        .disabled(
                            editSession.editorURL == nil
                                || loopValidationError != nil
                        )
                        Button("Show WAV in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [editSession.wavURL]
                            )
                        }
                        .buttonStyle(SuiteSecondaryButtonStyle())
                    }
                }
                .padding(7)
            }

            GroupBox("Return to the S950 IMG") {
                VStack(alignment: .leading, spacing: 9) {
                    Picker("Root pitch", selection: $editAttributes.rootNote) {
                        ForEach(0..<128, id: \.self) { note in
                            Text("\(P9Keygroup.noteName(note)) · MIDI \(note)")
                                .tag(note)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 34)
                    .background(Color.suiteSlab)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.suiteRule2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Picker(
                        "Playback direction",
                        selection: $editAttributes.playbackDirection
                    ) {
                        ForEach(S9PlaybackDirection.allCases) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(Color.suiteBlue)

                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("S950 SAMPLING BANDWIDTH")
                            .font(SuiteFont.medium(11))
                            .tracking(1.3)
                        HStack {
                            Slider(value: bandwidthDouble, in: 3_000...19_200, step: 100)
                                .tint(Color.suiteBlue)
                            bandwidthInput
                            Text("HZ BANDWIDTH")
                                .font(SuiteFont.regular(9))
                                .tracking(1.0)
                                .foregroundStyle(Color.suiteUnit)
                        }
                        Picker("Resampling character", selection: $resamplingMode) {
                            ForEach(S950ResamplingMode.allCases) { mode in Text(mode.title).tag(mode) }
                        }
                        .pickerStyle(.segmented)
                        .tint(Color.suiteBlue)
                        HStack(spacing: 18) {
                            LabeledContent("Actual sample rate", value: "\(bandwidthConversion.sampleRate.formatted()) samples/sec")
                            LabeledContent("Estimated memory saving", value: estimatedSaving.formatted(.percent.precision(.fractionLength(1))))
                        }
                        LabeledContent("Estimated IMG after replacement", value: "\(projectedUsed.formattedByteCount) used · \(projectedFree.formattedByteCount) free")
                        if isPreparingPreview {
                            Label("PREPARING CURRENT AUDITION PREVIEW…", systemImage: "waveform")
                                .font(SuiteFont.regular(10))
                                .foregroundStyle(Color.suiteUnit)
                        }
                        Text(resamplingMode == .antiAliased
                             ? "Clean mode removes frequencies that cannot survive the lower rate before conversion."
                             : "Raw mode applies no protective low-pass filter, intentionally allowing S950-style aliasing and grit.")
                            .font(SuiteFont.regular(10)).foregroundStyle(Color.suiteUnit)
                        if let previewError { Text(previewError).font(SuiteFont.regular(10)).foregroundStyle(Color.suiteRed) }
                    }
                    .padding(12)
                    .background(Color.suiteSlab)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.suiteRule2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                    Picker(
                        "Playback mode",
                        selection: $editAttributes.playbackMode
                    ) {
                        ForEach(S9PlaybackMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(Color.suiteBlue)

                    HStack(spacing: 18) {
                        LabeledContent(
                            "Sample length",
                            value: "\(editSession.originalAttributes.sampleLength.formatted()) samples"
                        )
                        Divider()
                        LabeledContent(
                            "Loop length",
                            value: "\(loopLength.formatted()) samples"
                        )
                    }

                    HStack {
                        Text("Loop start")
                        Spacer()
                        zeroCrossingControls(
                            position: loopStart,
                            previous: previousLoopStartCrossing,
                            next: nextLoopStartCrossing,
                            move: { loopStartBinding.wrappedValue = $0.frame }
                        )
                        TextField(
                            "Loop start",
                            value: loopStartBinding,
                            format: .number
                        )
                        .multilineTextAlignment(.trailing)
                        .font(SuiteFont.regular(11))
                        .frame(width: 130)
                        Stepper(
                            "Loop start",
                            value: loopStartBinding,
                            in: 0...Int(editSession.originalAttributes.sampleLength)
                        )
                        .labelsHidden()
                    }

                    HStack {
                        Text("Loop end")
                        Spacer()
                        zeroCrossingControls(
                            position: loopEnd,
                            previous: previousLoopEndCrossing,
                            next: nextLoopEndCrossing,
                            move: { loopEndBinding.wrappedValue = $0.frame }
                        )
                        TextField(
                            "Loop end",
                            value: loopEndBinding,
                            format: .number
                        )
                        .multilineTextAlignment(.trailing)
                        .font(SuiteFont.regular(11))
                        .frame(width: 130)
                        Stepper(
                            "Loop end",
                            value: loopEndBinding,
                            in: 0...Int(editSession.originalAttributes.sampleLength)
                        )
                        .labelsHidden()
                    }

                    if let loopValidationError {
                        Label(
                            loopValidationError,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(SuiteFont.regular(10))
                        .foregroundStyle(Color.suiteRed)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Label(
                            "After saving marker changes in the external editor, return here and click Refresh Loop Points from Saved WAV to update the values shown above. Replacement reads saved markers automatically; refreshing lets you verify them first.",
                            systemImage: "arrow.clockwise.circle.fill"
                        )
                        .font(SuiteFont.regular(10))
                        .foregroundStyle(Color.suiteAmber)
                        HStack {
                            Button("Refresh Loop Points from Saved WAV") {
                                checkSavedMarkers()
                            }
                            .buttonStyle(SuiteSecondaryButtonStyle())
                            Button {
                                toggleCurrentAudition()
                            } label: {
                                Label(
                                    audition.isPlaying
                                        ? "Stop Audition"
                                        : "Audition Current Settings",
                                    systemImage: audition.isPlaying
                                        ? "stop.fill" : "play.fill"
                                )
                            }
                            .buttonStyle(SuitePrimaryButtonStyle(role: .sample))
                            .disabled(
                                editSession.isReplacing
                                    || isPreparingPreview
                                    || (editAttributes.playbackMode.requiresLoopMarkers
                                        && loopValidationError != nil)
                            )
                            if let markerSummary {
                                Text(markerSummary)
                                    .font(SuiteFont.regular(10)).monospacedDigit()
                                    .foregroundStyle(Color.suiteUnit)
                            }
                        }
                        Text(
                            "Audition follows the selected direction and one-shot, loop or alternating-loop mode. Active loop playback updates immediately when either loop point changes."
                        )
                        .font(SuiteFont.regular(10))
                        .foregroundStyle(Color.suiteUnit)
                    }

                    Divider()
                    Toggle("Create compressed S950 sample", isOn: $compressed)
                    Toggle(
                        "Create and verify a complete IMG backup first",
                        isOn: $createBackup
                    )
                    Text(
                        "The replacement keeps the original sample name, so P9 references remain valid. "
                            + "The stored S9 is re-exported and compared byte-for-byte. "
                            + (createBackup
                                ? "If replacement or verification fails, the IMG backup is restored automatically."
                                : "Without a backup, automatic rollback is unavailable.")
                    )
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(
                        createBackup ? Color.suiteUnit : Color.suiteAmber
                    )
                }
                .padding(7)
            }

            if editSession.isReplacing {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.progress?.detail ?? "Preparing replacement…")
                        .foregroundStyle(Color.suiteUnit)
                        .lineLimit(1)
                }
            }
            if let errorMessage = editSession.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.suiteRed)
                    .font(SuiteFont.regular(11))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let auditionError = audition.errorMessage {
                Label(
                    auditionError,
                    systemImage: "speaker.slash.fill"
                )
                .foregroundStyle(Color.suiteRed)
                .font(SuiteFont.regular(11))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let zeroCrossingError {
                Label(
                    zeroCrossingError,
                    systemImage: "waveform.path.ecg.rectangle"
                )
                .foregroundStyle(Color.suiteRed)
                .font(SuiteFont.regular(11))
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
            HStack {
                Text("The source IMG remains unchanged until the final replacement step.")
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
                Spacer()
                Button("Cancel") {
                    audition.stop()
                    model.cancelExternalSampleEdit(editSession)
                }
                .buttonStyle(SuiteSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
                .disabled(editSession.isReplacing)
                Button(
                    createBackup
                        ? "Back Up and Replace Sample"
                        : "Replace Without Backup"
                ) {
                    audition.stop()
                    model.replaceEditedS9Sample(
                        editSession,
                        compressed: compressed,
                        createBackup: createBackup,
                        attributes: editAttributes,
                        loopPoints: loopPointsManuallyEdited
                            ? currentLoopPoints : nil,
                        bandwidthConversion: rateIsChanged ? bandwidthConversion : nil
                    )
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(SuitePrimaryButtonStyle(role: .destructive))
                .disabled(
                    editSession.isReplacing || loopValidationError != nil
                )
            }
        }
        .padding(22)
        .frame(width: 760, height: 900)
        .interactiveDismissDisabled(editSession.isReplacing)
        .onAppear {
            compressed = settings.compressedS900
            loadZeroCrossings()
        }
        .onChange(of: editAttributes.playbackMode) { oldValue, newValue in
            if oldValue != newValue, newValue.requiresLoopMarkers {
                loopPointsManuallyEdited = true
            }
            refreshAuditionIfPossible()
        }
        .onChange(of: editAttributes.playbackDirection) { _, _ in
            refreshAuditionIfPossible()
        }
        .onChange(of: bandwidth) { _, _ in invalidateConvertedPreview() }
        .onChange(of: resamplingMode) { _, _ in invalidateConvertedPreview() }
        .onDisappear { audition.stop() }
    }

    private var bandwidthDouble: Binding<Double> {
        Binding(get: { Double(bandwidth) }, set: { bandwidth = Int($0.rounded()) })
    }

    private var bandwidthInput: some View {
        TextField("Bandwidth", value: $bandwidth, format: .number)
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .frame(width: 88)
            .frame(minHeight: 30)
            .multilineTextAlignment(.trailing)
            .background(Color.suiteSlab2)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.suiteRule2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var bandwidthConversion: S950BandwidthConversion {
        S950BandwidthConversion(bandwidth: bandwidth, mode: resamplingMode)
    }

    private var rateIsChanged: Bool {
        bandwidthConversion.sampleRate != Int(editSession.originalInspection.sampleRate.rounded())
    }

    private var rateRatio: Double {
        Double(bandwidthConversion.sampleRate) / editSession.originalInspection.sampleRate
    }

    private var estimatedReplacementBytes: Int64 {
        max(60, 60 + Int64((Double(max(0, editSession.sourceFile.byteSize - 60)) * rateRatio).rounded()))
    }

    private var estimatedSaving: Double {
        guard editSession.sourceFile.byteSize > 0 else { return 0 }
        return max(0, 1 - Double(estimatedReplacementBytes) / Double(editSession.sourceFile.byteSize))
    }

    private var projectedUsed: Int64 {
        max(0, model.snapshot.usedBytes - editSession.sourceFile.byteSize + estimatedReplacementBytes)
    }

    private var projectedFree: Int64 {
        max(0, model.snapshot.totalBytes - projectedUsed)
    }

    private func invalidateConvertedPreview() {
        audition.stop()
        convertedPreviewURL = nil
        previewError = nil
    }

    private func prepareConvertedPreview(startAuditionAfter: Bool = false) {
        audition.stop()
        isPreparingPreview = true
        previewError = nil
        let source = editSession.wavURL
        let destination = editSession.workspace.url.appendingPathComponent("bandwidth-preview.wav")
        let conversion = bandwidthConversion
        Task {
            do {
                _ = try await Task.detached {
                    try? FileManager.default.removeItem(at: destination)
                    return try WAVService.resampleS950(source, to: destination, conversion: conversion)
                }.value
                convertedPreviewURL = destination
                if startAuditionAfter { beginCurrentAudition() }
            } catch {
                previewError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isPreparingPreview = false
        }
    }

    private func checkSavedMarkers() {
        do {
            let markers = try WAVService.cueSampleOffsets(in: editSession.wavURL)
                .sorted()
            if markers.count == 2, markers[0] < markers[1] {
                loadZeroCrossings()
                loopStart = Int(markers[0])
                loopEnd = Int(markers[1])
                loopPointsManuallyEdited = false
                markerSummary = "Start \(markers[0]) · End \(markers[1])"
                refreshAuditionIfPossible()
            } else {
                markerSummary = "Found \(markers.count); exactly 2 are required"
            }
        } catch {
            markerSummary = error.localizedDescription
        }
    }

    private var loopStartBinding: Binding<Int> {
        Binding(
            get: { loopStart },
            set: {
                loopStart = $0
                loopPointsManuallyEdited = true
                markerSummary = "Values changed here"
                refreshAuditionIfPossible()
            }
        )
    }

    private var loopEndBinding: Binding<Int> {
        Binding(
            get: { loopEnd },
            set: {
                loopEnd = $0
                loopPointsManuallyEdited = true
                markerSummary = "Values changed here"
                refreshAuditionIfPossible()
            }
        )
    }

    private var loopValidationError: String? {
        let length = Int(editSession.originalAttributes.sampleLength)
        guard loopStart >= 0, loopEnd >= 0 else {
            return "Loop positions cannot be negative."
        }
        guard loopStart < loopEnd else {
            return "Loop start must be before loop end."
        }
        guard loopEnd <= length else {
            return "Loop end must not exceed the sample length."
        }
        return nil
    }

    private var loopLength: Int {
        max(0, loopEnd - loopStart)
    }

    private var previousLoopStartCrossing: WAVZeroCrossing? {
        zeroCrossingMap?.previous(before: loopStart)
    }

    private var nextLoopStartCrossing: WAVZeroCrossing? {
        guard let crossing = zeroCrossingMap?.next(after: loopStart),
              crossing.frame < loopEnd
        else { return nil }
        return crossing
    }

    private var previousLoopEndCrossing: WAVZeroCrossing? {
        guard let crossing = zeroCrossingMap?.previous(before: loopEnd),
              crossing.frame > loopStart
        else { return nil }
        return crossing
    }

    private var nextLoopEndCrossing: WAVZeroCrossing? {
        zeroCrossingMap?.next(after: loopEnd)
    }

    @ViewBuilder
    private func zeroCrossingControls(
        position: Int,
        previous: WAVZeroCrossing?,
        next: WAVZeroCrossing?,
        move: @escaping (WAVZeroCrossing) -> Void
    ) -> some View {
        Button {
            if let previous { move(previous) }
        } label: {
            Image(systemName: "chevron.left")
        }
        .buttonStyle(.plain)
        .frame(width: 26, height: 24)
        .background(Color.suiteSlab)
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.suiteRule2))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .disabled(previous == nil)
        .help("Move to the previous zero crossing")

        Image(systemName: zeroCrossingIcon(at: position))
            .frame(width: 18)
            .foregroundStyle(
                zeroCrossingMap?.direction(at: position) == nil
                    ? Color.suiteUnit : Color.suiteBlue
            )
            .help(zeroCrossingDescription(at: position))

        Button {
            if let next { move(next) }
        } label: {
            Image(systemName: "chevron.right")
        }
        .buttonStyle(.plain)
        .frame(width: 26, height: 24)
        .background(Color.suiteSlab)
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.suiteRule2))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .disabled(next == nil)
        .help("Move to the next zero crossing")
    }

    private func zeroCrossingIcon(at position: Int) -> String {
        switch zeroCrossingMap?.direction(at: position) {
        case .upward: return "arrow.up.right"
        case .downward: return "arrow.down.right"
        case nil: return "minus"
        }
    }

    private func zeroCrossingDescription(at position: Int) -> String {
        switch zeroCrossingMap?.direction(at: position) {
        case .upward: return "Upward zero crossing"
        case .downward: return "Downward zero crossing"
        case nil: return "The current position is not a zero crossing"
        }
    }

    private func loadZeroCrossings() {
        do {
            zeroCrossingMap = try WAVService.zeroCrossings(
                in: editSession.wavURL
            )
            zeroCrossingError = nil
        } catch {
            zeroCrossingMap = nil
            zeroCrossingError =
                (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private var currentLoopPoints: S9LoopPoints? {
        guard loopValidationError == nil,
              let start = UInt32(exactly: loopStart),
              let end = UInt32(exactly: loopEnd)
        else { return nil }
        return S9LoopPoints(start: start, end: end)
    }

    private func openWAVInEditor() {
        audition.stop()
        let points = loopPointsManuallyEdited ? currentLoopPoints : nil
        if model.reopenExternalAudioEditor(
            editSession,
            loopPoints: points
        ), points != nil {
            loopPointsManuallyEdited = false
            markerSummary = "Loop markers saved to WAV"
        }
    }

    private func refreshAuditionIfPossible() {
        guard !editAttributes.playbackMode.requiresLoopMarkers
                || loopValidationError == nil else {
            audition.stop()
            return
        }
        guard let url = currentAuditionURL else {
            audition.stop()
            return
        }
        audition.updateIfPlaying(
            url: url,
            mode: editAttributes.playbackMode,
            direction: editAttributes.playbackDirection,
            start: auditionLoopStart,
            end: auditionLoopEnd
        )
    }

    private var currentAuditionURL: URL? {
        rateIsChanged ? convertedPreviewURL : editSession.wavURL
    }

    private var auditionLoopStart: Int {
        rateIsChanged ? Int((Double(loopStart) * rateRatio).rounded()) : loopStart
    }

    private var auditionLoopEnd: Int {
        rateIsChanged ? Int((Double(loopEnd) * rateRatio).rounded()) : loopEnd
    }

    private func toggleCurrentAudition() {
        if audition.isPlaying {
            audition.stop()
            return
        }
        if rateIsChanged, convertedPreviewURL == nil {
            prepareConvertedPreview(startAuditionAfter: true)
            return
        }
        beginCurrentAudition()
    }

    private func beginCurrentAudition() {
        guard let url = currentAuditionURL else { return }
        audition.play(
            url: url,
            mode: editAttributes.playbackMode,
            direction: editAttributes.playbackDirection,
            start: auditionLoopStart,
            end: auditionLoopEnd
        )
    }
}

struct FormatImageSheet: View {
    enum Mode: String, CaseIterable, Identifiable {
        case new = "New Image"
        case existing = "Format Open Image"
        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .new
    @State private var preset: FormatPreset = .s900Low
    @State private var destination: URL?
    @State private var backup = true
    @State private var confirmation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: mode == .new ? "plus.rectangle.on.rectangle" : "externaldrive.badge.exclamationmark")
                    .font(.system(size: 34))
                    .foregroundStyle(mode == .existing ? Color.suiteAmber : Color.suiteBlue)
                VStack(alignment: .leading) {
                    Text("New or Format Image")
                        .font(SuiteFont.medium(15)).tracking(2.4)
                    Text(mode == .new ? "Create an exact-size raw image and format it for an S950." : "Formatting permanently erases the open image.")
                        .foregroundStyle(Color.suiteUnit)
                }
            }

            Picker("Operation", selection: $mode) {
                ForEach(Mode.allCases) { value in
                    Text(value.rawValue).tag(value)
                        .disabled(value == .existing && model.session == nil)
                }
            }
            .pickerStyle(.segmented)

            Form {
                Picker("Format preset", selection: $preset) {
                    Section("Floppy images") {
                        ForEach(FormatPreset.allCases.filter(\.isFloppy)) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    Section("Hard-disk images") {
                        ForEach(FormatPreset.allCases.filter { !$0.isFloppy }) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                }
                LabeledContent("Exact size", value: Int64(preset.byteCount).formattedByteCount)
                LabeledContent("AKAI command", value: preset.command)
            }
            .formStyle(.grouped)

            if mode == .new {
                GroupBox("Destination") {
                    HStack {
                        Text(destination?.path ?? "Choose where to save the new IMG file")
                            .foregroundStyle(destination == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseDestination() }
                    }
                    .padding(7)
                }
            } else if let session = model.session {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Every file in \(session.imageURL.lastPathComponent) will be permanently erased.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.suiteAmber)
                        Toggle("Create timestamped backup first", isOn: $backup)
                        TextField("Type \(session.imageURL.lastPathComponent) to confirm", text: $confirmation)
                    }
                    .padding(6)
                }
            }

            Spacer()
            HStack {
                Text("Only image files are formatted. Physical drives are never targeted.")
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(mode == .new ? "Create and Format" : "Erase and Format", role: mode == .existing ? .destructive : nil) {
                    perform()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(SuitePrimaryButtonStyle(role: .neutral))
                .disabled(!canPerform)
            }
        }
        .padding(22)
        .frame(width: 660, height: 550)
        .onAppear {
            backup = settings.backupBeforeDestructive
            if model.session == nil { mode = .new }
        }
    }

    private var canPerform: Bool {
        switch mode {
        case .new: return destination != nil
        case .existing:
            return model.session != nil && confirmation == model.session?.imageURL.lastPathComponent
        }
    }

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.title = "Save New AKAI Image"
        panel.nameFieldStringValue = "AKAI Disk.img"
        panel.allowedContentTypes = [UTType(filenameExtension: "img") ?? .data]
        if panel.runModal() == .OK { destination = panel.url }
    }

    private func perform() {
        switch mode {
        case .new:
            if let destination { model.createAndFormat(at: destination, preset: preset) }
        case .existing:
            model.formatCurrent(preset: preset, backup: backup)
        }
    }
}

struct DiskInfoSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Disk Information", systemImage: "info.circle.fill")
                    .font(SuiteFont.medium(15)).tracking(2.4)
                Spacer()
                Button("Copy") { model.copyDiskInfo() }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            ScrollView {
                Text(model.diskInformationText)
                    .font(SuiteFont.regular(11))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(Color.suiteBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("Raw AKAI Util responses are included so unusual media can still be diagnosed.")
                .font(SuiteFont.regular(10))
                .foregroundStyle(Color.suiteUnit)
        }
        .padding(20)
        .frame(width: 720, height: 600)
    }
}

struct DeleteAllSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Delete Every File in This Volume", systemImage: "exclamationmark.triangle.fill")
                .font(SuiteFont.medium(15)).tracking(2.4)
                .foregroundStyle(Color.suiteRed)
            Text("This permanently deletes exactly \(model.snapshot.files.count) files from \(model.snapshot.currentPath). It does not use AKAI Util’s wipe-volume command.")
            ScrollView {
                Text(model.snapshot.files.map { "\($0.index). \($0.name)" }.joined(separator: "\n"))
                    .font(SuiteFont.regular(11))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(height: 170)
            .padding(8)
            .background(Color.suiteBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            Toggle("Create a timestamped backup first", isOn: $settings.backupBeforeDestructive)
            TextField("Type DELETE ALL to confirm", text: $confirmation)
            Text("Deletion inside an IMG is not recoverable without a backup.")
                .font(SuiteFont.regular(10))
                .foregroundStyle(Color.suiteUnit)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Delete All Files", role: .destructive) {
                    dismiss()
                    model.deleteAllFiles()
                }
                .disabled(confirmation != "DELETE ALL")
            }
        }
        .padding(22)
        .frame(width: 590, height: 510)
    }
}
