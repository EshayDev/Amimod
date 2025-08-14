import AVFoundation
import Foundation
import SwiftUI

class AudioManager: NSObject, ObservableObject {
    static let audioManager = AudioManager()
    @AppStorage("isMusicPaused") var isPaused: Bool = false

    private let engine = AVAudioEngine()
	private let masterGain: Float = 0.75
    private var sourceNode: AVAudioSourceNode?
    private var ctx: XMContext?
    private var moduleData: Data?
    private var sampleRateHz: Double = 48000
    private var fadeTotalFrames: Int = 0
    private var fadeRemainingFrames: Int = -1
    private var allowedLoops: Int = 0
    private var lastTableIndex: Int = 0
    private var loopsCompleted: Int = 0
    private var shouldStopAfterFade: Bool = false

    private var musicFiles: [URL] = []
    private var shuffledPlaylist: [URL] = []
    private var currentTrackIndex: Int = 0

    override init() {
        super.init()
        setRamping(true)
        loadMusicFiles()
        loadCurrentTrack()
        if isPaused {
            pause()
        } else {
            resume()
        }
    }

    deinit {
        unloadCurrentTrack()
    }

    private func loadMusicFiles() {
        guard let bundlePath = Bundle.main.resourcePath else { return }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: bundlePath) else { return }
        var found: [URL] = []
        for case let path as String in enumerator {
            let lower = path.lowercased()
            if lower.hasSuffix(".xm") || lower.hasSuffix(".mod")
                || lower.hasSuffix(".it") || lower.hasSuffix(".s3m")
            {
                let fullPath = (bundlePath as NSString).appendingPathComponent(
                    path)
                found.append(URL(fileURLWithPath: fullPath))
            }
        }
        musicFiles = found.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
        shufflePlaylist()
    }

    private func shufflePlaylist() {
        shuffledPlaylist = musicFiles.shuffled()
        currentTrackIndex = 0
    }

    private func loadCurrentTrack() {
        unloadCurrentTrack()

        guard !shuffledPlaylist.isEmpty else { return }

        let currentTrackURL = shuffledPlaylist[currentTrackIndex]
        startPlayingModule(fileURL: currentTrackURL)
    }

    private func unloadCurrentTrack() {
        stop()
        ctx = nil
        moduleData = nil
    }

    private func startPlayingModule(fileURL url: URL) {
        guard sourceNode == nil else { return }
        guard let data = try? Data(contentsOf: url),
            var context = LibXM.load(data: data)
        else {
            fputs("[AudioManager] Could not load module\n", stderr)
            return
        }
        self.moduleData = data

        let outFormat = engine.outputNode.outputFormat(forBus: 0)
        let hwRate = UInt16(clamping: Int(outFormat.sampleRate))
        LibXM.setSampleRate(&context, hwRate)
        self.sampleRateHz = outFormat.sampleRate
        self.ctx = context
        self.lastTableIndex = Int(context.currentTableIndex)
        self.loopsCompleted = 0
        self.fadeRemainingFrames = -1
        self.shouldStopAfterFade = false

        let lname = url.deletingPathExtension().lastPathComponent.lowercased()
        if lname == "01" {
            self.setAllowedLoops(0)
            self.setLinearInterpolation(true)
            self.setPanningType(8)
        } else if lname == "02" {
            self.setAllowedLoops(0)
            self.setLinearInterpolation(true)
            self.setPanningType(8)
        } else if lname == "03" {
            self.setAllowedLoops(2)
            self.setLinearInterpolation(true)
            self.setPanningType(8)
        } else if lname == "04" {
            self.setAllowedLoops(0)
            self.setLinearInterpolation(true)
            self.setPanningType(8)
        } else if lname == "05" {
            self.setAllowedLoops(3)
            self.setLinearInterpolation(true)
            self.setPanningType(8)
        } else if lname == "06" {
            self.setAllowedLoops(0)
            self.setLinearInterpolation(true)
            self.setPanningType(8)
        } else if lname == "07" {
            self.setAllowedLoops(0)
            self.setLinearInterpolation(true)
            self.setPanningType(8)
        } else if lname == "08" {
            self.setAllowedLoops(0)
            self.setLinearInterpolation(false)
            self.setPanningType(4)
        } else if lname == "09" {
            self.setAllowedLoops(1)
            self.setLinearInterpolation(false)
            self.setPanningType(4)
        } else if lname == "10" {
            self.setAllowedLoops(0)
            self.setLinearInterpolation(false)
            self.setPanningType(4)
        } else if lname == "11" {
            self.setAllowedLoops(1)
            self.setLinearInterpolation(false)
            self.setPanningType(4)
        } else if lname == "12" {
            self.setAllowedLoops(0)
            self.setLinearInterpolation(false)
            self.setPanningType(4)
        } else if lname == "13" {
            self.setAllowedLoops(0)
            self.setLinearInterpolation(true)
            self.setPanningType(8)
        } else if lname == "14" {
            self.setAllowedLoops(0)
            self.setLinearInterpolation(false)
            self.setPanningType(8)
        } else {
            self.setAllowedLoops(0)
            self.setLinearInterpolation(true)
            self.setPanningType(8)
        }

        let srcFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(hwRate),
            channels: 2,
            interleaved: false)!

        let node = AVAudioSourceNode {
            [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let strongSelf = self, var context = strongSelf.ctx else {
                return noErr
            }
            let frames = Int(frameCount)
            var left: [Float] = Array(repeating: 0, count: frames)
            var right: [Float] = Array(repeating: 0, count: frames)

            if !strongSelf.isPaused {
                LibXM.generateSamplesNoninterleaved(
                    &context, left: &left, right: &right, numsamples: frames)
            }

            let prevIdx = strongSelf.lastTableIndex
            let currIdx = Int(context.currentTableIndex)
            let len = Int(context.module.length)
            let restart = Int(context.module.restartPosition)
            if len > 0 && currIdx == restart && prevIdx != restart {
                strongSelf.loopsCompleted += 1
            }
            strongSelf.lastTableIndex = currIdx

            if strongSelf.fadeRemainingFrames < 0
                && strongSelf.loopsCompleted >= strongSelf.allowedLoops
            {
                let lastIndex = len - 1
                if lastIndex >= 0 && currIdx == lastIndex {
                    let patIdx = Int(
                        context.module.patternTable[
                            Int(context.currentTableIndex)])
                    if patIdx < context.patterns.count {
                        let numRows = Int(context.patterns[patIdx].numRows)
                        let curRow = Int(context.currentRow)
                        let bpm = max(1, Int(context.currentBpm))
                        let tempo = max(1, Int(context.currentTempo))
                        let secondsPerRow = (2.5 * Double(tempo)) / Double(bpm)
                        let rowsBeforeFade = Int(ceil(5.0 / secondsPerRow))
                        if numRows - curRow <= rowsBeforeFade
                            && (numRows > curRow)
                        {
                            strongSelf.fadeTotalFrames = Int(
                                5.0 * strongSelf.sampleRateHz)
                            strongSelf.fadeRemainingFrames =
                                strongSelf.fadeTotalFrames
                        }
                    }
                }
            }

            if strongSelf.fadeRemainingFrames >= 0
                && strongSelf.fadeTotalFrames > 0
            {
                let base = strongSelf.fadeRemainingFrames
                for i in 0..<frames {
                    let rem = base - i
                    let ratio = max(
                        0.0,
                        min(
                            1.0,
                            Double(rem) / Double(strongSelf.fadeTotalFrames)))
                    left[i] *= Float(ratio)
                    right[i] *= Float(ratio)
                }
                strongSelf.fadeRemainingFrames -= frames
                if strongSelf.fadeRemainingFrames <= 0 {
                    strongSelf.fadeRemainingFrames = 0
                    if !strongSelf.shouldStopAfterFade {
                        strongSelf.shouldStopAfterFade = true
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.stop()
                            self.playNextTrack()
                        }
                    }
                }
            }

            strongSelf.ctx = context

            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            if abl.count >= 2 {
                if let ptrL = abl[0].mData?.assumingMemoryBound(to: Float.self) {
                    ptrL.assign(from: left, count: frames)
                }
                if let ptrR = abl[1].mData?.assumingMemoryBound(to: Float.self) {
                    ptrR.assign(from: right, count: frames)
                }
            } else if abl.count == 1 {
                if let ptr = abl[0].mData?.assumingMemoryBound(to: Float.self) {
                    for i in 0..<frames { ptr[i] = 0.5 * (left[i] + right[i]) }
                }
            }
            return noErr
        }

        self.sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: srcFormat)
		engine.mainMixerNode.outputVolume = masterGain

        do {
            try engine.start()
        } catch {
            fputs("[AudioManager] Engine start failed: \(error)\n", stderr)
        }
    }

    private func stop() {
        engine.stop()
        if let node = sourceNode { engine.detach(node) }
        sourceNode = nil
    }

    private func pause() {
        engine.pause()
    }

    private func resume() {
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                fputs("[AudioManager] Engine resume failed: \(error)\n", stderr)
            }
        }
    }

    private func setLinearInterpolation(_ enabled: Bool) {
        LibXM.setLinearInterpolation(enabled)
    }

    private func setRamping(_ enabled: Bool) {
        LibXM.setRamping(enabled)
    }

    private func setPanningType(_ type: Int) {
        LibXM.setPanningType(type)
    }

    private func setMaxLoopCount(_ count: UInt8) {
        guard var c = ctx else { return }
        LibXM.setMaxLoopCount(&c, count)
        ctx = c
    }

    private func setAllowedLoops(_ loops: Int) {
        allowedLoops = max(0, loops)
        setMaxLoopCount(0)
        loopsCompleted = 0
        fadeRemainingFrames = -1
        shouldStopAfterFade = false
        if let c = ctx {
            lastTableIndex = Int(c.currentTableIndex)
        } else {
            lastTableIndex = 0
        }
    }

    func togglePause() {
        if isPaused {
            isPaused = false
            resume()
        } else {
            isPaused = true
            pause()
        }
    }

    func nextTrack() {
        fadeRemainingFrames = -1
        shouldStopAfterFade = false
        playNextTrack()
    }

    func previousTrack() {
        fadeRemainingFrames = -1
        shouldStopAfterFade = false

        guard !shuffledPlaylist.isEmpty else { return }
        currentTrackIndex -= 1
        if currentTrackIndex < 0 {
            currentTrackIndex = max(0, shuffledPlaylist.count - 1)
        }
        loadCurrentTrack()
        if !isPaused {
            resume()
        }
    }

    private func playNextTrack() {
        currentTrackIndex += 1
        if currentTrackIndex >= shuffledPlaylist.count {
            shufflePlaylist()
        }
        loadCurrentTrack()
        if !isPaused {
            resume()
        }
    }
}
