import Foundation
import WatchConnectivity

/// Phone side of the watch link. The watch never talks to the Mac directly
/// (no Tailscale on watchOS) — every request lands here and either drives the
/// player or gets proxied to the amapiano server.
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    private weak var player: PlayerViewModel?

    func activate(player: PlayerViewModel) {
        self.player = player
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        let action = message["action"] as? String ?? ""
        Task { @MainActor in
            switch action {
            case "state":
                replyHandler(self.stateSnapshot())
            case "toggle":
                self.player?.togglePlayPause()
                replyHandler(self.stateSnapshot())
            case "next":
                self.player?.next()
                replyHandler(self.stateSnapshot())
            case "prev":
                self.player?.previous()
                replyHandler(self.stateSnapshot())
            case "seek":
                if let t = message["t"] as? Double { self.player?.seek(to: t) }
                replyHandler(self.stateSnapshot())
            case "playCrate":
                await self.playCrate(name: message["name"] as? String ?? "",
                                     index: message["index"] as? Int ?? 0,
                                     trackId: message["trackId"] as? String)
                replyHandler(self.stateSnapshot())
            case "api":
                let reply = await self.proxy(message)
                replyHandler(reply)
            default:
                replyHandler(["error": "unknown action"])
            }
        }
    }

    @MainActor
    private func stateSnapshot() -> [String: Any] {
        guard let player else { return ["playing": false] }
        return [
            "playing": player.isPlaying,
            "title": player.currentTrack?.title ?? "",
            "artist": player.currentTrack?.artist ?? "",
            "time": player.currentTime,
            "duration": player.duration,
        ]
    }

    @MainActor
    private func playCrate(name: String, index: Int, trackId: String? = nil) async {
        guard let player, !name.isEmpty else { return }
        guard let tracks = try? await APIClient.shared.fetchCrateTracks(name: name),
              !tracks.isEmpty else { return }
        // Prefer the id the watch tapped — the index can be stale if the crate
        // changed since the watch last loaded it.
        let resolved = trackId.flatMap { id in tracks.firstIndex(where: { $0.id == id }) }
            ?? min(index, tracks.count - 1)
        player.play(track: tracks[resolved], from: tracks)
    }

    /// Forward a raw API call from the watch to the amapiano server.
    /// message: {action:"api", method:"GET"/"POST", path:"/api/…", body:<json string>}
    private func proxy(_ message: [String: Any]) async -> [String: Any] {
        let path = message["path"] as? String ?? ""
        guard let url = URL(string: APIClient.shared.baseURL + path) else {
            return ["error": "bad path"]
        }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = message["method"] as? String ?? "GET"
        if let body = message["body"] as? String, !body.isEmpty {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body.data(using: .utf8)
        }
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return ["data": String(data: data, encoding: .utf8) ?? "{}"]
        } catch {
            return ["error": error.localizedDescription]
        }
    }
}
