import SwiftUI
import NexCore
import NexApp

/// "Run Flutter on…": devices that are ready, plus simulators and emulators that can be started from here.
struct FlutterDevicePicker: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    let project: Project
    let dismiss: () -> Void
    @State private var starting: String?

    private var devices: DevicesModel { model.devices }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Run \(project.name) on…").font(.headline).foregroundStyle(theme.fg)
                Spacer()
                if devices.isLoading { ProgressView().controlSize(.small) }
                else { IconButton("arrow.clockwise", help: "Refresh devices") { Task { await devices.refresh() } } }
            }
            if devices.connected.isEmpty && !devices.isLoading {
                Text("No device is ready yet. Start one below.").font(.callout).foregroundStyle(theme.fg2)
            }
            ForEach(devices.connected) { device in
                Button {
                    dismiss()
                    Task { await model.run(project, kinds: [.flutter], flutterDevice: device.id) }
                } label: {
                    HStack {
                        Image(systemName: "play.fill").foregroundStyle(theme.accent)
                        Text(device.name).foregroundStyle(theme.fg)
                        Spacer()
                    }
                    .padding(8).background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            let idleSims = devices.simulators.filter { !$0.isBooted }
            if !idleSims.isEmpty || !devices.avds.isEmpty {
                Divider().overlay(theme.line)
                Text("START A DEVICE").font(.caption.weight(.bold)).tracking(0.6).foregroundStyle(theme.fg3)
                ForEach(DeviceParsers.shortlist(idleSims, limit: 4)) { sim in
                    startRow("iphone", sim.name, sim.runtime, id: sim.udid) { Task { await devices.boot(sim); await waitForDevices(after: 4) } }
                }
                ForEach(devices.avds, id: \.self) { avd in
                    startRow("smartphone", DeviceParsers.displayName(forAVD: avd), "Android emulator", id: avd) {
                        devices.launch(avd: avd); Task { await waitForDevices(after: 12) }
                    }
                }
            }
            if let starting { Label("Starting \(starting)… it appears above when ready.", systemImage: "hourglass").font(.caption).foregroundStyle(theme.fg2) }
        }
        .padding(16)
        .frame(width: 320)
        .task { await devices.refresh() }
    }

    private func startRow(_ symbol: String, _ name: String, _ detail: String, id: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(theme.fg2).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.callout).foregroundStyle(theme.fg)
                Text(detail).font(.caption).foregroundStyle(theme.fg3)
            }
            Spacer()
            Pill("Start", style: .quiet) { starting = name; action() }
        }
    }

    private func waitForDevices(after seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
        await devices.refresh()
        starting = nil
    }
}

/// The Flutter page's devices section: three compact cards that show only what's running.
/// Everything that can be started lives in a scrollable popover behind each card's Launch button.
struct FlutterDevicesPanel: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    @State private var showSimulators = false
    @State private var showEmulators = false
    private var devices: DevicesModel { model.devices }

    private var bootedSims: [SimulatorDevice] { devices.simulators.filter(\.isBooted) }
    private var runningEmulators: [FlutterDevice] { devices.connected.filter { $0.id.hasPrefix("emulator-") } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Devices", actionTitle: devices.isLoading ? nil : "Refresh") { Task { await devices.refresh() } }
            HStack(alignment: .top, spacing: 18) {
                card("iOS Simulators", "iphone") {
                    if bootedSims.isEmpty {
                        idle("No simulator running", devices.simulators.isEmpty ? "Add one in Xcode → Settings → Platforms." : "\(devices.simulators.count) available")
                    }
                    ForEach(bootedSims) { sim in
                        runningRow(sim.name, sim.runtime) {
                            Pill("Shut down", style: .quiet) { Task { await devices.shutdown(sim); await devices.refresh() } }
                        }
                    }
                } footer: {
                    Pill("Launch simulator…", systemImage: "play.fill") { showSimulators = true }
                        .disabled(devices.simulators.isEmpty)
                        .popover(isPresented: $showSimulators, arrowEdge: .bottom) { simulatorList }
                }
                card("Android Emulators", "smartphone") {
                    if runningEmulators.isEmpty {
                        idle("No emulator running", devices.androidHint ?? (devices.avds.isEmpty ? "Create one in Android Studio → Device Manager." : "\(devices.avds.count) from Android Studio"))
                    }
                    ForEach(runningEmulators) { d in runningRow(d.name, d.id) { EmptyView() } }
                } footer: {
                    Pill("Launch emulator…", systemImage: "play.fill") { showEmulators = true }
                        .disabled(devices.avds.isEmpty)
                        .popover(isPresented: $showEmulators, arrowEdge: .bottom) { emulatorList }
                }
                card("Ready to run", "checkmark.seal") {
                    if devices.connected.isEmpty {
                        idle("Nothing ready", "Launch a simulator or emulator.")
                    }
                    ForEach(devices.connected.prefix(4)) { d in runningRow(d.name, d.id) { EmptyView() } }
                    if devices.connected.count > 4 {
                        Text("and \(devices.connected.count - 4) more").font(.caption).foregroundStyle(theme.fg3)
                    }
                } footer: {
                    Text("Pick one when you press Flutter on a project.").font(.caption).foregroundStyle(theme.fg3)
                }
            }
            .animation(.spring(duration: 0.35), value: devices.connected.map(\.id))
            .animation(.spring(duration: 0.35), value: bootedSims.map(\.udid))
        }
        .task { if devices.simulators.isEmpty && devices.avds.isEmpty { await devices.refresh() } }
    }

    // MARK: Popovers

    private var simulatorList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Launch a simulator").font(.headline).foregroundStyle(theme.fg).padding(14)
            Divider().overlay(theme.line)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4, pinnedViews: .sectionHeaders) {
                    ForEach(DeviceParsers.groupedByRuntime(devices.simulators)) { group in
                        Section {
                            ForEach(group.devices) { sim in
                                listRow(sim.name, running: sim.isBooted, busy: devices.busy.contains(sim.udid)) {
                                    Task { await devices.boot(sim); await devices.refresh() }
                                }
                            }
                        } header: {
                            Text(group.runtime.uppercased()).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(theme.fg3)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 6)
                                .background(theme.surface)
                        }
                    }
                }
                .padding(8)
            }
            .frame(height: min(CGFloat(devices.simulators.count) * 40 + CGFloat(DeviceParsers.groupedByRuntime(devices.simulators).count) * 28 + 16, 380))
        }
        .frame(width: 320)
        .background(theme.surface)
    }

    private var emulatorList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Launch an emulator").font(.headline).foregroundStyle(theme.fg).padding(14)
            Divider().overlay(theme.line)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(devices.avds, id: \.self) { avd in
                        listRow(DeviceParsers.displayName(forAVD: avd), running: false, busy: false) {
                            devices.launch(avd: avd)
                            showEmulators = false
                            Task { try? await Task.sleep(for: .seconds(12)); await devices.refresh() }
                        }
                    }
                }
                .padding(8)
            }
            .frame(height: min(CGFloat(devices.avds.count) * 40 + 16, 380))
        }
        .frame(width: 300)
        .background(theme.surface)
    }

    // MARK: Pieces

    private func card<Content: View, Footer: View>(_ title: String, _ symbol: String,
                                                   @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) -> some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol).font(.headline).foregroundStyle(theme.fg)
                if devices.isLoading && devices.simulators.isEmpty && devices.connected.isEmpty {
                    ProgressView().controlSize(.small)
                }
                content()
                Spacer(minLength: 8)
                footer()
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        }
        .hoverLift()
    }

    private func idle(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.callout.weight(.medium)).foregroundStyle(theme.fg2)
            Text(detail).font(.caption).foregroundStyle(theme.fg3).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func runningRow<Trailing: View>(_ name: String, _ detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            PulsingDot(color: .green)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.callout.weight(.medium)).foregroundStyle(theme.fg).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(theme.fg3).lineLimit(1)
            }
            Spacer()
            trailing()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func listRow(_ name: String, running: Bool, busy: Bool, launch: @escaping () -> Void) -> some View {
        HStack {
            Circle().fill(running ? Color.green : theme.line).frame(width: 7, height: 7)
            Text(name).font(.callout).foregroundStyle(theme.fg).lineLimit(1)
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            else if running { Text("Running").font(.caption.weight(.semibold)).foregroundStyle(.green) }
            else { Pill("Launch", style: .quiet, action: launch) }
        }
        .padding(.horizontal, 10).frame(height: 36)
    }
}
