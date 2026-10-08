import XCTest
@testable import StorySoundsCore

/// Every audio id a generated activity can reference must exist in the REAL bundled manifest.
final class AudioIdCoverageTests: XCTestCase {
    private func ids(of a: Activity) -> [String] {
        var out: [String] = a.audioIds
        func add(_ cs: [Choice]) { for c in cs { if let id = c.audioId { out.append(id) } } }
        switch a.payload {
        case let .choose(choices, _, _): add(choices)
        case let .blend(_, _, choices, _): add(choices)
        case let .picture(_, choices): add(choices)
        case let .tricky(_, choices): add(choices)
        case let .sentence(_, _, choices, _): add(choices)
        case let .story(_, _, questions): for q in questions { add(q.choices) }
        case .order, .segment, .build, .fluency: break
        }
        return out
    }

    func testEveryAudioIdOfEveryGeneratedActivityResolvesInTheBundledManifest() throws {
        let curriculum = try Curriculum.loadBundled()
        let index = CurriculumIndex(curriculum)
        let manifest = try AudioManifest.loadBundled()
        let library = AudioLibrary(manifest: manifest, bundleResolver: { _ in nil })

        var checked = 0
        var missing: [String: String] = [:]   // id -> first activity key that referenced it
        var typesSeen = Set<ActivityType>()
        for extra in [0, 12] {
            for u in index.units {
                let known = min(index.maxOrder, u.order + extra)
                for type in ActivityGenerator.supportedTypes(index: index, unitId: u.id, knownOrder: known) {
                    for seed in 0..<3 {
                        var rng = SeededRNG(seed: UInt64(seed))
                        let spec = ActivitySpec(unitId: u.id, type: type, knownOrder: known, choiceCount: 3)
                        guard let a = ActivityGenerator.generate(curriculum: curriculum, index: index, spec: spec, rng: &rng) else { continue }
                        typesSeen.insert(type)
                        for id in ids(of: a) {
                            checked += 1
                            if library.entry(for: id) == nil && missing[id] == nil { missing[id] = a.key }
                            if id.hasPrefix("w-") { XCTAssertEqual(id, id.lowercased(), "word audio ids must be lower-case: \(id) in \(a.key)") }
                        }
                        // The easier guided variant references the same audio.
                        for id in ids(of: ActivityGenerator.simplify(a)) where library.entry(for: id) == nil && missing[id] == nil {
                            missing[id] = a.key + "~easy"
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 1000)
        XCTAssertTrue(missing.isEmpty, "audio ids with no manifest entry: \(missing.sorted { $0.key < $1.key })")
        // The sweep must actually reach the interesting types (tricky words, sentences with names, stories).
        for t in [ActivityType.identifyTricky, .completeSentence, .readStory, .blendToWord, .listenChooseSound] {
            XCTAssertTrue(typesSeen.contains(t), "sweep never produced \(t)")
        }
    }

    func testEveryWordTrickyWordAndSentenceTokenHasACaseSafeManifestEntry() throws {
        let curriculum = try Curriculum.loadBundled()
        let manifest = try AudioManifest.loadBundled()
        let library = AudioLibrary(manifest: manifest, bundleResolver: { _ in nil })
        var texts: [String] = curriculum.words.map { $0.text }
        texts.append(contentsOf: curriculum.trickyWords.map { $0.text })
        for s in curriculum.sentences {
            for t in s.tokens { texts.append(t.text) }
        }
        XCTAssertTrue(texts.contains("I"), "the curriculum is expected to contain the tricky word I")
        for text in texts {
            let id = AudioIds.word(text)
            XCTAssertNotNil(library.entry(for: id), "no audio entry for \(text) (\(id))")
        }
        for id in ["w-i", "w-mr", "w-mrs", "w-ms"] { XCTAssertNotNil(library.entry(for: id), id) }
    }

    func testManifestIdsAreUniqueAndWordIdsAreLowerCase() throws {
        let manifest = try AudioManifest.loadBundled()
        let ids = manifest.entries.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate audio ids")
        for e in manifest.entries where e.kind == .word { XCTAssertEqual(e.id, e.id.lowercased()) }
    }
}
