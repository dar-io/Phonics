import SwiftUI
import StorySoundsCore

// MARK: Buttons

/// The one button used on every child screen. It is ALWAYS a single `Button` with `FocusCardStyle`; Gentle mode only
/// changes an environment value the style reads (`\.calmMotion`). The view structure therefore never changes when
/// Gentle mode is toggled, so the focused button keeps its identity and focus. Disabled buttons are not focusable.
@MainActor
struct StoryButton<Label: View>: View {
    @EnvironmentObject private var env: AppEnvironment
    let prominent: Bool
    let action: () -> Void
    let label: () -> Label

    init(prominent: Bool = false, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.prominent = prominent
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action, label: label)
            .buttonStyle(FocusCardStyle(prominent: prominent))
            .environment(\.calmMotion, env.calmMotion)
    }
}

// MARK: Guide character

struct BeakShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Wren: a small round bird who carries a lantern. Built only from SwiftUI shapes (original artwork, decorative).
struct WrenView: View {
    enum Mood { case happy, cheer, think }
    var mood: Mood = .happy
    var size: CGFloat = 200

    var body: some View {
        let u = size / 200
        ZStack {
          Group {
            // Lantern glow
            Circle()
                .fill(RadialGradient(colors: [Theme.accent.opacity(0.55), Theme.accent.opacity(0)],
                                     center: .center, startRadius: 2, endRadius: 70 * u))
                .frame(width: 140 * u, height: 140 * u)
                .offset(x: 62 * u, y: 34 * u)
            // Lantern
            RoundedRectangle(cornerRadius: 10 * u)
                .fill(Theme.accent)
                .frame(width: 34 * u, height: 44 * u)
                .overlay(RoundedRectangle(cornerRadius: 10 * u).stroke(Theme.onAccent.opacity(0.6), lineWidth: 3 * u))
                .offset(x: 62 * u, y: 38 * u)
            Capsule().fill(Theme.onAccent.opacity(0.7))
                .frame(width: 4 * u, height: 26 * u)
                .offset(x: 62 * u, y: 4 * u)
          }
          Group {
            // Body
            Ellipse()
                .fill(Color(red: 0.72, green: 0.52, blue: 0.36))
                .frame(width: 130 * u, height: 120 * u)
                .offset(x: -10 * u, y: 28 * u)
            // Belly
            Ellipse()
                .fill(Color(red: 0.95, green: 0.88, blue: 0.74))
                .frame(width: 80 * u, height: 80 * u)
                .offset(x: -10 * u, y: 44 * u)
            // Wing
            Ellipse()
                .fill(Color(red: 0.55, green: 0.38, blue: 0.26))
                .frame(width: 56 * u, height: 70 * u)
                .rotationEffect(.degrees(mood == .cheer ? -25 : -10))
                .offset(x: 28 * u, y: 36 * u)
          }
          Group {
            // Head
            Circle()
                .fill(Color(red: 0.72, green: 0.52, blue: 0.36))
                .frame(width: 92 * u, height: 92 * u)
                .offset(x: -22 * u, y: -38 * u)
            // Beak
            BeakShape()
                .fill(Theme.accent)
                .frame(width: 28 * u, height: 22 * u)
                .offset(x: 14 * u, y: -34 * u)
            // Eye
            Circle().fill(Color.black)
                .frame(width: 14 * u, height: 14 * u)
                .offset(x: -6 * u, y: -48 * u)
            Circle().fill(Color.white)
                .frame(width: 5 * u, height: 5 * u)
                .offset(x: -3 * u, y: -51 * u)
            if mood == .think {
                Capsule().fill(Color(red: 0.55, green: 0.38, blue: 0.26))
                    .frame(width: 22 * u, height: 5 * u)
                    .offset(x: -6 * u, y: -64 * u)
            }
          }
          Group {
            // Feet
            Capsule().fill(Theme.accent).frame(width: 6 * u, height: 22 * u).offset(x: -34 * u, y: 94 * u)
            Capsule().fill(Theme.accent).frame(width: 6 * u, height: 22 * u).offset(x: 6 * u, y: 94 * u)
          }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Wren with a speech bubble. The caption is real text, so the spoken line is always visible too.
struct WrenSays: View {
    let text: String
    var mood: WrenView.Mood = .happy
    var wrenSize: CGFloat = 150

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            WrenView(mood: mood, size: wrenSize)
            Text(text)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 32).padding(.vertical, 22)
                .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.surface))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Feedback and captions

struct FeedbackBannerView: View {
    let text: String
    let positive: Bool
    let identifier: String

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: positive ? "star.fill" : "lightbulb.fill")
                .font(Theme.controlGlyphFont)
                .foregroundStyle(positive ? Theme.positive : Theme.accent)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32).padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(positive ? Theme.positive : Theme.accent, lineWidth: 3))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .a11yID(identifier)
    }
}

/// Large on-screen caption for a sound that has no recording yet (shown instead of playing it).
@MainActor
struct SoundCaptionPill: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        Group {
            if let caption = env.soundCaption {
                HStack(spacing: 16) {
                    Image(systemName: "speaker.wave.2.fill").accessibilityHidden(true)
                    Text("Sound: \(caption)")
                }
                .font(Theme.headingFont)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 40).padding(.vertical, 18)
                .background(Capsule().fill(Theme.accent))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Sound \(AccessibilityText.spoken(caption))")
                .a11yID("session.soundCaption")
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: env.soundCaption)
    }
}

enum AccessibilityText {
    /// "/sh/" -> "sh"; "a_e" -> "a e".
    static func spoken(_ label: String) -> String {
        label.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: "_", with: " ")
    }
    /// Split digraphs are shown with a dash: "a_e" -> "a-e".
    static func display(_ grapheme: String) -> String {
        grapheme.replacingOccurrences(of: "_", with: "\u{2013}")
    }
}

// MARK: Calm backdrop pieces

struct HillsDecoration: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse().fill(Theme.surface.opacity(0.7)).frame(width: 900, height: 260).offset(x: -420, y: 130)
            Ellipse().fill(Theme.surfaceRaised.opacity(0.5)).frame(width: 800, height: 220).offset(x: 440, y: 110)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Dimmed full-screen layer used by confirmations. Not focusable.
struct DimLayer: View {
    var body: some View {
        Color.black.opacity(0.65).ignoresSafeArea().accessibilityHidden(true)
    }
}
