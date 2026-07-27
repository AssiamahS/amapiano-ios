import SwiftUI

@main
struct AmapianoWatchApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            NowPlayingView()
            UpNextView()
            CratesView()
            WatchLibraryView()
            WatchSearchView()
        }
        .tabViewStyle(.verticalPage)
    }
}
