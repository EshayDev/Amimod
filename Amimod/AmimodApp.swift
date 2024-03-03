import SwiftUI

@main
struct AmimodApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var audioManager = AudioManager.audioManager
    @State private var isPaused: Bool = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(audioManager)
                .frame(minWidth: 500, idealWidth: 500, maxWidth: .infinity, minHeight: 400, idealHeight: 400, maxHeight: .infinity)
                .toolbar {
                    // Add a music toggle button to the toolbar
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            audioManager.togglePause()
                            isPaused = audioManager.isPaused
                        }) {
                            Image(systemName: isPaused ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        }
                    }
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
