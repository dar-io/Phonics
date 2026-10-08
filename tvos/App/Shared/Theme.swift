import SwiftUI

/// Design tokens for the ten-foot UI. Original palette; every pairing used for text meets WCAG AA (>= 4.5:1) —
/// meaning is never carried by colour alone (focus uses scale + thick outline + shadow as well as colour).
enum Theme {
    // Colours
    static let background = Color(red: 0.07, green: 0.16, blue: 0.20)       // deep teal
    static let surface = Color(red: 0.12, green: 0.25, blue: 0.30)
    static let surfaceRaised = Color(red: 0.17, green: 0.33, blue: 0.38)
    static let text = Color(red: 0.99, green: 0.97, blue: 0.92)             // warm white
    static let textSecondary = Color(red: 0.83, green: 0.90, blue: 0.90)
    static let accent = Color(red: 1.00, green: 0.80, blue: 0.30)           // lantern yellow
    static let onAccent = Color(red: 0.10, green: 0.14, blue: 0.16)
    static let positive = Color(red: 0.55, green: 0.85, blue: 0.62)
    static let focusRing = Color.white

    // Layout. tvOS SwiftUI already lays content out inside the system safe area (60 pt top/bottom, 80 pt sides), and
    // only backgrounds extend to the screen edge. So the container adds just a little EXTRA breathing room (not the
    // full 80/60 again, which previously double-inset every screen to ~160/120 pt).
    static let screenHorizontalPadding: CGFloat = 20
    static let screenVerticalPadding: CGFloat = 10
    static let spacing: CGFloat = 40
    static let cornerRadius: CGFloat = 28
    static let minTarget: CGFloat = 120

    // Type: Dynamic Type text styles (rounded design), so text follows the system text size. At the default size every
    // style used for reading text is >= 29 pt on tvOS (caption uses .callout, ~31 pt; nothing uses footnote/caption
    // styles, which are 23-25 pt). Never shrink text with minimumScaleFactor; let it wrap (lineLimit) instead.
    static let titleFont = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let headingFont = Font.system(.title2, design: .rounded).weight(.semibold)
    /// Section label inside a page (between heading and body).
    static let subheadingFont = Font.system(.title3, design: .rounded).weight(.semibold)
    static let bodyFont = Font.system(.headline, design: .rounded).weight(.regular)
    static let captionFont = Font.system(.callout, design: .rounded).weight(.regular)
    /// Symbols (scale with Dynamic Type like text).
    static let iconLargeFont = Font.system(.largeTitle, design: .rounded)
    static let iconMediumFont = Font.system(.title2, design: .rounded)
    static let controlGlyphFont = Font.system(.title3, design: .rounded).weight(.bold)
    /// Letters and words the child reads: deliberately very large and FIXED (a reading target, not UI text).
    /// Layouts cap these with `.dynamicTypeSize(...DynamicTypeSize.accessibility1)` where they sit beside UI text.
    static let glyphFont = Font.system(size: 140, weight: .bold, design: .rounded)
    static let wordFont = Font.system(size: 110, weight: .bold, design: .rounded)
}

// MARK: Gentle mode environment

private struct CalmMotionKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True when Gentle mode (or the forced-calm test flag) asks for no focus motion. Set by `StoryButton` and the
    /// grown-ups' area; read by the focus styles so ONE button/style serves both cases (no view-identity swap).
    var calmMotion: Bool {
        get { self[CalmMotionKey.self] }
        set { self[CalmMotionKey.self] = newValue }
    }
}

/// Focus appearance for any tappable card/button: scale + 8pt white outline + shadow (not colour alone).
/// Reduce Motion or Gentle mode removes the scale animation but keeps the outline.
struct FocusCardStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calmMotion) private var calm
    @ScaledMetric(relativeTo: .body) private var minTarget: CGFloat = Theme.minTarget

    func makeBody(configuration: Configuration) -> some View {
        let still = reduceMotion || calm
        return configuration.label
            .padding(.horizontal, 36).padding(.vertical, 24)
            .frame(minWidth: minTarget, minHeight: minTarget)
            .foregroundStyle(prominent ? Theme.onAccent : Theme.text)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(prominent ? Theme.accent : Theme.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.focusRing, lineWidth: isFocused ? 8 : 0))
            .scaleEffect(isFocused && !still ? 1.08 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: isFocused ? 24 : 0, y: isFocused ? 14 : 0)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(still ? nil : .easeOut(duration: 0.15), value: isFocused)
    }
}

extension View {
    /// Standard full-screen container: background + safe-area-respecting padding. Use on every screen.
    func screenContainer() -> some View {
        self.padding(.horizontal, Theme.screenHorizontalPadding)
            .padding(.vertical, Theme.screenVerticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .foregroundStyle(Theme.text)
    }
    /// Stable accessibility identifier convention: "<screen>.<element>" e.g. "home.start", "parent.reset".
    func a11yID(_ id: String) -> some View { accessibilityIdentifier(id) }
}
