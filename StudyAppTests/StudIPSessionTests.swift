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

@MainActor
struct StudIPSessionRefreshTests {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_760_000_000)
    }

    let service = FakeStudIPService()
    let store = InMemoryStudIPAccountStore()
    let slides = FakeSlideDocumentRepository()
    private let clock = Clock()

    private func makeViewModel() -> StudIPViewModel {
        StudIPViewModel(
            service: service,
            store: store,
            moduleRepository: FakeModuleRepository(),
            slideRepository: slides,
            importer: ImportSlideDocumentUseCase(repository: slides, storage: FakeFileStorage(), inspector: FakeInspector(pages: 3)),
            now: { [clock] in clock.now }
        )
    }

    private func saveSession(_ cookie: String) throws {
        try store.save(StudIPCredentials(
            account: StudIPAccount(serverURL: URL(string: "https://elearning.uni-oldenburg.de")!, username: "abcd1234"),
            authorization: .session(cookieHeader: cookie)
        ))
    }

    @Test func unforcedChecksAreThrottled() async throws {
        let viewModel = makeViewModel()
        try saveSession(service.acceptedSession)
        await viewModel.refreshSessionState()
        #expect(!viewModel.sessionExpired)

        try saveSession("Seminar_Session=abgelaufen")
        await viewModel.refreshSessionState(force: false)
        #expect(!viewModel.sessionExpired)

        clock.now += StudIPViewModel.sessionCheckInterval
        await viewModel.refreshSessionState(force: false)
        #expect(viewModel.sessionExpired)
    }
}
