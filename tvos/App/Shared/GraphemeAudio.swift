import Foundation
import StorySoundsCore

/// Which recording a tapped grapheme tile plays. Pedagogy B1: the sound must match the WORD the tile belongs to
/// (`o` in `cold` is /oa/, not the first-taught /o/).
/// TODO(core): when `CurriculumIndex.audioId(forGrapheme:inWord:)` lands in StorySoundsCore, call it from the marked
/// line below and delete the fallback. Until then this forwards to the first-taught reading, exactly as before.
enum GraphemeAudio {
    @MainActor
    static func audioId(index: CurriculumIndex, grapheme: String, inWord word: String) -> String? {
        // TODO(core): return index.audioId(forGrapheme: grapheme, inWord: word) ?? <fallback below>
        return index.audioId(forGrapheme: grapheme, atOrder: index.maxOrder)
    }
}
