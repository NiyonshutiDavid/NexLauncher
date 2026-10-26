import SwiftUI
import NexCore

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
                ForEach(idleSims.prefix(4)) { sim in
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

/// The Flutter page's devices section: iOS simulators, Android emulators and what Flutter can run on now.
struct FlutterDevicesPanel: View {
    @Bindable var model: AppModel
    @Environment(\.theme) private var theme
    private var devices: DevicesModel { model.devices }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Devices", actionTitle: devices.isLoading ? nil : "Refresh") { Task { await devices.refresh() } }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 520), spacing: 20)], alignment: .leading, spacing: 20) {
                card("iOS Simulators", "iphone", empty: "No simulators. Add one in Xcode → Settings → Platforms.") {
                    ForEach(devices.simulators) { sim in
                        row(sim.name, sim.runtime, booted: sim.isBooted, busy: devices.busy.contains(sim.udid)) {
                            if sim.isBooted { Pill("Shut down", style: .quiet) { Task { await devices.shutdown(sim); await devices.refresh() } } }
                            else { Pill("Launch", systemImage: "play.fill") { Task { await devices.boot(sim); await devices.refresh() } } }
                        }
                    }
                } isEmpty: { devices.simulators.isEmpty }
                card("Android Emulators", "smartphone", empty: devices.androidHint ?? "No virtual devices. Create one in Android Studio → Device Manager.") {
                    ForEach(devices.avds, id: \.self) { avd in
                        // Flutter names a running emulator by its system image, not its AVD name; only infer it when there is one AVD.
                        let running = devices.avds.count == 1 && devices.connected.contains { $0.id.hasPrefix("emulator-") }
                        row(DeviceParsers.displayName(forAVD: avd), "From Android Studio", booted: running, busy: false) {
                            Pill(running ? "Running" : "Launch", style: running ? .quiet : .prominent, systemImage: running ? nil : "play.fill") {
                                if !running { devices.launch(avd: avd); Task { try? await Task.sleep(for: .seconds(12)); await devices.refresh() } }
                            }
                        }
                    }
                } isEmpty: { devices.avds.isEmpty }
                card("Ready to run", "checkmark.seal", empty: "Nothing ready. Launch a simulator or emulator.") {
                    ForEach(devices.connected) { d in row(d.name, d.id, booted: true, busy: false) { EmptyView() } }
                } isEmpty: { devices.connected.isEmpty }
            }
        }
        .task { if devices.simulators.isEmpty && devices.avds.isEmpty { await devices.refresh() } }
    }

    private func card<Content: View>(_ title: String, _ symbol: String, empty: String, @ViewBuilder content: () -> Content, isEmpty: () -> Bool) -> some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol).font(.headline).foregroundStyle(theme.fg)
                if devices.isLoading && isEmpty() { ProgressView().controlSize(.small) }
                else if isEmpty() { Text(empty).font(.callout).foregroundStyle(theme.fg2).fixedSize(horizontal: false, vertical: true) }
                content()
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row<Trailing: View>(_ name: String, _ detail: String, booted: Bool, busy: Bool, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Circle().fill(booted ? Color.green : theme.line).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.callout.weight(.medium)).foregroundStyle(theme.fg).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(theme.fg3).lineLimit(1)
            }
            Spacer()
            if busy { ProgressView().controlSize(.small) } else { trailing() }
        }
    }
}
