import SwiftUI
import WebKit

/// Anmeldung bei Stud.IP in einem eingebetteten Browser – funktioniert auch mit Zwei-Faktor-Anmeldung.
/// Nach jedem Seitenaufruf werden die Cookies geprüft; sobald die Sitzung angemeldet ist, schließt sich das Fenster.
struct StudIPWebLoginSheet: View {
    let server: URL
    /// Prüft einen Cookie-Header und übernimmt ihn bei Erfolg.
    let onSession: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var isChecking = false

    /// `again=yes` zeigt die Anmeldeseite auch dann, wenn Stud.IP sonst die Startseite für Gäste öffnet.
    private var loginURL: URL {
        var components = URLComponents(url: server.appendingPathComponent("index.php"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "again", value: "yes")]
        return components?.url ?? server
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bei Stud.IP anmelden")
                        .font(Theme.Typography.title)
                    Text("Melde dich wie gewohnt an, auch mit dem Code deiner Zwei-Faktor-Anmeldung. Das Fenster schließt sich danach von selbst.")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if isChecking {
                    ProgressView().controlSize(.small)
                }
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            StudIPLoginWebView(url: loginURL, server: server) { cookieHeader in
                isChecking = true
                let connected = await onSession(cookieHeader)
                isChecking = false
                if connected { dismiss() }
                return connected
            }
        }
        .frame(width: 760, height: 680)
        .background(Theme.surface)
    }
}

private struct StudIPLoginWebView: NSViewRepresentable {
    let url: URL
    let server: URL
    let probe: @MainActor (String) async -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(server: server, probe: probe)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Dauerhafter Speicher: Merkt sich Stud.IP „diesem Gerät vertrauen“, fragt es beim nächsten Mal nicht erneut nach dem Code.
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let server: URL
        private let probe: @MainActor (String) async -> Bool
        private var isProbing = false
        /// Eine weitere Seite wurde geladen, während noch geprüft wurde – danach erneut prüfen.
        private var needsRecheck = false
        private var isDone = false

        init(server: URL, probe: @escaping @MainActor (String) async -> Bool) {
            self.server = server
            self.probe = probe
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !isDone else { return }
            guard !isProbing else {
                needsRecheck = true
                return
            }
            isProbing = true
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            Task {
                repeat {
                    needsRecheck = false
                    let cookies = await cookieStore.allCookies()
                    if let header = StudIPSessionCookies.header(for: cookies, server: server), await probe(header) {
                        isDone = true
                    }
                } while needsRecheck && !isDone
                isProbing = false
            }
        }
    }
}
