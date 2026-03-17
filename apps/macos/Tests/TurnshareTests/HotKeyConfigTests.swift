import XCTest
import HotKey

/// Tests for hotkey persistence logic (matching HotKeyConfig behavior).
/// Cannot @testable import an executable target, so we test the pattern directly.
final class HotKeyConfigTests: XCTestCase {

    private let suiteName = "com.turnshare.tests.hotkey"
    private let defaultsKey = "com.turnshare.hotkey"

    private func freshDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - Default Value

    func testDefaultKeyComboWhenNoPersistedValue() {
        let defaults = freshDefaults()
        let dict = defaults.dictionary(forKey: defaultsKey)
        XCTAssertNil(dict)

        // Fallback should be Cmd+Option+Control+C
        let defaultCombo = KeyCombo(key: .c, modifiers: [.command, .option, .control])
        XCTAssertEqual(defaultCombo.key, .c)
        XCTAssertTrue(defaultCombo.modifiers.contains(.command))
        XCTAssertTrue(defaultCombo.modifiers.contains(.option))
        XCTAssertTrue(defaultCombo.modifiers.contains(.control))
    }

    // MARK: - Persistence Round-Trip

    func testKeyComboSaveAndLoad() {
        let defaults = freshDefaults()

        let combo = KeyCombo(key: .v, modifiers: [.command, .shift])
        defaults.set(combo.dictionary, forKey: defaultsKey)

        let loaded = defaults.dictionary(forKey: defaultsKey)
        XCTAssertNotNil(loaded)

        let restored = KeyCombo(dictionary: loaded!)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.key, .v)
        XCTAssertTrue(restored!.modifiers.contains(.command))
        XCTAssertTrue(restored!.modifiers.contains(.shift))
    }

    func testMultipleComboRoundTrips() {
        let defaults = freshDefaults()

        let combos: [KeyCombo] = [
            KeyCombo(key: .a, modifiers: [.command]),
            KeyCombo(key: .space, modifiers: [.command, .option]),
            KeyCombo(key: .f1, modifiers: [.control, .shift]),
        ]

        for combo in combos {
            defaults.set(combo.dictionary, forKey: defaultsKey)
            let dict = defaults.dictionary(forKey: defaultsKey)!
            let restored = KeyCombo(dictionary: dict)!
            XCTAssertEqual(restored.key, combo.key)
            XCTAssertEqual(restored.modifiers, combo.modifiers)
        }
    }

    // MARK: - Reset

    func testResetOverwritesWithDefault() {
        let defaults = freshDefaults()

        // Set a custom combo
        let custom = KeyCombo(key: .z, modifiers: [.shift])
        defaults.set(custom.dictionary, forKey: defaultsKey)

        // Reset to default
        let defaultCombo = KeyCombo(key: .c, modifiers: [.command, .option, .control])
        defaults.set(defaultCombo.dictionary, forKey: defaultsKey)

        let dict = defaults.dictionary(forKey: defaultsKey)!
        let restored = KeyCombo(dictionary: dict)!
        XCTAssertEqual(restored.key, .c)
        XCTAssertTrue(restored.modifiers.contains(.command))
        XCTAssertTrue(restored.modifiers.contains(.option))
        XCTAssertTrue(restored.modifiers.contains(.control))
    }

    // MARK: - Dictionary Serialization

    func testKeyComboSerializesToDictionary() {
        let combo = KeyCombo(key: .c, modifiers: [.command, .option, .control])
        let dict = combo.dictionary

        XCTAssertNotNil(dict["keyCode"])
        XCTAssertNotNil(dict["modifiers"])
    }

    func testInvalidDictionaryReturnsNil() {
        let badDict: [String: Any] = ["foo": "bar"]
        let combo = KeyCombo(dictionary: badDict)
        XCTAssertNil(combo)
    }
}
