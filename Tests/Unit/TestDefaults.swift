import XCTest

/// Throwaway `UserDefaults` suites for tests.
///
/// `removePersistentDomain` empties a suite but cfprefsd still leaves an empty
/// `<suite>.plist` in `~/Library/Preferences`, and it recreates the file if it is
/// deleted while the suite is live. So each test empties its suite on teardown, and
/// the plist files are deleted once, after the whole test bundle has finished.
enum TestDefaults {
    private static let lock = NSLock()
    private static var suites: [String] = []
    private static let observer = BundleObserver()

    static func make(_ prefix: String, for test: XCTestCase) -> UserDefaults {
        makeWithSuite(prefix, for: test).defaults
    }

    static func makeWithSuite(_ prefix: String, for test: XCTestCase) -> (defaults: UserDefaults, suite: String) {
        let suite = "\(prefix)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        lock.lock()
        if suites.isEmpty { XCTestObservationCenter.shared.addTestObserver(observer) }
        suites.append(suite)
        lock.unlock()
        test.addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (defaults, suite)
    }

    fileprivate static func deleteLeftoverPlists() {
        lock.lock()
        let names = suites
        suites.removeAll()
        lock.unlock()
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferences")
        for name in names {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(name).plist"))
        }
    }

    private final class BundleObserver: NSObject, XCTestObservation {
        func testBundleDidFinish(_ testBundle: Bundle) { TestDefaults.deleteLeftoverPlists() }
    }
}
