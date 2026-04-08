import XCTest

/// Tests for launch-at-login persistence logic.
/// Tests the persistence contract directly (same pattern as PublishConfirmConfigTests).
final class LaunchAtLoginConfigTests: XCTestCase {

    private let suiteName = "com.turnshare.tests.launchAtLogin"
    private let defaultsKey = "com.turnshare.launchAtLogin"

    private func freshDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - Default Value

    func testDefaultValueIsTrue_whenKeyAbsent() {
        let defaults = freshDefaults()
        // Key is absent → object(forKey:) returns nil → should default to true.
        XCTAssertNil(defaults.object(forKey: defaultsKey))
    }

    func testBoolForKeyReturnsFalse_whenKeyAbsent() {
        let defaults = freshDefaults()
        // UserDefaults.bool(forKey:) returns false for absent keys,
        // which is why we use object(forKey:) nil-check for the true default.
        XCTAssertFalse(defaults.bool(forKey: defaultsKey))
    }

    func testDefaultResolvesToTrue_withNilCheck() {
        let defaults = freshDefaults()
        // Mirror the LaunchAtLoginConfig init logic:
        let result: Bool
        if defaults.object(forKey: defaultsKey) == nil {
            result = true
        } else {
            result = defaults.bool(forKey: defaultsKey)
        }
        XCTAssertTrue(result)
    }

    // MARK: - Persistence Round-Trip

    func testSaveAndLoadTrue() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: defaultsKey)

        XCTAssertTrue(defaults.bool(forKey: defaultsKey))
    }

    func testSaveAndLoadFalse() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: defaultsKey)

        XCTAssertFalse(defaults.bool(forKey: defaultsKey))
        // Key is now present (not nil), so the nil-check path won't trigger.
        XCTAssertNotNil(defaults.object(forKey: defaultsKey))
    }

    func testSaveTrueThenFalse() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: defaultsKey)
        defaults.set(false, forKey: defaultsKey)

        XCTAssertFalse(defaults.bool(forKey: defaultsKey))
    }

    func testSaveFalseThenTrue() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: defaultsKey)
        defaults.set(true, forKey: defaultsKey)

        XCTAssertTrue(defaults.bool(forKey: defaultsKey))
    }

    // MARK: - Reset

    func testResetOverwritesWithTrue() {
        let defaults = freshDefaults()

        defaults.set(false, forKey: defaultsKey)
        XCTAssertFalse(defaults.bool(forKey: defaultsKey))

        // Reset should restore to default (true)
        defaults.set(true, forKey: defaultsKey)
        XCTAssertTrue(defaults.bool(forKey: defaultsKey))
    }

    // MARK: - Multiple Updates

    func testMultipleUpdatesKeepLatest() {
        let defaults = freshDefaults()

        defaults.set(false, forKey: defaultsKey)
        defaults.set(true, forKey: defaultsKey)
        defaults.set(false, forKey: defaultsKey)

        XCTAssertFalse(defaults.bool(forKey: defaultsKey))
    }

    func testRapidToggles() {
        let defaults = freshDefaults()

        for i in 0..<10 {
            defaults.set(i % 2 == 0, forKey: defaultsKey)
        }
        // Last iteration: i=9, 9%2==1 → false
        XCTAssertFalse(defaults.bool(forKey: defaultsKey))
    }

    // MARK: - Invalid Values

    func testInvalidStringValueReturnsFalse() {
        let defaults = freshDefaults()
        defaults.set("invalid", forKey: defaultsKey)

        // UserDefaults.bool(forKey:) returns false for non-boolean strings.
        XCTAssertFalse(defaults.bool(forKey: defaultsKey))
        // But the key IS present, so nil-check won't kick in.
        XCTAssertNotNil(defaults.object(forKey: defaultsKey))
    }

    func testRemovingKeyRestoresDefault() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: defaultsKey)
        defaults.removeObject(forKey: defaultsKey)

        // After removing, object(forKey:) is nil → should default to true.
        XCTAssertNil(defaults.object(forKey: defaultsKey))
        let result: Bool
        if defaults.object(forKey: defaultsKey) == nil {
            result = true
        } else {
            result = defaults.bool(forKey: defaultsKey)
        }
        XCTAssertTrue(result)
    }

    // MARK: - Key Presence

    func testKeyBecomesPresent_afterFirstWrite() {
        let defaults = freshDefaults()
        XCTAssertNil(defaults.object(forKey: defaultsKey))

        defaults.set(true, forKey: defaultsKey)
        XCTAssertNotNil(defaults.object(forKey: defaultsKey))
    }

    func testExplicitTrueIsDifferentFromAbsent() {
        let defaults = freshDefaults()

        // Absent → nil
        XCTAssertNil(defaults.object(forKey: defaultsKey))

        // Explicit true → non-nil
        defaults.set(true, forKey: defaultsKey)
        XCTAssertNotNil(defaults.object(forKey: defaultsKey))
        XCTAssertTrue(defaults.bool(forKey: defaultsKey))
    }
}
