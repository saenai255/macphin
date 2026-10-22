import SwiftUI

struct SettingsView: View {
    @AppStorage("restoreSession") private var restoreSession = true
    @State private var isDefault = DefaultFileManager.isEnabled
    @State private var opensAtLogin = DefaultFileManager.opensAtLogin
    @State private var error: String?

    var body: some View {
        Form {
            Toggle("Restore windows and tabs from the previous session", isOn: $restoreSession)
            Section("Default File Manager") {
                Toggle("Use Macphin instead of Finder", isOn: Binding(get: { isDefault }, set: setDefault))
                Text("Folders opened from other apps, the Dock and Terminal (`open ~/Documents`) open in Macphin, and “Show in Finder” requests from apps come here once those apps are relaunched. Finder keeps running for the Desktop and Trash. Turn this off to hand everything back to Finder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Open Macphin at login", isOn: Binding(get: { opensAtLogin }, set: setOpensAtLogin))
                if !DefaultFileManager.isInstalledInApplications {
                    Text("Tip: move Macphin to /Applications (`./build-app.sh --install`) before making it the default.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("Privacy") {
                Text("Folders like Mail, Safari or other apps’ data need Full Disk Access to open in Macphin.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Full Disk Access Settings…") { Privacy.openFullDiskAccessSettings() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setDefault(_ enabled: Bool) {
        error = nil
        Task {
            do {
                try await DefaultFileManager.setEnabled(enabled)
            } catch {
                self.error = "Could not change the default file manager: \(error.localizedDescription)"
            }
            isDefault = DefaultFileManager.isEnabled
        }
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        error = nil
        do {
            try DefaultFileManager.setOpensAtLogin(enabled)
        } catch {
            self.error = "Could not change the login item: \(error.localizedDescription)"
        }
        opensAtLogin = DefaultFileManager.opensAtLogin
    }
}
