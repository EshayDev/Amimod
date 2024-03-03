import Foundation

class AudioManager: ObservableObject {
    static let audioManager = AudioManager() // This singleton instantiates the AudioManager class and runs setupAudio()

    let timeInterval: Double = 1.0 / 60.0 // 60 frames per second
    var stream: HSTREAM = 0
    var isPaused: Bool = false

    // Play this song when the app starts:
    let filePath = Bundle.main.path(forResource: "music", ofType: "xm")

    init() { setupAudio() }

    func setupAudio() {
        // Initialize the output device (i.e., speakers) that BASS should use:
        BASS_Init(-1, // device: -1 is the default device
                  48000, // freq: output sample rate is 48,000 sps
                  0, // flags:
                  nil, // win: 0 = the desktop window (use this for console applications)
                  nil) // Unused, set to nil
        // The sample format specified in the freq and flags parameters has no effect on the output on macOS or iOS.
        // The device's native sample format is automatically used.

        stream = BASS_MusicLoad(BOOL32(truncating: false), filePath, 0, 0, DWORD(BASS_SAMPLE_LOOP | BASS_MUSIC_SINCINTER | BASS_MUSIC_RAMP), 0)

        BASS_ChannelPlay(stream, 0) // starts the output
    }

    func togglePause() {
        if isPaused {
            BASS_ChannelPlay(stream, -1)
        } else {
            BASS_ChannelPause(stream)
        }
        isPaused.toggle()
    }
}
