import SwiftUI

/// Anmeldung bei Stud.IP in den Einstellungen.
struct StudIPSettingsSection: View {
    @Bindable var viewModel: StudIPViewModel

    @State private var server = StudIPViewModel.defaultServer
    @State private var username = ""
    @State private var password = ""
    @State private var formError: String?
    @State private var isConnecting = false

    private var canConnect: Bool {
        !server.trimmed.isEmpty && !username.trimmed.isEmpty && !password.isEmpty && !isConnecting
    }

    var body: some View {
        Section {
            if let account = viewModel.account {
                LabeledContent("Angemeldet als", value: account.username)
                LabeledContent("Server", value: account.serverURL.host ?? account.serverURL.absoluteString)
                Toggle("Neue Folien automatisch laden", isOn: $viewModel.autoSyncSlides)
                if let lastSync = viewModel.lastSync {
                    LabeledContent("Letzter Abgleich", value: lastSync.formatted(date: .abbreviated, time: .shortened))
                }
                HStack {
                    Button("Jetzt Folien laden") {
                        Task { await viewModel.syncNow() }
                    }
                    .disabled(viewModel.isSyncing)
                    if viewModel.isSyncing {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Button("Abmelden", role: .destructive) { viewModel.disconnect() }
                }
            } else {
                TextField("Server", text: $server, prompt: Text(StudIPViewModel.defaultServer))
                TextField("Nutzername", text: $username)
                    .textContentType(.username)
                SecureField("Passwort", text: $password)
                    .textContentType(.password)
                    .onSubmit(connect)
                if let formError {
                    Label(formError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
                HStack {
                    Spacer()
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    }
                    Button("Verbinden", action: connect)
                        .disabled(!canConnect)
                }
            }
        } header: {
            Text("Stud.IP")
        } footer: {
            Text(viewModel.isConnected
                 ? "Ordne Module über die Seitenleiste („+“ → „Stud.IP-Veranstaltungen zuordnen …“) zu. Neue PDFs landen dann automatisch in den Folien des Moduls."
                 : "Mit deinem Uni-Login lädt StudyApp neue Folien direkt aus dem Dateibereich deiner Veranstaltungen. Das Passwort liegt nur im Schlüsselbund deines Macs.")
        }
    }

    private func connect() {
        guard canConnect else { return }
        formError = nil
        isConnecting = true
        Task {
            do {
                try await viewModel.connect(server: server, username: username, password: password)
                password = ""
            } catch {
                formError = error.localizedDescription
            }
            isConnecting = false
        }
    }
}
