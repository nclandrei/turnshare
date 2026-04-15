import XCTest
import Foundation
@testable import Turnshare

/// Tests that Sparkle auto-update is only started when the app is properly
/// configured (i.e. has a valid SUFeedURL in its Info.plist).
/// In debug/unsigned builds this key is absent, so Sparkle should not start
/// automatically — otherwise it shows an "Unable to Check For Updates" alert.
final class UpdaterControllerTests: XCTestCase {

    /// The running test bundle does not embed SUFeedURL in its Info.plist,
    /// so `UpdaterController.shouldStartUpdater` must return false.
    func testShouldStartUpdaterReturnsFalseWithoutFeedURL() {
        XCTAssertFalse(UpdaterController.shouldStartUpdater,
                       "shouldStartUpdater must be false when SUFeedURL is missing")
    }
}
