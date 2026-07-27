import SwiftUI

@main
struct AmapianoApp: App {
    @StateObject private var player = PlayerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .preferredColorScheme(.dark)
                .onAppear { WatchBridge.shared.activate(player: player) }
        }
    }
}
