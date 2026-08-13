import Foundation

struct PLAY950FixtureProgram: Equatable {
    let name: String
    let sampleName: String
    let amplitude: P9Envelope
    let filter: Int
    let vcfAmount: Int
    let vcfEnvelope: P9Envelope
    let velocityFilter: Int
    let keyFilter: Int
    let oneShot: Bool
    let lowKey: Int
    let highKey: Int

    init(
        _ name: String,
        sample: String = "ENV TEST",
        amplitude: P9Envelope,
        filter: Int = 99,
        vcfAmount: Int = 0,
        vcfEnvelope: P9Envelope = P9Envelope(attack: 0, decay: 0, sustain: 99, release: 0),
        velocityFilter: Int = 0,
        keyFilter: Int = 0,
        oneShot: Bool = false,
        lowKey: Int = 0,
        highKey: Int = 127
    ) {
        self.name = name
        sampleName = sample
        self.amplitude = amplitude
        self.filter = filter
        self.vcfAmount = vcfAmount
        self.vcfEnvelope = vcfEnvelope
        self.velocityFilter = velocityFilter
        self.keyFilter = keyFilter
        self.oneShot = oneShot
        self.lowKey = lowKey
        self.highKey = highKey
    }

    func makeProgram() throws -> P9Program {
        var program = try P9Program.blank(named: name)
        var keygroup = program.keygroups[0]
        keygroup.lowKey = lowKey
        keygroup.highKey = highKey
        keygroup.envelope = amplitude
        keygroup.softSampleName = sampleName
        keygroup.softTuning = P9Tuning(transpose: 0, fine: 0)
        keygroup.softFilter = filter
        keygroup.softLoudness = 0
        keygroup.loudSampleName = ""
        keygroup.loudTuning = P9Tuning(transpose: 0, fine: 0)
        keygroup.loudFilter = filter
        keygroup.loudLoudness = 0
        keygroup.vcfEnvelope = vcfEnvelope
        keygroup.vcfAmount = vcfAmount
        keygroup.velocitySensitivity = P9VelocitySensitivity(
            loudness: 0,
            attack: 0,
            filter: velocityFilter,
            release: 0
        )
        keygroup.keyFilter = keyFilter
        keygroup.lfoDepth = 0
        keygroup.constantPitch = false
        keygroup.velocityCrossfade = false
        keygroup.oneShot = oneShot
        keygroup.releaseVelocityFromNoteOn = false
        keygroup.customVelocityCrossfadePoint = false
        keygroup.output = .all
        keygroup.midiChannelOffset = 0
        program.keygroups[0] = keygroup
        return program
    }
}

enum PLAY950FixtureSpecification {
    static let sampleSources: [(aliases: [String], importName: String, nativeName: String, forceMainLoop: Bool)] = [
        (["ENV_TEST.wav", "ENV-TEST.wav"], "ENV_TEST", "ENV TEST", true),
        (["NOISE.wav", "NOISE_TEST.wav"], "NOISE", "NOISE", true),
        (["FILTER_1.wav", "FILTER1.wav", "FILTER-1.wav"], "FILTER_1", "FILTER", true),
        (["LOW_SINE.wav", "LOW-SINE.wav"], "LOW_SINE", "LOW SINE", false),
        (["HIGH_SINE.wav", "HIGH-SINE.wav", "HIGHS-INE.wav"], "HIGH_SINE", "HIGH SINE", false)
    ]

    private static let neutral = P9Envelope(attack: 1, decay: 0, sustain: 99, release: 0)
    private static let neutralVCF = P9Envelope(attack: 0, decay: 0, sustain: 99, release: 0)
    private static let shapedVCF = P9Envelope(attack: 0, decay: 40, sustain: 50, release: 40)

    static let programs: [PLAY950FixtureProgram] = [
        .init("ENVA01", amplitude: .init(attack: 1, decay: 0, sustain: 99, release: 0)),
        .init("ENVA25", amplitude: .init(attack: 25, decay: 0, sustain: 99, release: 0)),
        .init("ENVA50", amplitude: .init(attack: 50, decay: 0, sustain: 99, release: 0)),
        .init("ENVA75", amplitude: .init(attack: 75, decay: 0, sustain: 99, release: 0)),
        .init("ENVA99", amplitude: .init(attack: 99, decay: 0, sustain: 99, release: 0)),

        .init("ENVD00", amplitude: .init(attack: 0, decay: 0, sustain: 25, release: 0)),
        .init("ENVD25", amplitude: .init(attack: 0, decay: 25, sustain: 25, release: 0)),
        .init("ENVD50", amplitude: .init(attack: 0, decay: 50, sustain: 25, release: 0)),
        .init("ENVD75", amplitude: .init(attack: 0, decay: 75, sustain: 25, release: 0)),
        .init("ENVD99", amplitude: .init(attack: 0, decay: 99, sustain: 25, release: 0)),

        .init("ENVS00", amplitude: .init(attack: 0, decay: 40, sustain: 0, release: 0)),
        .init("ENVS25", amplitude: .init(attack: 0, decay: 40, sustain: 25, release: 0)),
        .init("ENVS50", amplitude: .init(attack: 0, decay: 40, sustain: 50, release: 0)),
        .init("ENVS75", amplitude: .init(attack: 0, decay: 40, sustain: 75, release: 0)),
        .init("ENVS99", amplitude: .init(attack: 0, decay: 40, sustain: 99, release: 0)),

        .init("ENVR00", amplitude: neutral),
        .init("ENVR25", amplitude: .init(attack: 0, decay: 0, sustain: 99, release: 25)),
        .init("ENVR50", amplitude: .init(attack: 0, decay: 0, sustain: 99, release: 50)),
        .init("ENVR75", amplitude: .init(attack: 0, decay: 0, sustain: 99, release: 75)),
        .init("ENVR99", amplitude: .init(attack: 0, decay: 0, sustain: 99, release: 99)),

        .init("ENVGATE", amplitude: neutral),
        .init("ENVSLOW", amplitude: .init(attack: 50, decay: 50, sustain: 50, release: 50)),
        .init("ENVONESH", amplitude: neutral, oneShot: true),

        .init("FLNC00", sample: "NOISE", amplitude: neutral, filter: 0),
        .init("FLNC20", sample: "NOISE", amplitude: neutral, filter: 20),
        .init("FLNC40", sample: "NOISE", amplitude: neutral, filter: 40),
        .init("FLNC60", sample: "NOISE", amplitude: neutral, filter: 60),
        .init("FLNC80", sample: "NOISE", amplitude: neutral, filter: 80),
        .init("FLNC99", sample: "NOISE", amplitude: neutral, filter: 99),

        .init("FCUT00", sample: "FILTER", amplitude: neutral, filter: 0),
        .init("FCUT20", sample: "FILTER", amplitude: neutral, filter: 20),
        .init("FCUT40", sample: "FILTER", amplitude: neutral, filter: 40),
        .init("FCUT60", sample: "FILTER", amplitude: neutral, filter: 60),
        .init("FCUT80", sample: "FILTER", amplitude: neutral, filter: 80),
        .init("FCUT99", sample: "FILTER", amplitude: neutral, filter: 99),

        .init("KEYTRACK", sample: "FILTER", amplitude: neutral, filter: 50, keyFilter: 50, lowKey: 48, highKey: 72),
        .init("ENVNEG", sample: "FILTER", amplitude: neutral, filter: 50, vcfAmount: -50, vcfEnvelope: shapedVCF),
        .init("ENVZERO", sample: "FILTER", amplitude: neutral, filter: 50, vcfAmount: 0, vcfEnvelope: shapedVCF),
        .init("ENVPOS", sample: "FILTER", amplitude: neutral, filter: 50, vcfAmount: 50, vcfEnvelope: shapedVCF),
        .init("ENVFAST", sample: "FILTER", amplitude: neutral, filter: 50, vcfAmount: 50, vcfEnvelope: .init(attack: 0, decay: 0, sustain: 50, release: 0)),
        .init("ENVMID", sample: "FILTER", amplitude: neutral, filter: 50, vcfAmount: 50, vcfEnvelope: .init(attack: 50, decay: 50, sustain: 50, release: 50)),
        .init("VCFSLOW", sample: "FILTER", amplitude: neutral, filter: 50, vcfAmount: 50, vcfEnvelope: .init(attack: 99, decay: 99, sustain: 50, release: 99)),
        .init("VELFILT", sample: "FILTER", amplitude: neutral, filter: 50, velocityFilter: 99)
    ]
}
