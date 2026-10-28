import SwiftUI

/// Entry point: unit tests get an empty host app, so launch work (database, sync, menu bar) never runs under XCTest.
@main
enum AppLauncher {
    static func main() {
        if isRunningUnitTests {
            UnitTestHostApp.main()
        } else {
            StudyAppApp.main()
        }
    }

    private static var isRunningUnitTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }
}

/// Host app for the unit tests; the tests build what they need themselves.
private struct UnitTestHostApp: App {
    var body: some Scene {
        WindowGroup { EmptyView() }
    }
}
