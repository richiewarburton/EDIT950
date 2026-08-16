import AppKit
@preconcurrency import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SampleLoopAuditionController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let varispeed = AVAudioUnitVarispeed()
    private var playbackNodesAttached = false
    private var activeBuffer: AVAudioPCMBuffer?
    private var activeMode: S9PlaybackMode = .oneShot
    private var activeDirection: S9PlaybackDirection = .normal
    private var activeSemitoneOffset = 0
    private var playbackGeneration = UUID()
    var onPlaybackEnded: (() -> Void)?
#if AKAI_TESTING
    var onRenderedAudioForTesting: (() -> Void)?
    private var testTapInstalled = false
#endif

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
        end: Int,
        semitoneOffset: Int = 0
    ) {
        if isPlaying {
            stop()
        } else {
            play(
                url: url,
                mode: mode,
                direction: direction,
                start: start,
                end: end,
                semitoneOffset: semitoneOffset
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
        end: Int,
        semitoneOffset: Int? = nil
    ) {
        guard isPlaying else { return }
        play(
            url: url,
            mode: mode,
            direction: direction,
            start: start,
            end: end,
            semitoneOffset: semitoneOffset ?? activeSemitoneOffset
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
        end: Int,
        semitoneOffset: Int = 0
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
            let directedBuffer: AVAudioPCMBuffer
            switch (mode, direction) {
            case (.alternatingLoop, .normal):
                directedBuffer = try alternatingBuffer(
                    forward: forward,
                    startsReversed: false
                )
            case (.alternatingLoop, .reverse):
                directedBuffer = try alternatingBuffer(
                    forward: forward,
                    startsReversed: true
                )
            case (_, .reverse):
                directedBuffer = try reversedBuffer(forward)
            default:
                directedBuffer = forward
            }
            let playable = try convertedToCurrentOutputRate(directedBuffer)

            try preparePlayback(
                format: playable.format,
                semitoneOffset: semitoneOffset
            )
            activeBuffer = playable
            activeMode = mode
            activeDirection = direction
            activeSemitoneOffset = semitoneOffset
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

    private func preparePlayback(
        format: AVAudioFormat,
        semitoneOffset: Int
    ) throws {
        player.stop()
        engine.stop()
        if playbackNodesAttached {
            engine.disconnectNodeOutput(player)
            engine.disconnectNodeOutput(varispeed)
        } else {
            engine.attach(player)
            engine.attach(varispeed)
            playbackNodesAttached = true
        }
        varispeed.rate = Float(pow(2.0, Double(semitoneOffset) / 12.0))
        engine.connect(player, to: varispeed, format: format)
        engine.connect(varispeed, to: engine.mainMixerNode, format: format)
#if AKAI_TESTING
        if testTapInstalled {
            engine.mainMixerNode.removeTap(onBus: 0)
        }
        testTapInstalled = true
        engine.mainMixerNode.installTap(
            onBus: 0,
            bufferSize: 256,
            format: nil
        ) { [weak self] buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)
            guard (0..<channelCount).contains(where: { channel in
                (0..<frameCount).contains { abs(channels[channel][$0]) > 0.000_01 }
            }) else { return }
            Task { @MainActor [weak self] in
                self?.onRenderedAudioForTesting?()
            }
        }
#endif
        engine.prepare()
        try engine.start()
    }

    private func convertedToCurrentOutputRate(
        _ source: AVAudioPCMBuffer
    ) throws -> AVAudioPCMBuffer {
        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard outputRate > 0,
              abs(source.format.sampleRate - outputRate) >= 0.5
        else { return source }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: outputRate,
            channels: source.format.channelCount,
            interleaved: false
        ), let converter = AVAudioConverter(from: source.format, to: format) else {
            throw AppError.verificationFailed(
                "The audition audio could not be adapted to the current output sample rate."
            )
        }
        converter.sampleRateConverterQuality = .max
        let capacity = AVAudioFrameCount(
            ceil(
                Double(source.frameLength) * outputRate
                    / source.format.sampleRate
            )
        ) + 64
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: capacity
        ) else {
            throw AppError.verificationFailed(
                "The converted audition buffer could not be created."
            )
        }
        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) {
            _, inputStatus in
            guard !suppliedInput else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return source
        }
        if let conversionError { throw conversionError }
        guard status != .error, converted.frameLength > 0 else {
            throw AppError.verificationFailed(
                "The audition audio could not be converted to \(Int(outputRate)) Hz."
            )
        }
        return converted
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

private enum SampleEditWorkflowPage: Int, CaseIterable, Identifiable {
    case wavReplace
    case playbackLoop
    case bandwidthQuality

    var id: Int { rawValue }
    var number: String { "0\(rawValue + 1)" }
    var title: String {
        switch self {
        case .wavReplace: "WAV &\nSAVE"
        case .playbackLoop: "PLAYBACK &\nLOOP"
        case .bandwidthQuality: "BANDWIDTH &\nQUALITY"
        }
    }
}

struct ExternalSampleEditSheet: View {
    static let baseSize = CGSize(width: 720, height: 420)
    static let saveAsNewActionTitle = "SAVE AS NEW…"

    static func presentationSize(for zoom: SuiteZoomLevel) -> CGSize {
        let scale = CGFloat(zoom.rawValue)
        return CGSize(
            width: baseSize.width * scale,
            height: baseSize.height * scale
        )
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var editSession: ExternalSampleEditSession
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var suitePreferences: SuitePreferences
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
    @State private var convertedPreviewFrameCount: UInt32?
    @State private var isPreparingPreview = false
    @State private var previewError: String?
    @State private var previewGeneration = UUID()
    @State private var keyboardVisible = true
    @State private var keyboardBaseNote: Int
    @State private var selectedAuditionNote: Int
    @State private var keyboardBehavior: SampleKeyboardBehavior = .selectForAudition
    @State private var midiAuditionEnabled = false
    @State private var midiInputChannel = -1
    @State private var midiNoteTracker = MIDIMonophonicNoteTracker()
    @State private var activeHelpText: String?
    @State private var workflowPage: SampleEditWorkflowPage
    @State private var showSaveAsNewPrompt = false
    @State private var showReplacePrompt = false
    @State private var newSampleName = ""
    @StateObject private var audition = SampleLoopAuditionController()
    @StateObject private var midiMonitor = MIDIKeygroupMonitor()
    @FocusState private var newSampleNameFocused: Bool

    init(
        editSession: ExternalSampleEditSession,
        initialWorkflowPageIndex: Int = 0,
        initialSaveAsNewPromptVisible: Bool = false
    ) {
        self.editSession = editSession
        _workflowPage = State(
            initialValue: SampleEditWorkflowPage(
                rawValue: initialWorkflowPageIndex
            ) ?? .wavReplace
        )
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
        let rootNote = Int(attributes.rootNote)
        _selectedAuditionNote = State(initialValue: rootNote)
        _keyboardBaseNote = State(
            initialValue: Self.keyboardBase(near: rootNote)
        )
        _showSaveAsNewPrompt = State(
            initialValue: initialSaveAsNewPromptVisible
        )
        _newSampleName = State(initialValue: "NEW_SAMPLE")
    }

    var body: some View {
        VStack(spacing: 0) {
            sampleEditorHeader
            Divider().overlay(Color.suiteRule)
            HStack(spacing: 0) {
                workflowSidebar
                    .frame(width: 126)
                Divider().overlay(Color.suiteRule)
                workflowPageContent
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 306)
            Divider().overlay(Color.suiteRule)
            sampleEditorFooter
        }
        .frame(width: Self.baseSize.width, height: Self.baseSize.height)
        .foregroundStyle(Color.suiteInk)
        .background(Color.suiteBackground)
        .background {
            SampleEditorSpaceKeyMonitor {
                guard !editSession.isSaving,
                      !isPreparingPreview,
                      (!editAttributes.playbackMode.requiresLoopMarkers
                        || loopValidationError == nil)
                else { return false }
                toggleCurrentAudition()
                return true
            }
        }
        .overlay {
            if showSaveAsNewPrompt {
                saveAsNewPromptOverlay
            } else if showReplacePrompt {
                replacePromptOverlay
            }
        }
        .interactiveDismissDisabled(
            editSession.isSaving || showSaveAsNewPrompt || showReplacePrompt
        )
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
        .onChange(of: editAttributes.rootNote) { oldValue, newValue in
            if selectedAuditionNote == Int(oldValue) {
                selectedAuditionNote = Int(newValue)
            }
            keyboardBaseNote = Self.keyboardBase(near: Int(newValue))
            refreshAuditionIfPossible()
        }
        .onChange(of: bandwidth) { _, _ in bandwidthSettingsDidChange() }
        .onChange(of: resamplingMode) { _, _ in bandwidthSettingsDidChange() }
        .onChange(of: midiAuditionEnabled) { _, enabled in
            midiAuditionSettingDidChange(enabled)
        }
        .onChange(of: midiInputChannel) { _, channel in
            midiInputChannelDidChange(channel)
        }
        .onChange(of: midiMonitor.lastEvent) { _, envelope in
            handleMIDIEvent(envelope)
        }
        .onDisappear {
            previewGeneration = UUID()
            isPreparingPreview = false
            _ = midiNoteTracker.reset()
            midiMonitor.stop()
            audition.stop()
        }
        .scaleEffect(sampleEditorScale, anchor: .topLeading)
        .frame(
            width: sampleEditorPresentationSize.width,
            height: sampleEditorPresentationSize.height,
            alignment: .topLeading
        )
    }

    private var sampleEditorScale: CGFloat {
        CGFloat(suitePreferences.zoom.rawValue)
    }

    private var sampleEditorPresentationSize: CGSize {
        Self.presentationSize(for: suitePreferences.zoom)
    }

    private var sampleEditorHeader: some View {
        HStack(spacing: 11) {
            Image(nsImage: SuiteBrandAsset.image(named: "EDIT950-brand-mark"))
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("EDIT \(editSession.sourceFile.name.uppercased())")
                    .font(SuiteFont.medium(13))
                    .tracking(1.8)
                    .lineLimit(1)
                Text("S950 SAMPLE EDITOR · \(workflowPage.number) OF 03")
                    .font(SuiteFont.regular(8))
                    .tracking(1.0)
                    .foregroundStyle(Color.suiteUnit)
            }
            Spacer()
            Text("AUDITION: \(P9Keygroup.noteName(selectedAuditionNote))")
                .font(SuiteFont.medium(9))
                .tracking(0.8)
                .foregroundStyle(Color.suiteBlue)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var workflowSidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WORKFLOW")
                .font(SuiteFont.medium(8))
                .tracking(1.4)
                .foregroundStyle(Color.suiteUnit)
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
            ForEach(SampleEditWorkflowPage.allCases) { page in
                Button {
                    workflowPage = page
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(page.number)
                            .font(SuiteFont.medium(9))
                        Text(page.title)
                            .font(SuiteFont.medium(8))
                            .tracking(0.65)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(
                    SampleWorkflowButtonStyle(isSelected: workflowPage == page)
                )
            }
            Spacer()
            Text("ALL SETTINGS ARE KEPT AS YOU MOVE BETWEEN SCREENS")
                .font(SuiteFont.regular(7))
                .tracking(0.55)
                .foregroundStyle(Color.suiteUnit)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
        }
        .padding(.top, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.suitePanel)
    }

    @ViewBuilder
    private var workflowPageContent: some View {
        switch workflowPage {
        case .wavReplace:
            wavReplacePage
        case .playbackLoop:
            playbackLoopPage
        case .bandwidthQuality:
            bandwidthQualityPage
        }
    }

    private var wavReplacePage: some View {
        HStack(alignment: .top, spacing: 12) {
            compactSection(title: "WAV ROUND-TRIP") {
                compactValueRow("TEMPORARY FILE", editSession.wavURL.lastPathComponent)
                compactValueRow(
                    "EXPORTED FORMAT",
                    "\(Int(editSession.originalInspection.sampleRate)) Hz · "
                        + "\(editSession.originalInspection.bitDepth)-bit · "
                        + "\(editSession.originalInspection.channelCount == 1 ? "MONO" : "\(editSession.originalInspection.channelCount) CHANNELS")"
                )
                Text(
                    editSession.editorURL == nil
                        ? "Native attributes remain available. Choose an audio editor in Settings to edit the WAV."
                        : "Save over this WAV in the external editor; do not move it or use Save As."
                )
                .font(SuiteFont.regular(8))
                .foregroundStyle(Color.suiteUnit)
                .lineLimit(3)
                Button {
                    openWAVInEditor()
                } label: {
                    Text("OPEN WAV IN \(audioEditorName.uppercased())")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SuiteSecondaryButtonStyle())
                .disabled(editSession.editorURL == nil || loopValidationError != nil)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([editSession.wavURL])
                } label: {
                    Text("SHOW WAV IN FINDER")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SuiteSecondaryButtonStyle())
            }

            compactSection(
                title: "SAVE & VERIFY",
                help: saveHelp
            ) {
                Toggle("CREATE COMPRESSED S950 SAMPLE", isOn: $compressed)
                    .toggleStyle(.checkbox)
                    .font(SuiteFont.regular(9))
                Divider().overlay(Color.suiteRule2)
                compactValueRow(
                    "REPLACE PROJECTED IMG",
                    "\(projectedUsed.formattedByteCount) USED · \(projectedFree.formattedByteCount) FREE"
                )
                compactValueRow(
                    "SAVE AS NEW ESTIMATE",
                    "\(estimatedReplacementBytes.formattedByteCount) ADDITIONAL · \(projectedNewFree.formattedByteCount) FREE"
                )
                Label(
                    "ORIGINAL SAMPLE NAME AND P9 REFERENCES ARE PRESERVED",
                    systemImage: "checkmark.shield.fill"
                )
                .font(SuiteFont.medium(8))
                .foregroundStyle(Color.suiteBlue)
                .fixedSize(horizontal: false, vertical: true)
                Text(
                    "Choose whether to create a complete IMG backup in the final Save As New or Replace dialogue. The stored S9 is always re-exported and verified."
                )
                .font(SuiteFont.regular(8))
                .foregroundStyle(Color.suiteUnit)
                .lineLimit(4)
            }
        }
    }

    private var playbackLoopPage: some View {
        HStack(alignment: .top, spacing: 12) {
            compactSection(title: "PITCH & PLAYBACK") {
                HStack(alignment: .top, spacing: 7) {
                    rootPitchControl
                        .frame(width: 120)
                    WorkflowSegmentedPicker(
                        title: "DIRECTION",
                        options: S9PlaybackDirection.allCases,
                        selection: $editAttributes.playbackDirection,
                        label: \.title
                    )
                }
                WorkflowSegmentedPicker(
                    title: "PLAYBACK MODE",
                    options: S9PlaybackMode.allCases,
                    selection: $editAttributes.playbackMode,
                    label: \.title
                )
                samplePitchKeyboard
            }

            compactSection(title: "LOOP", help: markerRefreshHelp) {
                HStack(spacing: 10) {
                    compactMetric(
                        "SAMPLE",
                        editSession.originalAttributes.sampleLength.formatted()
                    )
                    compactMetric("LOOP", loopLength.formatted())
                }
                loopPositionRow(
                    title: "START",
                    value: loopStartBinding,
                    previous: previousLoopStartCrossing,
                    next: nextLoopStartCrossing
                )
                loopPositionRow(
                    title: "END",
                    value: loopEndBinding,
                    previous: previousLoopEndCrossing,
                    next: nextLoopEndCrossing
                )
                if let loopValidationError {
                    Label(loopValidationError, systemImage: "exclamationmark.triangle.fill")
                        .font(SuiteFont.regular(8))
                        .foregroundStyle(Color.suiteRed)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Button("REFRESH SAVED WAV MARKERS") { checkSavedMarkers() }
                        .buttonStyle(SuiteSecondaryButtonStyle())
                    helpButton(markerRefreshHelp)
                }
                if let markerSummary {
                    Text(markerSummary.uppercased())
                        .font(SuiteFont.regular(8))
                        .monospacedDigit()
                        .foregroundStyle(Color.suiteUnit)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Button {
                        toggleCurrentAudition()
                    } label: {
                        Label(
                            audition.isPlaying
                                ? "STOP · SPACE"
                                : "AUDITION \(P9Keygroup.noteName(selectedAuditionNote)) · SPACE",
                            systemImage: audition.isPlaying ? "stop.fill" : "play.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SuitePrimaryButtonStyle(role: .sample))
                    .disabled(
                        editSession.isSaving
                            || isPreparingPreview
                            || (editAttributes.playbackMode.requiresLoopMarkers
                                && loopValidationError != nil)
                    )
                    helpButton(auditionHelp)
                }
            }
        }
    }

    private var bandwidthQualityPage: some View {
        HStack(alignment: .top, spacing: 12) {
            compactSection(title: "S950 SAMPLING BANDWIDTH") {
                HStack(spacing: 8) {
                    Slider(value: bandwidthDouble, in: 3_000...19_200, step: 100)
                        .tint(Color.suiteBlue)
                    bandwidthInput
                }
                Text("\(bandwidth.formatted()) HZ BANDWIDTH")
                    .font(SuiteFont.medium(9))
                    .tracking(0.8)
                    .foregroundStyle(Color.suiteBlue)
                Divider().overlay(Color.suiteRule2)
                compactValueRow(
                    "ACTUAL SAMPLE RATE",
                    "\(bandwidthConversion.sampleRate.formatted()) SAMPLES/SEC"
                )
                HStack(spacing: 7) {
                    compactValueRow(
                        "SAMPLE SIZE BEFORE",
                        storageProjection.originalBytes.formattedByteCount
                    )
                    Divider()
                        .overlay(Color.suiteRule2)
                        .frame(height: 27)
                    compactValueRow(
                        "SAMPLE SIZE AFTER",
                        "\(storageProjection.convertedBytes.formattedByteCount) EST."
                    )
                }
                compactValueRow(
                    "ESTIMATED SAVING",
                    estimatedSaving.formatted(.percent.precision(.fractionLength(1)))
                )
                compactValueRow(
                    "PROJECTED IMG",
                    "\(projectedUsed.formattedByteCount) USED · \(projectedFree.formattedByteCount) FREE"
                )
                SuiteIMGCapacityMeter(
                    usedBytes: projectedUsed,
                    totalBytes: model.snapshot.totalBytes,
                    accessibilityLabel: "Projected IMG capacity"
                )
            }

            compactSection(title: "RESAMPLING QUALITY") {
                WorkflowSegmentedPicker(
                    title: "CHARACTER",
                    options: S950ResamplingMode.allCases,
                    selection: $resamplingMode,
                    label: \.title
                )
                Label(
                    resamplingMode == .antiAliased
                        ? "CLEAN · ANTI-ALIASED"
                        : "RAW · S950-STYLE ALIASING",
                    systemImage: resamplingMode == .antiAliased
                        ? "waveform.path.ecg" : "waveform"
                )
                .font(SuiteFont.medium(9))
                .foregroundStyle(Color.suiteBlue)
                Text(
                    resamplingMode == .antiAliased
                        ? "Removes frequencies that cannot survive the lower sample rate before conversion."
                        : "Applies no protective low-pass filter, intentionally retaining aliasing and grit."
                )
                .font(SuiteFont.regular(8))
                .foregroundStyle(Color.suiteUnit)
                .lineLimit(4)
                if isPreparingPreview {
                    Label("PREPARING AUDITION PREVIEW…", systemImage: "waveform")
                        .font(SuiteFont.regular(8))
                        .foregroundStyle(Color.suiteUnit)
                }
                if let previewError {
                    Label(previewError, systemImage: "exclamationmark.triangle.fill")
                        .font(SuiteFont.regular(8))
                        .foregroundStyle(Color.suiteRed)
                        .lineLimit(3)
                }
            }
        }
    }

    private var rootPitchControl: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ROOT PITCH")
                .font(SuiteFont.medium(7))
                .tracking(0.65)
                .foregroundStyle(Color.suiteUnit)
            Picker("Root pitch", selection: $editAttributes.rootNote) {
                ForEach(0..<128, id: \.self) { note in
                    Text("\(P9Keygroup.noteName(note)) · MIDI \(note)").tag(note)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(Color.suiteSlab)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.suiteRule2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func loopPositionRow(
        title: String,
        value: Binding<Int>,
        previous: WAVZeroCrossing?,
        next: WAVZeroCrossing?
    ) -> some View {
        HStack(spacing: 2) {
            Text(title)
                .font(SuiteFont.medium(8))
                .tracking(0.65)
                .frame(width: 36, alignment: .leading)
            Spacer(minLength: 1)
            zeroCrossingControls(
                position: value.wrappedValue,
                previous: previous,
                next: next,
                move: { value.wrappedValue = $0.frame }
            )
            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .font(SuiteFont.regular(9))
                .frame(width: 66)
            Stepper(
                title,
                value: value,
                in: 0...Int(editSession.originalAttributes.sampleLength)
            )
            .labelsHidden()
            .controlSize(.small)
        }
    }

    private func compactMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(SuiteFont.regular(7))
                .tracking(0.65)
                .foregroundStyle(Color.suiteUnit)
            Text(value)
                .font(SuiteFont.medium(10))
                .monospacedDigit()
            Text("SAMPLES")
                .font(SuiteFont.regular(7))
                .tracking(0.6)
                .foregroundStyle(Color.suiteUnit)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.suiteSlab2)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func compactValueRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(SuiteFont.regular(7))
                .tracking(0.65)
                .foregroundStyle(Color.suiteUnit)
            Text(value.uppercased())
                .font(SuiteFont.medium(9))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactSection<Content: View>(
        title: String,
        help: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color.suiteBlue)
                    .frame(width: 3, height: 14)
                Text(title)
                    .font(SuiteFont.medium(9))
                    .tracking(1.0)
                Spacer()
                if let help { helpButton(help) }
            }
            content()
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.suitePanel)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.suiteRule2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func helpButton(_ text: String) -> some View {
        Button {
            activeHelpText = activeHelpText == text ? nil : text
        } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 8, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Color.suiteSlab2)
                .overlay(Circle().stroke(Color.suiteRule2))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: Binding(
            get: { activeHelpText == text },
            set: { if !$0, activeHelpText == text { activeHelpText = nil } }
        ), arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Color.suiteBlue)
                        .frame(width: 3, height: 14)
                    Text("HELP")
                        .font(SuiteFont.medium(9))
                        .tracking(1.0)
                    Spacer()
                    Button("CLOSE") { activeHelpText = nil }
                        .buttonStyle(.plain)
                        .font(SuiteFont.medium(8))
                        .foregroundStyle(Color.suiteBlue)
                }
                Text(text)
                    .font(SuiteFont.regular(9))
                    .foregroundStyle(Color.suiteInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 300, alignment: .leading)
            .background(Color.suitePanel)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Help")
        .accessibilityHint(text)
    }

    private var saveAsNewPromptOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.suiteBlue)
                        .frame(width: 4, height: 18)
                    Text("SAVE EDITED SOUND AS NEW SAMPLE")
                        .font(SuiteFont.medium(11))
                        .tracking(1.2)
                }

                Text(
                    "The original \(editSession.sourceFile.name.uppercased()) and all existing P9 references remain unchanged."
                )
                .font(SuiteFont.regular(9))
                .foregroundStyle(Color.suiteUnit)
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("NEW S950 SAMPLE NAME")
                        .font(SuiteFont.medium(8))
                        .tracking(0.8)
                        .foregroundStyle(Color.suiteLabel)
                    TextField("Name", text: $newSampleName)
                        .textFieldStyle(.plain)
                        .font(SuiteFont.medium(12))
                        .padding(.horizontal, 9)
                        .frame(height: 32)
                        .background(Color.suiteSlab2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    saveAsNewValidationError == nil
                                        ? Color.suiteRule2 : Color.suiteRed
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .focused($newSampleNameFocused)
                        .onSubmit {
                            if saveAsNewValidationError == nil {
                                commitSaveAsNew()
                            }
                        }
                    Text("UP TO 10 CHARACTERS · A–Z, 0–9, _ OR -")
                        .font(SuiteFont.regular(7))
                        .tracking(0.55)
                        .foregroundStyle(Color.suiteUnit)
                }

                if let saveAsNewValidationError {
                    Label(
                        saveAsNewValidationError,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(SuiteFont.regular(8))
                    .foregroundStyle(Color.suiteRed)
                } else {
                    Label(
                        "ESTIMATED \(estimatedReplacementBytes.formattedByteCount) ADDITIONAL · \(projectedNewFree.formattedByteCount) FREE AFTER SAVE",
                        systemImage: "externaldrive.fill.badge.plus"
                    )
                    .font(SuiteFont.regular(8))
                    .foregroundStyle(
                        model.snapshot.freeBytes > 0
                            && estimatedReplacementBytes > model.snapshot.freeBytes
                                ? Color.suiteRed : Color.suiteBlue
                    )
                }

                backupChoice

                HStack(spacing: 8) {
                    Spacer()
                    Button("CANCEL") {
                        closeSaveAsNewPrompt()
                    }
                    .buttonStyle(SuiteSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)

                    Button {
                        commitSaveAsNew()
                    } label: {
                        Text("SAVE AS NEW")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    }
                    .buttonStyle(SuitePrimaryButtonStyle(role: .sample))
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        saveAsNewValidationError != nil
                            || (model.snapshot.freeBytes > 0
                                && estimatedReplacementBytes
                                    > model.snapshot.freeBytes)
                    )
                }
            }
            .padding(18)
            .frame(width: 430)
            .background(Color.suitePanel)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.suiteRule2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
        }
        .accessibilityAddTraits(.isModal)
        .onExitCommand(perform: closeSaveAsNewPrompt)
    }

    private var replacePromptOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(Color.suiteRed)
                        .frame(width: 4, height: 18)
                    Text("REPLACE ORIGINAL SAMPLE")
                        .font(SuiteFont.medium(11))
                        .tracking(1.2)
                }

                Text(
                    "Replace (editSession.sourceFile.name.uppercased()) in the IMG, then re-export and verify the stored S9 byte-for-byte."
                )
                .font(SuiteFont.regular(9))
                .foregroundStyle(Color.suiteUnit)
                .fixedSize(horizontal: false, vertical: true)

                backupChoice

                HStack(spacing: 8) {
                    Spacer()
                    Button("CANCEL") {
                        showReplacePrompt = false
                    }
                    .buttonStyle(SuiteSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)

                    Button("REPLACE") {
                        commitReplace()
                    }
                    .buttonStyle(SuitePrimaryButtonStyle(role: .destructive))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(18)
            .frame(width: 430)
            .background(Color.suitePanel)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.suiteRule2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
        }
        .accessibilityAddTraits(.isModal)
        .onExitCommand { showReplacePrompt = false }
    }

    private var backupChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("CREATE AND VERIFY A COMPLETE IMG BACKUP FIRST", isOn: $createBackup)
                .toggleStyle(.checkbox)
                .font(SuiteFont.regular(9))
            Text(
                createBackup
                    ? "A failed write or verification is restored automatically from the new backup."
                    : "No backup will be created. Automatic rollback is unavailable after mutation begins."
            )
            .font(SuiteFont.regular(8))
            .foregroundStyle(createBackup ? Color.suiteUnit : Color.suiteAmber)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.suiteSlab)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.suiteRule))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var sampleEditorFooter: some View {
        HStack(spacing: 10) {
            footerStatus
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("CANCEL") {
                audition.stop()
                model.cancelExternalSampleEdit(editSession)
            }
            .buttonStyle(SuiteSecondaryButtonStyle())
            .keyboardShortcut(.cancelAction)
            .disabled(editSession.isSaving || showSaveAsNewPrompt || showReplacePrompt)

            Button {
                requestSaveAsNew()
            } label: {
                Text(Self.saveAsNewActionTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            }
            .buttonStyle(SuitePrimaryButtonStyle(role: .sample))
            .disabled(
                editSession.isSaving
                    || showSaveAsNewPrompt
                    || showReplacePrompt
                    || loopValidationError != nil
            )

            Button("REPLACE") {
                audition.stop()
                editSession.errorMessage = nil
                showReplacePrompt = true
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(SuitePrimaryButtonStyle(role: .destructive))
            .disabled(
                editSession.isSaving
                    || showSaveAsNewPrompt
                    || showReplacePrompt
                    || loopValidationError != nil
            )
        }
        .padding(.horizontal, 12)
        .frame(height: 62)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.suitePanel)
    }

    @ViewBuilder
    private var footerStatus: some View {
        Group {
            if editSession.isSaving {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(model.progress?.detail ?? "PREPARING SAMPLE…")
                }
                .foregroundStyle(Color.suiteUnit)
            } else if let error = editSession.errorMessage
                        ?? audition.errorMessage
                        ?? zeroCrossingError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.suiteRed)
            } else {
                Text("SOURCE IMG REMAINS UNCHANGED UNTIL THE FINAL SAVE STEP")
                    .foregroundStyle(Color.suiteUnit)
            }
        }
        .font(SuiteFont.regular(8))
        .lineLimit(2)
    }

    private var suggestedNewSampleName: String {
        let sourceBase = AkaiFilename.sanitizedBase(
            editSession.sourceFile.name,
            family: .s900,
            maximumLength: 10
        )
        let existing = Set(model.availableSampleNames.map {
            AkaiFilename.sanitizedBase(
                $0,
                family: .s900,
                maximumLength: 10
            ).uppercased()
        })
        return AkaiFilename.uniqueName(
            base: sourceBase,
            existing: existing,
            maximumLength: 10
        )
    }

    private var saveAsNewValidationError: String? {
        if let validationError = AkaiFilename.s950BaseValidationError(
            newSampleName
        ) {
            return validationError
        }
        let requestedKey = AkaiFilename.normalizedS950Base(newSampleName)
            .replacingOccurrences(of: "_", with: " ")
        let existingKeys = Set(model.availableSampleNames.map {
            $0.uppercased().replacingOccurrences(of: "_", with: " ")
        })
        if existingKeys.contains(requestedKey) {
            return "\(AkaiFilename.normalizedS950Base(newSampleName)).S9 already exists in this volume."
        }
        return nil
    }

    private func requestSaveAsNew() {
        audition.stop()
        editSession.errorMessage = nil
        newSampleName = suggestedNewSampleName
        showSaveAsNewPrompt = true
        Task { @MainActor in
            newSampleNameFocused = true
        }
    }

    private func closeSaveAsNewPrompt() {
        newSampleNameFocused = false
        showSaveAsNewPrompt = false
    }

    private func commitReplace() {
        showReplacePrompt = false
        audition.stop()
        model.replaceEditedS9Sample(
            editSession,
            compressed: compressed,
            createBackup: createBackup,
            attributes: editAttributes,
            loopPoints: loopPointsManuallyEdited ? currentLoopPoints : nil,
            bandwidthConversion: rateIsChanged ? bandwidthConversion : nil,
            onSuccess: { dismiss() }
        )
    }

    private func commitSaveAsNew() {
        guard saveAsNewValidationError == nil else { return }
        let requestedName = AkaiFilename.normalizedS950Base(newSampleName)
        closeSaveAsNewPrompt()
        audition.stop()
        model.saveEditedS9SampleAsNew(
            editSession,
            requestedName: requestedName,
            compressed: compressed,
            createBackup: createBackup,
            attributes: editAttributes,
            loopPoints: loopPointsManuallyEdited ? currentLoopPoints : nil,
            bandwidthConversion: rateIsChanged ? bandwidthConversion : nil,
            onSuccess: { dismiss() }
        )
    }

    private var audioEditorName: String {
        editSession.editorURL?.deletingPathExtension().lastPathComponent
            ?? "AUDIO EDITOR"
    }

    private var markerRefreshHelp: String {
        "After saving marker changes in the external editor, return here and click Refresh Saved WAV Markers. Replacement reads saved markers automatically; refreshing lets you verify them first."
    }

    private var auditionHelp: String {
        "Space starts or stops audition at the selected keyboard note. Audition follows the selected direction and playback mode. Active playback updates when pitch, loop points or sampling bandwidth change; audio continues while a new bandwidth preview is prepared."
    }

    private var saveHelp: String {
        "Replace keeps the original sample name so P9 references remain valid. Save As New asks for a different S950 name, retains the original byte-for-byte and leaves its P9 references unchanged. The stored S9 is always re-exported and verified."
    }

    private var samplePitchKeyboard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        keyboardVisible.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(
                            systemName: keyboardVisible
                                ? "chevron.down" : "chevron.right"
                        )
                        .frame(width: 10)
                        Text("KEYBOARD")
                            .font(SuiteFont.medium(8))
                            .tracking(0.7)
                    }
                    .frame(minHeight: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(keyboardVisible ? "Hide pitch keyboard" : "Show pitch keyboard")

                Spacer(minLength: 2)

                Button {
                    keyboardBaseNote = max(0, keyboardBaseNote - 12)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.down")
                        Text("OCT")
                            .font(SuiteFont.medium(7))
                    }
                        .frame(width: 40, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SuiteKeyboardControlButtonStyle())
                .disabled(keyboardBaseNote == 0)
                .help("Keyboard down one octave")

                Text(keyboardRangeTitle)
                    .font(SuiteFont.regular(8))
                    .monospacedDigit()
                    .frame(minWidth: 52)

                Button {
                    keyboardBaseNote = min(96, keyboardBaseNote + 12)
                } label: {
                    HStack(spacing: 2) {
                        Text("OCT")
                            .font(SuiteFont.medium(7))
                        Image(systemName: "chevron.up")
                    }
                        .frame(width: 40, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SuiteKeyboardControlButtonStyle())
                .disabled(keyboardBaseNote == 96)
                .help("Keyboard up one octave")
            }

            if keyboardVisible {
                WorkflowSegmentedPicker(
                    title: "KEY ACTION",
                    options: SampleKeyboardBehavior.allCases,
                    selection: $keyboardBehavior,
                    label: \.title
                )

                HStack(spacing: 5) {
                    Toggle("MIDI AUDITION", isOn: $midiAuditionEnabled)
                        .font(SuiteFont.medium(7))
                        .tracking(0.45)
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("sample-midi-audition-toggle")
                        .help(midiAuditionHelp)
                    Spacer(minLength: 2)
                    Picker("MIDI input channel", selection: $midiInputChannel) {
                        Text("OMNI").tag(-1)
                        ForEach(0..<16, id: \.self) { channel in
                            Text("CH \(channel + 1)").tag(channel)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 68)
                    .disabled(!midiAuditionEnabled)
                    .accessibilityIdentifier("sample-midi-channel-picker")
                    Button("PANIC") { panicMIDIAudition() }
                        .font(SuiteFont.medium(7))
                        .buttonStyle(SuiteKeyboardControlButtonStyle())
                        .disabled(!midiAuditionEnabled)
                        .accessibilityIdentifier("sample-midi-panic-button")
                        .help("Stop audition and clear every held MIDI note.")
                }

                Text(midiAuditionStatus)
                    .font(SuiteFont.regular(7))
                    .tracking(0.35)
                    .foregroundStyle(
                        midiMonitor.errorMessage == nil
                            ? Color.suiteUnit : Color.suiteRed
                    )
                    .lineLimit(1)
                    .accessibilityIdentifier("sample-midi-audition-status")

                TwoOctaveSampleKeyboard(
                    baseNote: keyboardBaseNote,
                    rootNote: editAttributes.rootNote,
                    selectedNote: selectedAuditionNote,
                    height: 50,
                    noteAction: handleKeyboardNote
                )

                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.suiteBlue)
                        .frame(width: 7, height: 7)
                    Text("ROOT")
                    Circle()
                        .fill(Color.suiteYellow)
                        .frame(width: 7, height: 7)
                    Text("AUDITION NOTE")
                    Spacer()
                    Text(
                        "AUDITION: \(P9Keygroup.noteName(selectedAuditionNote))"
                    )
                    .foregroundStyle(Color.suiteBlue)
                }
                .font(SuiteFont.regular(7))
                .tracking(0.5)
            }
        }
        .padding(6)
        .background(Color.suiteSlab2)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.suiteRule2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var keyboardRangeTitle: String {
        "\(P9Keygroup.noteName(keyboardBaseNote))–"
            + P9Keygroup.noteName(min(127, keyboardBaseNote + 24))
    }

    private static func keyboardBase(near rootNote: Int) -> Int {
        min(96, max(0, ((rootNote / 12) - 1) * 12))
    }

    private func handleKeyboardNote(_ note: Int) {
        guard !editSession.isSaving,
              !isPreparingPreview,
              (!editAttributes.playbackMode.requiresLoopMarkers
                || loopValidationError == nil)
        else { return }
        selectedAuditionNote = note
        switch keyboardBehavior {
        case .playOnClick:
            if rateIsChanged, convertedPreviewURL == nil {
                prepareConvertedPreview(startAuditionAfter: true)
            } else {
                beginCurrentAudition()
            }
        case .selectForAudition:
            refreshAuditionIfPossible()
        }
    }

    private var midiAuditionHelp: String {
        "Input only. When enabled, MIDI notes play this temporary sample audition on the selected input channel. EDIT950 sends no MIDI and does not alter the IMG, P9 or S9."
    }

    private var midiAuditionStatus: String {
        guard midiAuditionEnabled else { return "MIDI AUDITION OFF · INPUT ONLY" }
        if let error = midiMonitor.errorMessage { return error.uppercased() }
        guard midiMonitor.sourceCount > 0 else {
            return "ON · NO MIDI INPUTS · INPUT ONLY"
        }
        return "\(midiMonitor.lastEventDescription.uppercased()) · INPUT ONLY"
    }

    private func midiAuditionSettingDidChange(_ enabled: Bool) {
        if enabled {
            _ = midiNoteTracker.setChannelFilter(
                midiInputChannel < 0 ? nil : midiInputChannel
            )
            midiMonitor.start()
        } else {
            if midiNoteTracker.reset() != nil { audition.stop() }
            midiMonitor.stop()
        }
    }

    private func midiInputChannelDidChange(_ channel: Int) {
        if midiNoteTracker.setChannelFilter(channel < 0 ? nil : channel) != nil {
            audition.stop()
        }
    }

    private func handleMIDIEvent(_ envelope: MIDIInputEventEnvelope?) {
        guard midiAuditionEnabled, let event = envelope?.event else { return }
        let action = MIDIAuditionPlaybackPolicy.resolvedAction(
            midiNoteTracker.handle(event),
            for: event,
            sustainsThroughNoteOff: editAttributes.playbackMode == .oneShot
        )
        guard let action else { return }
        switch action {
        case let .play(note, _):
            startMIDIAudition(note: note)
        case .stop:
            audition.stop()
        }
    }

    private func startMIDIAudition(note: Int) {
        guard !editSession.isSaving,
              (!editAttributes.playbackMode.requiresLoopMarkers
                || loopValidationError == nil)
        else { return }
        selectedAuditionNote = note
        if isPreparingPreview { return }
        if rateIsChanged, convertedPreviewURL == nil {
            prepareConvertedPreview(startAuditionAfter: true)
        } else {
            beginCurrentAudition()
        }
    }

    private func panicMIDIAudition() {
        _ = midiNoteTracker.reset()
        audition.stop()
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

    private var storageProjection: S9SampleStorageProjection {
        S9SampleStorageProjection(
            originalBytes: editSession.sourceFile.byteSize,
            originalSampleRate: editSession.originalInspection.sampleRate,
            convertedSampleRate: bandwidthConversion.sampleRate,
            currentImageUsedBytes: model.snapshot.usedBytes,
            imageTotalBytes: model.snapshot.totalBytes
        )
    }

    private var estimatedReplacementBytes: Int64 {
        storageProjection.convertedBytes
    }

    private var estimatedSaving: Double {
        guard editSession.sourceFile.byteSize > 0 else { return 0 }
        return max(0, 1 - Double(estimatedReplacementBytes) / Double(editSession.sourceFile.byteSize))
    }

    private var projectedUsed: Int64 {
        storageProjection.projectedImageUsedBytes
    }

    private var projectedFree: Int64 {
        storageProjection.projectedImageFreeBytes
    }

    private var projectedNewFree: Int64 {
        max(0, model.snapshot.freeBytes - estimatedReplacementBytes)
    }

    private func bandwidthSettingsDidChange() {
        let wasPlaying = audition.isPlaying
        let shouldContinueAudition = wasPlaying || isPreparingPreview
        previewGeneration = UUID()
        isPreparingPreview = false
        if let convertedPreviewURL {
            try? FileManager.default.removeItem(at: convertedPreviewURL)
        }
        convertedPreviewURL = nil
        convertedPreviewFrameCount = nil
        previewError = nil
        guard shouldContinueAudition else { return }

        if rateIsChanged {
            prepareConvertedPreview(
                startAuditionAfter: true,
                preserveCurrentPlayback: wasPlaying
            )
        } else {
            beginCurrentAudition()
        }
    }

    private func prepareConvertedPreview(
        startAuditionAfter: Bool = false,
        preserveCurrentPlayback: Bool = false
    ) {
        if !preserveCurrentPlayback {
            audition.stop()
        }
        let generation = UUID()
        previewGeneration = generation
        isPreparingPreview = true
        previewError = nil
        let source = editSession.wavURL
        let destination = editSession.workspace.url.appendingPathComponent(
            "bandwidth-preview-\(generation.uuidString).wav"
        )
        let conversion = bandwidthConversion
        Task {
            do {
                let inspection = try await Task.detached {
                    return try WAVService.resampleS950(source, to: destination, conversion: conversion)
                }.value
                guard previewGeneration == generation else {
                    try? FileManager.default.removeItem(at: destination)
                    return
                }
                guard let frameCount = UInt32(exactly: inspection.frameCount) else {
                    throw AppError.verificationFailed(
                        "The bandwidth preview has an unsupported sample length."
                    )
                }
                convertedPreviewURL = destination
                convertedPreviewFrameCount = frameCount
                isPreparingPreview = false
                if startAuditionAfter,
                   !preserveCurrentPlayback || audition.isPlaying {
                    beginCurrentAudition()
                }
            } catch {
                guard previewGeneration == generation else {
                    try? FileManager.default.removeItem(at: destination)
                    return
                }
                previewError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                isPreparingPreview = false
            }
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
        .buttonStyle(ZeroCrossingButtonStyle())
        .contentShape(Rectangle())
        .disabled(previous == nil)
        .accessibilityLabel("Previous zero crossing")
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
        .buttonStyle(ZeroCrossingButtonStyle())
        .contentShape(Rectangle())
        .disabled(next == nil)
        .accessibilityLabel("Next zero crossing")
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
            end: auditionLoopEnd,
            semitoneOffset: auditionSemitoneOffset
        )
    }

    private var currentAuditionURL: URL? {
        rateIsChanged ? convertedPreviewURL : editSession.wavURL
    }

    private var auditionLoopStart: Int {
        convertedAuditionLoopPoints.map { Int($0.start) } ?? loopStart
    }

    private var auditionLoopEnd: Int {
        convertedAuditionLoopPoints.map { Int($0.end) } ?? loopEnd
    }

    private var convertedAuditionLoopPoints: S9LoopPoints? {
        guard rateIsChanged,
              let convertedPreviewFrameCount,
              let points = currentLoopPoints
        else { return nil }
        return try? points.scaled(
            fromSampleLength: editSession.originalAttributes.sampleLength,
            toSampleLength: convertedPreviewFrameCount
        )
    }

    private var auditionSemitoneOffset: Int {
        selectedAuditionNote - editAttributes.rootNote
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
            end: auditionLoopEnd,
            semitoneOffset: auditionSemitoneOffset
        )
    }
}

private enum SampleKeyboardBehavior: String, CaseIterable, Hashable {
    case playOnClick
    case selectForAudition

    var title: String {
        switch self {
        case .playOnClick: return "Click plays note"
        case .selectForAudition: return "Audition uses note"
        }
    }
}

private struct TwoOctaveSampleKeyboard: View {
    let baseNote: Int
    let rootNote: Int
    let selectedNote: Int
    var height: CGFloat = 112
    let noteAction: (Int) -> Void

    private let whiteOffsets = [
        0, 2, 4, 5, 7, 9, 11,
        12, 14, 16, 17, 19, 21, 23, 24
    ]
    private let blackKeys: [(offset: Int, boundary: Int)] = [
        (1, 1), (3, 2), (6, 4), (8, 5), (10, 6),
        (13, 8), (15, 9), (18, 11), (20, 12), (22, 13)
    ]

    var body: some View {
        GeometryReader { geometry in
            let whiteWidth = geometry.size.width / CGFloat(whiteOffsets.count)
            let blackWidth = max(18, whiteWidth * 0.62)
            ZStack(alignment: .topLeading) {
                ForEach(Array(whiteOffsets.enumerated()), id: \.offset) { index, offset in
                    SamplePianoKey(
                        note: baseNote + offset,
                        isBlack: false,
                        isRoot: baseNote + offset == rootNote,
                        isSelected: baseNote + offset == selectedNote,
                        action: noteAction
                    )
                    .frame(width: max(18, whiteWidth - 1), height: height)
                    .offset(x: CGFloat(index) * whiteWidth)
                }
                ForEach(Array(blackKeys.enumerated()), id: \.offset) { _, key in
                    SamplePianoKey(
                        note: baseNote + key.offset,
                        isBlack: true,
                        isRoot: baseNote + key.offset == rootNote,
                        isSelected: baseNote + key.offset == selectedNote,
                        action: noteAction
                    )
                    .frame(width: blackWidth, height: height * 0.62)
                    .offset(
                        x: CGFloat(key.boundary) * whiteWidth - blackWidth / 2
                    )
                    .zIndex(2)
                }
            }
        }
        .frame(height: height)
        .padding(3)
        .background(Color.suiteBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.suiteRule2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct SamplePianoKey: View {
    let note: Int
    let isBlack: Bool
    let isRoot: Bool
    let isSelected: Bool
    let action: (Int) -> Void
    @State private var hovering = false

    var body: some View {
        Button { action(note) } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(keyFill)
                Text(P9Keygroup.noteName(note))
                    .font(SuiteFont.medium(isBlack ? 7 : 8))
                    .foregroundStyle(labelColor)
                    .padding(.bottom, isBlack ? 5 : 7)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(
                        isSelected ? Color.suiteYellow : Color.suiteRule2,
                        lineWidth: isSelected ? 3 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Audition \(P9Keygroup.noteName(note)), MIDI \(note)")
        .accessibilityValue(
            [isRoot ? "Root note" : nil, isSelected ? "Audition note" : nil]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
        .help(
            "\(P9Keygroup.noteName(note)) · MIDI \(note)"
                + (isRoot ? " · Root note" : "")
                + (isSelected ? " · Selected for audition" : "")
        )
    }

    private var keyFill: Color {
        if isRoot { return Color.suiteBlue }
        if isBlack {
            return hovering ? Color(nsColor: .darkGray) : Color.black
        }
        return hovering ? Color.suiteYellow.opacity(0.22) : Color.white
    }

    private var labelColor: Color {
        if isRoot || isBlack { return .white }
        return .black.opacity(0.82)
    }
}

private struct SuiteKeyboardControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.suiteInk)
            .background(
                configuration.isPressed ? Color.suiteBlue.opacity(0.3) : Color.suiteSlab
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.suiteRule2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct SampleEditorSpaceKeyMonitor: NSViewRepresentable {
    let handler: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handler = handler
        context.coordinator.attach(to: nsView)
    }

    final class Coordinator {
        var handler: () -> Bool
        private weak var window: NSWindow?
        private var monitor: Any?

        init(handler: @escaping () -> Bool) {
            self.handler = handler
        }

        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let window = view?.window else { return }
                self.window = window
                guard self.monitor == nil else { return }
                self.monitor = NSEvent.addLocalMonitorForEvents(
                    matching: .keyDown
                ) { [weak self] event in
                    guard let self,
                          event.window === self.window,
                          event.keyCode == 49,
                          event.modifierFlags.intersection(
                            [.command, .control, .option, .shift]
                          ).isEmpty
                    else { return event }
                    if event.isARepeat { return nil }
                    return self.handler() ? nil : event
                }
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

private struct SampleWorkflowButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isSelected ? Color.suiteOnYellow : Color.suiteInk)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? Color.suiteYellow
                            : configuration.isPressed
                                ? Color.suiteSlab2 : Color.clear
                    )
            )
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
    }
}

private struct WorkflowSegmentedPicker<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(SuiteFont.medium(7))
                .tracking(0.65)
                .foregroundStyle(Color.suiteUnit)
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selection == option
                    Button {
                        selection = option
                    } label: {
                        Text(label(option))
                            .font(isSelected ? SuiteFont.medium(8) : SuiteFont.regular(8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? Color.suiteOnBlue : Color.suiteInk)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSelected ? Color.suiteBlue : Color.suiteSlab2)
                    )
                    .accessibilityLabel(label(option))
                    .accessibilityValue(isSelected ? "Selected" : "")
                }
            }
            .padding(2)
            .background(Color.suiteSlab)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.suiteRule2))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct EditorSegmentedPicker<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let segmentMinWidth: CGFloat
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(SuiteFont.medium(10))
                .tracking(0.4)
                .foregroundStyle(Color.suiteInk)
                .fixedSize()
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { option in
                    let isSelected = selection == option
                    Button {
                        selection = option
                    } label: {
                        Text(label(option))
                    }
                    .buttonStyle(
                        EditorSegmentButtonStyle(
                            isSelected: isSelected,
                            minWidth: segmentMinWidth
                        )
                    )
                    .accessibilityLabel(label(option))
                    .accessibilityValue(isSelected ? "Selected" : "")
                }
            }
            .padding(2)
            .background(Color.suiteSlab)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.suiteRule2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            Spacer(minLength: 0)
        }
    }
}

private struct EditorSegmentButtonStyle: ButtonStyle {
    let isSelected: Bool
    let minWidth: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isSelected ? SuiteFont.medium(10) : SuiteFont.regular(10))
            .foregroundStyle(isSelected ? Color.suiteOnBlue : Color.suiteInk)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(minWidth: minWidth, minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        isSelected
                            ? Color.suiteBlue
                            : configuration.isPressed
                                ? Color.suiteSlab3
                                : Color.suiteSlab2
                    )
            )
            .contentShape(Rectangle())
    }
}

private struct ZeroCrossingButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Color.clear
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    configuration.isPressed
                        ? Color.suiteSlab2 : Color.suiteSlab
                )
                .frame(width: 34, height: 28)
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.suiteRule2)
                .frame(width: 34, height: 28)
            configuration.label
                .font(.system(size: 11, weight: .semibold))
        }
        .frame(width: 44, height: 36)
        .foregroundStyle(isEnabled ? Color.suiteInk : Color.suiteUnit)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.5)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
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
