import SwiftUI
import StorySoundsCore

enum ParentSection: String, CaseIterable, Identifiable, Hashable {
    case progress, practice, skills, audio, settings, data
    var id: String { rawValue }

    var title: String {
        switch self {
        case .progress: return "Progress"
        case .practice: return "Today's practice"
        case .skills: return "Skills"
        case .audio: return "Sound & audio"
        case .settings: return "Settings & accessibility"
        case .data: return "Your data"
        }
    }
    var subtitle: String {
        switch self {
        case .progress: return "How learning is going"
        case .practice: return "A five-minute idea"
        case .skills: return "Every sound, and why"
        case .audio: return "What you will hear"
        case .settings: return "Length, volume, comfort"
        case .data: return "Privacy, backup, reset"
        }
    }
    var symbol: String {
        switch self {
        case .progress: return "chart.bar.fill"
        case .practice: return "clock.fill"
        case .skills: return "list.bullet"
        case .audio: return "speaker.wave.2.fill"
        case .settings: return "gearshape.fill"
        case .data: return "lock.shield.fill"
        }
    }
}

/// Entry point for the grown-ups' area (gate, then a menu of large cards). Leaves with `env.route = .home`.
@MainActor
struct ParentAreaView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @State private var unlocked = false
    @State private var open: ParentSection?
    @State private var lastOpened: ParentSection = .progress
    @FocusState private var menuFocus: ParentSection?
    @FocusState private var leaveFocused: Bool

    var body: some View {
        Group {
            if !unlocked {
                ParentGateView(onUnlocked: { unlocked = true }, onExit: leave)
            } else if let section = open {
                sectionView(section)
            } else {
                menu
            }
        }
        // Gentle mode also calms the focus motion in the grown-ups' area.
        .environment(\.calmMotion, env.calmMotion)
        // Re-arm the gate if the app leaves the foreground.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { unlocked = false; open = nil }
        }
    }

    // MARK: Menu

    private var menu: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Grown-ups' area").font(Theme.titleFont).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 32), count: 3), spacing: 32) {
                ForEach(ParentSection.allCases) { section in
                    Button { lastOpened = section; open = section } label: {
                        VStack(spacing: 12) {
                            Image(systemName: section.symbol).font(Theme.iconMediumFont)
                            Text(section.title).font(Theme.subheadingFont.bold())
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            Text(section.subtitle).font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                    }
                    .buttonStyle(FocusCardStyle())
                    .focused($menuFocus, equals: section)
                    .a11yID("parent.menu.\(section.rawValue)")
                    .accessibilityLabel(section.title)
                    .accessibilityHint(section.subtitle)
                }
            }
            .focusSection()
            HStack {
                Spacer()
                Button(action: leave) {
                    Label("Leave grown-ups' area", systemImage: "arrow.uturn.backward").font(Theme.bodyFont)
                }
                .buttonStyle(FocusCardStyle())
                .focused($leaveFocused)
                .a11yID("parent.menu.leave")
                .accessibilityLabel("Leave grown-ups' area")
                .accessibilityHint("Returns to the Story Sounds home screen. The Menu button does the same.")
                Spacer()
            }
            .focusSection()
        }
        .screenContainer()
        .defaultFocus($menuFocus, lastOpened)
        .onAppear { menuFocus = lastOpened }
        .onExitCommand(perform: leave)
    }

    // MARK: Navigation

    private func leave() {
        unlocked = false
        open = nil
        env.route = .home
    }

    /// Back from a section: return to the menu and put focus back on the card that opened it.
    private func close() {
        open = nil
        DispatchQueue.main.async { menuFocus = lastOpened }
    }

    @ViewBuilder private func sectionView(_ section: ParentSection) -> some View {
        switch section {
        case .progress: ParentProgressView(onClose: close)
        case .practice: ParentPracticeView(onClose: close)
        case .skills: ParentSkillsView(onClose: close)
        case .audio: ParentAudioView(onClose: close)
        case .settings: ParentSettingsView(onClose: close)
        case .data: ParentDataView(onClose: close)
        }
    }
}
