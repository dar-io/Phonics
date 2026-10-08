import SwiftUI
import StorySoundsCore

/// Sound & audio: honest status of the audio that ships, and how real recordings get added.
@MainActor
struct ParentAudioView: View {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    @EnvironmentObject var env: AppEnvironment
    @State private var page = 0
    @State private var report: AudioStatusReport?

    private static let titles = ["What you hear today", "Adding real recordings"]

    var body: some View {
        ParentPageScaffold(title: "Sound & audio", pageTitle: Self.titles[page], idPrefix: "parent.audio",
                           page: $page, pageCount: Self.titles.count, onBack: onClose) {
            if page == 0 { status } else { howTo }
        }
        .onAppear { if report == nil { report = AudioLibrary(manifest: env.manifest).statusReport() } }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("Development placeholders — not approved recordings", systemImage: "exclamationmark.triangle.fill")
                .font(Theme.subheadingFont.bold())
                .padding(.vertical, 12).padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surfaceRaised))
                .accessibilityAddTraits(.isHeader)
                .a11yID("parent.audio.banner")
            if let r = report {
                Grid(alignment: .leading, horizontalSpacing: 36, verticalSpacing: 10) {
                    GridRow {
                        Text("")
                        Text("Placeholder").bold(); Text("Recorded").bold(); Text("Verified").bold()
                    }
                    countRow("Sounds", r.counts(for: .phoneme))
                    countRow("Words", r.counts(for: .word))
                    countRow("Instructions", r.counts(for: .instruction))
                    countRow("Effects", r.counts(for: .sfx))
                    countRow("All audio", r.total, bold: true)
                }
                .font(Theme.bodyFont)
                .accessibilityElement(children: .contain)
                .a11yID("parent.audio.counts")
            } else {
                Text("Checking audio…").font(Theme.bodyFont)
            }
            Text("Placeholder means there is no real recording yet. Letter sounds are never made by a computer voice, so a missing sound shows as a caption instead.")
                .font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
        }
    }

    private func countRow(_ name: String, _ c: AudioStatusReport.Counts, bold: Bool = false) -> some View {
        GridRow {
            Text(name).bold(bold)
            Text("\(c.placeholder)").monospacedDigit()
            Text("\(c.recorded)").monospacedDigit()
            Text("\(c.verified)").monospacedDigit()
        }
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 26) {
            ParentInfoBlock(heading: "How recordings are added",
                      text: "Put the audio files in the app's resources and list them in audio-manifest.json with the file name and a status of recorded or verified. No code change is needed; rebuild the app and the new sounds are used automatically.")
            ParentInfoBlock(heading: "Not available on Apple TV yet",
                      text: "Recording or importing audio on this Apple TV is not supported yet. It is a documented to-do, so for now recordings arrive only inside the app.")
        }
    }
}
