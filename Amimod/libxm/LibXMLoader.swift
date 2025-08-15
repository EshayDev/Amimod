import Foundation

private let XM_VERBOSE: Bool = true
@inline(__always) private func NOTICE(_ message: @autoclosure () -> String) {
    if XM_VERBOSE { fputs("[LibXM] \(message())\n", stderr) }
}

public enum XMFormat: UInt8 {
    case xm0104 = 0
    case mod = 1
    case modFLT8 = 2
}

public struct XMPrescanData {
    public var contextSize: UInt32 = 0
    public var format: XMFormat = .xm0104
    public var numRows: UInt32 = 0
    public var samplesDataLength: UInt32 = 0
    public var numPatterns: UInt16 = 0
    public var numSamples: UInt16 = 0
    public var potLength: UInt16 = 0
    public var numChannels: UInt8 = 0
    public var numInstruments: UInt8 = 0
}

public enum LibXMLoader {
    public static func prescanModule(_ data: Data) -> XMPrescanData? {
        var p = XMPrescanData()
        if prescanXM0104(data, &p) { return p }
        if prescanMOD(data, &p) { return p }
        NOTICE("input data does not look like a supported module")
        return nil
    }

    public static func sizeForContext(_ p: XMPrescanData) -> UInt32 {
        let patternsSize =
            UInt32(p.numPatterns) * UInt32(MemoryLayout<XMPattern>.stride)
        let patternSlotsSize =
            p.numRows * UInt32(p.numChannels)
            * UInt32(MemoryLayout<XMPatternSlot>.stride)
        let instrumentsSize =
            UInt32(p.numInstruments) * UInt32(MemoryLayout<XMInstrument>.stride)
        let samplesMetaSize =
            UInt32(p.numSamples) * UInt32(MemoryLayout<XMSample>.stride)
        let samplesDataSize =
            p.samplesDataLength * UInt32(MemoryLayout<XMSamplePoint>.stride)
        let channelsSize =
            UInt32(p.numChannels)
            * UInt32(MemoryLayout<XMChannelContext>.stride)
        let rowLoopCount = UInt32(
            XMBuildConfig.loopingType == 2
                ? XMConstants.maxRowsPerPattern * Int(p.potLength) : 0)
        let rowLoopSize = rowLoopCount * UInt32(MemoryLayout<UInt8>.stride)
        let contextOverhead = UInt32(MemoryLayout<XMContext>.stride)
        return patternsSize + patternSlotsSize + instrumentsSize
            + samplesMetaSize + samplesDataSize
            + channelsSize + rowLoopSize + contextOverhead
    }

    public static func createContext(from data: Data) -> XMContext? {
        guard var p = prescanModule(data) else { return nil }
        p.contextSize = sizeForContext(p)
        return createContext(prescan: p, data: data)
    }

    public static func createContext(prescan p: XMPrescanData, data: Data)
        -> XMContext?
    {
        var ctx = XMContext()
        ctx.channels = Array(
            repeating: XMChannelContext(), count: Int(p.numChannels))
        if XMBuildConfig.strings {}
        if p.numInstruments > 0 {
            ctx.instruments = Array(
                repeating: XMInstrument(), count: Int(p.numInstruments))
        }
        ctx.samples = Array(repeating: XMSample(), count: Int(p.numSamples))
        ctx.patterns = Array(repeating: XMPattern(), count: Int(p.numPatterns))
        ctx.samplesData = Array(repeating: 0, count: Int(p.samplesDataLength))
        ctx.patternSlots = Array(
            repeating: XMPatternSlot(),
            count: Int(p.numRows) * Int(p.numChannels))
        if XMBuildConfig.loopingType == 2 {
            ctx.rowLoopCount = Array(
                repeating: 0,
                count: XMConstants.maxRowsPerPattern * Int(p.potLength))
        }

        switch p.format {
        case .xm0104:
            loadXM0104(&ctx, data)
        case .mod:
            loadMOD(&ctx, data, p, isFLT8: false)
        case .modFLT8:
            loadMOD(&ctx, data, p, isFLT8: true)
            fixupMOD_FLT8(&ctx)
        }

        precondition(
            ctx.module.numChannels == p.numChannels, "numChannels mismatch")
        precondition(ctx.module.length == p.potLength, "pot length mismatch")
        precondition(
            ctx.module.numPatterns == p.numPatterns, "numPatterns mismatch")
        precondition(ctx.module.numRows == p.numRows, "numRows mismatch")
        precondition(
            ctx.module.numSamples == p.numSamples, "numSamples mismatch")
        precondition(
            ctx.module.samplesDataLength == p.samplesDataLength,
            "samplesDataLength mismatch")

        fixupContext(&ctx)
        return ctx
    }

    public static func contextSize(_ ctx: XMContext) -> UInt32 {
        var total: UInt32 = 0
        total += UInt32(MemoryLayout<XMContext>.stride)
        total +=
            UInt32(ctx.patterns.count) * UInt32(MemoryLayout<XMPattern>.stride)
        total +=
            UInt32(ctx.patternSlots.count)
            * UInt32(MemoryLayout<XMPatternSlot>.stride)
        total +=
            UInt32(ctx.instruments.count)
            * UInt32(MemoryLayout<XMInstrument>.stride)
        total +=
            UInt32(ctx.samples.count) * UInt32(MemoryLayout<XMSample>.stride)
        total +=
            UInt32(ctx.samplesData.count)
            * UInt32(MemoryLayout<XMSamplePoint>.stride)
        total +=
            UInt32(ctx.channels.count)
            * UInt32(MemoryLayout<XMChannelContext>.stride)
        total +=
            UInt32(ctx.rowLoopCount.count) * UInt32(MemoryLayout<UInt8>.stride)
        return total
    }

    public static func contextToLibxm(_ ctx: XMContext) -> Data {
        var encoder = XMEncoder()
        encoder.encode(ctx)
        return encoder.data
    }

    public static func createContextFromLibxm(_ data: Data) -> XMContext? {
        var decoder = XMDecoder(data: data)
        return decoder.decodeContext()
    }
}

extension LibXMLoader {
    fileprivate static func prescanXM0104(
        _ data: Data, _ out: inout XMPrescanData
    ) -> Bool {
        guard data.count >= 60,
            data.starts(with: Array("Extended Module: ".utf8)),
            data[37] == 0x1A,
            data[58] == 0x04, data[59] == 0x01
        else { return false }

        out.format = .xm0104
        var offset = 60

        let potLength = readU16LE(data, offset + 4)
        let numChannels = readU16LE(data, offset + 8)
        if numChannels > UInt16(XMConstants.maxChannels) {
            NOTICE(
                "module has too many channels (\(numChannels) > \(XMConstants.maxChannels))"
            )
            return false
        }
        out.numChannels = UInt8(numChannels)

        let numPatterns = readU16LE(data, offset + 10)
        if numPatterns > UInt16(XMConstants.maxPatterns) {
            NOTICE(
                "module has too many patterns (\(numPatterns) > \(XMConstants.maxPatterns))"
            )
            return false
        }
        out.numPatterns = numPatterns

        let numInstruments = readU16LE(data, offset + 12)
        if numInstruments > UInt16(XMConstants.maxInstruments) {
            NOTICE(
                "module has too many instruments (\(numInstruments) > \(XMConstants.maxInstruments))"
            )
            return false
        }
        out.numInstruments = UInt8(numInstruments)
        out.numSamples = 0
        out.numRows = 0
        out.samplesDataLength = 0

        let pot = readArray(
            data, offset + 20, XMConstants.patternOrderTableLength)
        offset += Int(readU32LE(data, offset))

        for _ in 0..<out.numPatterns {
            var numRows = readU16LE(data, offset + 5)
            let packedSize = readU16LE(data, offset + 7)
            if packedSize == 0 && numRows != UInt16(EMPTY_PATTERN_NUM_ROWS) {
                NOTICE(
                    "empty pattern has incorrect number of rows, overriding (\(numRows) -> \(EMPTY_PATTERN_NUM_ROWS))"
                )
                numRows = UInt16(EMPTY_PATTERN_NUM_ROWS)
            }
            if numRows > UInt16(XMConstants.maxRowsPerPattern) {
                NOTICE(
                    "pattern has too many rows (\(numRows) > \(XMConstants.maxRowsPerPattern))"
                )
                return false
            }
            out.numRows += UInt32(numRows)
            offset += Int(readU32LE(data, offset)) + Int(packedSize)
        }

        var potLen = potLength
        if potLen > UInt16(XMConstants.patternOrderTableLength) {
            potLen = UInt16(XMConstants.patternOrderTableLength)
        }
        out.potLength = potLen
        var needsEmptyPattern = false
        for i in 0..<potLen {
            if pot[Int(i)] >= out.numPatterns {
                needsEmptyPattern = true
                break
            }
        }
        if needsEmptyPattern {
            if out.numPatterns >= UInt16(XMConstants.maxPatterns) {
                NOTICE(
                    "no room left for blank pattern to replace an invalid pattern"
                )
                return false
            }
            NOTICE(
                "replacing invalid pattern in order table with empty pattern")
            out.numRows += UInt32(EMPTY_PATTERN_NUM_ROWS)
            out.numPatterns &+= 1
        }

        for _ in 0..<out.numInstruments {
            let numSamples = readU16LE(data, offset + 27)
            if numSamples > UInt16(XMConstants.maxSamplesPerInstrument) {
                NOTICE(
                    "instrument has too many samples (\(numSamples) > \(XMConstants.maxSamplesPerInstrument))"
                )
                return false
            }
            var instSamplesBytes: UInt32 = 0
            out.numSamples &+= UInt16(
                XMBuildConfig.disabledFeatures
                    & (1 << XMConstants.featureMultisampleInstruments)
                    == 0 ? numSamples : 1)

            let sampleHeaderSize = readU32LE(data, offset + 29)
            if numSamples > 0 && sampleHeaderSize != 40 {
                NOTICE(
                    "ignoring dodgy sample header size (\(sampleHeaderSize))")
            }
            let insHeaderSize = readU32LE(data, offset)
            offset += Int(insHeaderSize)

            for _j in 0..<numSamples {
                let sampleLengthBytes = readU32LE(data, offset)
                var sampleLength = sampleLengthBytes
                let loopStart = readU32LE(data, offset + 4)
                let loopLength = readU32LE(data, offset + 8)
                let flags = readU8(data, offset + 14)
                sampleLength = trimSampleLength(
                    sampleLength, loopStart, loopLength, flags)
                if (flags & SAMPLE_FLAG_16B) != 0 {
                    if sampleLength % 2 != 0 {
                        NOTICE("sample 16-bit odd length!")
                    }
                    sampleLength /= 2
                }
                var max = XMConstants.maxSampleLength
                if (flags & SAMPLE_FLAG_PING_PONG) != 0 { max /= 2 }
                if sampleLength > max {
                    NOTICE("sample is too big (\(sampleLength) > \(max))")
                    return false
                }
                if XMBuildConfig.disabledFeatures
                    & (1 << XMConstants.featureMultisampleInstruments)
                    == 0 || _j == 0
                {
                    out.samplesDataLength &+= sampleLength
                }
                instSamplesBytes &+= sampleLengthBytes
                offset += SAMPLE_HEADER_SIZE
            }

            offset += Int(instSamplesBytes)
        }

        out.contextSize = sizeForContext(out)
        NOTICE(
            "read \(out.numPatterns) patterns, \(out.numChannels) channels, \(out.numRows) rows, \(out.numInstruments) instruments, \(out.numSamples) samples, \(out.samplesDataLength) sample frames, \(out.potLength) pot length"
        )
        return true
    }

    fileprivate static func prescanMOD(_ data: Data, _ out: inout XMPrescanData)
        -> Bool
    {
        if data.count < 154 + 31 * 30 { return false }
        out.numInstruments = 31
        out.format = .mod
        var load = true
        let chn = data[150 + 31 * 30]
        let chn2 = data[151 + 31 * 30]
        let chn3 = data[153 + 31 * 30]
        let id = data[(150 + 31 * 30)..<(150 + 31 * 30 + 4)]
        if id.elementsEqual(Array("M.K.".utf8))
            || id.elementsEqual(Array("M!K!".utf8))
            || id.elementsEqual(Array("FLT4".utf8))
        {
            out.numChannels = 4
        } else if id.elementsEqual(Array("CD81".utf8))
            || id.elementsEqual(Array("OCTA".utf8))
            || id.elementsEqual(Array("OKTA".utf8))
        {
            out.numChannels = 8
        } else if id.elementsEqual(Array("FLT8".utf8)) {
            out.numChannels = 8
            out.format = .modFLT8
        } else if chn >= 0x31 && chn <= 0x39
            && data[151 + 31 * 30] == 0x43 /* C */
            && data[152 + 31 * 30] == 0x48 /* H */
            && data[153 + 31 * 30] == 0x4E /* N */
        {
            out.numChannels = chn - 0x30
        } else if chn >= 0x31 && chn <= 0x39 && chn2 >= 0x30 && chn2 <= 0x39
            && (data[152 + 31 * 30] == 0x43 /* C */
                || data[152 + 31 * 30] == 0x4E /* N */)
        {
            out.numChannels = (chn - 0x30) * 10 + (chn2 - 0x30)
        } else if chn3 >= 0x31 && chn3 <= 0x39
            && data[150 + 31 * 30] == 0x54 /* T */
            && data[151 + 31 * 30] == 0x44 /* D */
            && data[152 + 31 * 30] == 0x5A /* Z */
        {
            out.numChannels = chn3 - 0x30
        } else {
            load = false
        }
        if !load { return false }
        if !prescanMODDetails(data, &out) { return false }
        return true
    }

    fileprivate static func prescanMODDetails(
        _ data: Data, _ p: inout XMPrescanData
    ) -> Bool {
        p.numSamples = UInt16(p.numInstruments)
        p.samplesDataLength = 0
        for i in 0..<Int(p.numSamples) {
            let base = 42 + 30 * i
            let length = UInt32(readU16BE(data, base) * 2)
            let loopStart = UInt32(readU16BE(data, base + 4) * 2)
            let loopLength = UInt32(readU16BE(data, base + 6) * 2)
            var trimmed = length
            if loopLength > 2 {
                trimmed = trimSampleLength(
                    length, loopStart, loopLength, SAMPLE_FLAG_FORWARD)
            }
            p.samplesDataLength &+= trimmed
        }
        p.potLength = UInt16(readU8(data, 950))
        var numPatterns: UInt8 = 0
        for i in 0..<128 {
            let pv = readU8(data, 952 + i)
            if pv >= numPatterns { numPatterns = pv &+ 1 }
        }
        if p.format == .modFLT8 {
            var n = Int(numPatterns) + 1
            n /= 2
            numPatterns = UInt8(n)
        }
        p.numPatterns = UInt16(numPatterns)
        p.numRows = UInt32(64 * Int(numPatterns))

        let minSize = 1084 + Int(p.samplesDataLength)
        if data.count < minSize {
            NOTICE(
                "mod file too small, expected more bytes (\(data.count) < \(minSize))"
            )
            return false
        }
        p.contextSize = sizeForContext(p)
        return true
    }
}

extension LibXMLoader {
    fileprivate static let EMPTY_PATTERN_NUM_ROWS = 64
    fileprivate static let SAMPLE_HEADER_SIZE = 40
    fileprivate static let SAMPLE_FLAG_16B: UInt8 = 0b0001_0000
    fileprivate static let SAMPLE_FLAG_PING_PONG: UInt8 = 0b0000_0010
    fileprivate static let SAMPLE_FLAG_FORWARD: UInt8 = 0b0000_0001
    fileprivate static let ENVELOPE_FLAG_ENABLED: UInt8 = 0b0000_0001
    fileprivate static let ENVELOPE_FLAG_SUSTAIN: UInt8 = 0b0000_0010
    fileprivate static let ENVELOPE_FLAG_LOOP: UInt8 = 0b0000_0100

    @inline(__always)
    fileprivate static func trimSampleLength(
        _ length: UInt32, _ loopStart: UInt32, _ loopLength: UInt32,
        _ flags: UInt8
    ) -> UInt32 {
        if (flags & (SAMPLE_FLAG_PING_PONG | SAMPLE_FLAG_FORWARD)) != 0 {
            let ls = loopStart > length ? length : loopStart
            let ll = (loopStart + loopLength > length) ? 0 : loopLength
            return ls + ll
        } else {
            return length
        }
    }

    @inline(__always)
    fileprivate static func samplePointFromS8(_ v: Int8) -> XMSamplePoint {
        return XMSamplePoint(Int32(v) * 256)
    }
    @inline(__always)
    fileprivate static func samplePointFromS16(_ v: Int16) -> XMSamplePoint {
        return XMSamplePoint(v)
    }

    fileprivate static func loadXM0104(_ ctx: inout XMContext, _ data: Data) {
        var offset = loadXM0104ModuleHeader(&ctx, data)
        for i in 0..<ctx.module.numPatterns {
            offset = loadXM0104Pattern(&ctx, Int(i), data, offset)
        }
        var hasInvalid = false
        for i in 0..<ctx.module.length {
            if ctx.module.patternTable[Int(i)] >= ctx.module.numPatterns {
                hasInvalid = true
                break
            }
        }
        if hasInvalid {
            for i in 0..<ctx.module.length {
                if ctx.module.patternTable[Int(i)] < ctx.module.numPatterns {
                    continue
                }
                ctx.module.patternTable[Int(i)] = UInt8(
                    clamping: ctx.module.numPatterns)
            }
            ctx.patterns[Int(ctx.module.numPatterns)].numRows = UInt16(
                EMPTY_PATTERN_NUM_ROWS)
            ctx.patterns[Int(ctx.module.numPatterns)].rowsIndex = UInt16(
                ctx.module.numRows)
            ctx.module.numPatterns &+= 1
            ctx.module.numRows &+= UInt32(EMPTY_PATTERN_NUM_ROWS)
        }
        let numInstruments = Int(ctx.module.numInstruments)
        var curOffset = offset
        for i in 0..<numInstruments {
            curOffset = loadXM0104Instrument(&ctx, i, data, curOffset)
        }
    }

    fileprivate static func loadXM0104ModuleHeader(
        _ ctx: inout XMContext, _ data: Data
    ) -> Int {
        var offset = 0
        if XMBuildConfig.strings {
            ctx.module.name = readString(data, 17, 20)
            ctx.module.trackerName = readString(data, 38, 20)
        }
        ctx.module.isMOD = false
        offset += 60
        let headerSize = Int(readU32LE(data, offset))
        ctx.module.length = readU16LE(data, offset + 4)
        if ctx.module.length > UInt16(XMConstants.patternOrderTableLength) {
            NOTICE(
                "clamping module pot length \(ctx.module.length) to \(XMConstants.patternOrderTableLength)"
            )
            ctx.module.length = UInt16(XMConstants.patternOrderTableLength)
        }
        var restartPosition = readU16LE(data, offset + 6)
        if restartPosition >= ctx.module.length { restartPosition = 0 }
        ctx.module.restartPosition = UInt8(restartPosition)

        ctx.module.numChannels = UInt8(readU8(data, offset + 8))
        ctx.module.numPatterns = readU16LE(data, offset + 10)
        ctx.module.numInstruments = readU8(data, offset + 12)

        let flags = readU16LE(data, offset + 14)
        if (XMBuildConfig.disabledFeatures
            & ((1 << XMConstants.featureLinearFrequencies)
                | (1 << XMConstants.featureAmigaFrequencies)))
            == 0
        {
            ctx.module.amigaFrequencies = (flags & 1) == 0 ? true : false
        } else if XMBuildConfig.disabledFeatures
            & (1 << XMConstants.featureAmigaFrequencies) != 0
        {
            ctx.module.amigaFrequencies = false
        } else {
            ctx.module.amigaFrequencies = true
        }
        if (flags & 0b1111_1110) != 0 {
            NOTICE("unknown flags set in module header (\(flags))")
        }

        var tempo = readU16LE(data, offset + 16)
        if tempo >= UInt16(XMConstants.minBpm) {
            NOTICE("clamping tempo (\(tempo) -> \(XMConstants.minBpm-1))")
            tempo = UInt16(XMConstants.minBpm - 1)
        }
        ctx.module.tempo = UInt8(tempo)
        var bpm = readU16LE(data, offset + 18)
        if bpm > UInt16(XMConstants.maxBpm) {
            NOTICE("clamping bpm (\(bpm) -> \(XMConstants.maxBpm))")
            bpm = UInt16(XMConstants.maxBpm)
        }
        ctx.module.bpm = UInt8(bpm)

        ctx.module.patternTable = readArray(
            data, offset + 20, XMConstants.patternOrderTableLength)
        offset += headerSize
        return offset
    }

    fileprivate static func loadXM0104Pattern(
        _ ctx: inout XMContext, _ patIndex: Int, _ data: Data,
        _ headerOffset: Int
    ) -> Int {
        var offset = headerOffset
        let packedSize = Int(readU16LE(data, offset + 7))
        var numRows = readU16LE(data, offset + 5)
        precondition(numRows <= UInt16(XMConstants.maxRowsPerPattern))
        ctx.patterns[patIndex].rowsIndex = UInt16(ctx.module.numRows)
        ctx.patterns[patIndex].numRows = numRows
        ctx.module.numRows &+= UInt32(numRows)

        let packingType = readU8(data, offset + 4)
        if packingType != 0 {
            NOTICE("unknown packing type \(packingType) in pattern")
        }
        offset += Int(readU32LE(data, offset))
        if packedSize == 0 {
            ctx.module.numRows -= UInt32(numRows)
            numRows = UInt16(EMPTY_PATTERN_NUM_ROWS)
            ctx.patterns[patIndex].numRows = numRows
            ctx.module.numRows &+= UInt32(numRows)
            return offset
        }

        let end = offset + packedSize
        let slotsPerRow = Int(ctx.module.numChannels)
        var j = 0
        var k = 0
        let slotsBase = Int(ctx.patterns[patIndex].rowsIndex) * slotsPerRow
        while offset + j < end {
            let a = readU8Bounded(data, offset + j, end)
            var slot = XMPatternSlot()
            if (a & 0x80) != 0 {
                j += 1
                if (a & 0x01) != 0 {
                    slot.note = readU8Bounded(data, offset + j, end)
                    j += 1
                }
                if (a & 0x02) != 0 {
                    slot.instrument = readU8Bounded(data, offset + j, end)
                    j += 1
                }
                if (a & 0x04) != 0 {
                    slot.volumeColumn = readU8Bounded(data, offset + j, end)
                    j += 1
                }
                if (a & 0x08) != 0 {
                    slot.effectType = readU8Bounded(data, offset + j, end)
                    j += 1
                }
                if (a & 0x10) != 0 {
                    slot.effectParam = readU8Bounded(data, offset + j, end)
                    j += 1
                }
            } else {
                slot.note = a
                slot.instrument = readU8Bounded(data, offset + j + 1, end)
                slot.volumeColumn = readU8Bounded(data, offset + j + 2, end)
                slot.effectType = readU8Bounded(data, offset + j + 3, end)
                slot.effectParam = readU8Bounded(data, offset + j + 4, end)
                j += 5
            }
            if slotsBase + k < ctx.patternSlots.count {
                ctx.patternSlots[slotsBase + k] = slot
            }
            k += 1
        }
        if k != Int(numRows) * Int(ctx.module.numChannels) {
            NOTICE(
                "incomplete packed pattern data for pattern \(patIndex), expected \(Int(numRows) * Int(ctx.module.numChannels)) slots, got \(k)"
            )
        }
        return end
    }

    fileprivate static func loadXM0104Instrument(
        _ ctx: inout XMContext, _ instIndex: Int, _ data: Data,
        _ instOffset: Int
    ) -> Int {
        var offset = instOffset
        if XMBuildConfig.strings {
            let name = readString(data, offset + 4, 22)
            if instIndex < ctx.instruments.count {
                ctx.instruments[instIndex].name = name
            }
        }
        let insHeaderSize = Int(readU32LE(data, offset))
        let bound = offset + insHeaderSize
        let type = readU8Bounded(data, offset + 26, bound)
        if type != 0 { NOTICE("ignoring non-zero instrument type \(type)") }
        let numSamples = Int(readU8Bounded(data, offset + 27, bound))
        if numSamples == 0 {
            if XMBuildConfig.disabledFeatures
                & (1 << XMConstants.featureMultisampleInstruments)
                != 0
            {
                ctx.module.numSamples &+= 1
            }
            offset += insHeaderSize
            return offset
        }

        if instIndex < ctx.instruments.count {
            if XMBuildConfig.disabledFeatures
                & (1 << XMConstants.featureMultisampleInstruments)
                == 0
            {
                ctx.instruments[instIndex].sampleOfNotes = readArray(
                    data, offset + 33, Int(XMConstants.maxNote))
            }
            if XMBuildConfig.disabledFeatures
                & (1 << XMConstants.featureVolumeEnvelopes) == 0
            {
                var env = XMEnvelope()
                loadXM0104EnvelopePoints(
                    &env,
                    readSlice(
                        data, offset + 129, XMConstants.maxEnvelopePoints * 4))
                env.numPoints = readU8Bounded(data, offset + 225, bound)
                env.sustainPoint = readU8Bounded(data, offset + 227, bound)
                env.loopStartPoint = readU8Bounded(data, offset + 228, bound)
                env.loopEndPoint = readU8Bounded(data, offset + 229, bound)
                let flags = readU8Bounded(data, offset + 233, bound)
                checkAndFixEnvelope(&env, flags)
                ctx.instruments[instIndex].volumeEnvelope = env
            }
            if XMBuildConfig.panningType == 8
                && XMBuildConfig.disabledFeatures
                    & (1 << XMConstants.featurePanningEnvelopes) == 0
            {
                var env = XMEnvelope()
                loadXM0104EnvelopePoints(
                    &env,
                    readSlice(
                        data, offset + 177, XMConstants.maxEnvelopePoints * 4))
                env.numPoints = readU8Bounded(data, offset + 226, bound)
                env.sustainPoint = readU8Bounded(data, offset + 230, bound)
                env.loopStartPoint = readU8Bounded(data, offset + 231, bound)
                env.loopEndPoint = readU8Bounded(data, offset + 232, bound)
                let flags = readU8Bounded(data, offset + 234, bound)
                checkAndFixEnvelope(&env, flags)
                ctx.instruments[instIndex].panningEnvelope = env
            }
            if XMBuildConfig.disabledFeatures
                & (1 << XMConstants.featureAutovibrato) == 0
            {
                var vt = readU8Bounded(data, offset + 235, bound)
                let lut: [UInt8] = [0b00, 0b11, 0b11, 0b00]
                vt ^= lut[Int(vt & 0b11)]
                if (vt & 1) != 0 { vt ^= 0b10 }
                ctx.instruments[instIndex].vibratoType = vt
                ctx.instruments[instIndex].vibratoSweep = readU8Bounded(
                    data, offset + 236, bound)
                ctx.instruments[instIndex].vibratoDepth = readU8Bounded(
                    data, offset + 237, bound)
                ctx.instruments[instIndex].vibratoRate = readU8Bounded(
                    data, offset + 238, bound)
            }
            if XMBuildConfig.disabledFeatures
                & (1 << XMConstants.featureFadeoutVolume) == 0
            {
                ctx.instruments[instIndex].volumeFadeout = readU16LEBounded(
                    data, offset + 239, bound)
            }
        }
        offset += insHeaderSize

        let samplesIndex = Int(ctx.module.numSamples)
        var extraSamplesSize: UInt32 = 0
        if XMBuildConfig.disabledFeatures
            & (1 << XMConstants.featureMultisampleInstruments) == 0
        {
            ctx.instruments[instIndex].samplesIndex = UInt16(samplesIndex)
            ctx.instruments[instIndex].numSamples = UInt8(numSamples)
            ctx.module.numSamples &+= UInt16(numSamples)
        } else {
            ctx.module.numSamples &+= 1
        }

        var tempIs16: [Bool] = Array(repeating: false, count: numSamples)
        for i in 0..<numSamples {
            if XMBuildConfig.disabledFeatures
                & (1 << XMConstants.featureMultisampleInstruments)
                == 0 || i == 0
            {
                var is16 = false
                offset = Int(
                    loadXM0104SampleHeader(
                        &ctx.samples[samplesIndex + i], &is16, data: data,
                        offset))
                tempIs16[i] = is16
                if is16 {
                }
            } else {
                extraSamplesSize &+= readU32LE(data, offset)
                offset += SAMPLE_HEADER_SIZE
            }
        }

        for i in 0..<numSamples {
            var s = ctx.samples[samplesIndex + i]
            let sampleStart = Int(ctx.module.samplesDataLength)
            if tempIs16[i] {
                loadXM0104_16bSampleData(
                    length: s.length, into: &ctx.samplesData,
                    outIndex: sampleStart, data: data,
                    offset: offset)
                offset += Int(s.index * 2)
            } else {
                loadXM0104_8bSampleData(
                    length: s.length, into: &ctx.samplesData,
                    outIndex: sampleStart, data: data,
                    offset: offset)
                offset += Int(s.index)
            }
            s.index = ctx.module.samplesDataLength
            ctx.module.samplesDataLength &+= s.length
            ctx.samples[samplesIndex + i] = s
            if XMBuildConfig.disabledFeatures
                & (1 << XMConstants.featureMultisampleInstruments)
                != 0
            {
                offset += Int(extraSamplesSize)
                break
            }
        }
        return offset
    }

    fileprivate static func loadXM0104EnvelopePoints(
        _ env: inout XMEnvelope, _ slice: Data
    ) {
        let local = slice
        let bound = local.count
        for i in 0..<XMConstants.maxEnvelopePoints {
            let f = readU16LEBounded(local, 4 * i + 0, bound)
            var val = readU16LEBounded(local, 4 * i + 2, bound)
            if val > UInt16(XMConstants.maxEnvelopeValue) {
                NOTICE(
                    "clamped invalid envelope pt value (\(val) -> \(XMConstants.maxEnvelopeValue))"
                )
                val = UInt16(XMConstants.maxEnvelopeValue)
            }
            env.points[i] = XMEnvelopePoint(frame: f, value: UInt8(val))
        }
    }

    fileprivate static func checkAndFixEnvelope(
        _ env: inout XMEnvelope, _ flags: UInt8
    ) {
        if env.numPoints > UInt8(XMConstants.maxEnvelopePoints) {
            NOTICE(
                "clamped invalid envelope num_points (\(env.numPoints) -> \(XMConstants.maxEnvelopePoints))"
            )
            env.numPoints = UInt8(XMConstants.maxEnvelopePoints)
        }
        if (flags & ENVELOPE_FLAG_ENABLED) == 0 {
            killEnvelope(&env)
            return
        }
        if env.numPoints < 2 {
            NOTICE(
                "discarding invalid envelope data (needs 2 points at least, got \(env.numPoints))"
            )
            killEnvelope(&env)
            return
        }
        for i in 1..<env.numPoints {
            if env.points[Int(i - 1)].frame < env.points[Int(i)].frame {
                continue
            }
            NOTICE(
                "discarding invalid envelope data (point \(i-1) frame \(env.points[Int(i-1)].frame) -> point \(i) frame \(env.points[Int(i)].frame))"
            )
            killEnvelope(&env)
            return
        }
        if env.loopStartPoint >= env.numPoints {
            NOTICE(
                "clearing invalid envelope loop (start point \(env.loopStartPoint) > \(env.numPoints - 1))"
            )
            env.loopStartPoint = 0
            env.loopEndPoint = 0
        }
        if env.loopEndPoint >= env.numPoints
            || env.loopEndPoint < env.loopStartPoint
        {
            NOTICE(
                "clearing invalid envelope loop (end point \(env.loopEndPoint))"
            )
            env.loopStartPoint = 0
            env.loopEndPoint = 0
        }
        if env.loopStartPoint == env.loopEndPoint
            || (flags & ENVELOPE_FLAG_LOOP) == 0
        {
            env.loopStartPoint = 0
            env.loopEndPoint = 0
        }
        if env.sustainPoint >= env.numPoints {
            NOTICE(
                "clearing invalid envelope sustain point (\(env.sustainPoint) > \(env.numPoints - 1))"
            )
            env.sustainPoint = 128
        }
        if (flags & ENVELOPE_FLAG_SUSTAIN) == 0 {
            env.sustainPoint = 128
        }
    }

    fileprivate static func killEnvelope(_ env: inout XMEnvelope) {
        env = XMEnvelope()
    }

    fileprivate static func loadXM0104SampleHeader(
        _ sample: inout XMSample, _ is16: inout Bool, data: Data, _ offset: Int
    ) -> Int {
        var off = offset
        let length = readU32LE(data, off)
        sample.length = length
        sample.index = length
        let loopStart = readU32LE(data, off + 4)
        sample.loopLength = readU32LE(data, off + 8)
        let flags = readU8(data, off + 14)
        var ls = loopStart
        if ls > sample.length {
            NOTICE("fixing invalid sample loop start")
            ls = sample.length
        }
        if ls + sample.loopLength > sample.length {
            NOTICE("fixing invalid sample loop length")
            sample.loopLength = 0
        }
        sample.length = trimSampleLength(
            sample.length, ls, sample.loopLength, flags)
        var volume = readU8(data, off + 12)
        if volume > XMConstants.maxVolume {
            NOTICE(
                "clamping invalid sample volume (\(volume) > \(XMConstants.maxVolume))"
            )
            volume = XMConstants.maxVolume
        }
        sample.volume = volume
        sample.finetune = Int8(bitPattern: readU8(data, off + 13))
        sample.finetune = Int8(
            ((Int(sample.finetune) - Int(Int8.min)) / 8) - 16)
        sample.pingPong = (flags & SAMPLE_FLAG_PING_PONG) != 0
        if (flags & (SAMPLE_FLAG_FORWARD | SAMPLE_FLAG_PING_PONG)) == 0 {
            sample.loopLength = 0
        }
        if (flags
            & ~(SAMPLE_FLAG_PING_PONG | SAMPLE_FLAG_FORWARD | SAMPLE_FLAG_16B))
            != 0
        {
            NOTICE("ignoring unknown flags (\(flags)) in sample")
        }
        sample.panning = UInt16(readU8(data, off + 15))
        sample.relativeNote = Int8(bitPattern: readU8(data, off + 16))
        if XMBuildConfig.strings {
            sample.name = readString(data, off + 18, 22)
        }
        is16 = (flags & SAMPLE_FLAG_16B) != 0
        if is16 {
            sample.loopLength >>= 1
            sample.length >>= 1
            sample.index >>= 1
        }
        off += SAMPLE_HEADER_SIZE
        return off
    }

    fileprivate static func loadXM0104_8bSampleData(
        length: UInt32, into out: inout [XMSamplePoint], outIndex: Int,
        data: Data, offset: Int
    ) {
        var v: Int8 = 0
        for k in 0..<Int(length) {
            let s = Int8(bitPattern: readU8(data, offset + k))
            v &+= s
            out[outIndex + k] = samplePointFromS8(v)
        }
    }

    fileprivate static func loadXM0104_16bSampleData(
        length: UInt32, into out: inout [XMSamplePoint], outIndex: Int,
        data: Data, offset: Int
    ) {
        var v: Int16 = 0
        for k in 0..<Int(length) {
            let s = Int16(bitPattern: readU16LE(data, offset + (k << 1)))
            v &+= s
            out[outIndex + k] = samplePointFromS16(v)
        }
    }

    fileprivate static func loadMOD(
        _ ctx: inout XMContext, _ data: Data, _ p: XMPrescanData, isFLT8: Bool
    ) {
        if XMBuildConfig.strings {
            ctx.module.name = readString(data, 0, 20)
        }
        ctx.module.isMOD = true
        ctx.module.amigaFrequencies = true
        ctx.module.tempo = 6
        ctx.module.bpm = 125
        ctx.module.numChannels = p.numChannels
        ctx.module.numPatterns = p.numPatterns
        ctx.module.numRows = p.numRows
        ctx.module.numSamples = p.numSamples
        ctx.module.numInstruments = p.numInstruments

        var offset = 20
        for i in 0..<Int(ctx.module.numSamples) {
            var smp = ctx.samples[i]
            if XMBuildConfig.strings {
                ctx.instruments[i].name = readString(data, offset, 22)
            }
            let finetune = readU8(data, offset + 24)
            smp.finetune = Int8(
                (finetune < 16 ? (finetune < 8 ? finetune : finetune - 16) : 8)
                    * 2)
            var vol = readU8(data, offset + 25)
            if vol > XMConstants.maxVolume {
                NOTICE(
                    "clamping volume of sample \(i+1) (\(vol) -> \(XMConstants.maxVolume))"
                )
                vol = XMConstants.maxVolume
            }
            smp.volume = vol
            smp.panning = XMConstants.maxPanning / 2
            smp.length = UInt32(readU16BE(data, offset + 22) * 2)
            smp.index = smp.length
            let loopStart = UInt32(readU16BE(data, offset + 26) * 2)
            let loopLength = UInt32(readU16BE(data, offset + 28) * 2)
            if loopLength > 2 {
                smp.length = trimSampleLength(
                    smp.length, loopStart, loopLength, SAMPLE_FLAG_FORWARD)
                smp.loopLength = loopLength
            }
            ctx.samples[i] = smp
            offset += 30
        }

        for i in 0..<Int(ctx.module.numSamples) {
            ctx.instruments[i].samplesIndex = UInt16(i)
            ctx.instruments[i].numSamples = 1
            ctx.instruments[i].sampleOfNotes = Array(
                repeating: 0, count: Int(XMConstants.maxNote))
        }
        ctx.module.length = UInt16(readU8(data, offset))
        if ctx.module.length > 128 {
            NOTICE("clamping module pot length \(ctx.module.length) to 128")
            ctx.module.length = 128
        }
        ctx.module.restartPosition = readU8(data, offset + 1)
        if ctx.module.restartPosition >= ctx.module.length {
            ctx.module.restartPosition = 0
        }
        ctx.module.patternTable = readArray(data, offset + 2, 128)
        offset += 134

        var hasPanningEffects = false
        for pi in 0..<Int(ctx.module.numPatterns) {
            ctx.patterns[pi].numRows = 64
            ctx.patterns[pi].rowsIndex = UInt16(64 * pi)
            for j in 0..<(Int(ctx.module.numChannels) * 64) {
                let x = readU32BE(data, offset)
                offset += 4
                var slot = XMPatternSlot()
                slot.instrument = UInt8(
                    ((x & 0xF000_0000) >> 24) | ((x >> 12) & 0x0F))
                slot.effectType = UInt8((x >> 8) & 0x0F)
                slot.effectParam = UInt8(x & 0xFF)
                if slot.effectType == 0x8
                    || (slot.effectType == 0xE
                        && (slot.effectParam >> 4) == 0x8)
                {
                    hasPanningEffects = true
                }
                let period = UInt16((x >> 16) & 0x0FFF)
                if period > 0 {
                    var note: UInt8 = 73
                    var pval = period
                    while pval >= 112 {
                        pval &+= 1
                        pval = pval / 2
                        note &-= 12
                    }
                    let table: [UInt8] = [
                        106, 100, 94, 89, 84, 79, 75, 70, 66, 63, 59,
                    ]
                    var idx = 0
                    while idx < 11 && pval < table[idx] {
                        note &+= 1
                        idx &+= 1
                    }
                    slot.note = note
                }
                let base =
                    Int(ctx.patterns[pi].rowsIndex)
                    * Int(ctx.module.numChannels) + j
                ctx.patternSlots[base] = slot
            }
        }

        for i in 0..<Int(ctx.module.numSamples) {
            let outIndex = Int(ctx.module.samplesDataLength)
            let len = Int(ctx.samples[i].length)
            for k in 0..<len {
                let v = Int8(bitPattern: readU8(data, offset + k))
                ctx.samplesData[outIndex + k] = samplePointFromS8(v)
            }
            offset += Int(ctx.samples[i].index)
            ctx.samples[i].index = ctx.module.samplesDataLength
            ctx.module.samplesDataLength &+= ctx.samples[i].length
        }

        var slotIndex = 0
        for _ in 0..<Int(ctx.module.numRows) {
            for ch in 0..<Int(ctx.module.numChannels) {
                if !hasPanningEffects
                    && ctx.patternSlots[slotIndex].instrument != 0
                {
                    let hard = (((ch >> 1) ^ ch) & 1) != 0
                    ctx.patternSlots[slotIndex].volumeColumn =
                        hard ? 0xCF : 0xC1
                }
                if ctx.patternSlots[slotIndex].instrument != 0
                    && ctx.patternSlots[slotIndex].note == 0
                {
                    ctx.patternSlots[slotIndex].note = XMConstants.noteSwitch
                }
                if ctx.patternSlots[slotIndex].effectParam == 0 {
                    if [0x1, 0x2, 0xA].contains(
                        Int(ctx.patternSlots[slotIndex].effectType))
                    {
                        ctx.patternSlots[slotIndex].effectType = 0
                    }
                    if [0x5, 0x6].contains(
                        Int(ctx.patternSlots[slotIndex].effectType))
                    {
                        ctx.patternSlots[slotIndex].effectType &-= 2
                    }
                }
                if ctx.patternSlots[slotIndex].effectType == 0xE
                    && (ctx.patternSlots[slotIndex].effectParam >> 4) == 0x5
                {
                    ctx.patternSlots[slotIndex].effectParam ^= 0b0000_1000
                }
                slotIndex &+= 1
            }
        }
    }

    fileprivate static func fixupMOD_FLT8(_ ctx: inout XMContext) {
        for i in 0..<Int(ctx.module.numPatterns) {
            let pat = ctx.patterns[i]
            var scratch = Array(repeating: XMPatternSlot(), count: 8 * 64)
            for row in 0..<64 {
                let srcBase =
                    Int(pat.rowsIndex) * Int(ctx.module.numChannels) + row * 4
                let dstBase = 8 * row
                for c in 0..<4 {
                    scratch[dstBase + c] = ctx.patternSlots[srcBase + c]
                }
                for c in 0..<4 {
                    scratch[dstBase + 4 + c] =
                        ctx.patternSlots[srcBase + 32 * 8 + c]
                }
            }
            let destBase = Int(pat.rowsIndex) * Int(ctx.module.numChannels)
            for j in 0..<scratch.count {
                ctx.patternSlots[destBase + j] = scratch[j]
            }
        }
    }
}

extension LibXMLoader {
    fileprivate static func fixupContext(_ ctx: inout XMContext) {
        ctx.globalVolume = XMConstants.maxVolume
        ctx.currentTempo = ctx.module.tempo
        ctx.currentBpm = ctx.module.bpm
        ctx.module.rate = 48_000

        let totalSlots = Int(ctx.module.numRows) * Int(ctx.module.numChannels)
        for i in 0..<totalSlots {
            var slot = ctx.patternSlots[i]
            if slot.note == 97 { slot.note = XMConstants.noteKeyOff }
            if slot.effectType == 33 {
                switch slot.effectParam >> 4 {
                case 1:
                    slot.effectType = UInt8(
                        XMEffect.extraFinePortamentoUp.rawValue)
                    slot.effectParam &= 0x0F
                case 2:
                    slot.effectType = UInt8(
                        XMEffect.extraFinePortamentoDown.rawValue)
                    slot.effectParam &= 0x0F
                default:
                    slot.effectType = 0
                    slot.effectParam = 0
                }
            }
            if slot.effectType == 0xE {
                slot.effectType = UInt8(32 | (slot.effectParam >> 4))
                slot.effectParam &= 0x0F
            }
            if slot.effectType == UInt8(XMEffect.setBPM.rawValue)
                && slot.effectParam < XMConstants.minBpm
            {
                slot.effectType = UInt8(XMEffect.setTempo.rawValue)
            }
            if slot.effectType == UInt8(XMEffect.jumpToOrder.rawValue)
                && slot.effectParam >= ctx.module.length
            {
                slot.effectParam = 0
            }
            if (slot.effectType == UInt8(XMEffect.setVolume.rawValue)
                || slot.effectType == UInt8(XMEffect.setGlobalVolume.rawValue))
                && slot.effectParam > XMConstants.maxVolume
            {
                slot.effectParam = XMConstants.maxVolume
            }
            if slot.effectType == UInt8(XMEffect.setVibratoControl.rawValue)
                || slot.effectType == UInt8(XMEffect.setTremoloControl.rawValue)
            {
                slot.effectParam &=
                    ((slot.effectParam & 0b11) == 0b11)
                    ? 0b1111_0110 : 0b1111_0111
            }
            if slot.effectType == 40 {
                slot.effectType = UInt8(XMEffect.setPanning.rawValue)
                slot.effectParam = slot.effectParam &* 0x10
            }
            if slot.effectType == UInt8(XMEffect.cutNote.rawValue)
                && slot.effectParam == 0
            {
                slot.effectType = UInt8(XMEffect.setVolume.rawValue)
            }
            if slot.effectType == UInt8(XMEffect.delayNote.rawValue)
                && slot.effectParam == 0
            {
                slot.effectType = 0
            }
            if slot.effectType == UInt8(XMEffect.retriggerNote.rawValue)
                && slot.effectParam == 0
            {
                if slot.note != 0 { /* redundant */
                } else {
                    slot.note = XMConstants.noteRetrigger
                }
                slot.effectType = 0
            }
            if slot.volumeColumn == 0xA0 { slot.volumeColumn = 0 }
            ctx.patternSlots[i] = slot
        }
    }
}

private struct XMEncoder {
    var data = Data()
    mutating func append<T>(_ value: T) {
        var v = value
        withUnsafeBytes(of: &v) { raw in
            data.append(contentsOf: raw)
        }
    }
    mutating func appendArray<T>(_ array: [T]) {
        let count = UInt32(array.count)
        append(count)
        array.withUnsafeBytes { raw in
            data.append(contentsOf: raw)
        }
    }
    mutating func appendString(_ s: String) {
        let utf8 = s.data(using: .utf8) ?? Data()
        appendArray(Array(utf8)) as Void
    }
    mutating func encode(_ ctx: XMContext) {
        append(UInt32(1))
        append(ctx.module.samplesDataLength)
        append(ctx.module.numRows)
        append(ctx.module.length)
        append(ctx.module.numPatterns)
        append(ctx.module.numSamples)
        append(ctx.module.rate)
        append(ctx.module.numChannels)
        append(ctx.module.numInstruments)
        appendArray(ctx.module.patternTable)
        append(ctx.module.restartPosition)
        append(ctx.module.maxLoopCount)
        append(ctx.module.tempo)
        append(ctx.module.bpm)
        append(ctx.module.amigaFrequencies)
        appendString(ctx.module.name)
        appendString(ctx.module.trackerName)
        appendArray(ctx.patterns)
        appendArray(ctx.patternSlots)
        appendArray(ctx.instruments)
        appendArray(ctx.samples)
        appendArray(ctx.samplesData)
        appendArray(ctx.channels)
        appendArray(ctx.rowLoopCount)
        append(ctx.remainingSamplesInTick)
        append(ctx.generatedSamples)
        append(ctx.currentTableIndex)
        append(ctx.currentTick)
        append(ctx.currentRow)
        append(ctx.extraRowsDone)
        append(ctx.extraRows)
        append(ctx.globalVolume)
        append(ctx.currentTempo)
        append(ctx.currentBpm)
        append(ctx.patternBreak)
        append(ctx.positionJump)
        append(ctx.jumpDest)
        append(ctx.jumpRow)
        append(ctx.loopCount)
    }
}

private struct XMDecoder {
    let data: Data
    var offset: Int = 0
    mutating func read<T>(_ type: T.Type) -> T {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.count else { fatalError("decode overflow") }
        let v = data.subdata(in: offset..<(offset + size)).withUnsafeBytes {
            $0.load(as: T.self)
        }
        offset += size
        return v
    }
    mutating func readArray<T>(_ type: T.Type) -> [T] {
        let count: UInt32 = read(UInt32.self)
        let size = Int(count) * MemoryLayout<T>.size
        guard offset + size <= data.count else {
            fatalError("decode overflow array")
        }
        let arr: [T] = data.subdata(in: offset..<(offset + size))
            .withUnsafeBytes { buf in
                Array(buf.bindMemory(to: T.self))
            }
        offset += size
        return arr
    }
    mutating func readString() -> String {
        let raw: [UInt8] = readArray(UInt8.self)
        return String(bytes: raw, encoding: .utf8) ?? ""
    }
    mutating func decodeContext() -> XMContext? {
        var ctx = XMContext()
        let version: UInt32 = read(UInt32.self)
        guard version == 1 else { return nil }
        ctx.module.samplesDataLength = read(UInt32.self)
        ctx.module.numRows = read(UInt32.self)
        ctx.module.length = read(UInt16.self)
        ctx.module.numPatterns = read(UInt16.self)
        ctx.module.numSamples = read(UInt16.self)
        ctx.module.rate = read(UInt16.self)
        ctx.module.numChannels = read(UInt8.self)
        ctx.module.numInstruments = read(UInt8.self)
        ctx.module.patternTable = readArray(UInt8.self)
        ctx.module.restartPosition = read(UInt8.self)
        ctx.module.maxLoopCount = read(UInt8.self)
        ctx.module.tempo = read(UInt8.self)
        ctx.module.bpm = read(UInt8.self)
        ctx.module.amigaFrequencies = read(Bool.self)
        ctx.module.name = readString()
        ctx.module.trackerName = readString()
        ctx.patterns = readArray(XMPattern.self)
        ctx.patternSlots = readArray(XMPatternSlot.self)
        ctx.instruments = readArray(XMInstrument.self)
        ctx.samples = readArray(XMSample.self)
        ctx.samplesData = readArray(XMSamplePoint.self)
        ctx.channels = readArray(XMChannelContext.self)
        ctx.rowLoopCount = readArray(UInt8.self)
        ctx.remainingSamplesInTick = read(UInt32.self)
        ctx.generatedSamples = read(UInt32.self)
        ctx.currentTableIndex = read(UInt16.self)
        ctx.currentTick = read(UInt8.self)
        ctx.currentRow = read(UInt8.self)
        ctx.extraRowsDone = read(UInt8.self)
        ctx.extraRows = read(UInt8.self)
        ctx.globalVolume = read(UInt8.self)
        ctx.currentTempo = read(UInt8.self)
        ctx.currentBpm = read(UInt8.self)
        ctx.patternBreak = read(Bool.self)
        ctx.positionJump = read(Bool.self)
        ctx.jumpDest = read(UInt8.self)
        ctx.jumpRow = read(UInt8.self)
        ctx.loopCount = read(UInt8.self)
        return ctx
    }
}

@inline(__always) private func readU8(_ data: Data, _ offset: Int) -> UInt8 {
    if offset < 0 || offset >= data.count { return 0 }
    return data[offset]
}
@inline(__always) private func readU8Bounded(
    _ data: Data, _ offset: Int, _ bound: Int
) -> UInt8 {
    if offset < 0 || offset >= bound { return 0 }
    return (offset < data.count) ? data[offset] : 0
}
@inline(__always) private func readU16LE(_ data: Data, _ offset: Int) -> UInt16
{
    let lo = UInt16(readU8(data, offset))
    let hi = UInt16(readU8(data, offset + 1))
    return lo | (hi << 8)
}
@inline(__always) private func readU16LEBounded(
    _ data: Data, _ offset: Int, _ bound: Int
) -> UInt16 {
    let lo = UInt16(readU8Bounded(data, offset, bound))
    let hi = UInt16(readU8Bounded(data, offset + 1, bound))
    return lo | (hi << 8)
}
@inline(__always) private func readU16BE(_ data: Data, _ offset: Int) -> UInt16
{
    let hi = UInt16(readU8(data, offset))
    let lo = UInt16(readU8(data, offset + 1))
    return (hi << 8) | lo
}
@inline(__always) private func readU32LE(_ data: Data, _ offset: Int) -> UInt32
{
    let w0 = UInt32(readU16LE(data, offset))
    let w1 = UInt32(readU16LE(data, offset + 2))
    return w0 | (w1 << 16)
}
@inline(__always) private func readU32BE(_ data: Data, _ offset: Int) -> UInt32
{
    let w0 = UInt32(readU16BE(data, offset))
    let w1 = UInt32(readU16BE(data, offset + 2))
    return (w0 << 16) | w1
}
@inline(__always) private func readArray(
    _ data: Data, _ offset: Int, _ count: Int
) -> [UInt8] {
    if offset >= data.count { return Array(repeating: 0, count: count) }
    let end = min(data.count, offset + count)
    var arr = Array(data[offset..<end])
    if arr.count < count {
        arr.append(contentsOf: repeatElement(0, count: count - arr.count))
    }
    return arr
}
@inline(__always) private func readSlice(
    _ data: Data, _ offset: Int, _ length: Int
) -> Data {
    if offset >= data.count { return Data(repeating: 0, count: length) }
    let end = min(data.count, offset + length)
    var d = data.subdata(in: offset..<end)
    if d.count < length {
        d.append(Data(repeating: 0, count: length - d.count))
    }
    return d
}
@inline(__always) private func readString(
    _ data: Data, _ offset: Int, _ length: Int
) -> String {
    let bytes = readArray(data, offset, length)
    let trimmed =
        bytes.split(
            separator: 0, maxSplits: 1, omittingEmptySubsequences: false
        ).first.map(
            Array.init) ?? bytes
    return String(bytes: trimmed, encoding: .utf8) ?? ""
}
