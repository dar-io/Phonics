import SwiftUI
import StorySoundsCore

/// Plain-English explainers for the Progress section (static copy; no live data).
enum ParentExplainers {
    struct Term { let heading: String; let text: String }

    static let first: [Term] = [
        Term(heading: "Phonemes", text: "The smallest sounds in spoken words. 'cat' has three: c, a, t. Children hear and say sounds before they link them to letters."),
        Term(heading: "Graphemes", text: "The letters that stand for a sound. A grapheme can be one letter (t) or more (sh, igh). 'ship' has three graphemes: sh, i, p."),
        Term(heading: "Blending", text: "Saying each sound in order and pushing them together to read a word: c-a-t, cat. This is the key skill for reading."),
    ]
    static let second: [Term] = [
        Term(heading: "Segmenting", text: "The opposite of blending: hearing a word and splitting it into its sounds so it can be spelled. 'dog' becomes d-o-g."),
        Term(heading: "Tricky words", text: "Words with a part that does not follow the usual sound-letter pattern, like 'the' or 'said'. Children learn the tricky part by heart and sound out the rest."),
        Term(heading: "Phonics", text: "Phonics teaches reading by linking sounds to the letters that stand for them, so children can work out words they have never seen."),
    ]
}

struct ParentExplainerPage: View {
    let terms: [ParentExplainers.Term]
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ForEach(Array(terms.enumerated()), id: \.offset) { _, t in
                ParentInfoBlock(heading: t.heading, text: t.text)
            }
        }
    }
}

struct ParentAboutPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            ParentInfoBlock(heading: "Alongside teaching, not instead of it",
                      text: "Story Sounds supplements teaching at school and sharing books together. It does not replace either.")
            ParentInfoBlock(heading: "Independent",
                      text: "This app is independent. It is not affiliated with or endorsed by Little Wandle or any school.")
            ParentInfoBlock(heading: "Your say",
                      text: "You can choose what is practised next, how long a session is, and how quickly sounds count as secure.")
        }
    }
}

/// Units per term for Reception and Year 1, side by side.
struct ParentCurriculumGlance: View {
    let index: CurriculumIndex

    private struct TermCount: Identifiable { let id: String; let name: String; var count: Int }

    private func terms(for stage: Stage) -> [TermCount] {
        var out: [TermCount] = []
        for u in index.units where u.stage == stage {
            var name = u.term
            if let r = name.range(of: ",") { name = String(name[name.startIndex..<r.lowerBound]) }
            if let r = name.range(of: " (") { name = String(name[name.startIndex..<r.lowerBound]) }
            for prefix in ["Reception ", "Year 1 "] where name.hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)) }
            if let i = out.firstIndex(where: { $0.name == name }) { out[i].count += 1 }
            else { out.append(TermCount(id: stage.rawValue + name, name: name, count: 1)) }
        }
        return out
    }

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            column("Reception", terms(for: .reception))
            column("Year 1", terms(for: .year1))
        }
    }

    private func column(_ title: String, _ rows: [TermCount]) -> some View {
        let total = rows.reduce(0) { $0 + $1.count }
        return VStack(alignment: .leading, spacing: 14) {
            Text("\(title): \(total) steps").font(.system(size: 42, weight: .semibold, design: .rounded)).foregroundStyle(Theme.accent)
            ForEach(rows.prefix(6)) { r in
                HStack {
                    Text(r.name).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 12)
                    Text("\(r.count)").bold().monospacedDigit()
                }
                .font(Theme.bodyFont)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(r.name): \(r.count) steps")
            }
            Text("Each step is a sound and the letters that spell it.").font(Theme.captionFont).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
