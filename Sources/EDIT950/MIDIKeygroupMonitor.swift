import CoreMIDI
import Foundation

struct MIDINoteKey: Hashable {
    let channel: Int
    let note: Int
}

enum MIDIKeygroupTriggerMatcher {
    static func matches(
        _ keygroup: P9Keygroup,
        activeNotes: [MIDINoteKey: Int]
    ) -> Bool {
        activeNotes.keys.contains { event in
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

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSources: [MIDIEndpointRef] = []

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
        activeNotes.removeAll()
        sourceCount = 0
        isRunning = false
        lastEventDescription = "MIDI monitor stopped"
    }

    private func reconnectSources() {
        guard isRunning, inputPort != 0 else { return }
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
        var index = 0
        while index < bytes.count {
            let status = bytes[index]
            guard status & 0x80 != 0 else {
                index += 1
                continue
            }
            let type = status & 0xF0
            let channel = Int(status & 0x0F)
            let dataLength = (type == 0xC0 || type == 0xD0) ? 1 : 2
            guard index + dataLength < bytes.count else { break }
            if type == 0x80 || type == 0x90 {
                let note = Int(bytes[index + 1] & 0x7F)
                let velocity = Int(bytes[index + 2] & 0x7F)
                let key = MIDINoteKey(channel: channel, note: note)
                if type == 0x80 || velocity == 0 {
                    activeNotes[key] = nil
                    lastEventDescription =
                        "Off · \(P9Keygroup.noteName(note)) · Ch \(channel + 1)"
                } else {
                    activeNotes[key] = velocity
                    lastEventDescription =
                        "\(P9Keygroup.noteName(note)) · Vel \(velocity) · Ch \(channel + 1)"
                }
            }
            index += dataLength + 1
        }
    }
}
