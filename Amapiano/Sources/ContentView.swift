import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var player: PlayerViewModel

    @State private var ready = false
    @State private var checking = true

    var body: some View {
        Group {
            if checking {
                VStack {
                    Spacer()
                    Text("AMAPIANO")
                        .font(.system(size: 36, weight: .black))
                        .foregroundStyle(Color.accentOrange)
                    ProgressView("Connecting...")
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                    Spacer()
                }
            } else if ready {
                MainTabView()
            } else {
                SetupView()
            }
        }
        .task { await smartConnect() }
    }

    func smartConnect() async {
        // Try all known URLs quickly
        let urls = [
            UserDefaults.standard.string(forKey: "serverURL") ?? "",
            "http://100.97.199.99:8766",  // Tailscale
            "http://192.168.1.162:8766",   // Local WiFi
        ].filter { !$0.isEmpty }

        for url in urls {
            if await APIClient.shared.testConnection(url: url, timeout: 3) {
                APIClient.shared.baseURL = url
                await player.connect()
                if player.isConnected {
                    ready = true
                    checking = false
                    return
                }
            }
        }
        checking = false
    }
}

// MARK: - Setup
struct SetupView: View {
    @EnvironmentObject var player: PlayerViewModel
    @State private var serverIP = ""
    @State private var testing = false
    @State private var error = false
    @State private var autoConnecting = true

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("AMAPIANO")
                .font(.system(size: 36, weight: .black))
                .foregroundStyle(Color.accentOrange)

            if autoConnecting {
                ProgressView("Finding server...")
                    .foregroundStyle(.secondary)
            } else {
                Text("Connect to your music server")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                TextField("Server IP (e.g. 192.168.1.162)", text: $serverIP)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()

                if error {
                    Text("Could not connect. Make sure server is running.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await testAndConnect() }
                } label: {
                    HStack {
                        if testing { ProgressView().tint(.white) }
                        Text(testing ? "Connecting..." : "Connect")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(Color.accentOrange)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
                .disabled(serverIP.isEmpty || testing)
            }
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
        .task { await autoConnect() }
    }

    func testAndConnect() async {
        testing = true
        error = false
        // Clean up input — handle if user types full URL, just IP, or IP:port
        var input = serverIP.trimmingCharacters(in: .whitespacesAndNewlines)
        input = input.replacingOccurrences(of: "http://", with: "")
        input = input.replacingOccurrences(of: "https://", with: "")
        if input.contains(":") {
            // Already has port
            let url = "http://\(input)"
            if await APIClient.shared.testConnection(url: url) {
                APIClient.shared.baseURL = url
                await player.connect()
                testing = false
                return
            }
        }
        // Just an IP — add port
        let url = "http://\(input):8766"
        if await APIClient.shared.testConnection(url: url) {
            APIClient.shared.baseURL = url
            await player.connect()
        } else {
            error = true
        }
        testing = false
    }

    func autoConnect() async {
        // Build list: saved URL first, then known IPs
        var urls: [String] = []
        if let last = UserDefaults.standard.string(forKey: "serverURL"), !last.isEmpty {
            urls.append(last)
        }
        urls += [
            "http://100.97.199.99:8766",  // Tailscale
            "http://192.168.1.162:8766",   // Local WiFi
            "http://127.0.0.1:8766",
        ]
        // Remove duplicates
        var seen = Set<String>()
        urls = urls.filter { seen.insert($0).inserted }

        // Retry up to 3 times — first attempt triggers local network permission dialog on iOS 18+
        for attempt in 1...3 {
            for url in urls {
                if await APIClient.shared.testConnection(url: url) {
                    APIClient.shared.baseURL = url
                    await player.connect()
                    return
                }
            }
            if attempt < 3 {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s between retries
            }
        }

        autoConnecting = false
    }
}

// MARK: - Main Tabs
struct MainTabView: View {
    @EnvironmentObject var player: PlayerViewModel
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if selectedTab == 0 {
                    TracksView()
                } else {
                    PlaylistsView()
                }
            }

            VStack(spacing: 0) {
                if player.currentTrack != nil {
                    MiniPlayer()
                }
                CustomTabBar(selected: $selectedTab)
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}

struct CustomTabBar: View {
    @Binding var selected: Int

    var body: some View {
        HStack {
            tabButton(icon: "music.note.list", label: "Tracks", tag: 0)
            tabButton(icon: "square.stack", label: "Playlists", tag: 1)
        }
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
    }

    func tabButton(icon: String, label: String, tag: Int) -> some View {
        Button {
            selected = tag
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(selected == tag ? Color.accentOrange : .secondary)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Tracks View
struct TracksView: View {
    @EnvironmentObject var player: PlayerViewModel
    @State private var viewMode: ViewMode = .list

    enum ViewMode { case list, grid }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.tertiary)
                        TextField("Search tracks...", text: $player.searchQuery)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                        if !player.searchQuery.isEmpty {
                            Button { player.searchQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Genre chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            genreChip("All", genre: nil)
                            ForEach(player.genres, id: \.self) { g in
                                genreChip(g, genre: g)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }

                    // Cover Flow carousel
                    if !player.tracks.isEmpty && player.selectedGenre == nil && player.searchQuery.isEmpty {
                        CoverFlowView(tracks: Array(player.tracks.prefix(20)))
                            .padding(.bottom, 12)
                    }

                    // View toggle
                    HStack {
                        Text("\(player.tracks.count) tracks")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewMode = viewMode == .list ? .grid : .list
                            }
                        } label: {
                            Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                    // Track list or grid
                    if viewMode == .list {
                        LazyVStack(spacing: 0) {
                            ForEach(player.tracks) { track in
                                TrackRow(track: track)
                                    .onTapGesture {
                                        player.play(track: track, from: player.tracks)
                                    }
                            }
                        }
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 14) {
                            ForEach(player.tracks) { track in
                                GridCard(track: track)
                                    .onTapGesture {
                                        player.play(track: track, from: player.tracks)
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 120)
            }
            .navigationTitle("Amapiano")
            .refreshable { await player.loadTracks() }
        }
    }

    func genreChip(_ label: String, genre: String?) -> some View {
        let isActive = player.selectedGenre == genre
        return Button {
            player.filterByGenre(genre)
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(isActive ? Color.accentOrange : Color.white.opacity(0.08))
                .foregroundStyle(isActive ? .white : .secondary)
                .cornerRadius(16)
        }
    }
}

// MARK: - Cover Flow
struct CoverFlowView: View {
    let tracks: [Track]
    @EnvironmentObject var player: PlayerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recently Added")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(tracks) { track in
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack(alignment: .bottomTrailing) {
                                if let coverURL = APIClient.shared.coverURL(for: track) {
                                    AsyncImage(url: coverURL) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        coverPlaceholder
                                    }
                                } else {
                                    coverPlaceholder
                                }

                                // Play overlay
                                Circle()
                                    .fill(Color.accentOrange.opacity(0.9))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white)
                                            .offset(x: 1)
                                    )
                                    .padding(6)
                            }
                            .frame(width: 150, height: 150)
                            .cornerRadius(10)
                            .clipped()

                            Text(track.title)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if !track.genre.isEmpty {
                                Text(track.genre)
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(6)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(width: 150)
                        .onTapGesture {
                            player.play(track: track, from: tracks)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    var coverPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Grid Card
struct GridCard: View {
    let track: Track
    @EnvironmentObject var player: PlayerViewModel
    @State private var showEditSheet = false

    var isCurrent: Bool { player.currentTrack?.id == track.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                if let coverURL = APIClient.shared.coverURL(for: track) {
                    AsyncImage(url: coverURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        artPlaceholder
                    }
                } else {
                    artPlaceholder
                }

                if isCurrent && player.isPlaying {
                    Color.black.opacity(0.5)
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.accentOrange)
                        .symbolEffect(.variableColor.iterative)
                }
            }
            .aspectRatio(1, contentMode: .fill)
            .cornerRadius(8)
            .clipped()

            Text(track.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isCurrent ? Color.accentOrange : .primary)
                .lineLimit(1)
            Text(track.artist)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contextMenu {
            Button { showEditSheet = true } label: {
                Label("Edit Track", systemImage: "pencil")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            TrackEditSheet(track: track)
        }
    }

    var artPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note")
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Track Row
struct TrackRow: View {
    let track: Track
    @EnvironmentObject var player: PlayerViewModel
    @State private var showEditSheet = false

    var isCurrent: Bool { player.currentTrack?.id == track.id }

    var body: some View {
        HStack(spacing: 12) {
            // Cover art
            ZStack {
                if let coverURL = APIClient.shared.coverURL(for: track) {
                    AsyncImage(url: coverURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        artPlaceholder
                    }
                } else {
                    artPlaceholder
                }

                if isCurrent && player.isPlaying {
                    Color.black.opacity(0.5)
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.accentOrange)
                        .symbolEffect(.variableColor.iterative)
                }
            }
            .frame(width: 48, height: 48)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 15, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.accentOrange : .primary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if !track.genre.isEmpty {
                        Text(track.genre)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(6)
                            .foregroundStyle(.tertiary)
                    }
                    if track.flags?.contains("video") == true {
                        FlagBadge(icon: "video.fill", color: .white, bg: Color.black.opacity(0.6))
                    }
                    if track.flags?.contains("lyrics") == true || track.flags?.contains("visualizer") == true {
                        FlagBadge(icon: "text.quote", color: .green, bg: Color.green.opacity(0.15))
                    }
                }
            }

            Spacer()

            // Duration + more button
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatTime(track.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Button {
                    showEditSheet = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 28)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isCurrent ? Color.accentOrange.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .contextMenu {
            Button { showEditSheet = true } label: {
                Label("Edit Track", systemImage: "pencil")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            TrackEditSheet(track: track)
        }
    }

    var artPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note")
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Track Edit Sheet
struct TrackEditSheet: View {
    let track: Track
    @EnvironmentObject var player: PlayerViewModel
    @Environment(\.dismiss) var dismiss
    @State private var genre: String
    @State private var title: String
    @State private var artist: String
    @State private var saving = false
    @State private var addedToPlaylist: String?
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var exportedToSerato = false

    init(track: Track) {
        self.track = track
        _genre = State(initialValue: track.genre)
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Track Info") {
                    HStack {
                        Text("Title")
                            .foregroundStyle(.secondary)
                        TextField("Title", text: $title)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Artist")
                            .foregroundStyle(.secondary)
                        TextField("Artist", text: $artist)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Genre") {
                    TextField("Genre", text: $genre)

                    if !player.genres.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(player.genres, id: \.self) { g in
                                    Button(g) { genre = g }
                                        .font(.system(size: 12, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(genre == g ? Color.accentOrange : Color.white.opacity(0.08))
                                        .foregroundStyle(genre == g ? .white : .secondary)
                                        .cornerRadius(12)
                                }
                            }
                        }
                    }

                    Button("Lookup Genre via Spotify") {
                        Task { await spotifyLookup() }
                    }
                    .foregroundStyle(Color.accentOrange)
                }

                Section("Add to Playlist") {
                    // Create new playlist with this track
                    Button {
                        showNewPlaylist = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.accentOrange)
                            Text("New Playlist...")
                                .foregroundStyle(Color.accentOrange)
                        }
                    }

                    ForEach(player.playlists) { pl in
                        Button {
                            Task {
                                try? await APIClient.shared.addTrackToPlaylist(
                                    playlistId: pl.id, trackId: track.id
                                )
                                // Auto-export updated playlist to Serato
                                _ = try? await APIClient.shared.exportToSerato(playlistId: pl.id)
                                addedToPlaylist = pl.name
                                await player.loadPlaylists()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    addedToPlaylist = nil
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "music.note.list")
                                    .foregroundStyle(.secondary)
                                Text(pl.name)
                                Spacer()
                                if addedToPlaylist == pl.name {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                }
                                Text("\(pl.count ?? 0)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Section("Serato") {
                    Button {
                        Task {
                            // Create a playlist with just this track and export to Serato
                            let name = "\(track.artist) - \(track.title)"
                            let pid = try? await APIClient.shared.createPlaylist(name: name, trackIds: [track.id])
                            if let pid, !pid.isEmpty {
                                _ = try? await APIClient.shared.exportToSerato(playlistId: pid)
                                exportedToSerato = true
                                await player.loadPlaylists()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    exportedToSerato = false
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Color.accentOrange)
                            Text("Export as Serato Crate")
                            Spacer()
                            if exportedToSerato {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(saving)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
        .alert("New Playlist", isPresented: $showNewPlaylist) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Create & Add") {
                guard !newPlaylistName.isEmpty else { return }
                Task {
                    let pid = try? await APIClient.shared.createPlaylist(
                        name: newPlaylistName, trackIds: [track.id]
                    )
                    if let pid, !pid.isEmpty {
                        // Auto-export to Serato crate
                        _ = try? await APIClient.shared.exportToSerato(playlistId: pid)
                        addedToPlaylist = newPlaylistName
                        await player.loadPlaylists()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            addedToPlaylist = nil
                        }
                    }
                    newPlaylistName = ""
                }
            }
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
        }
    }

    func save() async {
        saving = true
        do {
            try await APIClient.shared.updateTrack(
                id: track.id,
                title: title != track.title ? title : nil,
                artist: artist != track.artist ? artist : nil,
                genre: genre != track.genre ? genre : nil
            )
            await player.loadTracks()
            dismiss()
        } catch {}
        saving = false
    }

    func spotifyLookup() async {
        if let g = try? await APIClient.shared.spotifyGenreLookup(title: title, artist: artist) {
            genre = g
        }
    }
}

// MARK: - Playlists
struct PlaylistsView: View {
    @EnvironmentObject var player: PlayerViewModel
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var showSeratoCrates = false
    @State private var seratoCrates: [APIClient.SeratoCrate] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Create + Serato buttons
                    HStack(spacing: 10) {
                        Button {
                            showNewPlaylist = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("New Playlist")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color.accentOrange)
                            .foregroundStyle(.white)
                            .cornerRadius(10)
                        }

                        Button {
                            Task {
                                seratoCrates = (try? await APIClient.shared.fetchSeratoCrates()) ?? []
                                showSeratoCrates = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "square.stack.3d.up")
                                Text("Serato Crates")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Color.white.opacity(0.08))
                            .foregroundStyle(.secondary)
                            .cornerRadius(10)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    LazyVStack(spacing: 0) {
                        ForEach(player.playlists) { pl in
                            NavigationLink(destination: PlaylistDetailView(playlist: pl)) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        LinearGradient(colors: [Color.accentOrange, Color.accentOrange.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        Image(systemName: "music.note.list")
                                            .font(.system(size: 20))
                                            .foregroundStyle(.white)
                                    }
                                    .frame(width: 48, height: 48)
                                    .cornerRadius(10)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pl.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.primary)
                                        Text("\(pl.count ?? 0) tracks")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            }
                            .contextMenu {
                                Button {
                                    Task {
                                        let path = try? await APIClient.shared.exportToSerato(playlistId: pl.id)
                                        if let p = path, !p.isEmpty {
                                            // Exported successfully
                                        }
                                    }
                                } label: {
                                    Label("Export to Serato", systemImage: "square.and.arrow.up")
                                }
                                Button(role: .destructive) {
                                    Task {
                                        try? await APIClient.shared.deletePlaylist(id: pl.id)
                                        await player.loadPlaylists()
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 120)
            }
            .navigationTitle("Playlists")
            .refreshable { await player.loadPlaylists() }
            .alert("New Playlist", isPresented: $showNewPlaylist) {
                TextField("Playlist name", text: $newPlaylistName)
                Button("Create") {
                    guard !newPlaylistName.isEmpty else { return }
                    Task {
                        _ = try? await APIClient.shared.createPlaylist(name: newPlaylistName)
                        newPlaylistName = ""
                        await player.loadPlaylists()
                    }
                }
                Button("Cancel", role: .cancel) { newPlaylistName = "" }
            }
            .sheet(isPresented: $showSeratoCrates) {
                SeratoCratesView(crates: seratoCrates)
            }
        }
    }
}

// MARK: - Serato Crates
struct SeratoCratesView: View {
    let crates: [APIClient.SeratoCrate]
    @EnvironmentObject var player: PlayerViewModel
    @Environment(\.dismiss) var dismiss
    @State private var importing: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(crates) { crate in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(crate.name)
                                .font(.system(size: 15, weight: .medium))
                            HStack(spacing: 8) {
                                Text("\(crate.count) tracks")
                                Text(crate.source)
                                    .foregroundStyle(crate.source == "live" ? .green : .orange)
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task {
                                importing = crate.name
                                try? await APIClient.shared.importSeratoCrate(path: crate.path, name: crate.name)
                                await player.loadPlaylists()
                                importing = nil
                            }
                        } label: {
                            if importing == crate.name {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Text("Import")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Color.accentOrange)
                                    .foregroundStyle(.white)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Serato Crates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct PlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var player: PlayerViewModel
    @State private var tracks: [Track] = []
    @State private var loading = true
    @State private var exporting = false
    @State private var exported = false

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().padding(40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(tracks) { track in
                        TrackRow(track: track)
                            .onTapGesture {
                                player.play(track: track, from: tracks)
                            }
                    }
                }
                .padding(.bottom, 120)
            }
        }
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        exporting = true
                        _ = try? await APIClient.shared.exportToSerato(playlistId: playlist.id)
                        exporting = false
                        exported = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exported = false }
                    }
                } label: {
                    if exporting {
                        ProgressView().scaleEffect(0.7)
                    } else if exported {
                        Image(systemName: "checkmark").foregroundStyle(.green)
                    } else {
                        Label("Export to Serato", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task {
            do {
                let detail = try await APIClient.shared.fetchPlaylist(id: playlist.id)
                tracks = detail.tracks
            } catch {}
            loading = false
        }
    }
}

// MARK: - Mini Player
struct MiniPlayer: View {
    @EnvironmentObject var player: PlayerViewModel
    @State private var showFullPlayer = false

    var body: some View {
        if let track = player.currentTrack {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let pct = player.duration > 0 ? player.currentTime / player.duration : 0
                    Rectangle()
                        .fill(Color.accentOrange)
                        .frame(width: geo.size.width * pct)
                }
                .frame(height: 2)
                .background(Color.white.opacity(0.08))

                HStack(spacing: 12) {
                    if let coverURL = APIClient.shared.coverURL(for: track) {
                        AsyncImage(url: coverURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.white.opacity(0.08)
                        }
                        .frame(width: 40, height: 40)
                        .cornerRadius(6)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button { player.previous() } label: {
                        Image(systemName: "backward.fill").font(.system(size: 16))
                    }
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20))
                    }
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.system(size: 16))
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)
            .onTapGesture { showFullPlayer = true }
            .fullScreenCover(isPresented: $showFullPlayer) {
                FullPlayerView(isPresented: $showFullPlayer)
            }
        }
    }
}

// MARK: - Full Player
struct FullPlayerView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var player: PlayerViewModel
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { isPresented = false } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
                Spacer()
                Text("Now Playing")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal, 8)

            Spacer()

            if let track = player.currentTrack {
                if let coverURL = APIClient.shared.coverURL(for: track) {
                    AsyncImage(url: coverURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        artPlaceholderLarge
                    }
                    .frame(width: 300, height: 300)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.4), radius: 20)
                } else {
                    artPlaceholderLarge
                        .frame(width: 300, height: 300)
                        .cornerRadius(16)
                }

                Spacer().frame(height: 32)

                VStack(spacing: 4) {
                    Text(track.title)
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(track.artist)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 28)

                VStack(spacing: 4) {
                    Slider(value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ), in: 0...max(player.duration, 1))
                    .tint(Color.accentOrange)

                    HStack {
                        Text(formatTime(player.currentTime))
                        Spacer()
                        Text("-\(formatTime(max(0, player.duration - player.currentTime)))")
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 24)

                Spacer().frame(height: 20)

                HStack(spacing: 32) {
                    Button { player.toggleShuffle() } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 18))
                            .foregroundStyle(player.isShuffled ? Color.accentOrange : .secondary)
                    }
                    Button { player.previous() } label: {
                        Image(systemName: "backward.fill").font(.system(size: 28))
                    }
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.accentOrange)
                    }
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.system(size: 28))
                    }
                    Button { player.cycleRepeat() } label: {
                        Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                            .font(.system(size: 18))
                            .foregroundStyle(player.repeatMode != .off ? Color.accentOrange : .secondary)
                    }
                }
                .foregroundStyle(.primary)
            }

            Spacer()
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        isPresented = false
                    }
                    withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                }
        )
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
    }

    var artPlaceholderLarge: some View {
        ZStack {
            LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note")
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Flag Badge
struct FlagBadge: View {
    let icon: String
    let color: Color
    let bg: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 18, height: 16)
            .background(bg)
            .cornerRadius(4)
    }
}

// MARK: - Helpers
extension Color {
    static let accentOrange = Color(red: 1.0, green: 0.333, blue: 0.0)
}

func formatTime(_ seconds: Double) -> String {
    guard !seconds.isNaN && seconds >= 0 else { return "0:00" }
    let m = Int(seconds) / 60
    let s = Int(seconds) % 60
    return "\(m):\(String(format: "%02d", s))"
}
