import SwiftUI

/// Wraps the floating panel root content and forces a dark color scheme.
///
/// The floating panel uses a fixed dark background (GitHub Dark palette).
/// Without an explicit color scheme, SwiftUI inherits the system appearance —
/// which means text using default `Color.primary` becomes near-black when the
/// system is in light mode, leaving labels invisible against our dark surface.
struct RootView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content.preferredColorScheme(.dark)
    }
}
