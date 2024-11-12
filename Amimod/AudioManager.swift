import Foundation

class AudioManager: ObservableObject {
    static let audioManager = AudioManager()
    @Published var isPaused: Bool = false

    let timeInterval: Double = 1.0 / 60.0
    var stream: HSTREAM = 0

    let filePath = Bundle.main.path(forResource: "music", ofType: "mp3")

    init() {
        setupAudio()
    }

    func setupAudio() {
        DispatchQueue.global(qos: .background).async {
            BASS_Init(-1, 48000, 0, nil, nil)
            self.stream = BASS_StreamCreateFile(BOOL32(truncating: false), self.filePath, 0, 0, DWORD(BASS_SAMPLE_LOOP))
            BASS_ChannelPlay(self.stream, 0)
        }
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
