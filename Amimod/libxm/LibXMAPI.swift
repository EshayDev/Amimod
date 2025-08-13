import Foundation

public enum LibXM {
    public static func load(data: Data) -> XMContext? {
        return LibXMLoader.createContext(from: data)
    }
    public static func load(url: URL) -> XMContext? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return load(data: d)
    }
    public static func load(path: String) -> XMContext? {
        return load(url: URL(fileURLWithPath: path))
    }

    public static func setSampleRate(_ ctx: inout XMContext, _ rate: UInt16) {
        ctx.module.rate = rate
    }
    public static func getSampleRate(_ ctx: XMContext) -> UInt16 {
        ctx.module.rate
    }

    public static func setLinearInterpolation(_ enabled: Bool) {
        XMBuildConfig.linearInterpolation = enabled
    }
    public static func isLinearInterpolationEnabled() -> Bool {
        XMBuildConfig.linearInterpolation
    }
    public static func setRamping(_ enabled: Bool) {
        XMBuildConfig.ramping = enabled
    }
    public static func isRampingEnabled() -> Bool { XMBuildConfig.ramping }
    public static func setPanningType(_ type: Int) {
        XMBuildConfig.panningType = max(0, min(8, type))
    }
    public static func getPanningType() -> Int { XMBuildConfig.panningType }

    public static func setMaxLoopCount(_ ctx: inout XMContext, _ loopcnt: UInt8)
    {
        ctx.module.maxLoopCount = loopcnt
    }
    public static func getLoopCount(_ ctx: XMContext) -> UInt8 { ctx.loopCount }
    public static func getMaxLoopCount(_ ctx: XMContext) -> UInt8 {
        ctx.module.maxLoopCount
    }

    public static func seek(
        _ ctx: inout XMContext, pot: UInt8, row: UInt8, tick: UInt8
    ) {
        ctx.currentTableIndex = UInt16(pot)
        ctx.currentRow = row
        ctx.currentTick = tick
        ctx.remainingSamplesInTick = 0
    }

    @discardableResult
    public static func muteChannel(
        _ ctx: inout XMContext, channel: UInt8, mute: Bool
    ) -> Bool {
        precondition(
            channel >= 1 && channel <= ctx.module.numChannels,
            "channel out of range")
        let idx = Int(channel - 1)
        let old = ctx.channels[idx].muted
        ctx.channels[idx].muted = mute
        return old
    }
    @discardableResult
    public static func muteInstrument(
        _ ctx: inout XMContext, instrument: UInt8, mute: Bool
    ) -> Bool {
        precondition(
            instrument >= 1 && instrument <= ctx.module.numInstruments,
            "instrument out of range")
        let idx = Int(instrument - 1)
        let old = ctx.instruments[idx].muted
        ctx.instruments[idx].muted = mute
        return old
    }

    public static func getModuleName(_ ctx: XMContext) -> String {
        ctx.module.name
    }
    public static func getTrackerName(_ ctx: XMContext) -> String {
        ctx.module.trackerName
    }
    public static func getInstrumentName(_ ctx: XMContext, _ i: UInt8) -> String
    {
        precondition(
            i >= 1 && i <= ctx.module.numInstruments, "instrument out of range")
        return ctx.instruments[Int(i - 1)].name
    }
    public static func getSampleName(
        _ ctx: XMContext, instrument i: UInt8, sample s: UInt8
    )
        -> String
    {
        precondition(
            i >= 1 && i <= ctx.module.numInstruments, "instrument out of range")
        let inst = ctx.instruments[Int(i - 1)]
        precondition(Int(s) < Int(inst.numSamples), "sample out of range")
        let sampleIdx = Int(inst.samplesIndex) + Int(s)
        return ctx.samples[sampleIdx].name
    }

    public static func getNumberOfChannels(_ ctx: XMContext) -> UInt8 {
        ctx.module.numChannels
    }
    public static func getModuleLength(_ ctx: XMContext) -> UInt16 {
        ctx.module.length
    }
    public static func getNumberOfPatterns(_ ctx: XMContext) -> UInt16 {
        ctx.module.numPatterns
    }
    public static func getNumberOfRows(_ ctx: XMContext, pattern: UInt16)
        -> UInt16
    {
        ctx.patterns[Int(pattern)].numRows
    }
    public static func getNumberOfInstruments(_ ctx: XMContext) -> UInt8 {
        ctx.module.numInstruments
    }
    public static func getNumberOfSamples(_ ctx: XMContext, instrument: UInt8)
        -> UInt8
    {
        precondition(
            instrument >= 1 && instrument <= ctx.module.numInstruments,
            "instrument out of range")
        return ctx.instruments[Int(instrument - 1)].numSamples
    }

    public static func withSampleWaveformMutable<R>(
        _ ctx: inout XMContext, instrument: UInt8, sample: UInt8,
        _ body: (inout UnsafeMutableBufferPointer<XMSamplePoint>) -> R
    ) -> R {
        precondition(
            instrument >= 1 && instrument <= ctx.module.numInstruments,
            "instrument out of range")
        let inst = ctx.instruments[Int(instrument - 1)]
        precondition(Int(sample) < Int(inst.numSamples), "sample out of range")
        let sMeta = ctx.samples[Int(inst.samplesIndex) + Int(sample)]
        let start = Int(sMeta.index)
        let len = Int(sMeta.length)
        return ctx.samplesData.withUnsafeMutableBufferPointer { buf -> R in
            var sub = UnsafeMutableBufferPointer<XMSamplePoint>(
                start: buf.baseAddress!.advanced(by: start), count: len)
            return body(&sub)
        }
    }

    public static func getPlayingSpeed(_ ctx: XMContext) -> (
        bpm: UInt8, tempo: UInt8
    ) {
        (ctx.currentBpm, ctx.currentTempo)
    }

    public static func getPosition(_ ctx: XMContext) -> (
        patternIndex: UInt8, pattern: UInt8, row: UInt8, samples: UInt32
    ) {
        let patIndex = UInt8(ctx.currentTableIndex)
        let pattern = ctx.module.patternTable[Int(ctx.currentTableIndex)]
        let row = ctx.currentRow &- 1
        let samples = ctx.generatedSamples
        return (patIndex, pattern, row, samples)
    }

    public static func getLatestTriggerOfInstrument(
        _ ctx: XMContext, instrument: UInt8
    ) -> UInt32 {
        precondition(
            instrument >= 1 && instrument <= ctx.module.numInstruments,
            "instrument out of range")
        return ctx.instruments[Int(instrument - 1)].latestTrigger
    }

    public static func getLatestTriggerOfSample(
        _ ctx: XMContext, instrument: UInt8, sample: UInt8
    )
        -> UInt32
    {
        precondition(
            instrument >= 1 && instrument <= ctx.module.numInstruments,
            "instrument out of range")
        let inst = ctx.instruments[Int(instrument - 1)]
        precondition(Int(sample) < Int(inst.numSamples), "sample out of range")
        return ctx.samples[Int(inst.samplesIndex) + Int(sample)].latestTrigger
    }

    public static func getLatestTriggerOfChannel(
        _ ctx: XMContext, channel: UInt8
    ) -> UInt32 {
        precondition(
            channel >= 1 && channel <= ctx.module.numChannels,
            "channel out of range")
        return ctx.channels[Int(channel - 1)].latestTrigger
    }

    public static func isChannelActive(_ ctx: XMContext, channel: UInt8) -> Bool
    {
        precondition(
            channel >= 1 && channel <= ctx.module.numChannels,
            "channel out of range")
        let ch = ctx.channels[Int(channel - 1)]
        return ch.sample != nil
            && (ch.actualVolume.0 + ch.actualVolume.1) > 0.001
    }

    public static func getInstrumentOfChannel(_ ctx: XMContext, channel: UInt8)
        -> UInt8
    {
        precondition(
            channel >= 1 && channel <= ctx.module.numChannels,
            "channel out of range")
        let ch = ctx.channels[Int(channel - 1)]
        if let inst = ch.instrument { return UInt8(inst + 1) }
        if let smp = ch.sample { return UInt8(smp + 1) }
        return 0
    }

    public static func getFrequencyOfChannel(_ ctx: XMContext, channel: UInt8)
        -> Float
    {
        precondition(
            channel >= 1 && channel <= ctx.module.numChannels,
            "channel out of range")
        let ch = ctx.channels[Int(channel - 1)]
        let rate = Float(ctx.module.rate)
        return Float(ch.step) * rate / Float(XMConstants.sampleMicrosteps)
    }

    public static func getVolumeOfChannel(_ ctx: XMContext, channel: UInt8)
        -> Float
    {
        precondition(
            channel >= 1 && channel <= ctx.module.numChannels,
            "channel out of range")
        let ch = ctx.channels[Int(channel - 1)]
        let x = ch.actualVolume.0
        let y = ch.actualVolume.1
        return sqrtf(x * x + y * y)
    }

    public static func getPanningOfChannel(_ ctx: XMContext, channel: UInt8)
        -> Float
    {
        precondition(
            channel >= 1 && channel <= ctx.module.numChannels,
            "channel out of range")
        let ch = ctx.channels[Int(channel - 1)]
        var x = ch.actualVolume.0
        var y = ch.actualVolume.1
        x *= x
        y *= y
        let sum = x + y
        if sum == 0 { return 0.5 }
        return y / sum
    }

    public static func resetContext(_ ctx: inout XMContext) {
        ctx.channels = Array(
            repeating: XMChannelContext(), count: ctx.channels.count)
        if !ctx.rowLoopCount.isEmpty {
            ctx.rowLoopCount = Array(
                repeating: 0, count: ctx.rowLoopCount.count)
        }
        ctx.remainingSamplesInTick = 0
        ctx.generatedSamples = 0
        ctx.currentTableIndex = 0
        ctx.currentTick = 0
        ctx.currentRow = 0
        ctx.extraRowsDone = 0
        ctx.extraRows = 0
        ctx.globalVolume = XMConstants.maxVolume
        ctx.currentTempo = ctx.module.tempo
        ctx.currentBpm = ctx.module.bpm
        ctx.patternBreak = false
        ctx.positionJump = false
        ctx.jumpRow = 0
        ctx.loopCount = 0
        for i in 0..<ctx.instruments.count {
            ctx.instruments[i].latestTrigger = 0
        }
        for i in 0..<ctx.samples.count { ctx.samples[i].latestTrigger = 0 }
    }

    public static func generateSamples(
        _ ctx: inout XMContext, output: inout [Float], numsamples: Int
    ) {
        LibXMPlayer.generateSamples(
            ctx: &ctx, output: &output, numsamples: numsamples)
    }
    public static func generateSamplesNoninterleaved(
        _ ctx: inout XMContext, left: inout [Float], right: inout [Float],
        numsamples: Int
    ) {
        LibXMPlayer.generateSamplesNoninterleaved(
            ctx: &ctx, left: &left, right: &right, numsamples: numsamples)
    }
    public static func generateSamplesUnmixed(
        _ ctx: inout XMContext, output: inout [Float], numsamples: Int
    ) {
        LibXMPlayer.generateSamplesUnmixed(
            ctx: &ctx, output: &output, numsamples: numsamples)
    }
}
