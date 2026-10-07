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

    // Layout (tvOS safe area is 60pt top/bottom and 80pt sides; the system also applies overscan insets)
    static let screenHorizontalPadding: CGFloat = 80
    static let screenVerticalPadding: CGFloat = 60
    static let spacing: CGFloat = 40
    static let cornerRadius: CGFloat = 28
    static let minTarget: CGFloat = 120

    // Type: tvOS text styles scale with the system; these floors keep things readable from ~3 m.
    static let titleFont = Font.system(size: 76, weight: .bold, design: .rounded)
    static let headingFont = Font.system(size: 52, weight: .semibold, design: .rounded)
    static let bodyFont = Font.system(size: 38, weight: .regular, design: .rounded)
    static let captionFont = Font.system(size: 32, weight: .regular, design: .rounded)
    /// Letters and words the child reads — deliberately very large.
    static let glyphFont = Font.system(size: 140, weight: .bold, design: .rounded)
    static let wordFont = Font.system(size: 110, weight: .bold, design: .rounded)
}

/// Focus appearance for any tappable card/button: scale + 6pt white outline + shadow (not colour alone).
/// Reduce Motion removes the scale animation but keeps the outline.
struct FocusCardStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 36).padding(.vertical, 24)
            .frame(minWidth: Theme.minTarget, minHeight: Theme.minTarget)
            .foregroundStyle(prominent ? Theme.onAccent : Theme.text)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(prominent ? Theme.accent : Theme.surfaceRaised))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.focusRing, lineWidth: isFocused ? 8 : 0))
            .scaleEffect(isFocused && !reduceMotion ? 1.08 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: isFocused ? 24 : 0, y: isFocused ? 14 : 0)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isFocused)
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
