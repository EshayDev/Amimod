import Foundation

public typealias XMSamplePoint = Int16

public enum XMConstants {
    public static let waveformSine: UInt8 = 0
    public static let waveformRampDown: UInt8 = 1
    public static let waveformSquare: UInt8 = 2
    public static let waveformRampUp: UInt8 = 3

    public static let featurePingPongLoops: Int = 0
    public static let featureNoteKeyOff: Int = 1
    public static let featureNoteSwitch: Int = 2
    public static let featureMultisampleInstruments: Int = 3
    public static let featureVolumeEnvelopes: Int = 4
    public static let featurePanningEnvelopes: Int = 5
    public static let featureFadeoutVolume: Int = 6
    public static let featureAutovibrato: Int = 7
    public static let featureLinearFrequencies: Int = 8
    public static let featureAmigaFrequencies: Int = 9
    public static func featureWaveform(_ w: UInt8) -> Int { return 12 | Int(w) }
    public static let featureAccurateSampleOffsetEffect: Int = 16
    public static let featureAccurateArpeggioOverflow: Int = 17
    public static let featureAccurateArpeggioGlissando: Int = 18
    public static let featureInvalidInstruments: Int = 19
    public static let featureInvalidSamples: Int = 20
    public static let featureInvalidNotes: Int = 21
    public static let featureClampPeriods: Int = 22
    public static let featureSampleRelativeNotes: Int = 23
    public static let featureSampleFinetunes: Int = 24
    public static let featureSamplePannings: Int = 25

    public static let featureVariableTempoBase: Int = 27
    public static let featureVariableBpmBase: Int = 32

    public static let sampleNameLength: Int = 24
    public static let instrumentNameLength: Int = 24
    public static let moduleNameLength: Int = 24
    public static let trackerNameLength: Int = 24

    public static let patternOrderTableLength: Int = 256
    public static let maxNote: UInt8 = 96
    public static let maxEnvelopePoints: Int = 12
    public static let maxRowsPerPattern: Int = 256
    public static let rampingPoints: Int = 255
    public static let maxVolume: UInt8 = 64
    public static let maxFadeoutVolume: UInt16 = 32768
    public static let maxPanning: UInt16 = 256
    public static let maxEnvelopeValue: UInt8 = 64
    public static let minBpm: UInt8 = 32
    public static let maxBpm: UInt8 = 255
    public static let maxPatterns: Int = 256
    public static let maxInstruments: Int = Int(UInt8.max)
    public static let maxChannels: Int = Int(UInt8.max)
    public static let maxSamplesPerInstrument: Int = Int(UInt8.max)

    public static let noteKeyOff: UInt8 = 128
    public static let noteRetrigger: UInt8 = maxNote &+ 1
    public static let noteSwitch: UInt8 = maxNote &+ 2

    public static let amplification: Float = 0.25

    public static let tickSubsamples: UInt32 = 1 << 13
    public static let sampleMicrosteps: UInt32 = 1 << 12

    public static let maxSampleLength: UInt32 = UInt32.max / sampleMicrosteps
}

public enum XMEffect: Int {
    case arpeggio = 0
    case portamentoUp = 1
    case portamentoDown = 2
    case tonePortamento = 3
    case vibrato = 4
    case tonePortamentoVolumeSlide = 5
    case vibratoVolumeSlide = 6
    case tremolo = 7
    case setPanning = 8
    case setSampleOffset = 9
    case volumeSlide = 0xA
    case jumpToOrder = 0xB
    case setVolume = 0xC
    case patternBreak = 0xD
    case setTempo = 0xE
    case setBPM = 0xF

    case setGlobalVolume = 16
    case globalVolumeSlide = 17
    case extraFinePortamentoUp = 18
    case extraFinePortamentoDown = 19
    case keyOff = 20
    case setEnvelopePosition = 21
    case panningSlide = 25
    case multiRetrigNote = 27
    case tremor = 29
    case finePortamentoUp = 33
    case finePortamentoDown = 34
    case setGlissandoControl = 35
    case setVibratoControl = 36
    case setFinetune = 37
    case patternLoop = 38
    case setTremoloControl = 39
    case retriggerNote = 41
    case fineVolumeSlideUp = 42
    case fineVolumeSlideDown = 43
    case cutNote = 44
    case delayNote = 45
    case delayPattern = 46
}

public enum XMVolumeEffect: Int {
    case slideDown = 6
    case slideUp = 7
    case fineSlideDown = 8
    case fineSlideUp = 9
    case vibratoSpeed = 0xA
    case vibrato = 0xB
    case setPanning = 0xC
    case panningSlideLeft = 0xD
    case panningSlideRight = 0xE
    case tonePortamento = 0xF
}

public struct XMBuildConfig {
    public static let disabledEffects: UInt64 = 0
    public static let disabledVolumeEffects: UInt16 = 0
    public static let disabledFeatures: UInt64 = 0

    public static var panningType: Int = 8
    public static let loopingType: Int = 2
    public static var linearInterpolation: Bool = false
    public static var ramping: Bool = true
    public static let strings: Bool = true
    public static let timingFunctions: Bool = true
    public static let mutingFunctions: Bool = true
}

public struct XMEnvelopePoint {
    public var frame: UInt16
    public var value: UInt8
}

public struct XMEnvelope {
    public var points: [XMEnvelopePoint] = Array(
        repeating: XMEnvelopePoint(frame: 0, value: 0),
        count: XMConstants.maxEnvelopePoints)
    public var numPoints: UInt8 = 0
    public var sustainPoint: UInt8 = 0
    public var loopStartPoint: UInt8 = 0
    public var loopEndPoint: UInt8 = 0
}

public struct XMSample {
    public var latestTrigger: UInt32 = 0

    public var index: UInt32 = 0
    public var length: UInt32 = 0
    public var loopLength: UInt32 = 0

    public var pingPong: Bool = false
    public var volume: UInt8 = XMConstants.maxVolume
    public var panning: UInt16 = XMConstants.maxPanning / 2
    public var finetune: Int8 = 0
    public var relativeNote: Int8 = 0

    public var name: String = ""
}

public struct XMInstrument {
    public var latestTrigger: UInt32 = 0

    public var volumeEnvelope: XMEnvelope = XMEnvelope()
    public var panningEnvelope: XMEnvelope = XMEnvelope()

    public var sampleOfNotes: [UInt8] = Array(
        repeating: 0, count: Int(XMConstants.maxNote))
    public var samplesIndex: UInt16 = 0
    public var numSamples: UInt8 = 0

    public var volumeFadeout: UInt16 = 0

    public var vibratoType: UInt8 = 0
    public var vibratoSweep: UInt8 = 0
    public var vibratoDepth: UInt8 = 0
    public var vibratoRate: UInt8 = 0

    public var muted: Bool = false

    public var name: String = ""
}

public struct XMPatternSlot {
    public var note: UInt8 = 0
    public var instrument: UInt8 = 0
    public var volumeColumn: UInt8 = 0
    public var effectType: UInt8 = 0
    public var effectParam: UInt8 = 0
}

public struct XMPattern {
    public var rowsIndex: UInt16 = 0
    public var numRows: UInt16 = 0
}

public struct XMModule {
    public var samplesDataLength: UInt32 = 0
    public var numRows: UInt32 = 0
    public var length: UInt16 = 0
    public var numPatterns: UInt16 = 0
    public var numSamples: UInt16 = 0

    public var rate: UInt16 = 48_000

    public var numChannels: UInt8 = 0
    public var numInstruments: UInt8 = 0

    public var patternTable: [UInt8] = Array(
        repeating: 0, count: XMConstants.patternOrderTableLength)

    public var restartPosition: UInt8 = 0
    public var maxLoopCount: UInt8 = 0

    public var tempo: UInt8 = XMConstants.minBpm - 1
    public var bpm: UInt8 = 125

    public var amigaFrequencies: Bool = false

    public var isMOD: Bool = false

    public var name: String = ""
    public var trackerName: String = ""
}

public struct XMChannelContext {
    public var instrument: Int? = nil
    public var sample: Int? = nil
    public var current: XMPatternSlot = XMPatternSlot()

    public var latestTrigger: UInt32 = 0

    public var samplePosition: UInt32 = 0
    public var step: UInt32 = 0

    public var actualVolume: (Float, Float) = (0, 0)
    public var targetVolume: (Float, Float) = (0, 0)
    public var frameCount: UInt32 = 0
    public var endOfPreviousSample: [Float] = Array(
        repeating: 0, count: XMConstants.rampingPoints)

    public var period: UInt16 = 0
    public var tonePortamentoTargetPeriod: UInt16 = 0

    public var fadeoutVolume: UInt16 = XMConstants.maxFadeoutVolume - 1

    public var autovibratoTicks: UInt16 = 0
    public var volumeEnvelopeFrameCount: UInt16 = 0
    public var panningEnvelopeFrameCount: UInt16 = 0

    public var volumeEnvelopeVolume: UInt8 = XMConstants.maxEnvelopeValue
    public var panningEnvelopePanning: UInt8 = XMConstants.maxEnvelopeValue / 2

    public var volume: UInt8 = XMConstants.maxVolume

    public var volumeOffset: Int8 = 0

    public var panning: UInt16 = XMConstants.maxPanning / 2

    public var origNote: UInt8 = 0
    public var finetune: Int8 = 0

    public var nextInstrument: UInt8 = 0

    public var volumeSlideParam: UInt8 = 0
    public var fineVolumeSlideUpParam: UInt8 = 0
    public var fineVolumeSlideDownParam: UInt8 = 0
    public var globalVolumeSlideParam: UInt8 = 0
    public var panningSlideParam: UInt8 = 0
    public var portamentoUpParam: UInt8 = 0
    public var portamentoDownParam: UInt8 = 0
    public var finePortamentoUpParam: UInt8 = 0
    public var finePortamentoDownParam: UInt8 = 0
    public var extraFinePortamentoUpParam: UInt8 = 0
    public var extraFinePortamentoDownParam: UInt8 = 0

    public var glissandoControlParam: UInt8 = 0
    public var glissandoControlError: Int8 = 0

    public var tonePortamentoParam: UInt8 = 0

    public var multiRetrigParam: UInt8 = 0
    public var multiRetrigTicks: UInt8 = 0

    public var patternLoopOrigin: UInt8 = 0
    public var patternLoopCount: UInt8 = 0

    public var sampleOffsetParam: UInt8 = 0
    public var sampleOffsetInvalid: Bool = false

    public var tremoloParam: UInt8 = 0
    public var tremoloTicks: UInt8 = 0
    public var tremoloControlParam: UInt8 = 0

    public var vibratoParam: UInt8 = 0
    public var vibratoTicks: UInt8 = 0
    public var vibratoOffset: Int8 = 0
    public var shouldResetVibrato: Bool = true
    public var vibratoControlParam: UInt8 = 0

    public var autovibratoOffset: Int8 = 0

    public var shouldResetArpeggio: Bool = false
    public var arpNoteOffset: UInt8 = 0

    public var tremorParam: UInt8 = 0
    public var tremorTicks: UInt8 = 0
    public var tremorOn: Bool = false

    public var sustained: Bool = true

    public var muted: Bool = false
}

public struct XMContext {
    public var patterns: [XMPattern] = []
    public var patternSlots: [XMPatternSlot] = []
    public var instruments: [XMInstrument] = []
    public var samples: [XMSample] = []
    public var samplesData: [XMSamplePoint] = []
    public var channels: [XMChannelContext] = []

    public var rowLoopCount: [UInt8] = []

    public var module: XMModule = XMModule()

    public var remainingSamplesInTick: UInt32 = 0
    public var generatedSamples: UInt32 = 0

    public var currentTableIndex: UInt16 = 0
    public var currentTick: UInt8 = 0
    public var currentRow: UInt8 = 0

    public var extraRowsDone: UInt8 = 0
    public var extraRows: UInt8 = 0

    public var globalVolume: UInt8 = XMConstants.maxVolume

    public var currentTempo: UInt8 = XMConstants.minBpm - 1
    public var currentBpm: UInt8 = XMConstants.minBpm

    public var patternBreak: Bool = false

    public var positionJump: Bool = false
    public var jumpDest: UInt8 = 0

    public var jumpRow: UInt8 = 0

    public var loopCount: UInt8 = 0

    public init() {}
}

public enum XMMacros {
    @inline(__always) public static func sampleRate(_ mod: XMModule) -> UInt16 {
        mod.rate
    }
    @inline(__always) public static func numInstruments(_ mod: XMModule)
        -> UInt8
    {
        mod.numInstruments
    }
    @inline(__always) public static func maxLoopCount(_ mod: XMModule) -> UInt8
    { mod.maxLoopCount }
    @inline(__always) public static func amigaFrequencies(_ mod: XMModule)
        -> Bool
    {
        mod.amigaFrequencies
    }
}
