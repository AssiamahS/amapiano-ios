import Foundation
import WatchConnectivity

/// Watch side of the phone link. Every call goes through the iPhone app,
/// which owns playback and the connection to the Mac.
final class WatchSession: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSession()
    @Published var reachable = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.reachable = session.isReachable }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.reachable = session.isReachable }
    }

    func request(_ message: [String: Any]) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { cont in
            WCSession.default.sendMessage(message) { reply in
                cont.resume(returning: reply)
            } errorHandler: { error in
                cont.resume(throwing: error)
            }
        }
    }

    /// Proxy a server API call through the phone and decode the JSON payload.
    func api(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> Any {
        var msg: [String: Any] = ["action": "api", "method": method, "path": path]
        if let body {
            msg["body"] = String(data: try JSONSerialization.data(withJSONObject: body), encoding: .utf8)
        }
        let reply = try await request(msg)
        if let err = reply["error"] as? String { throw NSError(domain: "watch", code: 1, userInfo: [NSLocalizedDescriptionKey: err]) }
        let raw = (reply["data"] as? String)?.data(using: .utf8) ?? Data("{}".utf8)
        return try JSONSerialization.jsonObject(with: raw)
    }
}
