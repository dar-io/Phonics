import Foundation
import StorySoundsCore

/// Which recording a tapped grapheme tile plays. Pedagogy B1: the sound must match the WORD the tile belongs to
/// (`o` in `cold` is /oa/, not the first-taught /o/). The package resolves this from the word's requirements.
enum GraphemeAudio {
    @MainActor
    static func audioId(index: CurriculumIndex, grapheme: String, inWord word: String) -> String? {
        if let id = index.audioId(forGrapheme: grapheme, inWord: word) { return id }
        // Unknown word or grapheme: fall back to the first-taught reading rather than staying silent.
        return index.audioId(forGrapheme: grapheme, atOrder: index.maxOrder)
    }
}
