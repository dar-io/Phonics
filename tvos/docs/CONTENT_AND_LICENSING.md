# Content and licensing

This is a factual record, not legal advice. Statements about who wrote what come from the project's authoring records and brief; the repository cannot prove authorship on its own, so the owner should confirm them before publishing.

## 1. Original content statement

The following were authored for this project:

- the words, sentences and stories (in `curriculum-tools/src/curriculum/author/*.ts`, compiled into `curriculum.json`);
- the pronunciation guidance, misconception notes and parent-facing text;
- the picture choices (emoji assignments and picture labels, chosen per word);
- the characters and art drawn in code (the bird "Wren", the sticker scene, built only from SwiftUI shapes);
- the app icon and Top Shelf artwork (`App/Assets.xcassets`).

The project uses no third-party worksheets, decodable books, recordings or illustrations, and no Little Wandle assets (texts, books, images, recordings, branding or fonts). The authoring guide says the same: "All words, sentences and stories are original." The only external material consulted was the layout of other schools' published phonics overviews, which informed the order of sounds (section 3); no text or images were copied from them.

Notes:
- Individual common English words are not owned by anyone; what is original here is the selection, segmentation, sentences, stories and the guidance text.
- The app has no third-party code or SDKs (`Package.swift` has no dependencies; the Node tools used for authoring are development tools and are not shipped).
- The authoring tools use `zod`, `tsx`, `typescript`, `vitest` and `@types/node` (development only; see `curriculum-tools/package.json`).

## 2. Emoji

Pictures in tasks are Unicode emoji characters (459 of the 1,284 words carry one). The app bundles no emoji images: the text is drawn by the operating system's emoji font. The appearance, design and licensing of those glyphs belong to the operating system vendor, not to this project. Consequences:

- Appearance can change with the tvOS version, and some newer or compound (ZWJ) emoji may be missing on older systems. The deployment target is tvOS 17; the rendering of every emoji used has not been checked.
- Marketing material or screenshots that show the system emoji font may be subject to the platform owner's terms; check them before publishing.
- Several words were deliberately left without a picture because no unambiguous emoji exists (the data marks them `concrete: false`). Ambiguous pairs with different emoji for near-synonyms were resolved by removing one picture.

## 3. Curriculum provenance and uncertainty

Every one of the 99 units carries `source: "inferred"`; the validator rejects `fetched`, so nothing can claim to have been read from an official page.

- The official pages (St Joseph's RBKC phonics and English pages, littlewandle.org.uk parent resources) could not be read: every fetch was blocked (HTTP 403 from the network proxy).
- The sequence was inferred from other schools' published overviews of a Little Wandle style programme, seen only through search-result summaries (five documents, cited by URL in the curriculum map), plus general knowledge of the Letters and Sounds family of programmes.
- Term-level placement is supported by those summaries for Reception; week-by-week order, Reception Spring 2 and Summer, and most of Year 1 (especially the later terms) are inferred and weakly supported. Tricky-word lists differ between versions of the published documents.
- It has not been confirmed that the school uses Little Wandle at all.
- Phase numbers: the whole of units 1 to 37 are labelled phase 2, which includes sounds the Letters and Sounds family usually calls phase 3 (the review flagged this; unchanged).
- Pronunciation guidance was written without review by a phonics lead, without a pronunciation dictionary, and in a UK, non-rhotic model. Accent-dependent words (bath, path, fast, pass, dance, room, roof...) are flagged but the app does not act on the flag.

Details, the five citations and the uncertainty list: [curriculum-tools/docs/curriculum-map.md](../../curriculum-tools/docs/curriculum-map.md); authoring rules: [curriculum-tools/docs/curriculum-authoring.md](../../curriculum-tools/docs/curriculum-authoring.md); the sequence data: [curriculum-tools/docs/research/gpc-sequence.json](../../curriculum-tools/docs/research/gpc-sequence.json). Note that the first heading of `curriculum-map.md` still reads "Little Wandle Letters and Sounds Revised style"; that wording should be neutralised before any of it reaches a public listing (see [REMAINING_WORK.md](REMAINING_WORK.md)).

## 4. Audio status and the recording workflow

### 4.1 Where things stand

All 1,483 entries in `audio-manifest.json` (95 sounds, 1,364 words, 18 instructions, 6 sound effects) are `status: "placeholder"` with `file: null`. There are no audio files in the repository. What a child hears today:

- **Letter sounds**: nothing. They are never synthesised (a computer voice adds an extra "uh"); a written caption is shown instead. The code enforces this in three places and the grown-ups' Sound & audio page says so.
- **Words and instructions**: the system text-to-speech voice, flagged as placeholder speech in the code and described to grown-ups as "Development placeholders - not approved recordings". It has not been reviewed.
- **Sound effects**: silent.

A children's phonics app without real recordings of the sounds is not releasable.

### 4.2 How bundled recordings are meant to work

`AudioLibrary.resolve` uses an entry's `file` only when its status is `recorded` or `verified` and the file can be found in the package's resource bundle (a plain name such as `ph-g-s.m4a` or `dir/name.m4a`; both a subdirectory and a flat lookup are tried). An optional `slowFile` is used for "Slowly"; without one the normal file is played at 0.7 speed. AVFoundation plays the file, so any format it supports works; the examples in the code use `.m4a`. Statuses: `placeholder`, then `recorded`, then `verified` once an adult has checked the pronunciation.

Ids to record: `ph-<unit id>` for each sound (a pure, crisp sound with no added "uh"), `w-<lower-case word>` for words and names, `i-...` for the 18 instruction phrases, `sfx-...` for the six effects. For graphemes with several sounds the right clip is chosen per word (for example `o` in `cold` plays the long-o clip), so every distinct sound needs its own clip.

Suggested order: the 95 sounds and 18 instructions first, then the words that are used earliest, then effects.

### 4.3 A gap in the tooling

The authoring guide says to swap in recordings "by editing only `public/audio/manifest.json`". That does not work today: `npm run build:curriculum` regenerates that file from scratch with every entry as a placeholder and `file: null`, and `npm run sync:tvos` then copies it into the app. A hand-edited manifest would be overwritten by the next `npm run verify`, and the CI drift check would fail if a hand-edited file were committed. The generator needs a recordings overlay (a separate file mapping ids to file and status that the build merges) before this workflow is usable. The manifest `statement` also says "Every entry is a temporary development placeholder", which would be wrong once recordings exist.

### 4.4 Parent recording import is not implemented

`RecordingStore` is a protocol with only an in-memory test double. tvOS has no durable Documents directory, no file sharing and no microphone recording UI, so recordings placed in Caches or tmp could be purged and there is no route to capture or import them. The grown-ups' page says "Recording or importing audio on this Apple TV is not supported yet". A possible future route (for example CloudKit assets, opt-in) is only noted in a code comment. Recordings arrive only inside the app bundle.

## 5. Non-affiliation

Story Sounds is independent. It is not affiliated with, endorsed by or approved by Little Wandle, any school, any publisher, or the authors of any phonics programme. Nothing in it should be described as following, matching or being aligned to a named programme. The statement appears in the app ("Independent" on the grown-ups' About page, the progress summary, the audio page and the audio-status disclaimer) and in the audio manifest.

## 6. Licence

No licence has been chosen for this project, and no `LICENSE` file exists in `tvos/` or `curriculum-tools/`. The repository root `package.json` declares `"license": "MIT"`, but that file belongs to an unrelated Framer starter kit that shares the repository, and does not by itself say how the tvOS app, the curriculum content or the artwork may be used. The owner should decide separately for the code, for the curriculum text and data, and for the artwork (for example one permissive licence for code and a different one for content), and add the file. Do not publish until that is done.
