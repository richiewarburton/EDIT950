import AppKit
import AVFoundation
import Combine
import Darwin
import Foundation

enum ProgramAuditionInputSource: Int32, Hashable, Sendable {
    case externalMIDI = 0
    case computerKeyboard = 1

    var title: String {
        switch self {
        case .externalMIDI: return "EXTERNAL MIDI"
        case .computerKeyboard: return "COMPUTER KEYBOARD"
        }
    }
}

struct ProgramAuditionDiagnosticEvent: Sendable {
    let level: DiagnosticLogLevel
    let message: String
    let fields: [String: String]
}

struct ProgramAuditionInputKey: Hashable, Sendable {
    let source: ProgramAuditionInputSource
    let channel: Int
    let note: Int
}

struct ProgramAuditionHeldNote: Identifiable, Equatable, Sendable {
    let id: UInt64
    let source: ProgramAuditionInputSource
    /// The physical channel received from CoreMIDI. Computer keys use the
    /// effective audition channel because they have no physical MIDI channel.
    let inputChannel: Int
    /// The P9 keygroup channel used for matching and voice ownership.
    let channel: Int
    let usesSelectedKeygroupChannel: Bool
    let note: Int
    let velocity: Int
    let physicalKey: String?
    let matchedKeygroup: Bool
    let playableSample: Bool
    let matchIssue: String?

    var summary: String {
        let noteText = "\(P9Keygroup.noteName(note)) · MIDI \(note)"
        let sourceText: String
        if let physicalKey {
            sourceText = "\(physicalKey.uppercased()) → \(noteText)"
                + (usesSelectedKeygroupChannel
                    ? " · KG CH \(channel + 1)" : " · OMNI")
        } else if usesSelectedKeygroupChannel {
            sourceText = "\(noteText) · IN CH \(inputChannel + 1) → KG CH \(channel + 1)"
        } else {
            sourceText = "\(noteText) · CH \(channel + 1)"
        }
        return "\(sourceText) · VEL \(velocity)"
            + matchIssue.map { " · \($0)" }.orEmpty
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}

enum ComputerMIDIKeyboardMapping {
    private static let noteOffsets: [String: Int] = [
        "a": 0, "w": 1, "s": 2, "e": 3, "d": 4, "f": 5,
        "t": 6, "g": 7, "y": 8, "h": 9, "u": 10, "j": 11,
        "k": 12, "o": 13, "l": 14, "p": 15
    ]

    static func note(for key: String, octave: Int) -> Int? {
        guard let offset = noteOffsets[key.lowercased()] else { return nil }
        let note = 60 + octave * 12 + offset
        guard (0...127).contains(note) else { return nil }
        return note
    }

    static func adjustedOctave(_ octave: Int, key: String) -> Int? {
        switch key.lowercased() {
        case "z": return max(-5, octave - 1)
        case "x": return min(4, octave + 1)
        default: return nil
        }
    }

    static func adjustedVelocity(_ velocity: Int, key: String) -> Int? {
        switch key.lowercased() {
        case "c": return max(1, velocity - 20)
        case "v": return min(127, velocity + 20)
        default: return nil
        }
    }
}

struct ProgramAuditionSample: Sendable {
    let fileID: AkaiFile.ID
    let normalizedName: String
    let samples: [Float]
    let sampleRate: Int
    let nominalPitchSixteenths: Int
    let playbackStart: Int
    let playbackEnd: Int
    let loopStart: Int
    let playbackMode: S9PlaybackMode
    let playbackDirection: S9PlaybackDirection
    let loudnessOffset: Int

    static func load(
        fileID: AkaiFile.ID,
        normalizedName: String,
        wavURL: URL,
        nativeData: Data
    ) throws -> ProgramAuditionSample {
        let attributes = try S9NativeSample.attributes(in: nativeData)
        let file = try AVAudioFile(forReading: wavURL)
        guard file.length > 0,
              file.length <= Int64(Int.max),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
              )
        else {
            throw AppError.verificationFailed(
                "The cached WAV for \(normalizedName) contains no playable audio."
            )
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else {
            throw AppError.verificationFailed(
                "The cached WAV for \(normalizedName) could not be decoded as PCM."
            )
        }
        let frameCount = Int(buffer.frameLength)
        let channelCount = max(1, Int(buffer.format.channelCount))
        var mono = [Float](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            var value: Float = 0
            for channel in 0..<channelCount {
                value += channels[channel][frame]
            }
            mono[frame] = value / Float(channelCount)
        }

        let start = min(frameCount, Int(attributes.playbackStart))
        let end = min(frameCount, Int(attributes.playbackEnd))
        guard start < end else {
            throw AppError.verificationFailed(
                "The cached S9 playback range for \(normalizedName) is invalid."
            )
        }
        let loop = min(end, max(start, Int(attributes.loopStart ?? UInt32(start))))
        let loudnessWord = UInt16(nativeData[0x18])
            | UInt16(nativeData[0x19]) << 8
        let loudness = Int(Int16(bitPattern: loudnessWord))
        return ProgramAuditionSample(
            fileID: fileID,
            normalizedName: normalizedName,
            samples: mono,
            sampleRate: Int(attributes.sampleRate),
            nominalPitchSixteenths: Int(attributes.nominalPitchSixteenths),
            playbackStart: start,
            playbackEnd: end,
            loopStart: loop,
            playbackMode: attributes.playbackMode,
            playbackDirection: attributes.playbackDirection,
            loudnessOffset: loudness
        )
    }
}

struct PreparedProgramAuditionKeygroup: Sendable {
    let lowKey: Int
    let highKey: Int
    let sampleIndex: Int?
    let softTuningSixteenths: Int
    let oneShot: Bool
    let constantPitch: Bool
    let amplitudeEnvelope: P9Envelope
    let filterEnvelope: P9Envelope
    let filterEnvelopeAmount: Int
    let velocityToLoudness: Int
    let velocityToFilter: Int
    let keyboardToFilter: Int
    let softFilter: Int
    let softLoudness: Int
    let midiChannelOffset: Int
}

struct PreparedProgramAudition: Sendable {
    let name: String
    let samples: [ProgramAuditionSample]
    let keygroups: [PreparedProgramAuditionKeygroup]

    init(
        name: String,
        samples: [ProgramAuditionSample],
        keygroups: [PreparedProgramAuditionKeygroup]
    ) {
        self.name = name
        self.samples = samples
        self.keygroups = keygroups
    }

    init(
        program: P9Program,
        availableSamples: [String: ProgramAuditionSample]
    ) {
        name = program.name
        var samples: [ProgramAuditionSample] = []
        var indexes: [String: Int] = [:]
        var keygroups: [PreparedProgramAuditionKeygroup] = []
        keygroups.reserveCapacity(program.keygroups.count)

        for keygroup in program.keygroups {
            let key = Self.normalizedName(keygroup.softSampleName)
            let sampleIndex: Int?
            if key.isEmpty || key == "2 SAMPLE" {
                sampleIndex = nil
            } else if let existing = indexes[key] {
                sampleIndex = existing
            } else if let sample = availableSamples[key] {
                sampleIndex = samples.count
                indexes[key] = samples.count
                samples.append(sample)
            } else {
                sampleIndex = nil
            }
            keygroups.append(
                PreparedProgramAuditionKeygroup(
                    lowKey: keygroup.lowKey,
                    highKey: keygroup.highKey,
                    sampleIndex: sampleIndex,
                    softTuningSixteenths: Int(keygroup.softTuning.rawSixteenths),
                    oneShot: keygroup.oneShot,
                    constantPitch: keygroup.constantPitch,
                    amplitudeEnvelope: keygroup.envelope,
                    filterEnvelope: keygroup.vcfEnvelope,
                    filterEnvelopeAmount: keygroup.vcfAmount,
                    velocityToLoudness: keygroup.velocitySensitivity.loudness,
                    velocityToFilter: keygroup.velocitySensitivity.filter,
                    keyboardToFilter: keygroup.keyFilter,
                    softFilter: keygroup.softFilter,
                    softLoudness: keygroup.softLoudness,
                    midiChannelOffset: keygroup.midiChannelOffset
                )
            )
        }
        self.samples = samples
        self.keygroups = keygroups
    }

    func matchingKeygroupIndex(
        channel: Int,
        note: Int,
        omni: Bool,
        selectedMIDIChannel: Int
    ) -> Int? {
        keygroups.firstIndex { keygroup in
            guard keygroup.lowKey <= keygroup.highKey,
                  (keygroup.lowKey...keygroup.highKey).contains(note)
            else { return false }
            return omni
                || (channel == selectedMIDIChannel
                    && keygroup.midiChannelOffset == selectedMIDIChannel)
        }
    }

    func playableKeygroupCount(omni: Bool, selectedMIDIChannel: Int) -> Int {
        keygroups.reduce(into: 0) { count, keygroup in
            guard omni || keygroup.midiChannelOffset == selectedMIDIChannel,
                  let sampleIndex = keygroup.sampleIndex,
                  samples.indices.contains(sampleIndex)
            else { return }
            count += 1
        }
    }

    static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .uppercased()
    }
}

private struct ProgramAuditionRenderEvent {
    // 0 empty, 1 note-on, 2 note-off, 3 all-notes-off.
    var kind: Int32 = 0
    var source: Int32 = 0
    var channel: Int32 = 0
    var note: Int32 = 0
    var velocity: Float = 0
    var noteID: UInt64 = 0
}

private final class ProgramAuditionEventQueue: @unchecked Sendable {
    private let capacity: Int32 = 256
    private let storage: UnsafeMutablePointer<ProgramAuditionRenderEvent>
    private var readIndex: Int32 = 0
    private var writeIndex: Int32 = 0

    init() {
        storage = .allocate(capacity: Int(capacity))
        storage.initialize(repeating: ProgramAuditionRenderEvent(), count: Int(capacity))
    }

    deinit {
        storage.deinitialize(count: Int(capacity))
        storage.deallocate()
    }

    func enqueue(_ event: ProgramAuditionRenderEvent) -> Bool {
        let write = OSAtomicAdd32Barrier(0, &writeIndex)
        let next = (write + 1) % capacity
        guard next != OSAtomicAdd32Barrier(0, &readIndex) else { return false }
        storage[Int(write)] = event
        OSMemoryBarrier()
        return OSAtomicCompareAndSwap32Barrier(write, next, &writeIndex)
    }

    func dequeue() -> ProgramAuditionRenderEvent? {
        let read = OSAtomicAdd32Barrier(0, &readIndex)
        guard read != OSAtomicAdd32Barrier(0, &writeIndex) else { return nil }
        let event = storage[Int(read)]
        OSMemoryBarrier()
        let next = (read + 1) % capacity
        guard OSAtomicCompareAndSwap32Barrier(read, next, &readIndex) else { return nil }
        return event
    }

    func reset() {
        readIndex = 0
        writeIndex = 0
    }
}

private final class ProgramAuditionActiveSlots: @unchecked Sendable {
    static let count = 16
    private let storage: UnsafeMutablePointer<Int32>

    init() {
        storage = .allocate(capacity: Self.count)
        storage.initialize(repeating: 0, count: Self.count)
    }

    deinit {
        storage.deinitialize(count: Self.count)
        storage.deallocate()
    }

    func store(_ value: Int32, at index: Int) {
        var previous = OSAtomicAdd32Barrier(0, storage + index)
        while !OSAtomicCompareAndSwap32Barrier(previous, value, storage + index) {
            previous = OSAtomicAdd32Barrier(0, storage + index)
        }
    }

    func values() -> [Int] {
        (0..<Self.count).map {
            Int(OSAtomicAdd32Barrier(0, storage + $0)) - 1
        }
    }

    func clear() {
        for index in 0..<Self.count { store(0, at: index) }
    }
}

struct ProgramAuditionVoicePool {
    static let voiceCount = 8

    private enum EnvelopeStage: Int {
        case attack
        case decay
        case sustain
        case release
        case done
    }

    private struct EnvelopeState {
        var parameters = P9Envelope(attack: 0, decay: 0, sustain: 99, release: 0)
        var stage = EnvelopeStage.done
        var level: Float = 0
        var releaseStart: Float = 0
        var stageSamples: UInt64 = 0
    }

    private struct Voice {
        var position: Double = 0
        var increment: Double = 1
        var age: UInt64 = 0
        var sampleIndex = 0
        var keygroupIndex = 0
        var source = ProgramAuditionInputSource.externalMIDI
        var midiChannel = 0
        var pitch = -1
        var noteID: UInt64 = 0
        var playbackDirection = 1
        var oneShot = false
        var active = false
        var velocity: Float = 1
        var baseFilter: Float = 99
        var loudnessGain: Float = 1
        var amplitude = EnvelopeState()
        var filter = EnvelopeState()
        var filterState0: Float = 0
        var filterState1: Float = 0
        var filterState2: Float = 0
        var filterState3: Float = 0
        var lastOutput: Float = 0
        var tailOutput: Float = 0
        var tailRemaining = 0
        var tailSampleIndex = -1
    }

    private(set) var program: PreparedProgramAudition?
    private var voices = [Voice](repeating: Voice(), count: voiceCount)
    private var hostSampleRate = 44_100.0
    private var nextAge: UInt64 = 1
    private(set) var omni = true
    private(set) var selectedMIDIChannel = 0

    mutating func setProgram(_ program: PreparedProgramAudition?) {
        self.program = program
        voices = [Voice](repeating: Voice(), count: Self.voiceCount)
        nextAge = 1
    }

    mutating func setHostSampleRate(_ sampleRate: Double) {
        if sampleRate > 0 { hostSampleRate = sampleRate }
    }

    mutating func setMIDIReception(omni: Bool, selectedMIDIChannel: Int) {
        self.omni = omni
        self.selectedMIDIChannel = max(0, min(15, selectedMIDIChannel))
    }

    var activeVoiceCount: Int {
        voices.reduce(0) { $0 + ($1.active ? 1 : 0) }
    }

    func isNoteActive(
        source: ProgramAuditionInputSource,
        channel: Int,
        noteID: UInt64
    ) -> Bool {
        voices.contains {
            $0.active && $0.source == source && $0.midiChannel == channel
                && $0.noteID == noteID
        }
    }

    mutating func noteOn(
        source: ProgramAuditionInputSource,
        channel: Int,
        pitch: Int,
        noteID: UInt64,
        velocity: Int
    ) {
        guard let program,
              channel >= 0, channel < 16,
              velocity > 0,
              let keygroupIndex = program.matchingKeygroupIndex(
                channel: channel,
                note: pitch,
                omni: omni,
                selectedMIDIChannel: selectedMIDIChannel
              )
        else { return }
        let keygroup = program.keygroups[keygroupIndex]
        guard let sampleIndex = keygroup.sampleIndex,
              program.samples.indices.contains(sampleIndex)
        else { return }
        let sample = program.samples[sampleIndex]
        guard !sample.samples.isEmpty,
              sample.sampleRate > 0,
              sample.playbackStart < sample.playbackEnd
        else { return }

        let voiceIndex = voiceIndexForNewNote()
        if voices[voiceIndex].active {
            beginTail(for: voiceIndex)
        }
        let preservedTail = (
            voices[voiceIndex].tailOutput,
            voices[voiceIndex].tailRemaining,
            voices[voiceIndex].tailSampleIndex
        )
        voices[voiceIndex] = Voice()
        voices[voiceIndex].tailOutput = preservedTail.0
        voices[voiceIndex].tailRemaining = preservedTail.1
        voices[voiceIndex].tailSampleIndex = preservedTail.2
        voices[voiceIndex].active = true
        voices[voiceIndex].source = source
        voices[voiceIndex].midiChannel = channel
        voices[voiceIndex].pitch = pitch
        voices[voiceIndex].noteID = noteID
        voices[voiceIndex].playbackDirection = sample.playbackDirection == .reverse ? -1 : 1
        voices[voiceIndex].position = voices[voiceIndex].playbackDirection > 0
            ? Double(sample.playbackStart) : Double(sample.playbackEnd - 1)
        voices[voiceIndex].sampleIndex = sampleIndex
        voices[voiceIndex].keygroupIndex = keygroupIndex
        voices[voiceIndex].oneShot = keygroup.oneShot
        voices[voiceIndex].velocity = Float(max(1, min(127, velocity))) / 127
        voices[voiceIndex].baseFilter = Float(keygroup.softFilter)
        voices[voiceIndex].loudnessGain = Self.loudnessGain(
            sampleOffset: sample.loudnessOffset,
            layerOffset: keygroup.softLoudness,
            sensitivity: keygroup.velocityToLoudness,
            velocity: voices[voiceIndex].velocity
        )
        voices[voiceIndex].amplitude = EnvelopeState(
            parameters: keygroup.amplitudeEnvelope,
            stage: .attack,
            level: 0,
            releaseStart: 0,
            stageSamples: 0
        )
        voices[voiceIndex].filter = EnvelopeState(
            parameters: keygroup.filterEnvelope,
            stage: .attack,
            level: 0,
            releaseStart: 0,
            stageSamples: 0
        )
        voices[voiceIndex].age = nextAge
        nextAge &+= 1
        let pitchSixteenths = keygroup.constantPitch
            ? sample.nominalPitchSixteenths + keygroup.softTuningSixteenths
            : pitch * 16 + keygroup.softTuningSixteenths
        let semitones = Double(pitchSixteenths - sample.nominalPitchSixteenths) / 192
        voices[voiceIndex].increment = Double(sample.sampleRate) / hostSampleRate
            * pow(2, semitones)
    }

    mutating func noteOff(
        source: ProgramAuditionInputSource,
        channel: Int,
        noteID: UInt64
    ) {
        for index in voices.indices where voices[index].active {
            guard voices[index].source == source,
                  voices[index].midiChannel == channel,
                  voices[index].noteID == noteID,
                  !voices[index].oneShot
            else { continue }
            if voices[index].amplitude.parameters.release == 0 {
                beginTail(for: index)
                voices[index].active = false
            } else {
                voices[index].amplitude.releaseStart = voices[index].amplitude.level
                voices[index].amplitude.stage = .release
                voices[index].amplitude.stageSamples = 0
                voices[index].filter.releaseStart = voices[index].filter.level
                voices[index].filter.stage = .release
                voices[index].filter.stageSamples = 0
            }
            return
        }
    }

    mutating func allNotesOff() {
        for index in voices.indices where voices[index].active {
            beginTail(for: index)
            voices[index].active = false
        }
    }

    mutating func renderAdd(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>?,
        frameCount: Int
    ) {
        guard frameCount > 0 else { return }
        for frame in 0..<frameCount {
            var mixed: Float = 0
            for index in voices.indices {
                if voices[index].active {
                    mixed += nextSample(for: index)
                }
                if voices[index].tailRemaining > 0 {
                    let fraction = Float(voices[index].tailRemaining) / 32
                    mixed += voices[index].tailOutput * fraction
                    voices[index].tailRemaining -= 1
                    if voices[index].tailRemaining == 0 {
                        voices[index].tailSampleIndex = -1
                    }
                }
            }
            left[frame] += mixed
            right?[frame] += mixed
        }
    }

    func activeSampleIndex(at slot: Int) -> Int {
        guard slot >= 0, slot < Self.voiceCount * 2 else { return -1 }
        if slot < Self.voiceCount {
            return voices[slot].active ? voices[slot].sampleIndex : -1
        }
        let voice = voices[slot - Self.voiceCount]
        return voice.tailRemaining > 0 ? voice.tailSampleIndex : -1
    }

    private mutating func voiceIndexForNewNote() -> Int {
        if let inactive = voices.firstIndex(where: { !$0.active }) { return inactive }
        return voices.indices.min(by: { voices[$0].age < voices[$1].age }) ?? 0
    }

    private mutating func beginTail(for index: Int) {
        voices[index].tailOutput = voices[index].lastOutput
        voices[index].tailRemaining = 32
        voices[index].tailSampleIndex = voices[index].sampleIndex
    }

    private mutating func nextSample(for index: Int) -> Float {
        guard let program else { return 0 }
        let sample = program.samples[voices[index].sampleIndex]
        let start = Double(sample.playbackStart)
        let end = Double(sample.playbackEnd)
        let high = end - 1
        let loopStart = Double(sample.loopStart)

        if sample.playbackMode == .alternatingLoop, loopStart < high {
            let span = high - loopStart
            if voices[index].playbackDirection > 0, voices[index].position > high {
                let phase = (voices[index].position - high).truncatingRemainder(
                    dividingBy: span * 2
                )
                if phase <= span {
                    voices[index].position = high - phase
                    voices[index].playbackDirection = -1
                } else {
                    voices[index].position = loopStart + phase - span
                }
            } else if voices[index].playbackDirection < 0,
                      voices[index].position < loopStart {
                let phase = (loopStart - voices[index].position).truncatingRemainder(
                    dividingBy: span * 2
                )
                if phase <= span {
                    voices[index].position = loopStart + phase
                    voices[index].playbackDirection = 1
                } else {
                    voices[index].position = high - (phase - span)
                }
            }
        } else if voices[index].playbackDirection > 0,
                  voices[index].position >= end {
            if sample.playbackMode == .oneShot || loopStart >= end {
                voices[index].active = false
                return 0
            }
            let span = end - loopStart
            voices[index].position = loopStart
                + (voices[index].position - end).truncatingRemainder(dividingBy: span)
        } else if voices[index].playbackDirection < 0,
                  voices[index].position < (sample.playbackMode == .oneShot ? start : loopStart) {
            if sample.playbackMode == .oneShot || loopStart >= end {
                voices[index].active = false
                return 0
            }
            let span = end - loopStart
            let remainder = (loopStart - voices[index].position)
                .truncatingRemainder(dividingBy: span)
            voices[index].position = remainder == 0 ? loopStart : end - remainder
        }

        let sampleIndex = min(
            sample.playbackEnd - 1,
            max(sample.playbackStart, Int(voices[index].position))
        )
        let nextIndex = min(sampleIndex + 1, sample.playbackEnd - 1)
        let fraction = Float(voices[index].position - Double(sampleIndex))
        var value = sample.samples[sampleIndex]
            + (sample.samples[nextIndex] - sample.samples[sampleIndex]) * fraction
        voices[index].position += voices[index].increment
            * Double(voices[index].playbackDirection)

        let keygroup = program.keygroups[voices[index].keygroupIndex]
        let amplitudeEnvelope = Self.advanceEnvelope(
            &voices[index].amplitude,
            hostSampleRate: hostSampleRate
        )
        let filterEnvelope = Self.advanceEnvelope(
            &voices[index].filter,
            hostSampleRate: hostSampleRate
        )
        if voices[index].amplitude.stage == .done {
            voices[index].active = false
            return 0
        }

        var filterControl = voices[index].baseFilter
        filterControl += Float(keygroup.filterEnvelopeAmount) * filterEnvelope
        filterControl += Float(keygroup.velocityToFilter) * (voices[index].velocity - 0.5)
        filterControl += Float(keygroup.keyboardToFilter)
            * Float(voices[index].pitch - 60) / 12
        filterControl = max(0, min(99, filterControl))
        if filterControl < 80 {
            let cutoff = min(Self.cutoff(for: filterControl), Float(hostSampleRate * 0.45))
            let coefficient = 1 - exp(-2 * Float.pi * cutoff / Float(hostSampleRate))
            voices[index].filterState0 += coefficient * (value - voices[index].filterState0)
            value = voices[index].filterState0
            voices[index].filterState1 += coefficient * (value - voices[index].filterState1)
            value = voices[index].filterState1
            voices[index].filterState2 += coefficient * (value - voices[index].filterState2)
            value = voices[index].filterState2
            voices[index].filterState3 += coefficient * (value - voices[index].filterState3)
            value = voices[index].filterState3
        }
        let amplitudeGain = pow(max(0, min(1, amplitudeEnvelope)), 2.5)
        value *= amplitudeGain * voices[index].loudnessGain
        voices[index].lastOutput = value
        return value
    }

    private static func advanceEnvelope(
        _ envelope: inout EnvelopeState,
        hostSampleRate: Double
    ) -> Float {
        for _ in 0..<3 {
            switch envelope.stage {
            case .sustain:
                envelope.level = Float(envelope.parameters.sustain) / 99
                return envelope.level
            case .done:
                envelope.level = 0
                return 0
            default:
                break
            }
            let parameter: Int
            switch envelope.stage {
            case .attack: parameter = envelope.parameters.attack
            case .decay: parameter = envelope.parameters.decay
            case .release: parameter = envelope.parameters.release
            case .sustain, .done: parameter = 0
            }
            let duration = UInt64(
                max(0, (Self.envelopeTimeSeconds(stage: envelope.stage, value: parameter)
                    * hostSampleRate).rounded())
            )
            if duration == 0 {
                switch envelope.stage {
                case .attack:
                    envelope.level = 1
                    envelope.stage = .decay
                case .decay:
                    envelope.level = Float(envelope.parameters.sustain) / 99
                    envelope.stage = .sustain
                case .release:
                    envelope.level = 0
                    envelope.stage = .done
                case .sustain, .done:
                    break
                }
                envelope.stageSamples = 0
                continue
            }
            let position = min(1, Float(envelope.stageSamples + 1) / Float(duration))
            switch envelope.stage {
            case .attack:
                envelope.level = pow(position, 0.72)
            case .decay:
                let sustain = Float(envelope.parameters.sustain) / 99
                envelope.level = sustain + (1 - sustain) * pow(1 - position, 2)
            case .release:
                envelope.level = envelope.releaseStart * pow(1 - position, 2)
            case .sustain, .done:
                break
            }
            envelope.stageSamples += 1
            if envelope.stageSamples >= duration {
                envelope.stageSamples = 0
                switch envelope.stage {
                case .attack: envelope.stage = .decay
                case .decay: envelope.stage = .sustain
                case .release: envelope.stage = .done
                case .sustain, .done: break
                }
            }
            return envelope.level
        }
        return envelope.level
    }

    private static func envelopeTimeSeconds(stage: EnvelopeStage, value: Int) -> Double {
        guard value > 0 else { return 0 }
        let normalized = Double(max(0, min(99, value))) / 99
        switch stage {
        case .attack: return 0.002 + 12 * pow(normalized, 3.5)
        case .decay: return 0.002 + 20 * pow(normalized, 4.5)
        case .release: return 0.002 + 22 * pow(normalized, 5.2)
        case .sustain, .done: return 0
        }
    }

    private static func cutoff(for control: Float) -> Float {
        let value = max(0, min(80, control))
        let lowerControl: Float
        let upperControl: Float
        let lowerFrequency: Float
        let upperFrequency: Float
        switch value {
        case ...20:
            (lowerControl, upperControl, lowerFrequency, upperFrequency) = (0, 20, 180, 220)
        case ...40:
            (lowerControl, upperControl, lowerFrequency, upperFrequency) = (20, 40, 220, 700)
        case ...60:
            (lowerControl, upperControl, lowerFrequency, upperFrequency) = (40, 60, 700, 5_500)
        default:
            (lowerControl, upperControl, lowerFrequency, upperFrequency) = (60, 80, 5_500, 24_000)
        }
        let position = (value - lowerControl) / (upperControl - lowerControl)
        return exp(log(lowerFrequency) * (1 - position) + log(upperFrequency) * position)
    }

    private static func loudnessGain(
        sampleOffset: Int,
        layerOffset: Int,
        sensitivity: Int,
        velocity: Float
    ) -> Float {
        let offset = max(-50, min(50, sampleOffset + layerOffset))
        let maximum = 1 + Float(offset) / 50
        let velocityDepth = Float(max(0, min(99, sensitivity))) / 99 * (2 - maximum)
        return max(0, min(2, maximum - velocityDepth * (1 - max(0, min(1, velocity)))))
    }
}

private final class ProgramAuditionRenderState: @unchecked Sendable {
    let events = ProgramAuditionEventQueue()
    let activeSlots = ProgramAuditionActiveSlots()
    var pool = ProgramAuditionVoicePool()

    func replaceProgram(
        _ program: PreparedProgramAudition?,
        sampleRate: Double,
        omni: Bool,
        selectedMIDIChannel: Int
    ) {
        events.reset()
        pool.setProgram(program)
        pool.setHostSampleRate(sampleRate)
        pool.setMIDIReception(
            omni: omni,
            selectedMIDIChannel: selectedMIDIChannel
        )
        activeSlots.clear()
    }

    func render(
        frameCount: Int,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        while let event = events.dequeue() {
            switch event.kind {
            case 1:
                pool.noteOn(
                    source: ProgramAuditionInputSource(rawValue: event.source) ?? .externalMIDI,
                    channel: Int(event.channel),
                    pitch: Int(event.note),
                    noteID: event.noteID,
                    velocity: Int(event.velocity)
                )
            case 2:
                pool.noteOff(
                    source: ProgramAuditionInputSource(rawValue: event.source) ?? .externalMIDI,
                    channel: Int(event.channel),
                    noteID: event.noteID
                )
            case 3:
                pool.allNotesOff()
            default:
                break
            }
        }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            data.assumingMemoryBound(to: Float.self)
                .initialize(repeating: 0, count: frameCount)
        }
        if let leftData = buffers.first?.mData {
            let left = leftData.assumingMemoryBound(to: Float.self)
            let right = buffers.count > 1
                ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            pool.renderAdd(left: left, right: right, frameCount: frameCount)
        }
        for index in 0..<ProgramAuditionActiveSlots.count {
            activeSlots.store(Int32(pool.activeSampleIndex(at: index) + 1), at: index)
        }
        return noErr
    }
}

@MainActor
private final class ProgramAuditionAudioEngine {
    private let engine = AVAudioEngine()
    private let state = ProgramAuditionRenderState()
    private let sourceNode: AVAudioSourceNode
    private(set) var isRunning = false
    private var desiredProgram: PreparedProgramAudition?
    private var desiredOmni = true
    private var desiredMIDIChannel = 0

    init() {
        let renderState = state
        sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList in
            renderState.render(
                frameCount: Int(frameCount),
                audioBufferList: audioBufferList
            )
        }
        engine.attach(sourceNode)
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44_100
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        )
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    func setProgram(
        _ program: PreparedProgramAudition?,
        omni: Bool,
        selectedMIDIChannel: Int
    ) throws {
        desiredProgram = program
        desiredOmni = omni
        desiredMIDIChannel = selectedMIDIChannel
        try restartDesiredProgram()
    }

    private func restartDesiredProgram() throws {
        engine.mainMixerNode.outputVolume = 0
        engine.stop()
        isRunning = false
        engine.disconnectNodeOutput(sourceNode)
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44_100
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        )
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        state.replaceProgram(
            desiredProgram,
            sampleRate: sampleRate,
            omni: desiredOmni,
            selectedMIDIChannel: desiredMIDIChannel
        )
        guard desiredProgram != nil else { return }
        engine.prepare()
        try engine.start()
        guard engine.isRunning else {
            throw AppError.processFailed("The program-audition audio engine did not start.")
        }
        engine.mainMixerNode.outputVolume = 1
        isRunning = true
    }

    func updateMIDIReception(omni: Bool, selectedMIDIChannel: Int) throws {
        desiredOmni = omni
        desiredMIDIChannel = selectedMIDIChannel
        try restartDesiredProgram()
    }

    func noteOn(_ note: ProgramAuditionHeldNote) throws -> (queued: Bool, recovered: Bool) {
        let recovered = try recoverIfNeeded()
        let queued = state.events.enqueue(
            ProgramAuditionRenderEvent(
                kind: 1,
                source: note.source.rawValue,
                channel: Int32(note.channel),
                note: Int32(note.note),
                velocity: Float(note.velocity),
                noteID: note.id
            )
        )
        return (queued, recovered)
    }

    func noteOff(_ note: ProgramAuditionHeldNote) -> Bool {
        state.events.enqueue(
            ProgramAuditionRenderEvent(
                kind: 2,
                source: note.source.rawValue,
                channel: Int32(note.channel),
                note: Int32(note.note),
                velocity: 0,
                noteID: note.id
            )
        )
    }

    func allNotesOff() {
        _ = state.events.enqueue(ProgramAuditionRenderEvent(kind: 3))
    }

    func activeSampleIndexes() -> [Int] {
        state.activeSlots.values()
    }

    func recoverIfNeeded() throws -> Bool {
        guard desiredProgram != nil else { return false }
        guard !engine.isRunning else {
            isRunning = true
            return false
        }
        try restartDesiredProgram()
        return true
    }

#if AKAI_TESTING
    func stopForRecoveryTest() {
        engine.stop()
        isRunning = false
    }
#endif
}

@MainActor
final class ProgramAuditionController: ObservableObject {
    nonisolated static let feedbackHoldDuration: TimeInterval = 3

    @Published private(set) var hardwareMIDIEnabled = false
    @Published private(set) var computerKeyboardEnabled = false
    @Published private(set) var omni = true
    @Published private(set) var selectedMIDIChannel = 0
    @Published private(set) var computerOctave = 0
    @Published private(set) var computerVelocity = 100
    @Published private(set) var heldNotes: [ProgramAuditionHeldNote] = []
    @Published private(set) var visibleNotes: [ProgramAuditionHeldNote] = []
    @Published private(set) var activeSampleIDs = Set<AkaiFile.ID>()
    @Published private(set) var recentlyTriggeredSampleIDs = Set<AkaiFile.ID>()
    @Published private(set) var indicatedSampleIDs = Set<AkaiFile.ID>()
    @Published private(set) var targetName: String?
    @Published private(set) var isPreparingProgram = false
    @Published private(set) var status = "AUDITION OFF"
    @Published private(set) var errorMessage: String?

    let midiMonitor = MIDIKeygroupMonitor()
    var onSampleIndicatorsChanged: ((Set<AkaiFile.ID>) -> Void)?
    var onInputAvailabilityChanged: (() -> Void)?
    var onDiagnosticEvent: ((ProgramAuditionDiagnosticEvent) -> Void)?

    private let audio = ProgramAuditionAudioEngine()
    private var mainProgram: PreparedProgramAudition?
    private var pendingMainProgramName: String?
    private var editorProgram: PreparedProgramAudition?
    private var editorActive = false
    private var currentProgram: PreparedProgramAudition?
    private var nextNoteID: UInt64 = 1
    private var heldByID: [UInt64: ProgramAuditionHeldNote] = [:]
    private var heldStacks: [ProgramAuditionInputKey: [UInt64]] = [:]
    private var computerPhysicalNotes: [String: UInt64] = [:]
    private var activeSampleTimer: Timer?
    private var feedbackTask: Task<Void, Never>?
    private var lastFeedbackNote: ProgramAuditionHeldNote?
    private let feedbackHoldDuration: TimeInterval

    init(feedbackHoldDuration: TimeInterval = ProgramAuditionController.feedbackHoldDuration) {
        self.feedbackHoldDuration = max(0, feedbackHoldDuration)
        midiMonitor.eventHandler = { [weak self] envelope in
            self?.receiveExternalMIDI(envelope.event)
        }
        activeSampleTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 30.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshActiveSamples() }
        }
    }

    deinit {
        activeSampleTimer?.invalidate()
        feedbackTask?.cancel()
    }

    var inputEnabled: Bool { hardwareMIDIEnabled || computerKeyboardEnabled }

    var activeNotesForKeygroups: [MIDINoteKey: Int] {
        Dictionary(
            heldNotes.map { (MIDINoteKey(channel: $0.channel, note: $0.note), $0.velocity) },
            uniquingKeysWith: max
        )
    }

    func isKeygroupHeld(_ keygroup: P9Keygroup) -> Bool {
        guard keygroup.lowKey <= keygroup.highKey else { return false }
        return heldNotes.contains { held in
            (keygroup.lowKey...keygroup.highKey).contains(held.note)
                && (omni || held.channel == keygroup.midiChannelOffset)
        }
    }

    func setHardwareMIDIEnabled(_ enabled: Bool) {
        guard hardwareMIDIEnabled != enabled else { return }
        let wasInputEnabled = inputEnabled
        hardwareMIDIEnabled = enabled
        if enabled {
            midiMonitor.start()
        } else {
            clearInputsAndVoices()
            midiMonitor.stop()
        }
        updateStatus()
        emit(
            .info,
            "Hardware MIDI audition \(enabled ? "enabled" : "disabled")",
            fields: [
                "inputs": String(midiMonitor.sourceCount),
                "monitorRunning": String(midiMonitor.isRunning)
            ]
        )
        if inputEnabled != wasInputEnabled { onInputAvailabilityChanged?() }
    }

    func setComputerKeyboardEnabled(_ enabled: Bool) {
        guard computerKeyboardEnabled != enabled else { return }
        let wasInputEnabled = inputEnabled
        computerKeyboardEnabled = enabled
        if !enabled { clearInputsAndVoices() }
        updateStatus()
        emit(
            .info,
            "Computer keyboard audition \(enabled ? "enabled" : "disabled")"
        )
        if inputEnabled != wasInputEnabled { onInputAvailabilityChanged?() }
    }

    func setMIDIChannelSelection(_ selection: Int) {
        let newOmni = selection < 0
        let newChannel = max(0, min(15, selection))
        guard omni != newOmni || selectedMIDIChannel != newChannel else { return }
        clearInputsAndVoices()
        omni = newOmni
        if !newOmni { selectedMIDIChannel = newChannel }
        do {
            try audio.updateMIDIReception(
                omni: omni,
                selectedMIDIChannel: selectedMIDIChannel
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            emit(
                .error,
                "Could not update audition channel",
                fields: ["error": error.localizedDescription]
            )
        }
        updateStatus()
    }

    func setMainProgram(_ program: PreparedProgramAudition?) {
        errorMessage = nil
        mainProgram = program
        pendingMainProgramName = nil
        guard !editorActive else { return }
        activate(program)
    }

    func beginMainProgramPreparation(named name: String) {
        mainProgram = nil
        pendingMainProgramName = name
        guard !editorActive else { return }
        activate(nil, preparingName: name)
    }

    func setMainProgramPreparationError(_ message: String, targetName: String? = nil) {
        mainProgram = nil
        pendingMainProgramName = nil
        errorMessage = message
        guard !editorActive else { return }
        activate(nil)
        self.targetName = targetName
        errorMessage = message
        updateStatus()
    }

    func activateEditor(_ program: PreparedProgramAudition) {
        editorActive = true
        editorProgram = program
        isPreparingProgram = false
        activate(program)
    }

    func updateEditor(_ program: PreparedProgramAudition) {
        guard editorActive else { return }
        editorProgram = program
        activate(program)
    }

    func deactivateEditor() {
        editorActive = false
        editorProgram = nil
        if let mainProgram {
            activate(mainProgram)
        } else if let pendingMainProgramName {
            activate(nil, preparingName: pendingMainProgramName)
        } else {
            activate(nil)
        }
    }

    func clearPrograms() {
        mainProgram = nil
        pendingMainProgramName = nil
        editorProgram = nil
        editorActive = false
        activate(nil)
    }

    func panic() {
        clearInputsAndVoices()
        do {
            let recovered = try audio.recoverIfNeeded()
            if recovered { errorMessage = nil }
            emit(
                recovered ? .warning : .info,
                recovered
                    ? "PANIC restarted the program-audition audio engine"
                    : "PANIC cleared program-audition notes",
                fields: ["audioRunning": String(audio.isRunning)]
            )
        } catch {
            errorMessage = error.localizedDescription
            emit(
                .error,
                "PANIC could not restart the program-audition audio engine",
                fields: ["error": error.localizedDescription]
            )
        }
        updateStatus()
    }

    func handleComputerKeyDown(_ event: NSEvent) -> Bool {
        guard computerKeyboardEnabled,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              let raw = event.charactersIgnoringModifiers?.lowercased(),
              raw.count == 1
        else { return false }
        if let octave = ComputerMIDIKeyboardMapping.adjustedOctave(
            computerOctave,
            key: raw
        ) {
            computerOctave = octave
            updateStatus()
            return true
        }
        if let velocity = ComputerMIDIKeyboardMapping.adjustedVelocity(
            computerVelocity,
            key: raw
        ) {
            computerVelocity = velocity
            updateStatus()
            return true
        }
        guard let note = ComputerMIDIKeyboardMapping.note(
            for: raw,
            octave: computerOctave
        ) else { return false }
        guard currentProgram != nil else {
            updateStatus()
            return true
        }
        if computerPhysicalNotes[raw] != nil { return true }
        let effectiveChannel = omni ? 0 : selectedMIDIChannel
        let held = beginNote(
            source: .computerKeyboard,
            inputChannel: effectiveChannel,
            channel: effectiveChannel,
            usesSelectedKeygroupChannel: !omni,
            note: note,
            velocity: computerVelocity,
            physicalKey: raw.uppercased()
        )
        computerPhysicalNotes[raw] = held.id
        return true
    }

    func handleComputerKeyUp(_ event: NSEvent) -> Bool {
        guard computerKeyboardEnabled,
              let raw = event.charactersIgnoringModifiers?.lowercased(),
              let noteID = computerPhysicalNotes.removeValue(forKey: raw)
        else { return false }
        endNote(noteID)
        return true
    }

    func focusWasLost() { clearInputsAndVoices() }

    func receiveExternalMIDI(_ event: MIDIInputEvent) {
        handleExternalMIDI(event)
    }

    private func activate(
        _ program: PreparedProgramAudition?,
        preparingName: String? = nil
    ) {
        clearInputsAndVoices()
        currentProgram = program
        targetName = program?.name ?? preparingName
        isPreparingProgram = program == nil && preparingName != nil
        do {
            try audio.setProgram(
                program,
                omni: omni,
                selectedMIDIChannel: selectedMIDIChannel
            )
            errorMessage = nil
            emit(
                .info,
                program == nil ? "Program audition target cleared" : "Program audition ready",
                fields: [
                    "audioRunning": String(audio.isRunning),
                    "program": program?.name ?? preparingName ?? "none",
                    "samples": String(program?.samples.count ?? 0)
                ]
            )
        } catch {
            errorMessage = error.localizedDescription
            emit(
                .error,
                "Program-audition audio engine could not start",
                fields: [
                    "error": error.localizedDescription,
                    "program": program?.name ?? preparingName ?? "none"
                ]
            )
        }
        refreshActiveSamples()
        updateStatus()
    }

    private func handleExternalMIDI(_ event: MIDIInputEvent) {
        guard hardwareMIDIEnabled else { return }
        switch event {
        case let .noteOn(key, velocity):
            guard currentProgram != nil else {
                updateStatus()
                return
            }
            let effectiveChannel = omni ? key.channel : selectedMIDIChannel
            _ = beginNote(
                source: .externalMIDI,
                inputChannel: key.channel,
                channel: effectiveChannel,
                usesSelectedKeygroupChannel: !omni,
                note: key.note,
                velocity: velocity,
                physicalKey: nil
            )
        case let .noteOff(key, _):
            let inputKey = ProgramAuditionInputKey(
                source: .externalMIDI,
                channel: key.channel,
                note: key.note
            )
            guard var stack = heldStacks[inputKey], !stack.isEmpty else { return }
            let noteID = stack.removeFirst()
            heldStacks[inputKey] = stack.isEmpty ? nil : stack
            endNote(noteID, removeFromStack: false)
        case let .allNotesOff(channel):
            let ids = heldByID.values.filter {
                $0.source == .externalMIDI
                    && (channel == nil || $0.inputChannel == channel)
            }.map(\.id)
            for id in ids { endNote(id) }
        }
    }

    @discardableResult
    private func beginNote(
        source: ProgramAuditionInputSource,
        inputChannel: Int,
        channel: Int,
        usesSelectedKeygroupChannel: Bool,
        note: Int,
        velocity: Int,
        physicalKey: String?
    ) -> ProgramAuditionHeldNote {
        let id = nextNoteID
        nextNoteID &+= 1
        let matchedKeygroupIndex = currentProgram?.matchingKeygroupIndex(
            channel: channel,
            note: note,
            omni: omni,
            selectedMIDIChannel: selectedMIDIChannel
        )
        let matched = matchedKeygroupIndex != nil
        let sampleID: AkaiFile.ID? = matchedKeygroupIndex.flatMap { keygroupIndex in
            guard let program = currentProgram,
                  program.keygroups.indices.contains(keygroupIndex),
                  let sampleIndex = program.keygroups[keygroupIndex].sampleIndex,
                  program.samples.indices.contains(sampleIndex)
            else { return nil }
            return program.samples[sampleIndex].fileID
        }
        let matchIssue: String?
        if !matched {
            matchIssue = "NO KG MATCH"
        } else if sampleID == nil {
            matchIssue = "NO PLAYABLE SOFT S9"
        } else {
            matchIssue = nil
        }
        let held = ProgramAuditionHeldNote(
            id: id,
            source: source,
            inputChannel: inputChannel,
            channel: channel,
            usesSelectedKeygroupChannel: usesSelectedKeygroupChannel,
            note: note,
            velocity: max(1, min(127, velocity)),
            physicalKey: physicalKey,
            matchedKeygroup: matched,
            playableSample: sampleID != nil,
            matchIssue: matchIssue
        )
        heldByID[id] = held
        let inputKey = ProgramAuditionInputKey(
            source: source,
            channel: inputChannel,
            note: note
        )
        heldStacks[inputKey, default: []].append(id)
        beginFeedback(for: held, sampleID: sampleID)
        publishHeldNotes()
        if held.playableSample {
            do {
                let result = try audio.noteOn(held)
                if result.recovered {
                    emit(
                        .warning,
                        "Program-audition audio engine recovered before Note On",
                        fields: ["source": source.title]
                    )
                }
                if result.queued {
                    errorMessage = nil
                } else {
                    errorMessage = "The real-time MIDI event queue is full. Use PANIC before continuing."
                    emit(.error, "Program-audition event queue is full")
                }
            } catch {
                errorMessage = error.localizedDescription
                emit(
                    .error,
                    "Program-audition Note On could not start audio",
                    fields: [
                        "error": error.localizedDescription,
                        "source": source.title
                    ]
                )
            }
        }
        emit(
            .debug,
            "Program-audition Note On",
            fields: [
                "audioRunning": String(audio.isRunning),
                "channel": String(channel + 1),
                "matched": String(matched),
                "note": String(note),
                "playable": String(held.playableSample),
                "source": source.title
            ]
        )
        updateStatus(lastInput: held.summary)
        return held
    }

    private func endNote(_ id: UInt64, removeFromStack: Bool = true) {
        guard let held = heldByID.removeValue(forKey: id) else { return }
        if removeFromStack {
            let inputKey = ProgramAuditionInputKey(
                source: held.source,
                channel: held.inputChannel,
                note: held.note
            )
            if var stack = heldStacks[inputKey] {
                stack.removeAll { $0 == id }
                heldStacks[inputKey] = stack.isEmpty ? nil : stack
            }
        }
        _ = audio.noteOff(held)
        publishHeldNotes()
        updateStatus()
    }

    private func clearInputsAndVoices() {
        feedbackTask?.cancel()
        feedbackTask = nil
        lastFeedbackNote = nil
        recentlyTriggeredSampleIDs.removeAll()
        heldByID.removeAll()
        heldStacks.removeAll()
        computerPhysicalNotes.removeAll()
        heldNotes.removeAll()
        visibleNotes.removeAll()
        activeSampleIDs.removeAll()
        publishSampleIndicators()
        audio.allNotesOff()
        updateStatus()
    }

    private func publishHeldNotes() {
        heldNotes = heldByID.values.sorted { $0.id < $1.id }
        publishVisibleNotes()
    }

    private func beginFeedback(
        for note: ProgramAuditionHeldNote,
        sampleID: AkaiFile.ID?
    ) {
        feedbackTask?.cancel()
        lastFeedbackNote = note
        recentlyTriggeredSampleIDs = sampleID.map { Set([$0]) } ?? []
        publishVisibleNotes()
        publishSampleIndicators()

        let duration = feedbackHoldDuration
        feedbackTask = Task { [weak self] in
            guard duration > 0 else {
                self?.expireFeedback(noteID: note.id)
                return
            }
            try? await Task.sleep(
                nanoseconds: UInt64(duration * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            self?.expireFeedback(noteID: note.id)
        }
    }

    private func expireFeedback(noteID: UInt64) {
        guard lastFeedbackNote?.id == noteID else { return }
        lastFeedbackNote = nil
        recentlyTriggeredSampleIDs.removeAll()
        feedbackTask = nil
        publishVisibleNotes()
        publishSampleIndicators()
        updateStatus()
    }

    private func publishVisibleNotes() {
        var notes = heldNotes
        if let lastFeedbackNote,
           !notes.contains(where: { $0.id == lastFeedbackNote.id }) {
            notes.append(lastFeedbackNote)
        }
        visibleNotes = notes.sorted { $0.id < $1.id }
    }

    private func refreshActiveSamples() {
        let ids: Set<AkaiFile.ID>
        if let program = currentProgram {
            ids = Set(audio.activeSampleIndexes().compactMap { index in
                program.samples.indices.contains(index)
                    ? program.samples[index].fileID : nil
            })
        } else {
            ids = []
        }
        guard ids != activeSampleIDs else { return }
        activeSampleIDs = ids
        publishSampleIndicators()
    }

    private func publishSampleIndicators() {
        // The table spot follows the latest Note On immediately. It deliberately
        // does not union older voices that may still be sounding or releasing.
        let ids = recentlyTriggeredSampleIDs
        guard ids != indicatedSampleIDs else { return }
        indicatedSampleIDs = ids
        onSampleIndicatorsChanged?(ids)
    }

    private func updateStatus(lastInput: String? = nil) {
        if let errorMessage {
            status = errorMessage.uppercased()
        } else if !inputEnabled {
            status = "AUDITION OFF"
        } else if isPreparingProgram {
            status = "PREPARING · \(targetName?.uppercased() ?? "P9 PROGRAM")"
        } else if currentProgram == nil {
            status = "SELECT AN AUDITION PROGRAM"
        } else if let lastInput {
            status = lastInput.uppercased()
        } else if let lastFeedbackNote {
            status = lastFeedbackNote.summary.uppercased()
        } else if let currentProgram {
            let route = omni ? "OMNI" : "KG CH \(selectedMIDIChannel + 1)"
            let playable = currentProgram.playableKeygroupCount(
                omni: omni,
                selectedMIDIChannel: selectedMIDIChannel
            )
            status = "READY · \(targetName?.uppercased() ?? "PROGRAM") · \(route) · "
                + (playable == 0 ? "NO PLAYABLE SOFT KGS" : "\(playable) PLAYABLE KGS")
        } else {
            status = "SELECT AN AUDITION PROGRAM"
        }
    }

    private func emit(
        _ level: DiagnosticLogLevel,
        _ message: String,
        fields: [String: String] = [:]
    ) {
        onDiagnosticEvent?(
            ProgramAuditionDiagnosticEvent(
                level: level,
                message: message,
                fields: fields
            )
        )
    }

#if AKAI_TESTING
    var audioEngineRunningForTesting: Bool { audio.isRunning }

    func stopAudioEngineForRecoveryTest() {
        audio.stopForRecoveryTest()
    }
#endif
}
