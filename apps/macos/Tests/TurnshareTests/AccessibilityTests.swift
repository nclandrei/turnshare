import XCTest
@testable import Turnshare

/// Tests for accessibility identifiers and labels on key UI elements.
/// Verifies that accessibility constants are defined and correct,
/// ensuring VoiceOver and UI tests can locate settings controls.
final class AccessibilityTests: XCTestCase {

    // MARK: - Settings Gear Button

    func testSettingsButtonAccessibilityLabel() {
        XCTAssertEqual(
            AccessibilityID.settingsButtonLabel,
            "Settings",
            "Gear button should have 'Settings' as its accessibility label, not the SF Symbol name"
        )
    }

    // MARK: - Toggle Identifiers

    func testConfirmBeforePublishingToggleIdentifier() {
        XCTAssertEqual(
            AccessibilityID.confirmBeforePublishingToggle,
            "confirmBeforePublishing",
            "Confirm toggle should have a stable accessibility identifier"
        )
    }

    func testLaunchAtLoginToggleIdentifier() {
        XCTAssertEqual(
            AccessibilityID.launchAtLoginToggle,
            "launchAtLogin",
            "Launch at login toggle should have a stable accessibility identifier"
        )
    }

    // MARK: - Toggle Labels

    func testConfirmBeforePublishingToggleLabel() {
        XCTAssertEqual(
            AccessibilityID.confirmBeforePublishingLabel,
            "Confirm before publishing",
            "Confirm toggle should have a descriptive accessibility label"
        )
    }

    func testLaunchAtLoginToggleLabel() {
        XCTAssertEqual(
            AccessibilityID.launchAtLoginLabel,
            "Launch at login",
            "Launch at login toggle should have a descriptive accessibility label"
        )
    }
}
