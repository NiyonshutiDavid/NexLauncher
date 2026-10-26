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
            running: [.init(projectName: "CleanPay", kind: .frontend, port: 5173), .init(projectName: "CleanPay", kind: .backend, port: 8000)],
            pinned: [.init(id: "a", name: "CleanPay"), .init(id: "b", name: "Jarama"), .init(id: "c", name: "NVMS")],
            tasks: [.init(title: "Fix login on Safari", projectName: "CleanPay", done: true),
                    .init(title: "Add dark mode", projectName: "Jarama", done: false)],
            openTaskCount: 3))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : SnapshotEntry(date: .now, snapshot: SharedContainer.read(from: Self.directory)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: SharedContainer.read(from: Self.directory))
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

// MARK: - Brand pieces

private struct Brand {
    let theme: Theme
    init(_ scheme: ColorScheme) { theme = .resolve(.ember, dark: scheme == .dark) }
    var gradient: LinearGradient {
        LinearGradient(colors: [Color(red: 1.0, green: 0.455, blue: 0.251), Color(red: 0.812, green: 0.247, blue: 0.055), Color(red: 0.51, green: 0.157, blue: 0.063)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct WidgetHeader: View {
    let title: String
    let symbol: String
    var light = false
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.caption.weight(.bold))
            Text(title.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(0.8)
        }
        .foregroundStyle(light ? Color.white.opacity(0.9) : Color(red: 0.812, green: 0.247, blue: 0.055))
    }
}

// MARK: - Running services

struct RunningServicesView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: SnapshotEntry

    private var limit: Int { family == .systemSmall ? 3 : family == .systemMedium ? 3 : 8 }

    var body: some View {
        let running = entry.snapshot.running
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                WidgetHeader(title: "Running", symbol: "bolt.horizontal.circle.fill", light: true)
                if running.isEmpty {
                    Spacer(minLength: 0)
                    Text("All quiet").font(.title3.weight(.bold)).foregroundStyle(.white)
                    Text("Start a project in NexLauncher").font(.caption).foregroundStyle(.white.opacity(0.8))
                } else {
                    Text("\(running.count)").font(.system(size: 30, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        + Text(" live").font(.callout.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    ForEach(Array(running.prefix(limit).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 6) {
                            Circle().fill(Color.green).frame(width: 7, height: 7).shadow(color: .green, radius: 3)
                            Text(item.projectName).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                            Spacer(minLength: 2)
                            Text(item.port.map { ":\($0)" } ?? item.kind.rawValue).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.16), in: Capsule())
                    }
                }
                Spacer(minLength: 0)
            }
            if family != .systemSmall {
                IllustrationView(running.isEmpty ? .power : .play)
                    .environment(\.theme, .resolve(.ember, dark: true))
                    .frame(width: 92, height: 92)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Quick launch

struct QuickLaunchView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: SnapshotEntry

    var body: some View {
        let brand = Brand(scheme)
        let pinned = entry.snapshot.pinned
        VStack(alignment: .leading, spacing: 7) {
            WidgetHeader(title: "Quick Launch", symbol: "play.circle.fill")
            if pinned.isEmpty {
                Spacer(minLength: 0)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No pins yet").font(.headline).foregroundStyle(brand.theme.fg)
                        Text("Pin projects in NexLauncher").font(.caption).foregroundStyle(brand.theme.fg2)
                    }
                    Spacer()
                    IllustrationView(.pin).environment(\.theme, brand.theme).frame(width: 60, height: 60)
                }
                Spacer(minLength: 0)
            } else {
                let columns = family == .systemSmall ? 1 : 2
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                    ForEach(Array(pinned.prefix(family == .systemSmall ? 3 : 6).enumerated()), id: \.offset) { _, project in
                        Link(destination: Self.url(for: project.id)) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 18, height: 18).background(brand.gradient, in: Circle())
                                Text(project.name).font(.caption.weight(.semibold)).foregroundStyle(brand.theme.fg).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 7).padding(.vertical, 6)
                            .background(brand.theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
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

// MARK: - Tasks

struct TasksView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: SnapshotEntry

    var body: some View {
        let brand = Brand(scheme)
        let tasks = entry.snapshot.tasks
        let limit = family == .systemSmall ? 3 : family == .systemMedium ? 4 : 9
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "Tasks", symbol: "checklist")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(entry.snapshot.openTaskCount)").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(brand.theme.fg)
                    Text("open").font(.caption.weight(.semibold)).foregroundStyle(brand.theme.fg2)
                }
                if tasks.isEmpty {
                    Text("Add tasks to your projects in NexLauncher").font(.caption).foregroundStyle(brand.theme.fg2)
                }
                ForEach(Array(tasks.prefix(limit).enumerated()), id: \.offset) { _, task in
                    HStack(spacing: 6) {
                        Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                            .font(.caption).foregroundStyle(task.done ? brand.theme.accent : brand.theme.fg3)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(task.title).font(.caption.weight(.medium)).strikethrough(task.done)
                                .foregroundStyle(task.done ? brand.theme.fg2 : brand.theme.fg).lineLimit(1)
                            if family != .systemSmall { Text(task.projectName).font(.system(size: 9)).foregroundStyle(brand.theme.fg3).lineLimit(1) }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            if family != .systemSmall {
                IllustrationView(.checklist).environment(\.theme, brand.theme).frame(width: 84, height: 84)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Widgets

private struct SoftBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let theme = Theme.resolve(.ember, dark: scheme == .dark)
        ZStack {
            theme.surface
            LinearGradient(colors: [theme.accentSoft, theme.surface], startPoint: .topTrailing, endPoint: .bottomLeading)
            Circle().fill(theme.accent.opacity(scheme == .dark ? 0.20 : 0.12)).frame(width: 160).blur(radius: 40).offset(x: 90, y: -60)
        }
    }
}

struct RunningServicesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RunningServices", provider: SnapshotProvider()) { entry in
            RunningServicesView(entry: entry).containerBackground(for: .widget) { Brand(.light).gradient }
        }
        .configurationDisplayName("Running Services")
        .description("Your live dev servers and their ports.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct QuickLaunchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickLaunch", provider: SnapshotProvider()) { entry in
            QuickLaunchView(entry: entry).containerBackground(for: .widget) { SoftBackground() }
        }
        .configurationDisplayName("Quick Launch")
        .description("Start your pinned projects with one click.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Tasks", provider: SnapshotProvider()) { entry in
            TasksView(entry: entry).containerBackground(for: .widget) { SoftBackground() }
        }
        .configurationDisplayName("Tasks")
        .description("What you've finished and what's still open across your projects.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct NexWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RunningServicesWidget()
        QuickLaunchWidget()
        TasksWidget()
    }
}
