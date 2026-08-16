import Foundation

enum P9TestFixture {
    static func make(keygroupCount: Int) -> Data {
        var data = Data(
            repeating: 0xA5,
            count: P9Program.headerSize
                + keygroupCount * P9Program.keygroupSize
        )
        data.replaceSubrange(
            0x00..<0x0A,
            with: Array("JUNGLE    ".utf8)
        )
        data[0x15] = 0
        data[0x17] = UInt8(keygroupCount)

        for index in 0..<keygroupCount {
            let base = P9Program.headerSize
                + index * P9Program.keygroupSize
            data[base + 0x00] = UInt8(60 + index)
            data[base + 0x01] = UInt8(60 + index)
            data[base + 0x02] = 128
            data[base + 0x03] = 0
            data[base + 0x04] = 80
            data[base + 0x05] = 99
            data[base + 0x06] = 30
            data[base + 0x07] = 31
            data[base + 0x08] = 52
            data[base + 0x09] = 13
            data[base + 0x0A] = UInt8(bitPattern: Int8(-7))
            data[base + 0x0B] = 47
            data[base + 0x12] = 0x04
            data[base + 0x13] = 0xFF
            data[base + 0x14] = 0
            data[base + 0x17] = 0
            data.replaceSubrange(
                (base + 0x18)..<(base + 0x22),
                with: Array("AMEN-01   ".utf8)
            )
            data[base + 0x22] = 20
            data[base + 0x23] = 20
            data[base + 0x24] = 20
            data[base + 0x25] = 20
            data[base + 0x26] = 64
            data[base + 0x27] = 0x5A
            data[base + 0x2A] = 0
            data[base + 0x2B] = 0
            data[base + 0x2C] = 99
            data[base + 0x2D] = 0
            data.replaceSubrange(
                (base + 0x2E)..<(base + 0x38),
                with: Array("HARD-01   ".utf8)
            )
            data[base + 0x40] = 0
            data[base + 0x41] = 0
            data[base + 0x42] = 99
            data[base + 0x43] = 0
        }
        return data
    }
}
