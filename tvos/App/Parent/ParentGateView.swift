import SwiftUI
import StorySoundsCore

/// Child-resistant entry to the grown-ups' area: (1) press-and-hold, (2) a 4-answer adult question,
/// with a calm lockout after repeated wrong answers. Menu/Back leaves to Home.
///
/// HOLD IMPLEMENTATION NOTE: a tvOS `Button` has no press-and-hold gesture, so the hold control is a plain focusable
/// view using `.onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)` (SwiftUI, tvOS 14+),
/// which is driven by a click-and-hold of the Siri Remote touch surface. The ring is fed by `ParentGateSession`/`HoldGate`.
/// UNVERIFIED on a real device/simulator (no Swift toolchain in the authoring environment). If the long press does not
/// fire on tvOS, the fallback is repeated-select-with-progress: replace `holdControl`'s gesture with `.onTapGesture`
/// calling a `tapStep()` that advances a 0...1 counter (e.g. 6 taps, each within 1.5 s of the last).
/// Assistive technology: VoiceOver users cannot press-and-hold, so the control exposes a named accessibility action
/// ("Continue to the question") that skips ONLY the hold step; the adult question is still required.
@MainActor
struct ParentGateView: View {
    let onUnlocked: () -> Void
    let onExit: () -> Void

    private enum GateFocus: Hashable { case hold, back, answer(Int) }
    private static let lockoutKey = "storysounds.parentgate.lockout"
    private static let holdSeconds: TimeInterval = 3
    /// UI tests only (`-uitest-parent-gate-pass`): skips the hold step; the adult question is still required.
    private static let skipHoldForTests = CommandLine.arguments.contains("-uitest-parent-gate-pass")

    @State private var session: ParentGateSession
    @State private var now = Date()
    @State private var notice: String?
    @FocusState private var focus: GateFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let ticker = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    init(onUnlocked: @escaping () -> Void, onExit: @escaping () -> Void) {
        self.onUnlocked = onUnlocked
        self.onExit = onExit
        _session = State(initialValue: ParentGateSession(requiredHold: ParentGateView.holdSeconds,
                                                         lockout: ParentGateView.loadLockout()))
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 32) {
            Text("Grown-ups only").font(Theme.titleFont).accessibilityAddTraits(.isHeader)
            stageContent
            Button(action: onExit) {
                Label("Back to Story Sounds", systemImage: "chevron.left").font(Theme.bodyFont)
            }
            .buttonStyle(FocusCardStyle())
            .focused($focus, equals: .back)
            .a11yID("parentgate.back")
            .accessibilityLabel("Back to Story Sounds")
            .accessibilityHint("Leaves the grown-ups' area. The Menu button does the same.")
        }
        .screenContainer()
        .defaultFocus($focus, defaultTarget)
        .onExitCommand(perform: onExit)
        .onReceive(ticker) { tick($0) }
        .onAppear {
            session.refresh(at: Date())
            focus = defaultTarget
            if ParentGateView.skipHoldForTests { skipHoldForAssistiveTech() }
        }
        .onChange(of: stageKey) { _, _ in
            focus = defaultTarget
            if case .unlocked = session.stage {
                session.relock()
                onUnlocked()
            }
        }
    }

    // MARK: Stage

    private var stageKey: String {
        switch session.stage {
        case .hold: return "hold"
        case .challenge: return "challenge"
        case .lockedOut: return "locked"
        case .unlocked: return "unlocked"
        }
    }

    private var defaultTarget: GateFocus {
        switch session.stage {
        case .hold: return .hold
        case .challenge: return .answer(0)
        case .lockedOut, .unlocked: return .back
        }
    }

    @ViewBuilder private var stageContent: some View {
        switch session.stage {
        case .hold:
            holdControl
        case .challenge(let c):
            challengeView(c)
        case .lockedOut(let until):
            lockedView(until)
        case .unlocked:
            Text("Opening…").font(Theme.bodyFont)
        }
    }

    // MARK: Hold

    private var holdProgress: Double { session.hold.progress(at: now) }

    private var holdControl: some View {
        let isFocused = focus == .hold
        let remaining = max(1, Int(ceil(ParentGateView.holdSeconds * (1 - holdProgress))))
        return VStack(spacing: 24) {
            ZStack {
                Circle().stroke(Theme.surfaceRaised, lineWidth: 24)
                Circle().trim(from: 0, to: holdProgress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 24, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.system(size: 64))
                    Text(session.hold.isHolding ? "Keep holding" : "Hold").font(Theme.bodyFont).bold()
                }
            }
            .frame(width: 300, height: 300)
            .padding(24)
            .background(Circle().fill(Theme.surface))
            .overlay(Circle().stroke(Theme.focusRing, lineWidth: isFocused ? 8 : 0))
            .scaleEffect(isFocused && !reduceMotion ? 1.06 : 1.0)
            .focusable()
            .focused($focus, equals: .hold)
            .onLongPressGesture(minimumDuration: ParentGateView.holdSeconds, perform: {
                completeHold()
            }, onPressingChanged: { pressing in
                if pressing {
                    let d = Date()
                    now = d
                    session.holdBegan(at: d)
                } else {
                    session.holdCancelled()
                }
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hold to continue")
            .accessibilityHint("Press and hold the Select button for \(Int(ParentGateView.holdSeconds)) seconds. This is for grown-ups.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Continue to the question") { skipHoldForAssistiveTech() }
            .a11yID("parentgate.hold")

            Text(session.hold.isHolding
                 ? "Keep holding… \(remaining) more second\(remaining == 1 ? "" : "s")"
                 : "Press and hold the Select button for \(Int(ParentGateView.holdSeconds)) seconds.")
                .font(Theme.bodyFont).multilineTextAlignment(.center)
            if let notice = notice {
                Text(notice).font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func completeHold() {
        // The system measured a continuous hold; the small tolerance covers the gap between the two callbacks.
        if !session.hold.isHolding { session.holdBegan(at: Date().addingTimeInterval(-ParentGateView.holdSeconds)) }
        session.holdTick(at: Date().addingTimeInterval(0.5), challengeSeed: ParentGateView.newSeed())
    }

    private func skipHoldForAssistiveTech() {
        session.holdBegan(at: Date().addingTimeInterval(-ParentGateView.holdSeconds - 1))
        session.holdTick(at: Date(), challengeSeed: ParentGateView.newSeed())
    }

    // MARK: Challenge

    private func challengeView(_ c: AdultChallenge) -> some View {
        VStack(spacing: 28) {
            Text("One quick question to continue").font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
            Text(c.prompt).font(Theme.headingFont).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .a11yID("parentgate.prompt")
            if let notice = notice {
                Text(notice).font(Theme.captionFont).foregroundStyle(Theme.textSecondary).a11yID("parentgate.notice")
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 32), GridItem(.flexible(), spacing: 32)], spacing: 32) {
                ForEach(0..<c.options.count, id: \.self) { i in
                    Button { answer(i) } label: {
                        Text(c.options[i]).font(Theme.headingFont).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FocusCardStyle())
                    .focused($focus, equals: .answer(i))
                    .a11yID("parentgate.answer.\(i)")
                    .accessibilityLabel("Answer \(c.options[i])")
                    .accessibilityHint("Choose this answer")
                }
            }
            .focusSection()
        }
    }

    private func answer(_ i: Int) {
        let t = Date()
        now = t
        session.answer(optionIndex: i, at: t, nextSeed: ParentGateView.newSeed())
        ParentGateView.saveLockout(session.lockout)
        switch session.stage {
        case .challenge: notice = "Not quite. Here is another question."
        default: notice = nil
        }
    }

    // MARK: Lockout

    private func lockedView(_ until: Date) -> some View {
        let secs = max(1, Int(ceil(until.timeIntervalSince(now))))
        let text = secs >= 60 ? "\(secs / 60) min \(secs % 60) s" : "\(secs) seconds"
        return VStack(spacing: 20) {
            Image(systemName: "clock").font(.system(size: 90))
            Text("Let's take a short break.").font(Theme.headingFont)
            Text("Please try again in \(text).").font(Theme.headingFont).monospacedDigit()
            Text("Nothing is wrong. The grown-ups' area just waits for a moment after a few wrong answers.")
                .font(Theme.captionFont).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Locked for a short break. Please try again in a little while.")
        .a11yID("parentgate.locked")
    }

    // MARK: Timer

    private func tick(_ date: Date) {
        switch session.stage {
        case .hold:
            if session.hold.isHolding {
                now = date
                session.holdTick(at: date, challengeSeed: ParentGateView.newSeed())
            }
        case .lockedOut:
            now = date
            session.refresh(at: date)
        default:
            break
        }
    }

    // MARK: Persistence (so the lockout survives relaunch)

    private static func newSeed() -> UInt64 { UInt64.random(in: UInt64.min...UInt64.max) }

    private static func loadLockout() -> GateLockout {
        guard let d = UserDefaults.standard.data(forKey: lockoutKey),
              let l = try? JSONDecoder().decode(GateLockout.self, from: d) else { return GateLockout() }
        return l
    }

    private static func saveLockout(_ l: GateLockout) {
        if let d = try? JSONEncoder().encode(l) { UserDefaults.standard.set(d, forKey: lockoutKey) }
    }

    /// Called by "Delete everything" so no gate state outlives a full wipe.
    static func clearStoredLockout() { UserDefaults.standard.removeObject(forKey: lockoutKey) }
}
