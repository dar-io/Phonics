import SwiftUI
import StorySoundsCore

/// Settings & accessibility: session length, comfort options, volume, mastery thresholds. No text entry.
@MainActor
struct ParentSettingsView: View {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    @EnvironmentObject var env: AppEnvironment
    @State private var page = 0

    private static let titles = ["Session and comfort", "Volume", "When a sound counts as secure (1 of 2)", "When a sound counts as secure (2 of 2)"]
    private static let sessionChoices = [5, 7, 10]
    private static let defaults = MasterySettings()

    var body: some View {
        ParentPageScaffold(title: "Settings & accessibility", pageTitle: Self.titles[page], idPrefix: "parent.settings",
                           page: $page, pageCount: Self.titles.count, pagerIsDefault: false, onBack: onClose) {
            switch page {
            case 0: sessionAndComfort
            case 1: volume
            case 2: masteryScore
            default: masterySpread
            }
        }
    }

    private func change(_ mutate: (inout LearnerSettings) -> Void) {
        var s = env.settings
        mutate(&s)
        env.setSettings(s)
    }

    // MARK: Page 0

    private var sessionAndComfort: some View {
        let s = env.settings
        return VStack(alignment: .leading, spacing: 22) {
            ParentStepperRow(title: "Session length", hint: "Short sessions suit young children. Default 7.",
                       valueText: "\(s.mastery.sessionMinutes) min", idPrefix: "parent.settings.session",
                       onDec: { stepSession(-1) }, onInc: { stepSession(1) })
            ParentToggleRow(title: "Gentle mode", hint: "Calmer: less movement and softer sound effects.",
                      isOn: s.gentleMode, id: "parent.settings.gentle") { change { $0.gentleMode.toggle() } }
            ParentToggleRow(title: "Captions", hint: "Shows a written caption of each letter sound when it plays. Instructions are always shown on screen.",
                      isOn: s.showCaptions, id: "parent.settings.captions") { change { $0.showCaptions.toggle() } }
        }
    }

    private func stepSession(_ delta: Int) {
        let choices = Self.sessionChoices
        let current = env.settings.mastery.sessionMinutes
        // Nearest listed length, then move one step (stops at the ends).
        let i = choices.enumerated().min(by: { abs($0.element - current) < abs($1.element - current) })?.offset ?? 1
        let j = min(choices.count - 1, max(0, i + delta))
        change { $0.mastery.sessionMinutes = choices[j] }
    }

    // MARK: Page 1

    private var volume: some View {
        let s = env.settings
        return VStack(alignment: .leading, spacing: 22) {
            ParentStepperRow(title: "Narration", hint: "Voice and instructions", valueText: percent(s.narrationVolume),
                       idPrefix: "parent.settings.volume.narration",
                       onDec: { change { $0.narrationVolume = stepped($0.narrationVolume, -0.1) } },
                       onInc: { change { $0.narrationVolume = stepped($0.narrationVolume, 0.1) } })
            ParentStepperRow(title: "Effects", hint: "Taps, chimes and cheers", valueText: percent(s.effectsVolume),
                       idPrefix: "parent.settings.volume.effects",
                       onDec: { change { $0.effectsVolume = stepped($0.effectsVolume, -0.1) } },
                       onInc: { change { $0.effectsVolume = stepped($0.effectsVolume, 0.1) } })
            // Music is deliberately not offered: the app does not play background music yet.
            Text("These work together with the TV's own volume.").font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
        }
    }

    private func stepped(_ v: Double, _ d: Double) -> Double { min(1, max(0, ((v + d) * 10).rounded() / 10)) }
    private func percent(_ v: Double) -> String { v <= 0.001 ? "Off" : "\(Int((v * 100).rounded()))%" }

    // MARK: Pages 2 and 3 (mastery thresholds, split so each page fits on screen without scrolling)

    private var masteryScore: some View {
        let m = env.settings.mastery
        let d = Self.defaults
        return VStack(alignment: .leading, spacing: 22) {
            ParentStepperRow(title: "Score needed", hint: "Default \(Int((d.secureScore * 100).rounded()))%. Higher is stricter.",
                       valueText: "\(Int((m.secureScore * 100).rounded()))%", idPrefix: "parent.settings.mastery.score",
                       onDec: { stepScore(-0.05) }, onInc: { stepScore(0.05) })
            ParentStepperRow(title: "Tries needed", hint: "Default \(d.minAttempts). Answers before a sound can be secure.",
                       valueText: "\(m.minAttempts)", idPrefix: "parent.settings.mastery.attempts",
                       onDec: { stepInt(\.minAttempts, -1, 4, 12) }, onInc: { stepInt(\.minAttempts, 1, 4, 12) })
        }
    }

    private var masterySpread: some View {
        let m = env.settings.mastery
        let d = Self.defaults
        return VStack(alignment: .leading, spacing: 22) {
            ParentStepperRow(title: "Sessions needed", hint: "Default \(d.minSessions). Different play sessions.",
                       valueText: "\(m.minSessions)", idPrefix: "parent.settings.mastery.sessions",
                       onDec: { stepInt(\.minSessions, -1, 1, 4) }, onInc: { stepInt(\.minSessions, 1, 1, 4) })
            ParentStepperRow(title: "Days needed", hint: "Default \(d.minDays). Different days.",
                       valueText: "\(m.minDays)", idPrefix: "parent.settings.mastery.days",
                       onDec: { stepInt(\.minDays, -1, 1, 4) }, onInc: { stepInt(\.minDays, 1, 1, 4) })
            Button {
                change {
                    $0.mastery.secureScore = d.secureScore; $0.mastery.minAttempts = d.minAttempts
                    $0.mastery.minSessions = d.minSessions; $0.mastery.minDays = d.minDays
                }
            } label: {
                Label("Reset all four to defaults", systemImage: "arrow.counterclockwise").font(Theme.bodyFont).frame(maxWidth: .infinity)
            }
            .buttonStyle(ParentRowStyle())
            .a11yID("parent.settings.mastery.reset")
            .accessibilityLabel("Reset thresholds to defaults")
            .accessibilityHint("Score \(Int((d.secureScore * 100).rounded())) percent, \(d.minAttempts) tries, \(d.minSessions) sessions, \(d.minDays) days")
        }
    }

    private func stepScore(_ delta: Double) {
        change { $0.mastery.secureScore = min(0.95, max(0.70, (($0.mastery.secureScore + delta) * 20).rounded() / 20)) }
    }

    private func stepInt(_ key: WritableKeyPath<MasterySettings, Int>, _ delta: Int, _ lo: Int, _ hi: Int) {
        change { $0.mastery[keyPath: key] = min(hi, max(lo, $0.mastery[keyPath: key] + delta)) }
    }
}
