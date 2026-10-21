import SwiftUI

/// Anmeldung bei Stud.IP in den Einstellungen: im Browserfenster (auch mit 2FA) oder per Passwort.
struct StudIPSettingsSection: View {
    @Bindable var viewModel: StudIPViewModel

    @State private var server = StudIPViewModel.defaultServer
    @State private var username = ""
    @State private var password = ""
    @State private var formError: String?
    @State private var isConnecting = false
    @State private var showsPasswordLogin = false
    @State private var webLogin: WebLogin?

    /// Server, für den das Anmeldefenster offen ist.
    private struct WebLogin: Identifiable {
        let server: URL
        var id: String { server.absoluteString }
    }

    private var canConnect: Bool {
        !server.trimmed.isEmpty && !username.trimmed.isEmpty && !password.isEmpty && !isConnecting
    }

    var body: some View {
        Section {
            if let account = viewModel.account {
                connectedRows(account)
            } else {
                loginRows
            }
        } header: {
            Text("Stud.IP")
        } footer: {
            Text(viewModel.isConnected
                 ? "Ordne Module über die Seitenleiste („+“ → „Stud.IP-Veranstaltungen zuordnen …“) zu. Neue Folien und Dateien landen dann automatisch im Modul."
                 : "Mit deinem Uni-Login lädt StudyApp neue Folien und Dateien direkt aus deinen Veranstaltungen. Zugangsdaten bzw. Sitzung liegen nur im Schlüsselbund deines Macs.")
        }
        .sheet(item: $webLogin) { login in
            StudIPWebLoginSheet(server: login.server) { cookieHeader in
                await viewModel.connect(server: login.server, cookieHeader: cookieHeader)
            }
        }
    }

    // MARK: Angemeldet

    @ViewBuilder
    private func connectedRows(_ account: StudIPAccount) -> some View {
        if viewModel.sessionExpired {
            HStack {
                Label("Sitzung abgelaufen – Abgleich pausiert", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                Spacer()
                Button("Erneut anmelden …") { webLogin = WebLogin(server: account.serverURL) }
                    .buttonStyle(.borderedProminent)
            }
        }
        LabeledContent("Angemeldet als", value: account.username)
        LabeledContent("Server", value: account.serverURL.host ?? account.serverURL.absoluteString)
        LabeledContent("Anmeldung", value: viewModel.usesBrowserLogin ? "Browser (mit 2FA)" : "Passwort")
        Toggle("Neue Folien und Dateien automatisch laden", isOn: $viewModel.autoSyncSlides)
        if let lastSync = viewModel.lastSync {
            LabeledContent("Letzter Abgleich", value: lastSync.formatted(date: .abbreviated, time: .shortened))
        }
        HStack {
            Button("Jetzt abgleichen") {
                Task { await viewModel.syncNow() }
            }
            .disabled(viewModel.isSyncing || viewModel.sessionExpired)
            if viewModel.isSyncing {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button("Abmelden", role: .destructive) { viewModel.disconnect() }
        }
    }

    // MARK: Anmelden

    @ViewBuilder
    private var loginRows: some View {
        TextField("Server", text: $server, prompt: Text(StudIPViewModel.defaultServer))
        HStack {
            Text("Empfohlen, auch mit Zwei-Faktor-Anmeldung")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("Im Browser anmelden …", action: openWebLogin)
                .buttonStyle(.borderedProminent)
                .disabled(server.trimmed.isEmpty)
        }
        if let formError {
            Label(formError, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(Theme.danger)
        }
        DisclosureGroup("Mit Passwort anmelden (ohne 2FA)", isExpanded: $showsPasswordLogin) {
            TextField("Stud.IP-Nutzername", text: $username)
                .textContentType(.username)
            SecureField("Passwort", text: $password)
                .textContentType(.password)
                .onSubmit(connectWithPassword)
            HStack {
                Spacer()
                if isConnecting {
                    ProgressView().controlSize(.small)
                }
                Button("Verbinden", action: connectWithPassword)
                    .disabled(!canConnect)
            }
        }
    }

    private func openWebLogin() {
        do {
            formError = nil
            webLogin = WebLogin(server: try StudIPServerURL.normalized(server))
        } catch {
            formError = error.localizedDescription
        }
    }

    private func connectWithPassword() {
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
