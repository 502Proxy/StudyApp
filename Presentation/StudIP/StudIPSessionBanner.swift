import SwiftUI

/// Banner at the top of the main window while the Stud.IP session is expired. Signing in opens the
/// browser sign-in (with two-factor authentication); the banner can be dismissed until the next launch.
struct StudIPSessionBanner: View {
    let viewModel: StudIPViewModel
    let onDismiss: () -> Void
    @State private var isSigningIn = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Stud.IP-Sitzung abgelaufen")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("Neue Folien und Dateien werden erst nach einer neuen Anmeldung geladen.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 12)
            Button("Jetzt anmelden …") { isSigningIn = true }
                .buttonStyle(.borderedProminent)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Bis zum nächsten Start ausblenden")
            .accessibilityLabel("Hinweis ausblenden")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.warning.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
        .sheet(isPresented: $isSigningIn) {
            let server = viewModel.loginServer
            StudIPWebLoginSheet(server: server) { cookieHeader in
                await viewModel.connect(server: server, cookieHeader: cookieHeader)
            }
        }
    }
}
