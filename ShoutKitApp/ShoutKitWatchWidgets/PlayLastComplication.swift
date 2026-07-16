import SwiftUI
import WidgetKit

struct PlayLastComplicationEntry: TimelineEntry {
    let date: Date
}

struct PlayLastComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlayLastComplicationEntry {
        PlayLastComplicationEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (PlayLastComplicationEntry) -> Void) {
        completion(PlayLastComplicationEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlayLastComplicationEntry>) -> Void) {
        completion(Timeline(entries: [PlayLastComplicationEntry(date: .now)], policy: .never))
    }
}

struct PlayLastComplication: Widget {
    private let kind = "ShoutKitPlayLastComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlayLastComplicationProvider()) { _ in
            PlayLastComplicationView()
        }
        .configurationDisplayName("Play Last Station")
        .description("Open ShoutKit on Apple Watch and start your most recent station.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

private struct PlayLastComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: "play.fill")
                    Text("Last")
                        .font(.caption2)
                }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ShoutKit")
                            .font(.headline)
                        Text("Play Last")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            default:
                Image(systemName: "play.fill")
            }
        }
        .widgetURL(WatchLaunchRoute.playLastURL)
    }
}
