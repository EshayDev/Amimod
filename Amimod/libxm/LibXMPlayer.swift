import Foundation

public enum LibXMPlayer {
    public static func generateSamples(
        ctx: inout XMContext, output: inout [Float], numsamples: Int
    ) {
        if output.count < numsamples * 2 {
            output = Array(repeating: 0, count: numsamples * 2)
        }
        ctx.generatedSamples &+= UInt32(numsamples)
        var outIndex = 0
        for _ in 0..<numsamples {
            var l: Float = 0
            var r: Float = 0
            sample(ctx: &ctx, outLeft: &l, outRight: &r)
            output[outIndex] = l
            output[outIndex + 1] = r
            outIndex &+= 2
        }
    }

    public static func generateSamplesNoninterleaved(
        ctx: inout XMContext, left: inout [Float], right: inout [Float],
        numsamples: Int
    ) {
        if left.count < numsamples {
            left = Array(repeating: 0, count: numsamples)
        }
        if right.count < numsamples {
            right = Array(repeating: 0, count: numsamples)
        }
        ctx.generatedSamples &+= UInt32(numsamples)
        for i in 0..<numsamples {
            var l: Float = 0
            var r: Float = 0
            sample(ctx: &ctx, outLeft: &l, outRight: &r)
            left[i] = l
            right[i] = r
        }
    }

    public static func generateSamplesUnmixed(
        ctx: inout XMContext, output: inout [Float], numsamples: Int
    ) {
        let frameWidth = Int(ctx.module.numChannels) * 2
        if output.count < numsamples * frameWidth {
            output = Array(repeating: 0, count: numsamples * frameWidth)
        }
        ctx.generatedSamples &+= UInt32(numsamples)
        var outIdx = 0
        for _ in 0..<numsamples {
            sampleUnmixed(ctx: &ctx, outLR: &output, outIndex: outIdx)
            outIdx &+= frameWidth
        }
    }
}

extension LibXMPlayer {
    @inline(__always)
    fileprivate static func NOTE_IS_KEY_OFF(_ n: UInt8) -> Bool {
        return (n & 128) != 0
    }

    @inline(__always)
    fileprivate static func XM_CLAMP_UP(_ v: inout Float) { if v > 1 { v = 1 } }
    @inline(__always)
    fileprivate static func XM_CLAMP_DOWN(_ v: inout Float) {
        if v < 0 { v = 0 }
    }
    @inline(__always)
    fileprivate static func XM_LERP(_ u: Float, _ v: Float, _ t: Float) -> Float
    { u + t * (v - u) }

    fileprivate static func xm_waveform(_ waveform: UInt8, _ step: UInt8)
        -> Int8
    {
        let s = step % 0x40
        switch waveform & 3 {
        case XMConstants.waveformSine:
            let sinLut: [Int8] = [
                0, 12, 24, 37, 48, 60, 71, 81, 90, 98, 106, 112, 118, 122, 125,
                127,
            ]
            let idx: Int =
                (s & 0x10) != 0 ? Int(0x0F - (s & 0x0F)) : Int(s & 0x0F)
            return (s < 0x20) ? -sinLut[idx] : sinLut[idx]
        case XMConstants.waveformSquare:
            return (s < 0x20) ? Int8.min : Int8.max
        case XMConstants.waveformRampDown:
            return Int8(truncatingIfNeeded: -Int(s) * 4 - 1)
        case XMConstants.waveformRampUp:
            return Int8(truncatingIfNeeded: Int(s) * 4)
        default:
            let sinLut: [Int8] = [
                0, 12, 24, 37, 48, 60, 71, 81, 90, 98, 106, 112, 118, 122, 125,
                127,
            ]
            let idx: Int =
                (s & 0x10) != 0 ? Int(0x0F - (s & 0x0F)) : Int(s & 0x0F)
            return (s < 0x20) ? -sinLut[idx] : sinLut[idx]
        }
    }

    fileprivate static func xm_autovibrato(_ ch: inout XMChannelContext) {
        guard ch.instrument != nil else { return }
    }

    @inline(__always)
    fileprivate static func UPDATE_EFFECT_MEMORY_XY(
        _ memory: inout UInt8, _ value: UInt8
    ) {
        if (value & 0x0F) != 0 { memory = (memory & 0xF0) | (value & 0x0F) }
        if (value & 0xF0) != 0 { memory = (memory & 0x0F) | (value & 0xF0) }
    }

    fileprivate static func xm_slot_has_vibrato(_ s: XMPatternSlot) -> Bool {
        return (s.effectType == UInt8(XMEffect.vibrato.rawValue))
            || (s.effectType == UInt8(XMEffect.vibratoVolumeSlide.rawValue))
            || ((s.volumeColumn >> 4) == UInt8(XMVolumeEffect.vibrato.rawValue))
    }

    fileprivate static func xm_slot_has_tone_portamento(_ s: XMPatternSlot)
        -> Bool
    {
        return (s.effectType == UInt8(XMEffect.tonePortamento.rawValue))
            || (s.effectType
                == UInt8(XMEffect.tonePortamentoVolumeSlide.rawValue))
            || ((s.volumeColumn >> 4)
                == UInt8(XMVolumeEffect.tonePortamento.rawValue))
    }

    fileprivate static func xm_pitch_slide(
        _ ch: inout XMChannelContext, _ periodOffset: Int16
    ) {
        ch.period = UInt16(Int(ch.period) &+ Int(ch.glissandoControlError))
        ch.glissandoControlError = 0
        ch.vibratoOffset = 0
        let newPeriod = Int32(Int(ch.period) &+ Int(periodOffset))
        ch.period = newPeriod < 1 ? 1 : UInt16(newPeriod)
    }

    fileprivate static func xm_param_slide(
        _ param: inout UInt8, _ rawval: UInt8, _ max: UInt8
    ) {
        if (rawval & 0xF0) != 0 {
            let newVal = Int(param) + Int(rawval >> 4)
            param = newVal > Int(max) ? max : UInt8(newVal)
        } else {
            let newVal = Int(param) - Int(rawval & 0x0F)
            param = newVal < 0 ? 0 : UInt8(newVal)
        }
    }

    fileprivate static func xm_linear_period(_ note: Int16) -> UInt16 {
        let val = 7680 - Int(note) * 4
        return UInt16(clamping: val)
    }

    fileprivate static func xm_linear_frequency(
        _ period: UInt16, _ arpNoteOffset: UInt8
    ) -> UInt32 {
        var p = Int(period)
        if arpNoteOffset != 0 {
            p -= Int(arpNoteOffset) * 64
            if p < 1540 { p = 1540 }
        }
        let expVal = powf(2.0, (4608.0 - Float(p)) / 768.0)
        return UInt32(8363.0 * expVal)
    }

    fileprivate static func xm_amiga_period(_ note: Int16) -> UInt16 {
        let v = 32.0 * 856.0 * powf(2.0, Float(note) / (-192.0))
        return UInt16(clamping: Int(v))
    }

    fileprivate static func xm_amiga_frequency(
        _ ctx: XMContext, _ period: UInt16, _ arpNoteOffset: UInt8
    ) -> UInt32 {
        var p = Float(period)
        if arpNoteOffset != 0 {
            p *= powf(2.0, Float(arpNoteOffset) / -12.0)
            if p < 107.0 { p = 107.0 }
        }
        let amigaClockHz: Float = ctx.module.isMOD ? 7_093_789.2 : 7_159_090.5
        return UInt32(4.0 * amigaClockHz / (p * 2.0))
    }

    fileprivate static func xm_period(_ ctx: XMContext, _ note: Int16) -> UInt16
    {
        return ctx.module.amigaFrequencies
            ? xm_amiga_period(note) : xm_linear_period(note)
    }

    fileprivate static func xm_frequency(
        _ ctx: XMContext, _ ch: XMChannelContext
    ) -> UInt32 {
        precondition(ch.period > 0)
        var pInt =
            Int(ch.period) - Int(ch.vibratoOffset) - Int(ch.autovibratoOffset)
        if pInt < 1 { pInt = 1 }
        let period = UInt16(clamping: pInt)
        return ctx.module.amigaFrequencies
            ? xm_amiga_frequency(ctx, period, ch.arpNoteOffset)
            : xm_linear_frequency(period, ch.arpNoteOffset)
    }

    fileprivate static func xm_round_linear_period_to_semitone(
        _ ch: inout XMChannelContext
    ) {
        let newPeriod = UInt16(
            ((Int(ch.period) + Int(ch.finetune) * 4 + 32) & 0xFFC0) - Int(
                ch.finetune) * 4)
        ch.glissandoControlError = Int8(Int(ch.period) - Int(newPeriod))
        ch.period = newPeriod
    }

    fileprivate static func xm_round_period_to_semitone(
        _ ctx: XMContext, _ ch: inout XMChannelContext
    ) {
        xm_pitch_slide(&ch, 0)
        if ctx.module.amigaFrequencies {
        } else {
            xm_round_linear_period_to_semitone(&ch)
        }
    }

    fileprivate static func xm_handle_pattern_slot(
        ctx: inout XMContext, ch: inout XMChannelContext
    ) {
        let s = ch.current
        if s.instrument != 0 { ch.nextInstrument = s.instrument }
        if !NOTE_IS_KEY_OFF(s.note) {
            if s.note != 0 {
                if s.note <= XMConstants.maxNote {
                    if xm_slot_has_tone_portamento(s) {
                        xm_tone_portamento_target(ctx: ctx, ch: &ch)
                    } else {
                        ch.origNote = s.note
                        xm_trigger_note(ctx: &ctx, ch: &ch)
                    }
                } else {
                    xm_trigger_note(ctx: &ctx, ch: &ch)
                }
            }
        } else {
            xm_key_off(ctx: &ctx, &ch)
        }
        if s.instrument != 0 {
            if let smpIdx = ch.sample {
                ch.volume = ctx.samples[smpIdx].volume
                ch.panning = ctx.samples[smpIdx].panning
            }
            if !NOTE_IS_KEY_OFF(s.note) {
                xm_trigger_instrument(ctx: &ctx, ch: &ch)
            }
        }
        if s.volumeColumn >= 0x10 && s.volumeColumn <= 0x50 {
            ch.volumeOffset = 0
            ch.volume = s.volumeColumn &- 0x10
        }
        if s.volumeColumn >> 4 == UInt8(XMVolumeEffect.setPanning.rawValue) {
            let nibble = s.volumeColumn & 0x0F
            ch.panning = UInt16(nibble) * 0x10
        }
        if (s.volumeColumn >> 4)
            == UInt8(XMVolumeEffect.tonePortamento.rawValue)
        {
            if (s.volumeColumn & 0x0F) != 0 {
                ch.tonePortamentoParam = s.volumeColumn << 4
            }
        } else if s.effectType == UInt8(XMEffect.tonePortamento.rawValue) {
            if s.effectParam > 0 { ch.tonePortamentoParam = s.effectParam }
        }

        switch s.effectType {
        case UInt8(XMEffect.setVolume.rawValue):
            ch.volumeOffset = 0
            ch.volume = s.effectParam
        case UInt8(XMEffect.fineVolumeSlideUp.rawValue):
            if s.effectParam != 0 {
                ch.fineVolumeSlideUpParam = s.effectParam << 4
            }
            ch.volumeOffset = 0
            xm_param_slide(
                &ch.volume, ch.fineVolumeSlideUpParam, XMConstants.maxVolume)
        case UInt8(XMEffect.fineVolumeSlideDown.rawValue):
            if s.effectParam != 0 {
                ch.fineVolumeSlideDownParam = s.effectParam
            }
            ch.volumeOffset = 0
            xm_param_slide(
                &ch.volume, ch.fineVolumeSlideDownParam, XMConstants.maxVolume)
        case UInt8(XMEffect.setPanning.rawValue):
            ch.panning = UInt16(s.effectParam)
        case UInt8(XMEffect.jumpToOrder.rawValue):
            ctx.positionJump = true
            ctx.jumpDest = s.effectParam
            ctx.jumpRow = 0
        case UInt8(XMEffect.patternBreak.rawValue):
            ctx.patternBreak = true
            let t = s.effectParam >> 4
            ctx.jumpRow = s.effectParam &- (t &* 6)
        case UInt8(XMEffect.setTempo.rawValue):
            ctx.currentTempo = s.effectParam
        case UInt8(XMEffect.setBPM.rawValue):
            ctx.currentBpm = s.effectParam
        case UInt8(XMEffect.setGlobalVolume.rawValue):
            ctx.globalVolume = s.effectParam
        case UInt8(XMEffect.setEnvelopePosition.rawValue):
            ch.volumeEnvelopeFrameCount = UInt16(s.effectParam)
            ch.panningEnvelopeFrameCount = UInt16(s.effectParam)
        case UInt8(XMEffect.multiRetrigNote.rawValue):
            xm_multi_retrig_note(ctx: &ctx, ch: &ch)
        case UInt8(XMEffect.extraFinePortamentoUp.rawValue):
            if (s.effectParam & 0x0F) != 0 {
                ch.extraFinePortamentoUpParam = s.effectParam
            }
            xm_pitch_slide(&ch, -Int16(ch.extraFinePortamentoUpParam))
        case UInt8(XMEffect.extraFinePortamentoDown.rawValue):
            if s.effectParam != 0 {
                ch.extraFinePortamentoDownParam = s.effectParam
            }
            xm_pitch_slide(&ch, Int16(ch.extraFinePortamentoDownParam))
        case UInt8(XMEffect.finePortamentoUp.rawValue):
            if s.effectParam != 0 {
                ch.finePortamentoUpParam = s.effectParam &* 4
            }
            xm_pitch_slide(&ch, -Int16(ch.finePortamentoUpParam))
        case UInt8(XMEffect.finePortamentoDown.rawValue):
            if s.effectParam != 0 {
                ch.finePortamentoDownParam = s.effectParam &* 4
            }
            xm_pitch_slide(&ch, Int16(ch.finePortamentoDownParam))
        case UInt8(XMEffect.setGlissandoControl.rawValue):
            ch.glissandoControlParam = s.effectParam
        case UInt8(XMEffect.setVibratoControl.rawValue):
            ch.vibratoControlParam = s.effectParam
        case UInt8(XMEffect.setTremoloControl.rawValue):
            ch.tremoloControlParam = s.effectParam
        case UInt8(XMEffect.patternLoop.rawValue):
            if s.effectParam != 0 {
                if s.effectParam == ch.patternLoopCount {
                    ch.patternLoopCount = 0
                } else {
                    ch.patternLoopCount &+= 1
                    ctx.positionJump = true
                    ctx.jumpRow = ch.patternLoopOrigin
                    ctx.jumpDest = UInt8(ctx.currentTableIndex)
                }
            } else {
                ch.patternLoopOrigin = ctx.currentRow
                ctx.jumpRow = ch.patternLoopOrigin
            }
        case UInt8(XMEffect.delayPattern.rawValue):
            ctx.extraRows = s.effectParam
        default:
            break
        }
    }

    fileprivate static func xm_tone_portamento(
        ctx: XMContext, ch: inout XMChannelContext
    ) {
        if ch.tonePortamentoTargetPeriod == 0 || ch.period == 0 { return }
        let incr: UInt16 = UInt16(ch.tonePortamentoParam) * 4
        var diff = Int32(Int(ch.tonePortamentoTargetPeriod) - Int(ch.period))
        if diff > Int32(incr) { diff = Int32(incr) }
        if diff < -Int32(incr) { diff = -Int32(incr) }
        xm_pitch_slide(&ch, Int16(diff))
        if ch.glissandoControlParam != 0 {
            var tmp = ch
            xm_round_period_to_semitone(ctx, &tmp)
            ch.period = tmp.period
            ch.glissandoControlError = tmp.glissandoControlError
        }
    }

    fileprivate static func xm_tone_portamento_target(
        ctx: XMContext, ch: inout XMChannelContext
    ) {
        precondition(xm_slot_has_tone_portamento(ch.current))
        guard ch.sample != nil else { return }
        let note = Int16(
            Int(ch.current.note) + Int(ch.finetuneSampleRelativeNote(ctx)))
        if note <= 0 || note >= 120 { return }
        ch.tonePortamentoTargetPeriod = xm_period(
            ctx, Int16(16 * (Int(note) - 1) + Int(ch.finetune)))
    }

    fileprivate static func xm_vibrato(_ ch: inout XMChannelContext) {
        xm_pitch_slide(&ch, 0)
        let wave = ch.vibratoControlParam
        let ticks = ch.vibratoTicks
        let off = xm_waveform(wave, UInt8(truncatingIfNeeded: ticks))
        ch.vibratoOffset = Int8(Int(off) * Int(ch.vibratoParam & 0x0F) / 0x10)
        ch.vibratoTicks &+= ch.vibratoParam >> 4
    }

    fileprivate static func xm_tremolo(_ ch: inout XMChannelContext) {
        var ticks = ch.tremoloTicks
        if (ch.tremoloControlParam & 1) != 0 {
            ticks = ticks % 0x40
            if ticks >= 0x20 { ticks = 0x20 &- ticks }
            if ch.vibratoTicks % 0x40 >= 0x20 { ticks = 0x20 &- ticks }
        }
        let w = xm_waveform(ch.tremoloControlParam, ticks)
        ch.volumeOffset = Int8(Int(w) * Int(ch.tremoloParam & 0x0F) * 4 / 128)
        ch.tremoloTicks &+= ch.tremoloParam >> 4
    }

    fileprivate static func xm_multi_retrig_note(
        ctx: inout XMContext, ch: inout XMChannelContext
    ) {
        UPDATE_EFFECT_MEMORY_XY(&ch.multiRetrigParam, ch.current.effectParam)
        if ch.current.volumeColumn != 0 && ctx.currentTick == 0 { return }
        ch.multiRetrigTicks &+= 1
        if ch.multiRetrigTicks < (ch.multiRetrigParam & 0x0F) { return }
        ch.multiRetrigTicks = 0
        xm_trigger_note(ctx: &ctx, ch: &ch)
        if ch.current.volumeColumn >= 0x10 && ch.current.volumeColumn <= 0x50 {
            return
        }
        let add: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 4, 8, 16, 0, 0]
        let mul: [UInt8] = [1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 3, 2]
        let x = ch.multiRetrigParam >> 4
        var vol = Int(ch.volume)
        vol += Int(add[Int(x)])
        vol -= Int(add[Int(x ^ 8)])
        vol *= Int(mul[Int(x)])
        vol /= Int(mul[Int(x ^ 8)])
        if vol < 0 { vol = 0 }
        if vol > Int(XMConstants.maxVolume) { vol = Int(XMConstants.maxVolume) }
        ch.volume = UInt8(vol)
    }

    fileprivate static func xm_arpeggio(
        ctx: XMContext, ch: inout XMChannelContext
    ) {
        if ctx.module.isMOD {
            let t = Int(ctx.currentTick) % 3
            ch.arpNoteOffset =
                (t == 0)
                ? 0
                : (t == 1
                    ? (ch.current.effectParam >> 4)
                    : (ch.current.effectParam & 0x0F))
            return
        }
        let t = Int(ctx.currentTempo) - Int(ctx.currentTick)
        if (ctx.currentTick == 0 && ctx.extraRows != 0) || t == 16
            || (t < 16 && (t % 3) == 0)
        {
            ch.arpNoteOffset = 0
            return
        }
        ch.shouldResetArpeggio = true
        var tmp = ch
        xm_round_period_to_semitone(ctx, &tmp)
        ch.period = tmp.period
        ch.glissandoControlError = tmp.glissandoControlError
        if t > 16 || (t % 3) == 2 {
            ch.arpNoteOffset = ch.current.effectParam & 0x0F
        } else {
            ch.arpNoteOffset = ch.current.effectParam >> 4
        }
    }

    fileprivate static func xm_tick_envelope(
        ch: inout XMChannelContext, env: XMEnvelope, counter: inout UInt16
    ) -> UInt8 {
        precondition(env.numPoints >= 2)
        if counter == env.points[Int(env.loopEndPoint)].frame
            && (ch.sustained || env.sustainPoint != env.loopEndPoint)
        {
            counter = env.points[Int(env.loopStartPoint)].frame
        }
        if ch.sustained && (env.sustainPoint & 128) == 0
            && counter == env.points[Int(env.sustainPoint)].frame
        {
            return env.points[Int(env.sustainPoint)].value
        }
        for j in stride(from: Int(env.numPoints) - 1, through: 1, by: -1) {
            if counter < env.points[j - 1].frame { continue }
            let a = env.points[j - 1]
            let b = env.points[j]
            if counter >= b.frame {
                counter &+= 1
                return b.value
            }
            let val =
                UInt32(b.value) * UInt32(counter - a.frame) + UInt32(a.value)
                * UInt32(b.frame - counter)
            let denom = UInt16(b.frame - a.frame)
            counter &+= 1
            return UInt8(val / UInt32(denom))
        }
        return 0
    }

    fileprivate static func xm_tick_envelopes(
        ctx: XMContext, ch: inout XMChannelContext
    ) {
        if let instIdx = ch.instrument, instIdx < ctx.instruments.count {
            let instr = ctx.instruments[instIdx]
            if instr.vibratoDepth != 0
                && (instr.vibratoRate > 0
                    || instr.vibratoType == XMConstants.waveformSquare)
            {
                let ticksScaled: UInt8 = UInt8(
                    truncatingIfNeeded: (UInt32(ch.autovibratoTicks)
                        &* UInt32(instr.vibratoRate))
                        / 4)
                let wf = xm_waveform(instr.vibratoType, ticksScaled)
                var off = Int8(Int(wf) * -Int(instr.vibratoDepth) / 128)
                if ch.autovibratoTicks < instr.vibratoSweep {
                    off = Int8(
                        Int(off) * Int(ch.autovibratoTicks)
                            / Int(instr.vibratoSweep))
                }
                ch.autovibratoOffset = off
                ch.autovibratoTicks &+= 1
            }
            if !ch.sustained {
                ch.fadeoutVolume =
                    ch.fadeoutVolume < instr.volumeFadeout
                    ? 0 : ch.fadeoutVolume &- instr.volumeFadeout
            } else {
                ch.fadeoutVolume = XMConstants.maxFadeoutVolume &- 1
            }
            if instr.volumeEnvelope.numPoints != 0 {
                var volCounter = ch.volumeEnvelopeFrameCount
                let vol = xm_tick_envelope(
                    ch: &ch, env: instr.volumeEnvelope, counter: &volCounter)
                ch.volumeEnvelopeFrameCount = volCounter
                ch.volumeEnvelopeVolume = vol
            } else {
                ch.volumeEnvelopeVolume = XMConstants.maxEnvelopeValue
            }
            if instr.panningEnvelope.numPoints != 0 {
                var panCounter = ch.panningEnvelopeFrameCount
                let pan = xm_tick_envelope(
                    ch: &ch, env: instr.panningEnvelope, counter: &panCounter)
                ch.panningEnvelopeFrameCount = panCounter
                ch.panningEnvelopePanning = pan
            } else {
                ch.panningEnvelopePanning = XMConstants.maxEnvelopeValue / 2
            }
        }
    }

    fileprivate static func xm_tick_effects(
        ctx: inout XMContext, ch: inout XMChannelContext
    ) {
        switch ch.current.volumeColumn >> 4 {
        case UInt8(XMVolumeEffect.slideDown.rawValue):
            ch.volumeOffset = 0
            xm_param_slide(
                &ch.volume, ch.current.volumeColumn & 0x0F,
                XMConstants.maxVolume)
        case UInt8(XMVolumeEffect.slideUp.rawValue):
            ch.volumeOffset = 0
            xm_param_slide(
                &ch.volume, ch.current.volumeColumn << 4, XMConstants.maxVolume)
        case UInt8(XMVolumeEffect.vibrato.rawValue):
            UPDATE_EFFECT_MEMORY_XY(
                &ch.vibratoParam, ch.current.volumeColumn & 0x0F)
            ch.shouldResetVibrato = false
            xm_vibrato(&ch)
        case UInt8(XMVolumeEffect.panningSlideLeft.rawValue):
            xm_param_slide(
                &ch.panningAsByte, ch.current.volumeColumn & 0x0F,
                UInt8(XMConstants.maxPanning - 1)
            )
        case UInt8(XMVolumeEffect.panningSlideRight.rawValue):
            xm_param_slide(
                &ch.panningAsByte, ch.current.volumeColumn << 4,
                UInt8(XMConstants.maxPanning - 1))
        case UInt8(XMVolumeEffect.tonePortamento.rawValue):
            xm_tone_portamento(ctx: ctx, ch: &ch)
        default:
            break
        }

        switch ch.current.effectType {
        case UInt8(XMEffect.arpeggio.rawValue):
            if ch.current.effectParam != 0 { xm_arpeggio(ctx: ctx, ch: &ch) }
        case UInt8(XMEffect.portamentoUp.rawValue):
            if ch.current.effectParam > 0 {
                ch.portamentoUpParam = ch.current.effectParam
            }
            xm_pitch_slide(&ch, -Int16(ch.portamentoUpParam) * 4)
        case UInt8(XMEffect.portamentoDown.rawValue):
            if ch.current.effectParam > 0 {
                ch.portamentoDownParam = ch.current.effectParam
            }
            xm_pitch_slide(&ch, Int16(ch.portamentoDownParam) * 4)
        case UInt8(XMEffect.tonePortamento.rawValue),
            UInt8(XMEffect.tonePortamentoVolumeSlide.rawValue):
            xm_tone_portamento(ctx: ctx, ch: &ch)
            if ch.current.effectType
                == UInt8(XMEffect.tonePortamentoVolumeSlide.rawValue)
            {
                fallthrough
            }
        case UInt8(XMEffect.volumeSlide.rawValue):
            if ch.current.effectParam > 0 {
                ch.volumeSlideParam = ch.current.effectParam
            }
            ch.volumeOffset = 0
            xm_param_slide(
                &ch.volume, ch.volumeSlideParam, XMConstants.maxVolume)
        case UInt8(XMEffect.vibrato.rawValue):
            UPDATE_EFFECT_MEMORY_XY(&ch.vibratoParam, ch.current.effectParam)
            ch.shouldResetVibrato = true
            xm_vibrato(&ch)
        case UInt8(XMEffect.vibratoVolumeSlide.rawValue):
            ch.shouldResetVibrato = true
            xm_vibrato(&ch)
            if ch.current.effectParam > 0 {
                ch.volumeSlideParam = ch.current.effectParam
            }
            ch.volumeOffset = 0
            xm_param_slide(
                &ch.volume, ch.volumeSlideParam, XMConstants.maxVolume)
        case UInt8(XMEffect.tremolo.rawValue):
            UPDATE_EFFECT_MEMORY_XY(&ch.tremoloParam, ch.current.effectParam)
            xm_tremolo(&ch)
        case UInt8(XMEffect.globalVolumeSlide.rawValue):
            if ch.current.effectParam > 0 {
                ch.globalVolumeSlideParam = ch.current.effectParam
            }
            xm_param_slide(
                &ctx.globalVolume, ch.globalVolumeSlideParam,
                XMConstants.maxVolume)
        case UInt8(XMEffect.keyOff.rawValue):
            if ctx.currentTick == ch.current.effectParam {
                xm_key_off(ctx: &ctx, &ch)
            }
        case UInt8(XMEffect.panningSlide.rawValue):
            if ch.current.effectParam > 0 {
                ch.panningSlideParam = ch.current.effectParam
            }
            xm_param_slide(
                &ch.panningAsByte, ch.panningSlideParam,
                UInt8(XMConstants.maxPanning - 1))
        case UInt8(XMEffect.multiRetrigNote.rawValue):
            xm_multi_retrig_note(ctx: &ctx, ch: &ch)
        case UInt8(XMEffect.tremor.rawValue):
            if ch.current.effectParam > 0 {
                ch.tremorParam = ch.current.effectParam
            }
            if ch.tremorTicks == 0 {
                ch.tremorOn.toggle()
                ch.tremorTicks =
                    ch.tremorOn
                    ? (ch.tremorParam >> 4) : (ch.tremorParam & 0x0F)
            } else {
                ch.tremorTicks &-= 1
            }
            ch.volumeOffset = ch.tremorOn ? 0 : Int8(XMConstants.maxVolume)
        case UInt8(XMEffect.retriggerNote.rawValue):
            if ch.current.effectParam != 0
                && (ctx.currentTick % ch.current.effectParam) == 0
            {
                xm_trigger_instrument(ctx: &ctx, ch: &ch)
                xm_trigger_note(ctx: &ctx, ch: &ch)
                xm_tick_envelopes(ctx: ctx, ch: &ch)
            }
        case UInt8(XMEffect.cutNote.rawValue):
            if ctx.currentTick == ch.current.effectParam { xm_cut_note(&ch) }
        case UInt8(XMEffect.delayNote.rawValue):
            if ctx.currentTick == ch.current.effectParam {
                xm_handle_pattern_slot(ctx: &ctx, ch: &ch)
                xm_trigger_instrument(ctx: &ctx, ch: &ch)
                if !NOTE_IS_KEY_OFF(ch.current.note) {
                    xm_trigger_note(ctx: &ctx, ch: &ch)
                }
                xm_tick_envelopes(ctx: ctx, ch: &ch)
            }
        default:
            break
        }
    }

    fileprivate static func xm_row(ctx: inout XMContext) {
        if ctx.positionJump || ctx.patternBreak {
            if ctx.positionJump {
                ctx.currentTableIndex = UInt16(ctx.jumpDest)
            } else {
                ctx.currentTableIndex &+= 1
                maybeRestartPOT(&ctx)
            }
            ctx.patternBreak = false
            ctx.positionJump = false
            ctx.currentRow = ctx.jumpRow
            ctx.jumpRow = 0
        }
        let curPatternIndex = Int(
            ctx.module.patternTable[Int(ctx.currentTableIndex)])
        let numCh = Int(ctx.module.numChannels)
        let base = Int(ctx.patterns[curPatternIndex].rowsIndex) * numCh
        var sIndex = base + Int(ctx.currentRow) * numCh
        var inLoop = false
        for chIndex in 0..<numCh {
            var ch = ctx.channels[chIndex]
            ch.current = ctx.patternSlots[sIndex]
            if !(ctx.currentTick == 0 && ctx.extraRows != 0
                && ch.current.effectType == UInt8(XMEffect.delayNote.rawValue))
            {
                xm_handle_pattern_slot(ctx: &ctx, ch: &ch)
            }
            if ch.patternLoopCount > 0 { inLoop = true }
            if ch.shouldResetVibrato && !xm_slot_has_vibrato(ch.current) {
                ch.vibratoOffset = 0
            }
            ctx.channels[chIndex] = ch
            sIndex &+= 1
        }
        if !inLoop && XMBuildConfig.loopingType == 2 {
            let idx =
                Int(ctx.currentTableIndex) * XMConstants.maxRowsPerPattern
                + Int(ctx.currentRow)
            if idx < ctx.rowLoopCount.count {
                ctx.loopCount = ctx.rowLoopCount[idx]
                ctx.rowLoopCount[idx] &+= 1
            }
        }
        ctx.currentRow &+= 1
        if !ctx.positionJump && !ctx.patternBreak {
            let pat = ctx.patterns[curPatternIndex]
            if ctx.currentRow >= pat.numRows || ctx.currentRow == 0 {
                ctx.currentRow = ctx.jumpRow
                ctx.jumpRow = 0
                ctx.currentTableIndex &+= 1
                maybeRestartPOT(&ctx)
            }
        }
    }

    fileprivate static func maybeRestartPOT(_ ctx: inout XMContext) {
        if ctx.currentTableIndex >= ctx.module.length {
            ctx.currentTableIndex = UInt16(ctx.module.restartPosition)
        }
    }

    fileprivate static func xm_tick(ctx: inout XMContext) {
        if ctx.currentTick >= ctx.currentTempo {
            ctx.currentTick = 0
            ctx.extraRowsDone &+= 1
        }
        if ctx.currentTick == 0
            && (ctx.extraRows == 0 || ctx.extraRowsDone > ctx.extraRows)
        {
            ctx.extraRows = 0
            ctx.extraRowsDone = 0
            xm_row(ctx: &ctx)
        }
        for i in 0..<Int(ctx.module.numChannels) {
            var ch = ctx.channels[i]
            xm_tick_envelopes(ctx: ctx, ch: &ch)
            if ctx.currentTick != 0 || ctx.extraRowsDone != 0 {
                xm_tick_effects(ctx: &ctx, ch: &ch)
            }
            if ch.period == 0 {
                ctx.channels[i] = ch
                continue
            }
            let freq = xm_frequency(ctx, ch)
            let rate = UInt32(XMMacros.sampleRate(ctx.module))
            ch.step = UInt32(
                (UInt64(freq) * UInt64(XMConstants.sampleMicrosteps) + UInt64(
                    rate) / 2)
                    / UInt64(rate))
            var base = Int32(Int(ch.volume) - Int(ch.volumeOffset))
            if base < 0 { base = 0 }
            if base > Int32(XMConstants.maxVolume) {
                base = Int32(XMConstants.maxVolume)
            }
            base *= Int32(ch.volumeEnvelopeVolume)
            base *= Int32(ch.fadeoutVolume)
            base /= 4
            base *= Int32(ctx.globalVolume)
            var volume = Float(base) / Float(Int32.max)
            if volume < 0 { volume = 0 }
            if volume > 1 { volume = 1 }
            var outL: Float = 0
            var outR: Float = 0
            if XMBuildConfig.panningType == 8 {
                let pann = UInt8(
                    clamping: Int(ch.panning)
                        + Int(
                            (Int(ch.panningEnvelopePanning)
                                - Int(XMConstants.maxEnvelopeValue / 2))
                                * (Int(XMConstants.maxPanning / 2)
                                    - abs(
                                        Int(ch.panning)
                                            - Int(XMConstants.maxPanning / 2)))
                                / Int(XMConstants.maxEnvelopeValue / 2)))
                outL =
                    volume
                    * sqrtf(
                        Float(Int(XMConstants.maxPanning) - Int(pann))
                            / Float(XMConstants.maxPanning))
                outR =
                    volume
                    * sqrtf(Float(Int(pann)) / Float(XMConstants.maxPanning))
            } else if XMBuildConfig.panningType > 0 {
                let lut: [Float]
                switch XMBuildConfig.panningType {
                case 1: lut = [0.66015625, 0.75]
                case 2: lut = [0.61328125, 0.7890625]
                case 3: lut = [0.55859375, 0.828125]
                case 4: lut = [0.5, 0.8671875]
                case 5: lut = [0.43359375, 0.90234375]
                case 6: lut = [0.353515625, 0.93359375]
                default: lut = [0.25, 0.96875]
                }
                if (((i >> 1) ^ i) & 1) != 0 {
                    outL = volume * lut[0]
                    outR = volume * lut[1]
                } else {
                    outL = volume * lut[1]
                    outR = volume * lut[0]
                }
            } else {
                outL = volume * 0.70703125
                outR = volume * 0.70703125
            }
            if XMBuildConfig.ramping {
                ch.targetVolume = (outL, outR)
            } else {
                ch.actualVolume = (outL, outR)
            }
            ctx.channels[i] = ch
        }
        ctx.currentTick &+= 1
        var samplesInTick = UInt32(XMMacros.sampleRate(ctx.module))
        samplesInTick &*= 10 * (XMConstants.tickSubsamples / 4)
        samplesInTick /= UInt32(ctx.currentBpm)
        ctx.remainingSamplesInTick &+= samplesInTick
    }

    fileprivate static func sampleUnmixed(
        ctx: inout XMContext, outLR: inout [Float], outIndex: Int
    ) {
        if ctx.remainingSamplesInTick < XMConstants.tickSubsamples {
            xm_tick(ctx: &ctx)
        } else {
            ctx.remainingSamplesInTick &-= XMConstants.tickSubsamples
        }
        var idx = outIndex
        for i in 0..<Int(ctx.module.numChannels) {
            outLR[idx] = 0
            outLR[idx + 1] = 0
            var l = outLR[idx]
            var r = outLR[idx + 1]
            xm_next_of_channel(ctx: &ctx, chIndex: i, outLeft: &l, outRight: &r)
            outLR[idx] = l
            outLR[idx + 1] = r
            idx &+= 2
        }
    }

    fileprivate static func sample(
        ctx: inout XMContext, outLeft: inout Float, outRight: inout Float
    ) {
        if ctx.remainingSamplesInTick < XMConstants.tickSubsamples {
            xm_tick(ctx: &ctx)
        } else {
            ctx.remainingSamplesInTick &-= XMConstants.tickSubsamples
        }
        for i in 0..<Int(ctx.module.numChannels) {
            xm_next_of_channel(
                ctx: &ctx, chIndex: i, outLeft: &outLeft, outRight: &outRight)
        }
        let lim = Float(ctx.module.numChannels)
        outLeft = min(max(outLeft, -lim), lim)
        outRight = min(max(outRight, -lim), lim)
    }

    fileprivate static func xm_next_of_channel(
        ctx: inout XMContext, chIndex: Int, outLeft: inout Float,
        outRight: inout Float
    ) {
        var ch = ctx.channels[chIndex]
        let fval =
            xm_next_of_sample(ctx: &ctx, ch: &ch) * XMConstants.amplification
        var muted = ch.muted
        if let instIdx = ch.instrument, instIdx < ctx.instruments.count {
            muted = muted || ctx.instruments[instIdx].muted
        }
        if ctx.module.maxLoopCount > 0
            && ctx.loopCount >= ctx.module.maxLoopCount
        {
            muted = true
        }
        if !muted {
            outLeft += fval * ch.actualVolume.0
            outRight += fval * ch.actualVolume.1
        }
        if XMBuildConfig.ramping {
            ch.frameCount &+= 1
            slideTowards(&ch.actualVolume.0, ch.targetVolume.0, 1.0 / 256.0)
            slideTowards(&ch.actualVolume.1, ch.targetVolume.1, 1.0 / 256.0)
        }
        ctx.channels[chIndex] = ch
    }

    fileprivate static func slideTowards(
        _ val: inout Float, _ goal: Float, _ incr: Float
    ) {
        if val > goal {
            val -= incr
            if val < goal { val = goal }
        } else {
            val += incr
            if val > goal { val = goal }
        }
    }

    fileprivate static func xm_sample_at(
        ctx: XMContext, sample: XMSample, k: UInt32
    ) -> Float {
        precondition(k < sample.length)
        precondition(sample.index + k < ctx.module.samplesDataLength)
        let v = ctx.samplesData[Int(sample.index + k)]
        return Float(v) / Float(Int16.max)
    }

    fileprivate static func xm_next_of_sample(
        ctx: inout XMContext, ch: inout XMChannelContext
    )
        -> Float
    {
        guard let smpIdx = ch.sample else {
            if XMBuildConfig.ramping {
                if ch.frameCount >= UInt32(XMConstants.rampingPoints) {
                    return 0
                }
                let t = Float(ch.frameCount) / Float(XMConstants.rampingPoints)
                return XM_LERP(ch.endOfPreviousSample[Int(ch.frameCount)], 0, t)
            }
            return 0
        }
        let smp = ctx.samples[smpIdx]
        if ch.sampleOffsetInvalid
            || smp.loopLength == 0
                && ch.samplePosition >= smp.length
                    * XMConstants.sampleMicrosteps
        {
            if XMBuildConfig.ramping {
                if ch.frameCount >= UInt32(XMConstants.rampingPoints) {
                    return 0
                }
                let t = Float(ch.frameCount) / Float(XMConstants.rampingPoints)
                return XM_LERP(ch.endOfPreviousSample[Int(ch.frameCount)], 0, t)
            }
            return 0
        }
        var pos = ch.samplePosition
        if smp.loopLength != 0
            && ch.samplePosition >= smp.length * XMConstants.sampleMicrosteps
        {
            let off =
                (smp.length &- smp.loopLength) * XMConstants.sampleMicrosteps
            pos &-= off
            let loopSpan =
                smp.pingPong
                ? smp.loopLength &* XMConstants.sampleMicrosteps &* 2
                : smp.loopLength &* XMConstants.sampleMicrosteps
            pos = (pos % loopSpan) &+ off
        }
        var a = pos / XMConstants.sampleMicrosteps
        var b: UInt32
        let linear = XMBuildConfig.linearInterpolation
        var t: Float = 0
        if linear {
            t =
                Float(pos % XMConstants.sampleMicrosteps)
                / Float(XMConstants.sampleMicrosteps)
        }
        if smp.loopLength == 0 {
            b = (a + 1 < smp.length) ? (a + 1) : a
        } else if !smp.pingPong {
            b = (a + 1 == smp.length) ? (smp.length &- smp.loopLength) : (a + 1)
        } else {
            if a < smp.length {
                b = (a + 1 == smp.length) ? a : (a + 1)
            } else {
                let ra = smp.length &* 2 &- 1 &- a
                var rb = ra == smp.length &- smp.loopLength ? ra : (ra &- 1)
                if rb > smp.length { rb = smp.length &- 1 }
                a = ra
                b = rb
            }
        }
        var u = xm_sample_at(ctx: ctx, sample: smp, k: a)
        if linear {
            u = XM_LERP(u, xm_sample_at(ctx: ctx, sample: smp, k: b), t)
        }
        if XMBuildConfig.ramping {
            if ch.frameCount < UInt32(XMConstants.rampingPoints) {
                let blend =
                    Float(ch.frameCount) / Float(XMConstants.rampingPoints)
                u = XM_LERP(
                    ch.endOfPreviousSample[Int(ch.frameCount)], u, blend)
            }
        }
        ch.samplePosition &+= ch.step
        return u
    }

    fileprivate static func xm_trigger_instrument(
        ctx: inout XMContext, ch: inout XMChannelContext
    ) {
        ch.sustained = true
        ch.volumeEnvelopeFrameCount = 0
        ch.panningEnvelopeFrameCount = 0
        ch.multiRetrigTicks = 0
        ch.tremorTicks = 0
        ch.autovibratoTicks = 0
        ch.volumeOffset = 0
        if (ch.vibratoControlParam & 4) == 0 { ch.vibratoTicks = 0 }
        if (ch.tremoloControlParam & 4) == 0 { ch.tremoloTicks = 0 }
        ch.latestTrigger = ctx.generatedSamples
        if let instIdx = ch.instrument, instIdx < ctx.instruments.count {
            var inst = ctx.instruments[instIdx]
            inst.latestTrigger = ctx.generatedSamples
            ctx.instruments[instIdx] = inst
        }
    }

    fileprivate static func xm_trigger_note(
        ctx: inout XMContext, ch: inout XMChannelContext
    ) {
        if XMBuildConfig.ramping {
            if ch.sample != nil && ch.period != 0 {
                for i in 0..<XMConstants.rampingPoints {
                    ch.endOfPreviousSample[i] = xm_next_of_sample(
                        ctx: &ctx, ch: &ch)
                }
            } else {
                for i in 0..<XMConstants.rampingPoints {
                    ch.endOfPreviousSample[i] = 0
                }
            }
            ch.frameCount = 0
        }
        if ch.nextInstrument == 0
            || ch.nextInstrument > XMMacros.numInstruments(ctx.module)
        {
            ch.instrument = nil
            ch.sample = nil
            xm_cut_note(&ch)
            return
        }
        ch.instrument = Int(ch.nextInstrument - 1)
        let newSampleIndex: Int
        if let instIdx = ch.instrument {
            let inst = ctx.instruments[instIdx]
            newSampleIndex =
                Int(inst.samplesIndex)
                + Int(inst.sampleOfNotes[max(0, Int(ch.origNote) - 1)])
        } else {
            newSampleIndex = Int(ch.nextInstrument - 1)
        }
        if let instIdx = ch.instrument {
            let inst = ctx.instruments[instIdx]
            let sIdx = Int(inst.sampleOfNotes[max(0, Int(ch.origNote) - 1)])
            if sIdx >= Int(inst.numSamples) {
                ch.instrument = nil
                ch.sample = nil
                xm_cut_note(&ch)
                return
            }
        }
        ch.sample = newSampleIndex
        if ch.current.note == XMConstants.noteSwitch { return }
        if ch.current.effectType == UInt8(XMEffect.setFinetune.rawValue) {
            ch.finetune = Int8(Int(ch.current.effectParam) * 2 - 16)
        } else if let smpIdx = ch.sample {
            ch.finetune = ctx.samples[smpIdx].finetune
        }
        var note = Int16(
            Int(ch.origNote) + Int(ch.finetuneSampleRelativeNote(ctx)))
        if note <= 0 || note >= 120 { return }
        ch.period = xm_period(
            ctx, Int16(16 * (Int(note) - 1) + Int(ch.finetune)))
        if ch.current.effectType == UInt8(XMEffect.setSampleOffset.rawValue) {
            if ch.current.effectParam > 0 {
                ch.sampleOffsetParam = ch.current.effectParam
            }
            ch.samplePosition =
                UInt32(ch.sampleOffsetParam) * 256
                * XMConstants.sampleMicrosteps
            ch.sampleOffsetInvalid =
                (ch.samplePosition
                    >= (ctx.samples[newSampleIndex].length
                        * XMConstants.sampleMicrosteps))
        } else {
            ch.samplePosition = 0
            ch.sampleOffsetInvalid = false
        }
        ch.glissandoControlError = 0
        ch.vibratoOffset = 0
        ch.latestTrigger = ctx.generatedSamples
        ctx.samples[newSampleIndex].latestTrigger = ctx.generatedSamples
    }

    fileprivate static func xm_cut_note(_ ch: inout XMChannelContext) {
        ch.volume = 0
    }

    fileprivate static func xm_key_off(
        ctx: inout XMContext, _ ch: inout XMChannelContext
    ) {
        ch.sustained = false
        if let instIdx = ch.instrument {
            let instr = ctx.instruments[instIdx]
            if instr.volumeEnvelope.numPoints == 0 { xm_cut_note(&ch) }
        } else {
            xm_cut_note(&ch)
        }
    }
}

extension XMChannelContext {
    fileprivate var panningAsByte: UInt8 {
        get { UInt8(clamping: Int(self.panning)) }
        set { self.panning = UInt16(newValue) }
    }
    fileprivate func finetuneSampleRelativeNote(_ ctx: XMContext) -> Int8 {
        if let s = self.sample, s < ctx.samples.count {
            return ctx.samples[s].relativeNote
        }
        return 0
    }
}
