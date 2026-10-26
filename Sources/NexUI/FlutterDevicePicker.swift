import SwiftUI
import NexCore

struct FlutterDevicePicker: View {
    let model: AppModel
    let project: Project
    let dismiss: () -> Void
    @State private var devices: [FlutterDevice]?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run Flutter on…").font(.headline)
            if let devices {
                if devices.isEmpty {
                    Text("No devices found. Is Flutter installed and a simulator booted?")
                        .foregroundStyle(.secondary).frame(width: 240, alignment: .leading)
                }
                ForEach(devices) { device in
                    Button(device.name) {
                        dismiss()
                        Task { await model.run(project, kinds: [.flutter], flutterDevice: device.id) }
                    }
                    .buttonStyle(.glass)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(16)
        .task { devices = await model.flutterDevices() }
    }
}
