import XCTest
import SwiftUI
@testable import Turnshare

/// Tests for `RootView` — the wrapper that forces a dark color scheme
/// on the floating panel content so SwiftUI default text colors render
/// correctly against our dark background even when the system appearance
/// is set to light mode.
final class RootViewTests: XCTestCase {

    func testRootViewBodyAppliesPreferredColorSchemeDark() {
        let view = RootView { Text("test") }
        let bodyType = String(reflecting: type(of: view.body))

        // `View.preferredColorScheme(_:)` writes the `PreferredColorSchemeKey`
        // preference, which appears in the wrapped type description.
        XCTAssertTrue(
            bodyType.contains("PreferredColorSchemeKey"),
            "Expected RootView body to apply preferredColorScheme(.dark) — got type: \(bodyType)"
        )
    }
}
