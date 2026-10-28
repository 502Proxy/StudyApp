import Foundation
import Testing
@testable import StudyApp

@MainActor
struct CheckStudIPSessionTests {
    let service = FakeStudIPService()
    let store = InMemoryStudIPAccountStore()

    private var check: CheckStudIPSessionUseCase { CheckStudIPSessionUseCase(service: service, store: store) }

    private func session(_ cookie: String) -> StudIPCredentials {
        StudIPCredentials(
            account: StudIPAccount(serverURL: URL(string: "https://elearning.uni-oldenburg.de")!, username: "abcd1234"),
            authorization: .session(cookieHeader: cookie)
        )
    }

    @Test func reportsNotConnectedWithoutCredentials() async {
        #expect(await check() == .notConnected)
    }

    @Test func acceptedSessionIsValid() async throws {
        try store.save(session(service.acceptedSession))
        #expect(await check() == .valid)
    }

    @Test func rejectedSessionOrPasswordIsExpired() async throws {
        try store.save(session("Seminar_Session=abgelaufen"))
        #expect(await check() == .expired)

        try store.save(StudIPCredentials(account: session("").account, password: "falsch"))
        #expect(await check() == .expired)
    }
}
