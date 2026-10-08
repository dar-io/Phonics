# Remaining work

Built from the open findings in the four reviews ([reviews/](reviews)), checked against the current code (read or searched; not run on a device), plus the verification gaps. The reviews describe an earlier state of the code, and a large part of their findings has since been fixed (section 5 lists those, so nobody re-does them). "Open" below means the problem was found still present in the code today.

Priorities: **P0** before any child uses the app or it is submitted to the App Store; **P1** before a wider release; **P2** quality and polish.

## P0: must do first

| # | Work | Why / evidence |
|---|---|---|
| 1 | **Record real audio** for the 95 sounds, then the 18 instructions, then words and effects; get an adult or phonics lead to check each sound ("recorded" then "verified") | All 1,483 manifest entries are placeholders with no file. Letter sounds are shown as captions only; words and instructions use system speech. A phonics app without real sounds is not releasable |
| 2 | **Fix the recording workflow in the generator** | `npm run build:curriculum` rewrites the manifest as all-placeholder, so recordings listed by hand are overwritten, and CI's drift check would fail. Add an overlay file the build merges, and update the manifest `statement` |
| 3 | **Test on a real Apple TV with a real Siri Remote** | Never done. In particular: the 3-second press-and-hold in the parent gate (the source file itself says unverified), focus movement and restoration, Menu and Play/Pause behaviour, the "Gentle mode keeps focus" fix, performance, audio-session interruptions, and how the icon, Top Shelf and screens actually look |
| 4 | **Check overscan and the safe area on a TV** | Container padding was cut from 80/60 to 20/10 pt on the assumption that SwiftUI already insets content by the system safe area; unverified. The two-by-two choose screen and the parent pages were reasoned to fit, not seen |
| 5 | **Have a phonics lead review the curriculum**: sequence, phase labels, grapheme choices, pronunciation guidance, tricky-word lists, words flagged accent-dependent, and the audio recording brief | Everything is `source: inferred`. Official sources were unreachable (403). No expert has reviewed it |
| 6 | **Verify the sequence against the official source** if the school's programme matters, and record the result in `curriculum-map.md` | The school's programme is not even confirmed to be Little Wandle |
| 7 | **Real VoiceOver pass**, and fix the open accessibility items in [ACCESSIBILITY.md](ACCESSIBILITY.md) section 4 (m-11 phoneme labels, m-3 auto focus moves, m-8 and m-9 contrast, M-8 remainder) | VoiceOver has never been run; announcements are untested |
| 8 | **Supervised pilot with a few children and an adult** before wider use | The pedagogy review judged the engine "fit for supervised pilot use" only after its fixes, and no child has used it. Check the baseline, the pace, session length and the parent gate with real children |
| 9 | **Neutralise the "Little Wandle ... style" heading** in `curriculum-tools/docs/curriculum-map.md` (line 1) | Open since review F-14; the rest of the app and documents say "independent, not affiliated" |
| 10 | **Choose a licence** for code, curriculum data and artwork; add the `LICENSE` file | None exists (see [CONTENT_AND_LICENSING.md](CONTENT_AND_LICENSING.md)) |
| 11 | **Decide on iCloud backup**: test it end to end on a signed build with the capability (backup, restore on a second Apple TV, delete), or hide it for the first release | Never exercised; the entitlement exists but sync is unproven |
| 12 | **App Store preparation**: development team and real bundle id, version and build numbers, privacy policy, App Privacy questionnaire, age rating, screenshots and metadata, Kids Category requirements (including how Apple would judge the parent gate), privacy-manifest validation, a Release-build archive | Nothing in the repository covers these; no approval is claimed |
| 13 | **Build and run a Release configuration** and confirm the DEBUG-only launch arguments and test hooks are absent | They are wrapped in `#if DEBUG`, but no test exercises Release |

## P1: before a wider release

Learning engine and content
- **Mastery evidence ignores item variety** (`Mastery` never reads `itemKey`): a half-knowing child can become secure; require, for example, four distinct items among the last eight and five of the last six correct. Open (pedagogy m4).
- **Response time**: `useResponseTime` is on by default, is not exposed to grown-ups, and is measured from when the activity appears, so it includes the spoken prompt. Either measure from the end of the prompt or default it off. Open (pedagogy m13, code-quality minor 3).
- **Baseline**: the plan has 16 samples but the view stops at 10, so the later six are never asked. Decide the right number and make the plan, the view and the documentation agree.
- **Plural `-s` as /z/** (about 126 words) is untaught and the tile plays /s/. Add a unit or exclude those words from blending until taught. Open (m5).
- **Year 1 tricky words** missing (`where who once friend any many again two from`). Open (m9).
- **Pronunciation wording**: `er` says "a hint of r" while `air` says "no r"; `c` says "click"; `igh` is described as "the same as the letter name I". Open (m8 and others).
- **Phase labels**: units 1 to 37 are all `phase 2`. Open (m1).
- **Alternative-pronunciation units** gate on isolated recognition, not on choosing the right sound inside a word. Open by design (m14).
- **Pace**: two days per unit by default is about 200 sessions end to end. Decide whether the defaults suit the target children.
- **Vocabulary and names**: `pill`, `weed`, `kiss`, `nail`, `fat`, `smoke` remain as words (their emoji were removed); all names are Anglo (no Ali, Asha, Kofi, Mei...). Open (m11, m12).
- `decodablePartsKnown` is inconsistent for `is`, `like`, `when` (not read by the engine). Open (m10).
- `accentNote` is in the data but the Swift model ignores it. Either use it (for example avoid those words in picture tasks) or drop it.
- Emoji rendering on tvOS 17 (especially the compound ones) has not been checked.
- Add a "read aloud to a grown-up" mode, or document clearly that reading tasks are on-screen multiple choice (pedagogy section 4.5).

Parent controls and household
- **Household profiles (`TVUserManager`) are not implemented.** `AppEnvironment.currentUserScope()` returns nil by design and TVServices is not imported, so all children share one profile. Siblings are not supported.
- **Parent overrides**: `ParentPracticeActions.unmark` removes all overrides for a unit, including an earlier `unlocked`; `mark` stamps `Date()` instead of the app's clock. Two separate `overrideFocusUnit` functions (package and app) should be reconciled. Open (code-quality minor 6).
- "Stored on this Apple TV only" on the privacy page is unqualified when iCloud backup is on. Open.

Persistence and robustness
- **Measure real UserDefaults usage** on a device after weeks of use, against the roughly 500 KB limit (budgets were lowered but not measured, and the read-back check proves acceptance, not durability).
- `PersistenceCoordinator`: after a failed save there is no retry until the next change; a failed flush leaves the "could not save" flag until then. Open (code-quality minor 16).
- Codable forward compatibility: only `MasterySettings`, `Word` and the curriculum types decode leniently; adding a field to `SkillState`, `LearnerProfile` and similar types would fail to decode old data until a migration is written. There is no migration yet (`Migrator.standard` is empty) and no test with a real older fixture. Open (code-quality minor 18).
- `AppEnvironment.blankManifest` still contains a `fatalError`; `Bundle.module` traps if the resource bundle is missing. Open (privacy F-12).
- `SessionModel.finish` returns nil if called twice, which can send the child home instead of to the summary. Not re-checked in detail (code-quality minor 5).
- Provisional (baseline) skills appear as "due reviews" in the planner after one to seven days, but the parent view hides them; probably intended, not documented elsewhere (code-quality minor 9).

Accessibility (see [ACCESSIBILITY.md](ACCESSIBILITY.md) section 4 for the full list)
- Home "Sound" and "Gentle mode" need the toggle trait; blend tiles need a "played" state; the guided tile needs a spoken "next"; auto focus moves in the blend task should be off in Gentle mode and with VoiceOver; "tried" and "used" states need contrast; Increase Contrast; a sample sound when volume changes.

## P2: quality and polish

- Split `AppEnvironment` (storage, audio, navigation) into smaller objects so leaf views are environment-free.
- Remove dead code: `SeededGenerator` (a duplicate of `SeededRNG` in `Parent/ParentGate.swift`), `Mastery.isUnitMastered` (duplicates the `Progression` one), `GraphemeUnit.reviewIntervalsDays`, `HillsDecoration`, `InMemoryRecordingStore` outside tests, other unreferenced helpers named in the code-quality review section 3 item 22.
- Use Core's `activeProfileId` in place of the app's `ProfileSelection` stand-in (`TODO(core)` in `AppEnvironment.swift`).
- Update the stale header comment in `App/Parent/ParentBackupController.swift` (it says the controller is not wired; it is).
- Compactor: `fold` can re-add a pruned confusion as a count of one; fold into the existing record or skip. Open (code-quality minor 8).
- Replace the remaining `DispatchQueue.main.asyncAfter` focus nudges with one helper; keep `defaultFocus`.
- Tests: `AppEnvironment` has no unit tests (the unit-test target links only the package); UI tests are tied to copy strings and use a duplicated adult-question solver; add a Codable older-fixture test.
- Upload the `.xcresult` bundles from CI, not only the logs.
- Feedback prints raw grapheme labels such as `a_e`; say "a ... e". Minor.
- Mastery sticker names such as "Sound /s/" are not pre-reader friendly; the "effort" sticker threshold of three activities is low.

## Verification gaps (what has never been checked)

- A real Apple TV and Siri Remote; real VoiceOver; overscan; anything visual (no screenshot has been inspected); the app icon and Top Shelf appearance.
- Real audio: none exists. Pronunciation has not been reviewed by a person.
- iCloud backup and restore, end to end.
- The curriculum against official sources; the pronunciation guidance by a phonics lead.
- Behaviour with a child, including whether the thresholds feel right.
- A Release build, an archive, and App Store Connect validation.
- Memory, storage and performance on device.

## Fixed since the reviews (for the record; verified by reading the code)

So these are not re-opened by mistake. "Fixed" means the change is present in the code and, for logic, covered by unit tests; not device-verified.

- Pedagogy: B1 per-word sound for letter tiles (`audioId(forGrapheme:inWord:)`); B2 no trap (soft pass, working parent "unlock"); M1 baseline placement now steps back three units and ignores samples above the first miss; M2 homophone and ambiguous-cloze distractors; M3 voiced and unvoiced `th` are separate units; M4 `p4-suffix` no longer has a recognition gate; M5 units 1 and 2 are introductions, not evidence; M6 wrong or ambiguous emoji removed from the data; M7 `gnaw` and similar segmentation fixed and a pronunciation audit script runs in CI.
- Code quality: the load-error screen crash; restore and profile selection; overrides now change what is played; speech no longer queues up; storage budgets; deterministic UI tests (`-uitest-seed`, `-uitest-session-minutes`, `-uitest-first-choice-wrong`) and no `XCTSkip`; case-safe audio ids with a coverage test; captions wired and the Music control removed; iCloud entitlement; destructive actions re-arm the save on failure; local-day counting; one old error no longer demotes a secure skill; single-choice items are not evidence; `.inactive` only flushes.
- Privacy and security: F-1, F-2, F-4 to F-11, F-13 (see [PRIVACY_AND_CHILD_SAFETY.md](PRIVACY_AND_CHILD_SAFETY.md) section 8).
- Accessibility: B-1, M-1 to M-5, m-1, m-2, m-4 to m-7, and parts of M-6, M-7, M-8, m-10 (see [ACCESSIBILITY.md](ACCESSIBILITY.md)).
