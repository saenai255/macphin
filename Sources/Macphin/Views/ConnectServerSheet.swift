import SwiftUI

struct ConnectServerSheet: View {
    let window: WindowState

    @State private var address = ""
    @State private var user = ""
    @State private var password = ""
    @State private var remember = true
    @Environment(\.dismiss) private var dismiss

    private var parsed: URL? { RemoteMounter.parse(address) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect to Server").font(.headline)
            Form {
                TextField("Address:", text: $address, prompt: Text("smb://server/share"))
                TextField("User:", text: $user, prompt: Text("Optional"))
                SecureField("Password:", text: $password, prompt: Text("Optional"))
                Toggle("Add to Network in Places", isOn: $remember)
            }
            Text("Supports smb, afp, nfs, ftp, webdav and webdavs. sftp needs macFUSE and sshfs. Leave the password empty to use the system login prompt or your SSH key.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !PlacesStore.shared.servers.isEmpty {
                Text("Saved servers").font(.subheadline).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(PlacesStore.shared.servers) { server in
                            Button { address = server.url.absoluteString } label: {
                                Label(server.url.absoluteString, systemImage: "network")
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Connect") { connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsed == nil)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func connect() {
        guard let url = parsed else { return }
        if remember { PlacesStore.shared.addServer(url) }
        dismiss()
        window.connect(to: url, user: user.isEmpty ? nil : user, password: password.isEmpty ? nil : password)
    }
}
