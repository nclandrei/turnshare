import XCTest

/// Tests for publish confirmation persistence logic.
/// Tests the persistence contract directly (same pattern as QuickPublishConfigTests).
final class PublishConfirmConfigTests: XCTestCase {

    private let suiteName = "com.turnshare.tests.publishConfirm"
    private let defaultsKey = "com.turnshare.publishConfirmation"

    private func freshDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - Default Value

    func testDefaultValueIsFalse() {
        let defaults = freshDefaults()
        // bool(forKey:) returns false when key is absent
        XCTAssertFalse(defaults.bool(forKey: defaultsKey))
    }

    // MARK: - Persistence Round-Trip

    func testSaveAndLoadTrue() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: defaultsKey)

        XCTAssertTrue(defaults.bool(forKey: defaultsKey))
    }

    func testSaveAndLoadFalse() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: defaultsKey)
        defaults.set(false, forKey: defaultsKey)

        XCTAssertFalse(defaults.bool(forKey: defaultsKey))
    }

    // MARK: - Reset

    func testResetOverwritesWithFalse() {
        let defaults = freshDefaults()

        defaults.set(true, forKey: defaultsKey)
        XCTAssertTrue(defaults.bool(forKey: defaultsKey))

        // Reset to default
        defaults.set(false, forKey: defaultsKey)
        XCTAssertFalse(defaults.bool(forKey: defaultsKey))
    }

    // MARK: - Multiple Updates

    func testMultipleUpdatesKeepLatest() {
        let defaults = freshDefaults()

        defaults.set(true, forKey: defaultsKey)
        defaults.set(false, forKey: defaultsKey)
        defaults.set(true, forKey: defaultsKey)

        XCTAssertTrue(defaults.bool(forKey: defaultsKey))
    }

    // MARK: - Invalid Values

    func testInvalidStringValueReturnsFalse() {
        let defaults = freshDefaults()
        defaults.set("invalid", forKey: defaultsKey)

        // UserDefaults.bool(forKey:) returns false for non-boolean strings
        XCTAssertFalse(defaults.bool(forKey: defaultsKey))
    }

    func testRemovingKeyReturnsFalse() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: defaultsKey)
        defaults.removeObject(forKey: defaultsKey)

        XCTAssertFalse(defaults.bool(forKey: defaultsKey))
    }
}
