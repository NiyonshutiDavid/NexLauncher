import WidgetKit
import SwiftUI

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SnapshotProvider: TimelineProvider {
    /// The sandboxed widget reads the real home folder through a read-only entitlement exception.
    static var directory: URL { AppSettings.supportDirectory }

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: WidgetSnapshot(
            running: [.init(projectName: "CleanPay", kind: .frontend, port: 5173)],
            pinned: [.init(id: "x", name: "CleanPay")]))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : SnapshotEntry(date: .now, snapshot: SharedContainer.read(from: Self.directory)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: SharedContainer.read(from: Self.directory))
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct RunningServicesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var limit: Int { family == .systemSmall ? 3 : family == .systemMedium ? 4 : 9 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Running", systemImage: "bolt.horizontal.circle.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if entry.snapshot.running.isEmpty {
                Spacer()
                Text("Nothing running").font(.headline)
                Text("Start a project from NexLauncher").font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(entry.snapshot.running.prefix(limit).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Circle().fill(.green).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.projectName).font(.callout.weight(.medium)).lineLimit(1)
                            Text(item.kind.rawValue + (item.port.map { " · :\($0)" } ?? ""))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if entry.snapshot.running.count > limit {
                    Text("+\(entry.snapshot.running.count - limit) more").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct QuickLaunchView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Quick Launch", systemImage: "play.circle.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if entry.snapshot.pinned.isEmpty {
                Spacer()
                Text("No pinned projects").font(.headline)
                Text("Pin projects in NexLauncher Settings").font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(entry.snapshot.pinned.prefix(family == .systemSmall ? 3 : 5).enumerated()), id: \.offset) { _, project in
                    Link(destination: Self.url(for: project.id)) {
                        HStack {
                            Image(systemName: "play.fill").font(.caption)
                            Text(project.name).font(.callout.weight(.medium)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.quaternary, in: Capsule())
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    static func url(for id: String) -> URL {
        var c = URLComponents(string: "nexlauncher://run")!
        c.queryItems = [URLQueryItem(name: "project", value: id)]
        return c.url!
    }
}

struct RunningServicesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RunningServices", provider: SnapshotProvider()) { entry in
            RunningServicesView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Running Services")
        .description("See which dev servers are running and on which ports.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct QuickLaunchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickLaunch", provider: SnapshotProvider()) { entry in
            QuickLaunchView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Launch")
        .description("Start your pinned projects with one click.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct NexWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RunningServicesWidget()
        QuickLaunchWidget()
    }
}
