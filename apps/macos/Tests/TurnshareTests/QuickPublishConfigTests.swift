import XCTest
import AppKit

/// Tests for quick-publish modifier persistence logic.
/// Cannot @testable import an executable target, so we test the persistence
/// contract directly (same pattern as HotKeyConfigTests).
final class QuickPublishConfigTests: XCTestCase {

    private let suiteName = "com.turnshare.tests.quickPublish"
    private let defaultsKey = "com.turnshare.quickPublishModifier"

    /// Mirror of the modifier enum for testing the persistence contract.
    private enum Modifier: String, CaseIterable {
        case command
        case option
        case control

        var eventFlag: NSEvent.ModifierFlags {
            switch self {
            case .command: return .command
            case .option: return .option
            case .control: return .control
            }
        }

        var symbol: String {
            switch self {
            case .command: return "\u{2318}"
            case .option: return "\u{2325}"
            case .control: return "\u{2303}"
            }
        }
    }

    private func freshDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - Default Value

    func testDefaultModifierWhenNoPersistedValue() {
        let defaults = freshDefaults()
        let raw = defaults.string(forKey: defaultsKey)
        XCTAssertNil(raw)
        // When no persisted value, config should fall back to "command"
    }

    // MARK: - Persistence Round-Trip

    func testSaveAndLoadCommand() {
        let defaults = freshDefaults()
        defaults.set(Modifier.command.rawValue, forKey: defaultsKey)

        let loaded = defaults.string(forKey: defaultsKey)
        XCTAssertEqual(loaded, "command")
        XCTAssertEqual(Modifier(rawValue: loaded!), .command)
    }

    func testSaveAndLoadOption() {
        let defaults = freshDefaults()
        defaults.set(Modifier.option.rawValue, forKey: defaultsKey)

        let loaded = defaults.string(forKey: defaultsKey)
        XCTAssertEqual(loaded, "option")
        XCTAssertEqual(Modifier(rawValue: loaded!), .option)
    }

    func testSaveAndLoadControl() {
        let defaults = freshDefaults()
        defaults.set(Modifier.control.rawValue, forKey: defaultsKey)

        let loaded = defaults.string(forKey: defaultsKey)
        XCTAssertEqual(loaded, "control")
        XCTAssertEqual(Modifier(rawValue: loaded!), .control)
    }

    func testMultipleUpdatesKeepLatest() {
        let defaults = freshDefaults()

        defaults.set("option", forKey: defaultsKey)
        defaults.set("control", forKey: defaultsKey)
        defaults.set("command", forKey: defaultsKey)

        let loaded = defaults.string(forKey: defaultsKey)
        XCTAssertEqual(loaded, "command")
    }

    // MARK: - Reset

    func testResetOverwritesWithCommand() {
        let defaults = freshDefaults()

        // Set a non-default modifier
        defaults.set("control", forKey: defaultsKey)
        XCTAssertEqual(defaults.string(forKey: defaultsKey), "control")

        // Reset to default
        defaults.set("command", forKey: defaultsKey)
        XCTAssertEqual(defaults.string(forKey: defaultsKey), "command")
    }

    // MARK: - Invalid Values

    func testInvalidValueFallsBackGracefully() {
        let defaults = freshDefaults()
        defaults.set("invalid_modifier", forKey: defaultsKey)

        let raw = defaults.string(forKey: defaultsKey)!
        let modifier = Modifier(rawValue: raw)
        XCTAssertNil(modifier, "Invalid raw value should not produce a valid modifier")
    }

    func testEmptyStringFallsBackGracefully() {
        let defaults = freshDefaults()
        defaults.set("", forKey: defaultsKey)

        let raw = defaults.string(forKey: defaultsKey)!
        let modifier = Modifier(rawValue: raw)
        XCTAssertNil(modifier)
    }

    // MARK: - Event Flags

    func testCommandEventFlag() {
        XCTAssertEqual(Modifier.command.eventFlag, .command)
    }

    func testOptionEventFlag() {
        XCTAssertEqual(Modifier.option.eventFlag, .option)
    }

    func testControlEventFlag() {
        XCTAssertEqual(Modifier.control.eventFlag, .control)
    }

    // MARK: - Symbols

    func testCommandSymbol() {
        XCTAssertEqual(Modifier.command.symbol, "\u{2318}")
    }

    func testOptionSymbol() {
        XCTAssertEqual(Modifier.option.symbol, "\u{2325}")
    }

    func testControlSymbol() {
        XCTAssertEqual(Modifier.control.symbol, "\u{2303}")
    }

    // MARK: - All Modifiers

    func testAllCasesHasThreeModifiers() {
        XCTAssertEqual(Modifier.allCases.count, 3)
    }

    func testAllRawValuesAreDistinct() {
        let rawValues = Set(Modifier.allCases.map(\.rawValue))
        XCTAssertEqual(rawValues.count, 3)
    }

    func testAllEventFlagsAreDistinct() {
        let flags = Modifier.allCases.map(\.eventFlag)
        // Each flag should be different from the others
        for i in 0..<flags.count {
            for j in (i+1)..<flags.count {
                XCTAssertNotEqual(flags[i], flags[j])
            }
        }
    }

    func testAllSymbolsAreDistinct() {
        let symbols = Set(Modifier.allCases.map(\.symbol))
        XCTAssertEqual(symbols.count, 3)
    }

    // MARK: - Full Round-Trip for All Modifiers

    func testAllModifiersRoundTrip() {
        let defaults = freshDefaults()

        for mod in Modifier.allCases {
            defaults.set(mod.rawValue, forKey: defaultsKey)
            let loaded = defaults.string(forKey: defaultsKey)!
            let restored = Modifier(rawValue: loaded)
            XCTAssertEqual(restored, mod, "Round-trip failed for \(mod.rawValue)")
        }
    }
}
