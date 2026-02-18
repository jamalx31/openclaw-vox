import SwiftUI

@main
struct OpenClawVoxApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("OpenClaw Vox", systemImage: "waveform") {
            VStack(alignment: .leading, spacing: 10) {
                Text("OpenClaw Vox")
                    .font(.headline)

                Text("Hotkey: \u{2303}\u{2325} Space")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Hotkey backend: \(model.hotkeyBackendLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !model.inputMonitoringGranted {
                    Button("Enable Input Monitoring") {
                        model.requestInputMonitoringAccess()
                    }
                }

                TextField("Agent Name", text: $model.agentName)
                    .textFieldStyle(.roundedBorder)
                TextField("Gateway URL", text: $model.channelBaseURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("Gateway Token", text: $model.channelToken)
                    .textFieldStyle(.roundedBorder)
                TextField("Session", text: $model.sessionId)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Test Connection") {
                        model.testConnection()
                    }
                    .disabled(model.isTestingConnection)

                    Text(model.connectionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Button(model.isRecording ? "Stop Recording" : "Start Recording") {
                    model.toggleRecording()
                }

                Button("Show Overlay") {
                    model.showOverlay()
                }

                Toggle("Auto speak", isOn: $model.autoSpeak)

                Divider()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .padding(12)
            .frame(minWidth: 360, idealWidth: 460)
            .fixedSize(horizontal: false, vertical: true)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
