import AVFoundation
import Foundation
import SwiftUI

class AudioManager: ObservableObject {
    static let audioManager = AudioManager()
    @AppStorage("isMusicPaused") var isPaused: Bool = false

    var audioPlayer: AVAudioPlayer?

    init() {
        setupAudio()
        if isPaused {
            audioPlayer?.pause()
        } else {
            audioPlayer?.play()
        }
    }

    func setupAudio() {
        guard let path = Bundle.main.path(forResource: "music", ofType: "m4a") else {
            return
        }

        let url = URL(fileURLWithPath: path)

        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.numberOfLoops = -1
        audioPlayer?.prepareToPlay()
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
}
