import SwiftUI

// MARK: - Now Playing (scrub with the crown, like Spotify's watch app)

struct NowPlayingView: View {
    @ObservedObject private var session = WatchSession.shared
    @State private var title = ""
    @State private var artist = ""
    @State private var playing = false
    @State private var time: Double = 0
    @State private var duration: Double = 1
    @State private var crownTime: Double = 0
    @State private var scrubbing = false
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 8) {
            if title.isEmpty {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(session.reachable ? "Play something on the phone" : "Open Amapiano on your iPhone")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(artist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ProgressView(value: min(scrubbing ? crownTime : time, duration), total: max(duration, 1))
                    .tint(.orange)
                HStack {
                    Text(fmt(scrubbing ? crownTime : time))
                    Spacer()
                    Text(fmt(duration))
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

                HStack(spacing: 18) {
                    Button { send("prev") } label: { Image(systemName: "backward.fill") }
                    Button { send("toggle") } label: {
                        Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title)
                    }
                    Button { send("next") } label: { Image(systemName: "forward.fill") }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .focusable()
        .digitalCrownRotation($crownTime, from: 0, through: max(duration, 1), by: max(duration / 60, 1),
                              sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crownTime) { _, newValue in
            scrubbing = true
            scrubTask?.cancel()
            scrubTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                _ = try? await session.request(["action": "seek", "t": newValue])
                scrubbing = false
            }
        }
        .onReceive(poll) { _ in refresh() }
        .onAppear { refresh() }
    }

    @State private var scrubTask: Task<Void, Never>?

    private func refresh() {
        guard !scrubbing else { return }
        Task {
            guard let reply = try? await session.request(["action": "state"]) else { return }
            apply(reply)
        }
    }

    private func send(_ action: String) {
        Task {
            if let reply = try? await session.request(["action": action]) { apply(reply) }
        }
    }

    private func apply(_ reply: [String: Any]) {
        title = reply["title"] as? String ?? ""
        artist = reply["artist"] as? String ?? ""
        playing = reply["playing"] as? Bool ?? false
        time = reply["time"] as? Double ?? 0
        duration = max(reply["duration"] as? Double ?? 1, 1)
        if !scrubbing { crownTime = time }
    }

    private func fmt(_ t: Double) -> String {
        let s = max(0, Int(t.isFinite ? t : 0))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Crates (browse, play, rename, delete, reorder, move nested)

struct WatchCrate: Identifiable {
    let name: String
    let count: Int
    var id: String { name }
    var leafName: String { name.components(separatedBy: " > ").last ?? name }
    var parent: String? {
        let parts = name.components(separatedBy: " > ")
        return parts.count > 1 ? parts.dropLast().joined(separator: " > ") : nil
    }
}

struct CratesView: View {
    @State private var crates: [WatchCrate] = []
    @State private var errorLine: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorLine {
                    Text(errorLine).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(crates) { crate in
                    NavigationLink {
                        WatchCrateDetailView(crate: crate, allCrates: crates, onChanged: { Task { await load() } })
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(crate.leafName).lineLimit(1)
                            HStack(spacing: 4) {
                                if let parent = crate.parent {
                                    Text("in \(parent)").lineLimit(1)
                                }
                                Text("\(crate.count) tracks")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Crates")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        do {
            let json = try await WatchSession.shared.api("GET", "/api/serato/crates") as? [String: Any]
            let list = json?["crates"] as? [[String: Any]] ?? []
            crates = list.filter { ($0["source"] as? String) != "backup" }.map {
                WatchCrate(name: $0["name"] as? String ?? "", count: $0["count"] as? Int ?? 0)
            }
            errorLine = crates.isEmpty ? "No crates yet" : nil
        } catch {
            errorLine = "Phone unreachable"
        }
    }
}

struct WatchCrateDetailView: View {
    let crate: WatchCrate
    let allCrates: [WatchCrate]
    var onChanged: () -> Void

    @State private var tracks: [(id: String, title: String, artist: String)] = []
    @State private var showRename = false
    @State private var newName = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, track in
                Button {
                    Task { _ = try? await WatchSession.shared.request(
                        ["action": "playCrate", "name": crate.name, "index": i]) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(.footnote).lineLimit(1)
                        Text(track.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .onDelete { offsets in
                let removed = offsets.map { tracks[$0].id }
                tracks.remove(atOffsets: offsets)
                Task {
                    for tid in removed {
                        _ = try? await WatchSession.shared.api(
                            "POST", "/api/serato/crates/\(encoded)/remove", body: ["track_id": tid])
                    }
                    onChanged()
                }
            }
            .onMove { from, to in
                tracks.move(fromOffsets: from, toOffset: to)
                Task {
                    _ = try? await WatchSession.shared.api(
                        "POST", "/api/serato/crates/\(encoded)/reorder", body: ["track_ids": tracks.map(\.id)])
                }
            }

            Section {
                Button {
                    newName = crate.leafName
                    showRename = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                if !possibleParents.isEmpty {
                    NavigationLink {
                        MoveCrateView(crate: crate, parents: possibleParents) { dismiss(); onChanged() }
                    } label: {
                        Label("Move to…", systemImage: "folder")
                    }
                }
            }
        }
        .navigationTitle(crate.leafName)
        .task { await load() }
        .sheet(isPresented: $showRename) {
            VStack {
                TextField("Crate name", text: $newName)
                Button("Save") {
                    Task {
                        let full = crate.parent.map { "\($0) > \(newName)" } ?? newName
                        _ = try? await WatchSession.shared.api(
                            "POST", "/api/serato/crates/\(encoded)/rename", body: ["name": full])
                        showRename = false
                        dismiss()
                        onChanged()
                    }
                }
            }
        }
    }

    private var encoded: String {
        crate.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? crate.name
    }

    private var possibleParents: [String] {
        // any crate that isn't this one or inside it can become the parent
        allCrates.map(\.name).filter { $0 != crate.name && !$0.hasPrefix(crate.name + " > ") }
    }

    private func load() async {
        guard let json = try? await WatchSession.shared.api(
            "GET", "/api/serato/crates/\(encoded)/tracks") as? [String: Any] else { return }
        let list = json["tracks"] as? [[String: Any]] ?? []
        tracks = list.map {
            (id: $0["id"] as? String ?? "",
             title: $0["title"] as? String ?? "?",
             artist: $0["artist"] as? String ?? "")
        }
    }
}

struct MoveCrateView: View {
    let crate: WatchCrate
    let parents: [String]
    var onMoved: () -> Void

    var body: some View {
        List {
            Button("Top level") { move(to: nil) }
            ForEach(parents, id: \.self) { parent in
                Button(parent) { move(to: parent) }
            }
        }
        .navigationTitle("Move to")
    }

    private func move(to parent: String?) {
        Task {
            let encoded = crate.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? crate.name
            let full = parent.map { "\($0) > \(crate.leafName)" } ?? crate.leafName
            _ = try? await WatchSession.shared.api(
                "POST", "/api/serato/crates/\(encoded)/rename", body: ["name": full])
            onMoved()
        }
    }
}
