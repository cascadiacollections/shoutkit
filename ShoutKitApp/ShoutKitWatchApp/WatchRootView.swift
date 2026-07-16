import Persistence
import Playback
import RadioDirectory
import SwiftData
import SwiftUI

struct WatchRootView: View {
    @Environment(\.playbackController) private var playback
    @Query(sort: \RecentStation.playedAt, order: .reverse) private var recents: [RecentStation]

    var body: some View {
        List {
            Section {
                Button {
                    playLastStation()
                } label: {
                    Label(latestRecent?.name ?? "Play Last Station", systemImage: "play.circle.fill")
                }
                .disabled(latestRecent == nil)
            } footer: {
                if latestRecent == nil {
                    Text("Recent stations appear here after your first play.")
                }
            }

            Section("Now Playing") {
                if let playback, let station = playback.currentStation {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(station.name)
                            .font(.headline)
                        Text(trackLine(playback) ?? station.genre)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button(isPlaying(playback) ? "Pause" : "Play") {
                                playback.togglePlayPause()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Stop", systemImage: "stop.fill") {
                                playback.stop()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    Text("Nothing playing right now.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Recent Stations") {
                if recentStations.isEmpty {
                    Text("No recent stations yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentStations, id: \.stationID) { recent in
                        Button {
                            playback?.toggle(recent.station)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recent.name)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(recent.genre)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: symbolName(for: recent.station))
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("ShoutKit")
    }

    private var latestRecent: RecentStation? {
        recents.first
    }

    private var recentStations: [RecentStation] {
        Array(recents.prefix(10))
    }

    private func playLastStation() {
        guard let station = latestRecent?.station else {
            WatchAppDependencies.playLastStation()
            return
        }
        guard let playback else {
            WatchAppDependencies.playLastStation()
            return
        }

        switch playback.phase(for: station) {
        case .playing, .loading:
            break
        case .paused, .failed:
            playback.resume()
        case .idle:
            playback.play(station)
        }
    }

    private func symbolName(for station: Station) -> String {
        guard let playback else { return "play.fill" }
        switch playback.phase(for: station) {
        case .loading:
            return "waveform"
        case .playing:
            return "pause.fill"
        case .paused, .failed, .idle:
            return "play.fill"
        }
    }

    private func trackLine(_ playback: PlaybackController) -> String? {
        guard let track = playback.nowPlaying, let title = track.title else { return nil }
        if let artist = track.artist {
            return "\(title) — \(artist)"
        }
        return title
    }

    private func isPlaying(_ playback: PlaybackController) -> Bool {
        if case .playing = playback.state {
            return true
        }
        return false
    }
}

#Preview {
    NavigationStack {
        WatchRootView()
    }
}
