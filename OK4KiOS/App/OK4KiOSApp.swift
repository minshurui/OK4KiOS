import SwiftUI

@main
struct OK4KiOSApp: App {
    init() {
        configureAudioSession()
        LocalProxyServer.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    private func configureAudioSession() {
        AudioSessionController.shared.activate()
    }
}
