import CoreMIDI
import Foundation

struct MIDINoteKey: Hashable, Sendable {
    let channel: Int
    let note: Int
}

enum MIDIInputEvent: Equatable, Sendable {
    case noteOn(key: MIDINoteKey, velocity: Int)
    case noteOff(key: MIDINoteKey, velocity: Int)
    case allNotesOff(channel: Int?)
}

struct MIDIInputEventEnvelope: Equatable, Sendable {
    let sequence: UInt64
    let event: MIDIInputEvent
}

enum MIDIAuditionAction: Equatable {
    case play(note: Int, velocity: Int)
    case stop
}

enum MIDIAuditionPlaybackPolicy {
    static func resolvedAction(
        _ action: MIDIAuditionAction?,
        for event: MIDIInputEvent,
        sustainsThroughNoteOff: Bool
    ) -> MIDIAuditionAction? {
        if case .noteOff = event, sustainsThroughNoteOff {
            return nil
        }
        return action
    }
}

struct MIDIMonophonicNoteTracker: Equatable {
    private(set) var channelFilter: Int?
    private(set) var heldNotes: [MIDINoteKey] = []
    private var velocities: [MIDINoteKey: Int] = [:]

    init(channelFilter: Int? = nil) {
        self.channelFilter = channelFilter
    }

    mutating func setChannelFilter(_ channel: Int?) -> MIDIAuditionAction? {
        guard channelFilter != channel else { return nil }
        channelFilter = channel
        return reset()
    }

    mutating func handle(_ event: MIDIInputEvent) -> MIDIAuditionAction? {
        switch event {
        case let .noteOn(key, velocity):
            guard accepts(key.channel) else { return nil }
            heldNotes.removeAll { $0 == key }
            heldNotes.append(key)
            velocities[key] = velocity
            return .play(note: key.note, velocity: velocity)

        case let .noteOff(key, _):
            guard accepts(key.channel) else { return nil }
            let wasCurrent = heldNotes.last == key
            heldNotes.removeAll { $0 == key }
            velocities[key] = nil
            guard wasCurrent else { return nil }
            return currentPlayAction ?? .stop

        case let .allNotesOff(channel):
            let previousCurrent = heldNotes.last
            if let channel {
                heldNotes.removeAll { $0.channel == channel }
                velocities = velocities.filter { $0.key.channel != channel }
            } else {
                heldNotes.removeAll()
                velocities.removeAll()
            }
            guard heldNotes.last != previousCurrent else { return nil }
            return currentPlayAction ?? .stop
        }
    }

    mutating func reset() -> MIDIAuditionAction? {
        let hadNotes = !heldNotes.isEmpty
        heldNotes.removeAll()
        velocities.removeAll()
        return hadNotes ? .stop : nil
    }

    private func accepts(_ channel: Int) -> Bool {
        channelFilter == nil || channelFilter == channel
    }

    private var currentPlayAction: MIDIAuditionAction? {
        guard let key = heldNotes.last else { return nil }
        return .play(note: key.note, velocity: velocities[key] ?? 0)
    }
}

struct MIDIMessageDecoder {
    private var runningStatus: UInt8?
    private var pendingStatus: UInt8?
    private var pendingData: [UInt8] = []
    private var isInsideSystemExclusive = false

    mutating func decode(_ bytes: [UInt8]) -> [MIDIInputEvent] {
        var events: [MIDIInputEvent] = []
        for byte in bytes {
            if byte >= 0xF8 {
                if byte == 0xFF {
                    events.append(.allNotesOff(channel: nil))
                    resetParserState()
                }
                continue
            }

            if byte & 0x80 != 0 {
                beginMessage(with: byte)
                continue
            }

            guard !isInsideSystemExclusive else { continue }
            if pendingStatus == nil {
                pendingStatus = runningStatus
            }
            guard let status = pendingStatus,
                  let requiredCount = Self.dataLength(for: status),
                  requiredCount > 0
            else {
                continue
            }

            pendingData.append(byte & 0x7F)
            guard pendingData.count == requiredCount else { continue }
            if let event = Self.event(status: status, data: pendingData) {
                events.append(event)
            }
            pendingData.removeAll(keepingCapacity: true)
            pendingStatus = status < 0xF0 ? runningStatus : nil
        }
        return events
    }

    mutating func reset() {
        resetParserState()
    }

    private mutating func resetParserState() {
        runningStatus = nil
        pendingStatus = nil
        pendingData.removeAll(keepingCapacity: true)
        isInsideSystemExclusive = false
    }

    private mutating func beginMessage(with status: UInt8) {
        pendingData.removeAll(keepingCapacity: true)
        switch status {
        case 0x80...0xEF:
            isInsideSystemExclusive = false
            runningStatus = status
            pendingStatus = status
        case 0xF0:
            isInsideSystemExclusive = true
            runningStatus = nil
            pendingStatus = nil
        case 0xF7:
            isInsideSystemExclusive = false
            runningStatus = nil
            pendingStatus = nil
        default:
            isInsideSystemExclusive = false
            runningStatus = nil
            pendingStatus = Self.dataLength(for: status) == 0 ? nil : status
        }
    }

    private static func dataLength(for status: UInt8) -> Int? {
        switch status {
        case 0x80...0xBF, 0xE0...0xEF, 0xF2:
            return 2
        case 0xC0...0xDF, 0xF1, 0xF3:
            return 1
        case 0xF6, 0xF7:
            return 0
        default:
            return nil
        }
    }

    private static func event(
        status: UInt8,
        data: [UInt8]
    ) -> MIDIInputEvent? {
        let type = status & 0xF0
        let channel = Int(status & 0x0F)
        switch type {
        case 0x80:
            return .noteOff(
                key: MIDINoteKey(channel: channel, note: Int(data[0])),
                velocity: Int(data[1])
            )
        case 0x90:
            let key = MIDINoteKey(channel: channel, note: Int(data[0]))
            let velocity = Int(data[1])
            return velocity == 0
                ? .noteOff(key: key, velocity: 0)
                : .noteOn(key: key, velocity: velocity)
        case 0xB0 where data[0] == 120 || data[0] == 123:
            return .allNotesOff(channel: channel)
        default:
            return nil
        }
    }
}

enum MIDIKeygroupTriggerMatcher {
    static func matches(
        _ keygroup: P9Keygroup,
        activeNotes: [MIDINoteKey: Int]
    ) -> Bool {
        // A temporarily inverted range can exist while the two note fields are
        // edited independently. Forming `lowKey...highKey` in that state traps,
        // so treat the incomplete range as non-triggering until it is valid.
        guard keygroup.lowKey <= keygroup.highKey else { return false }
        return activeNotes.keys.contains { event in
            event.channel == keygroup.midiChannelOffset
                && (keygroup.lowKey...keygroup.highKey).contains(event.note)
        }
    }
}

@MainActor
final class MIDIKeygroupMonitor: ObservableObject {
    @Published private(set) var activeNotes: [MIDINoteKey: Int] = [:]
    @Published private(set) var sourceCount = 0
    @Published private(set) var lastEventDescription = "Waiting for MIDI"
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRunning = false
    @Published private(set) var lastEvent: MIDIInputEventEnvelope?

    var eventHandler: ((MIDIInputEventEnvelope) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSources: [MIDIEndpointRef] = []
    private var decoder = MIDIMessageDecoder()
    private var eventSequence: UInt64 = 0

    func start() {
        guard !isRunning else { return }
        var newClient = MIDIClientRef()
        let clientStatus = MIDIClientCreateWithBlock(
            "EDIT950 MIDI Monitor" as CFString,
            &newClient
        ) { [weak self] _ in
            guard let monitor = self else { return }
            Task { @MainActor in monitor.reconnectSources() }
        }
        guard clientStatus == noErr else {
            errorMessage = "CoreMIDI could not create a client (\(clientStatus))."
            return
        }
        client = newClient

        var newPort = MIDIPortRef()
        let portStatus = MIDIInputPortCreateWithBlock(
            client,
            "All MIDI Inputs" as CFString,
            &newPort
        ) { [weak self] packetList, _ in
            self?.receive(packetList)
        }
        guard portStatus == noErr else {
            MIDIClientDispose(client)
            client = MIDIClientRef()
            errorMessage = "CoreMIDI could not create an input port (\(portStatus))."
            return
        }
        inputPort = newPort
        decoder.reset()
        isRunning = true
        errorMessage = nil
        reconnectSources()
    }

    func stop() {
        guard isRunning || client != 0 else { return }
        for source in connectedSources {
            MIDIPortDisconnectSource(inputPort, source)
        }
        connectedSources.removeAll()
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if client != 0 { MIDIClientDispose(client) }
        inputPort = MIDIPortRef()
        client = MIDIClientRef()
        decoder.reset()
        publishAllNotesOff(description: "MIDI monitor stopped")
        sourceCount = 0
        isRunning = false
    }

    private func reconnectSources() {
        guard isRunning, inputPort != 0 else { return }
        decoder.reset()
        if !activeNotes.isEmpty {
            publishAllNotesOff(description: "MIDI inputs changed · all notes off")
        }
        for source in connectedSources {
            MIDIPortDisconnectSource(inputPort, source)
        }
        connectedSources.removeAll()
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            guard source != 0,
                  MIDIPortConnectSource(inputPort, source, nil) == noErr
            else { continue }
            connectedSources.append(source)
        }
        sourceCount = connectedSources.count
        lastEventDescription = sourceCount == 0
            ? "No MIDI input devices"
            : "Listening to \(sourceCount) MIDI input\(sourceCount == 1 ? "" : "s")"
    }

    nonisolated private func receive(_ packetList: UnsafePointer<MIDIPacketList>) {
        var messages: [[UInt8]] = []
        withUnsafePointer(to: packetList.pointee.packet) { firstPacket in
            var packetPointer = UnsafeMutablePointer(mutating: firstPacket)
            for _ in 0..<packetList.pointee.numPackets {
                let packet = packetPointer.pointee
                let bytes = withUnsafeBytes(of: packet.data) {
                    Array($0.prefix(Int(packet.length)))
                }
                messages.append(bytes)
                packetPointer = MIDIPacketNext(packetPointer)
            }
        }
        let receivedMessages = messages
        Task { @MainActor [weak self, receivedMessages] in
            for bytes in receivedMessages { self?.consume(bytes) }
        }
    }

    private func consume(_ bytes: [UInt8]) {
        for event in decoder.decode(bytes) {
            apply(event)
        }
    }

    private func apply(_ event: MIDIInputEvent) {
        switch event {
        case let .noteOn(key, velocity):
            activeNotes[key] = velocity
            publish(
                event,
                description:
                    "\(P9Keygroup.noteName(key.note)) · Vel \(velocity) · Ch \(key.channel + 1)"
            )
        case let .noteOff(key, _):
            activeNotes[key] = nil
            publish(
                event,
                description:
                    "Off · \(P9Keygroup.noteName(key.note)) · Ch \(key.channel + 1)"
            )
        case let .allNotesOff(channel):
            if let channel {
                activeNotes = activeNotes.filter { $0.key.channel != channel }
                publish(
                    event,
                    description: "All notes off · Ch \(channel + 1)"
                )
            } else {
                publishAllNotesOff(description: "All notes off")
            }
        }
    }

    private func publishAllNotesOff(description: String) {
        activeNotes.removeAll()
        publish(.allNotesOff(channel: nil), description: description)
    }

    private func publish(_ event: MIDIInputEvent, description: String) {
        eventSequence &+= 1
        let envelope = MIDIInputEventEnvelope(
            sequence: eventSequence,
            event: event
        )
        lastEvent = envelope
        lastEventDescription = description
        eventHandler?(envelope)
    }
}
