import SwiftUI
import StorySoundsCore

/// The "story world": every sticker the child has earned sits on a calm scene. Nothing is ever removed and
/// nothing is ranked. Positions are derived from the sticker id so the scene is stable between visits.
@MainActor
struct StickerBookView: View {
    @EnvironmentObject private var env: AppEnvironment
    let onClose: () -> Void
    @FocusState private var backFocused: Bool

    private var stickers: [StickerInfo] {
        env.snapshot.profile.stickers.map { StickerCatalog.info(for: $0, index: env.index) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 28) {
                Text("My story world")
                    .font(Theme.titleFont)
                    .accessibilityAddTraits(.isHeader)
                    .a11yID("stickers.title")
                Spacer()
                Text(stickers.count == 1 ? "1 sticker" : "\(stickers.count) stickers")
                    .font(Theme.headingFont).foregroundStyle(Theme.accent)
                    .a11yID("stickers.count")
            }
            scene
            HStack {
                StoryButton(action: onClose) {
                    Label("Back", systemImage: "chevron.left").font(Theme.bodyFont)
                }
                .focused($backFocused)
                .accessibilityLabel("Back to home")
                .a11yID("stickers.back")
                if stickers.isEmpty {
                    Text("Play today's adventure to find your first sticker.")
                        .font(Theme.bodyFont).foregroundStyle(Theme.textSecondary)
                        .padding(.leading, 24)
                }
                Spacer()
            }
        }
        .screenContainer()
        .defaultFocus($backFocused, true)
        .task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            backFocused = true
        }
        .onExitCommand { onClose() }
    }

    private var scene: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.16, green: 0.30, blue: 0.48), Color(red: 0.55, green: 0.55, blue: 0.62)],
                               startPoint: .top, endPoint: .bottom)
                Circle().fill(Theme.accent.opacity(0.9)).frame(width: 110, height: 110)
                    .position(x: w * 0.86, y: h * 0.16)
                Ellipse().fill(Color(red: 0.20, green: 0.42, blue: 0.34))
                    .frame(width: w * 1.1, height: h * 0.55).position(x: w * 0.25, y: h * 1.0)
                Ellipse().fill(Color(red: 0.27, green: 0.52, blue: 0.38))
                    .frame(width: w * 0.9, height: h * 0.45).position(x: w * 0.8, y: h * 1.02)
                ForEach(Array(stickers.suffix(80).enumerated()), id: \.offset) { _, s in
                    let p = position(for: s, in: CGSize(width: w, height: h))
                    Text(s.emoji)
                        .font(.system(size: 72))
                        .position(x: p.x, y: p.y)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your story world")
        .accessibilityValue(stickers.isEmpty ? "No stickers yet" : stickers.map { $0.title }.joined(separator: ", "))
        .a11yID("stickers.scene")
    }

    /// Effort stickers sit in the meadow, practice stickers in the sky, mastery stickers on the hills.
    private func position(for s: StickerInfo, in size: CGSize) -> CGPoint {
        let hash = SeededRNG.stableHash(s.id)
        let fx = Double(hash % 1000) / 1000.0
        let fy = Double((hash / 1000) % 1000) / 1000.0
        let x = 60 + fx * Double(max(1, size.width - 120))
        let band: (lo: Double, hi: Double)
        switch s.kind {
        case .practice: band = (0.06, 0.34)
        case .mastery: band = (0.38, 0.62)
        case .effort: band = (0.64, 0.90)
        case .welcome: band = (0.30, 0.40)
        }
        let y = (band.lo + fy * (band.hi - band.lo)) * Double(size.height)
        return CGPoint(x: x, y: y)
    }
}
