import SwiftUI

@main
struct AmapianoWatchApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Shared tab selection so any screen can jump straight back to Now Playing.
final class WatchNav: ObservableObject {
    static let shared = WatchNav()
    @Published var tab = 0
}

struct RootView: View {
    @ObservedObject private var nav = WatchNav.shared

    var body: some View {
        TabView(selection: $nav.tab) {
            NowPlayingView().tag(0)
            UpNextView().tag(1)
            CratesView().tag(2)
            WatchLibraryView().tag(3)
            WatchSearchView().tag(4)
        }
        .tabViewStyle(.verticalPage)
    }
}

extension View {
    /// One-tap jump to Now Playing from any browse screen — keeps the
    /// navigation stack you were in, so swiping back returns to your spot.
    func nowPlayingShortcut() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    WatchNav.shared.tab = 0
                } label: {
                    Image(systemName: "waveform")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
