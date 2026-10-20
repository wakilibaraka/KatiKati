import XCTest
@testable import KatiKati

final class StartupUIPolicyTests: XCTestCase {
    func testFirstRunGuideSurvivesQuietStart() {
        XCTAssertTrue(StartupUIPolicy.shouldPresentWelcomeGuide(isFirstRun: true, launchHidden: true),
                      "a fresh install walks its setup exactly once, even hidden")
        XCTAssertTrue(StartupUIPolicy.shouldPresentWelcomeGuide(isFirstRun: true, launchHidden: false))
    }

    func testQuietStartSuppressesLaterGuidePresentations() {
        XCTAssertFalse(StartupUIPolicy.shouldPresentWelcomeGuide(isFirstRun: false, launchHidden: true))
        XCTAssertTrue(StartupUIPolicy.shouldPresentWelcomeGuide(isFirstRun: false, launchHidden: false))
    }
}

final class AppLanguagePickerChoiceTests: XCTestCase {
    func testAbsentKeyIsTheSystemTier() {
        XCTAssertEqual(AppLanguagePickerChoice.current(appDomainValue: nil, effectiveLocalization: "ja"), .system)
        XCTAssertEqual(AppLanguagePickerChoice.current(appDomainValue: [], effectiveLocalization: "ja"), .system)
        XCTAssertEqual(AppLanguagePickerChoice.current(appDomainValue: ["de"], effectiveLocalization: "de"), .option(.german))
    }

    func testSystemTierWritesByRemovingTheKey() {
        XCTAssertNil(AppLanguagePickerChoice.system.appleLanguagesValue, "key absence is the follow-system mechanism")
        XCTAssertEqual(AppLanguagePickerChoice.option(.japanese).appleLanguagesValue, ["ja"])
    }

    func testOnlyRealChangesAskForARestart() {
        // On an English system, pinning English changes nothing — no restart nag.
        XCTAssertFalse(AppLanguagePickerChoice.option(.english)
            .changesLocalization(currentEffective: "en", systemPreferred: ["en-US"]))
        XCTAssertTrue(AppLanguagePickerChoice.option(.japanese)
            .changesLocalization(currentEffective: "en", systemPreferred: ["en-US"]))
        // Going back to System on an English system keeps English loaded — no nag.
        XCTAssertFalse(AppLanguagePickerChoice.system
            .changesLocalization(currentEffective: "en", systemPreferred: ["en-US"]))
        XCTAssertTrue(AppLanguagePickerChoice.system
            .changesLocalization(currentEffective: "ja", systemPreferred: ["en-US"]))
    }
}
