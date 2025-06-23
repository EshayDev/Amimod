import AVFoundation
import Foundation
import SwiftUI

class AudioManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let audioManager = AudioManager()
    @AppStorage("isMusicPaused") var isPaused: Bool = false

    private var audioPlayer: AVAudioPlayer?
    private var musicFiles: [String] = []
    private var shuffledPlaylist: [String] = []
    private var currentTrackIndex: Int = 0

    override init() {
        super.init()
        loadMusicFiles()
        loadCurrentTrack()
        if isPaused {
            audioPlayer?.pause()
        } else {
            audioPlayer?.play()
        }
    }

    deinit {
        unloadCurrentTrack()
    }

    private func loadMusicFiles() {
        guard let bundlePath = Bundle.main.resourcePath else {
            return
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(atPath: bundlePath)
            musicFiles = files.filter { $0.hasSuffix(".m4a") }.sorted()
            shufflePlaylist()
        } catch {
            return
        }
    }

    private func shufflePlaylist() {
        shuffledPlaylist = musicFiles.shuffled()
        currentTrackIndex = 0
    }

    private func loadCurrentTrack() {
        unloadCurrentTrack()
        
        guard !shuffledPlaylist.isEmpty else {
            return
        }

        let currentTrack = shuffledPlaylist[currentTrackIndex]
        let trackNameWithoutExtension = String(currentTrack.dropLast(4))
        guard let path = Bundle.main.path(forResource: trackNameWithoutExtension, ofType: "m4a")
        else {
            return
        }

        let url = URL(fileURLWithPath: path)

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
        } catch {
            return
        }
    }

    private func unloadCurrentTrack() {
        audioPlayer?.stop()
        audioPlayer?.delegate = nil
        audioPlayer = nil
        autoreleasepool {
        }
    }

    func togglePause() {
        guard let player = audioPlayer else { return }
        if player.isPlaying {
            player.pause()
            isPaused = true
        } else {
            player.play()
            isPaused = false
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag {
            playNextTrack()
        }
    }

    private func playNextTrack() {
        currentTrackIndex += 1

        if currentTrackIndex >= shuffledPlaylist.count {
            shufflePlaylist()
        }

        loadCurrentTrack()
        if !isPaused {
            audioPlayer?.play()
        }
    }
}
