import SwiftUI

// MARK: - models (mirror /api/sanitize/report)

struct SanitizeReport: Decodable {
    let total_tracks: Int
    let counts: [String: Int]
    let buckets: [String: [SanitizeTrack]]
    let quality_score: Double
}

struct SanitizeTrack: Decodable, Identifiable {
    let id: String
    let artist: String
    let title: String
    let duration: Double?
    let bitrate_kbps: Double?
}

struct SanitizeJob: Decodable {
    let id: String
    let status: String
    let total: Int
    let progress: Int
}

// MARK: - bucket metadata

private let bucketOrder = ["music_video", "live", "lyric_video", "short_preview", "low_bitrate", "unknown"]

private func bucketLabel(_ key: String) -> String {
    switch key {
    case "music_video": return "Music videos"
    case "live": return "Live versions"
    case "lyric_video": return "Lyric videos"
    case "short_preview": return "Cut-off previews"
    case "low_bitrate": return "Low bitrate"
    case "unknown": return "Unclassified"
    default: return key
    }
}

private func bucketIcon(_ key: String) -> String {
    switch key {
    case "music_video": return "video.fill"
    case "live": return "mic.fill"
    case "lyric_video": return "text.quote"
    case "short_preview": return "scissors"
    case "low_bitrate": return "waveform.badge.exclamationmark"
    default: return "questionmark.circle"
    }
}

// MARK: - view

struct SanitizeView: View {
    @State private var report: SanitizeReport?
    @State private var loading = true
    @State private var errorLine: String?
    @State private var job: SanitizeJob?
    @State private var fixing = false

    var body: some View {
        NavigationStack {
            List {
                if let report {
                    scoreSection(report)
                    if let job, job.status != "done" {
                        jobSection(job)
                    }
                    bucketsSection(report)
                } else if let errorLine {
                    Text(errorLine).foregroundStyle(.secondary)
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Sanitize")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func scoreSection(_ report: SanitizeReport) -> some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(report.quality_score))% clean")
                        .font(.title2.bold())
                    Text("\(report.total_tracks) tracks in the library")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await fixAll() }
                } label: {
                    Label(fixing ? "Cleaning…" : "Clean All", systemImage: "sparkles")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.borderedProminent)
                .disabled(fixing)
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Clean All re-downloads audio-only versions of music videos, live takes and cut-off previews, then rewrites your crates.")
        }
    }

    private func jobSection(_ job: SanitizeJob) -> some View {
        Section("Cleaning in progress") {
            HStack {
                ProgressView(value: Double(job.progress), total: Double(max(job.total, 1)))
                Text("\(job.progress)/\(job.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bucketsSection(_ report: SanitizeReport) -> some View {
        Section("Needs attention") {
            ForEach(bucketOrder, id: \.self) { key in
                if let tracks = report.buckets[key], !tracks.isEmpty, key != "unknown" {
                    NavigationLink {
                        SanitizeBucketView(title: bucketLabel(key), tracks: tracks)
                    } label: {
                        Label {
                            Text(bucketLabel(key))
                        } icon: {
                            Image(systemName: bucketIcon(key))
                                .foregroundStyle(Color.accentOrange)
                        }
                        .badge(tracks.count)
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            report = try await APIClient.shared.sanitizeReport()
            errorLine = nil
        } catch {
            errorLine = "Can't reach the Mac — \(error.localizedDescription)"
        }
        loading = false
    }

    private func fixAll() async {
        fixing = true
        defer { fixing = false }
        guard let jobId = try? await APIClient.shared.sanitizeFixAll() else { return }
        while true {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let j = try? await APIClient.shared.sanitizeJob(id: jobId) else { break }
            job = j
            if j.status == "done" || j.status == "error" { break }
        }
        await load()
    }
}

struct SanitizeBucketView: View {
    let title: String
    let tracks: [SanitizeTrack]
    @State private var replaced: Set<String> = []
    @State private var replacing: Set<String> = []

    var body: some View {
        List(tracks) { track in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if replaced.contains(track.id) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if replacing.contains(track.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Replace") {
                        Task { await replace(track) }
                    }
                    .font(.caption.bold())
                    .buttonStyle(.bordered)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func replace(_ track: SanitizeTrack) async {
        replacing.insert(track.id)
        defer { replacing.remove(track.id) }
        if (try? await APIClient.shared.sanitizeReplace(id: track.id)) != nil {
            replaced.insert(track.id)
        }
    }
}
