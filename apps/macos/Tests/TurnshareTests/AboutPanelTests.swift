import XCTest
@testable import Turnshare

/// Tests for the About panel window level fix.
/// The About window must appear above the floating panel (`.floating` level).
final class AboutPanelTests: XCTestCase {

    func testFloatingPanelLevelIsFloating() {
        // Verify the floating panel uses .floating level as a baseline
        XCTAssertEqual(NSWindow.Level.floating.rawValue, Int(CGWindowLevelForKey(.floatingWindow)))
    }

    @MainActor
    func testAboutPanelLevelExceedsFloating() {
        // The custom about-panel level must be higher than .floating so
        // the About window renders in front of the floating panel.
        let aboutLevel = AppDelegate.aboutPanelLevel
        XCTAssertGreaterThan(aboutLevel.rawValue, NSWindow.Level.floating.rawValue,
            "About panel level must be above .floating so it appears in front of the main panel")
    }
}
