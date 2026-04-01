import Foundation
import AVFoundation
import MediaPlayer
import Combine

@MainActor
class PlayerViewModel: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var playlists: [Playlist] = []
    @Published var genres: [String] = []
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isShuffled = false
    @Published var repeatMode: RepeatMode = .off
    @Published var searchQuery = ""
    @Published var selectedGenre: String?
    @Published var isLoading = false
    @Published var isConnected = false
    @Published var errorMessage: String?

    enum RepeatMode { case off, all, one }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var queue: [Track] = []
    private var currentIndex = -1
    private var cancellables = Set<AnyCancellable>()
    private let api = APIClient.shared

    init() {
        setupAudioSession()
        setupRemoteCommands()

        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.loadTracks() }
            }
            .store(in: &cancellables)
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    func connect() async {
        guard api.isConfigured else { return }
        isLoading = true
        isConnected = await api.testConnection(url: api.baseURL)
        if isConnected {
            await loadTracks()
            await loadPlaylists()
            await loadGenres()
        }
        isLoading = false
    }

    func loadTracks() async {
        do {
            tracks = try await api.fetchTracks(
                query: searchQuery.isEmpty ? nil : searchQuery,
                genre: selectedGenre
            )
        } catch {
            errorMessage = "Failed to load tracks"
        }
    }

    func loadPlaylists() async {
        do {
            playlists = try await api.fetchPlaylists()
        } catch {}
    }

    func loadGenres() async {
        do {
            let tags = try await api.fetchTags()
            genres = tags.genres
        } catch {}
    }

    func play(track: Track, from trackList: [Track]? = nil) {
        if let list = trackList {
            queue = isShuffled ? list.shuffled() : list
            currentIndex = queue.firstIndex(of: track) ?? 0
        }

        currentTrack = track
        guard let audioURL = api.audioURL(for: track) else { return }

        if let observer = timeObserver, let p = player {
            p.removeTimeObserver(observer)
        }

        let item = AVPlayerItem(url: audioURL)
        player = AVPlayer(playerItem: item)

        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = time.seconds
                self.duration = self.player?.currentItem?.duration.seconds ?? 0
                if self.duration.isNaN { self.duration = track.duration }
                self.updateNowPlaying()
            }
        }

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                switch self.repeatMode {
                case .one:
                    self.player?.seek(to: .zero)
                    self.player?.play()
                case .all:
                    self.next()
                case .off:
                    if self.currentIndex < self.queue.count - 1 { self.next() }
                    else { self.isPlaying = false }
                }
            }
        }

        player?.play()
        isPlaying = true
        updateNowPlaying()
    }

    func togglePlayPause() {
        guard player != nil else { return }
        if isPlaying { player?.pause() } else { player?.play() }
        isPlaying.toggle()
        updateNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        currentIndex = (currentIndex + 1) % queue.count
        play(track: queue[currentIndex])
    }

    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        guard !queue.isEmpty else { return }
        currentIndex = (currentIndex - 1 + queue.count) % queue.count
        play(track: queue[currentIndex])
    }

    func seek(to time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        currentTime = time
    }

    func toggleShuffle() {
        isShuffled.toggle()
        if isShuffled, let current = currentTrack {
            queue.shuffle()
            if let idx = queue.firstIndex(of: current) {
                queue.remove(at: idx)
                queue.insert(current, at: 0)
                currentIndex = 0
            }
        }
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    func filterByGenre(_ genre: String?) {
        selectedGenre = genre
        Task { await loadTracks() }
    }

    private func updateNowPlaying() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if !track.genre.isEmpty {
            info[MPMediaItemPropertyGenre] = track.genre
        }

        // Load artwork async
        if let coverURL = api.coverURL(for: track) {
            Task.detached {
                if let (data, _) = try? await URLSession.shared.data(from: coverURL),
                   let image = UIImage(data: data) {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    await MainActor.run {
                        var nowPlaying = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                        nowPlaying[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlaying
                    }
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
