import AVFoundation
import Foundation
import SwiftUI

class AudioManager: ObservableObject {
    static let audioManager = AudioManager()
    @Published var isPaused: Bool = false

    var audioPlayer: AVAudioPlayer?

    init() {
        setupAudio()
    }

    func setupAudio() {
        guard let path = Bundle.main.path(forResource: "music", ofType: "mp3") else {
            print("Music file not found.")
            return
        }

        let url = URL(fileURLWithPath: path)

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("Failed to initialize AVAudioPlayer: \(error.localizedDescription)")
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
}
