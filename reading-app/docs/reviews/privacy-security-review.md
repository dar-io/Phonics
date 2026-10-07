# Story Sounds (tvOS) - Independent Privacy, Child-Safety and Security Review

Scope: `/home/user/framer-bridge-starter-kit/tvos` (App/, Sources/StorySoundsCore, Tests, UITests, project.yml, Package.swift), about 12.7k lines of Swift. Read-only review; no source edited. Findings come from reading the code and grepping, not from comments. Nothing was compiled or run (no Swift toolchain in this environment), so runtime behaviour on a device is unverified.

## Verdict

CONDITIONAL PASS. No BLOCKER was found. The privacy posture is genuinely strong: the app has no network code, no analytics, no ads, no outbound links, no free-text input, and collects only a preset nickname plus learning progress. Do not ship to the Kids Category yet, though, until the 4 MAJOR items below are fixed. The two that matter most are:

1. The parent gate is a 4-option multiple-choice question that a child can pass about 58% of the time per lockout round by tapping at random (F-1).
2. A failed or corrupt profile load silently starts a new profile, and a later launch may then load the wrong one (F-3).

Counts: 0 BLOCKER, 4 MAJOR, 9 MINOR, plus informational notes.

---

## 1. Data collected and stored - verified

Searches for `URLSession`, `URL(string:`, `http`, `Network`, `WebKit`, `SafariServices`, `openURL`, `Link(`, `ShareLink`, `mailto`, `os_log`, `Logger`, `NSLog`, `print(`, `CoreLocation`, `AVAudioRecorder`, `Speech` (recognition), `AdSupport`, `analytics` across `App/` and `Sources/` returned **no network, logging, analytics, ads, web or external-link code**. The only `URL(string:)` hits are `file:///` fixtures in tests. The bundled `curriculum.json` has zero `http(s)://` strings. Its `citation` fields name third-party school domains as text only. Nothing in the UI renders them (the `citation` property is declared at `Models/Curriculum.swift:33` and never read by the UI).

Persistent stores actually used (complete list):

| Store | Key(s) | Content |
|---|---|---|
| UserDefaults | `storysounds.learner.<scope>.snap.<id>.<gen>` and `.ptr.<id>` | Learner snapshot JSON: random UUID, preset nickname, created date, settings, skill scores, attempts (item keys, correct/incorrect, chosen/expected grapheme, response ms), sessions, stickers |
| UserDefaults | `storysounds.privacy.<scope>` | `iCloudBackupEnabled` (default false), `lastBackupAt` |
| UserDefaults | `storysounds.parentgate.lockout` (`ParentGateView.swift:21`) | failure count, lock round, `lockedUntil` |
| UserDefaults | `storysounds.ui.soundOn` (`AppEnvironment.swift:102,175,242`) | Bool |
| iCloud KVS (opt-in) | `storysounds.backup.v1` | Compressed `BackupPayload` (see section 4) |

- **Not collected:** full name, date of birth, photo, voice, location, contacts, device identifiers. There is no microphone or recorder code. `RecordingStore` (`Audio/AudioLibrary.swift:9`) is a protocol with only an in-memory implementation, and the UI says recording or import is unsupported (`ParentAudioView.swift:69`).
- **Nickname:** chosen from a preset grid (`OnboardingView.swift:22-47`, "Grown-ups: please choose a nickname"). There is no text field anywhere. Default is "Reader" (`AppEnvironment.swift` freshSnapshot). The nickname is only drawn as on-screen text (`HomeView.swift:35`, `SummaryView.swift:18`, `ParentConfirmView.swift:19`, `ParentReport.swift:145`). It is never passed to TTS and never leaves the device unless the parent opts into backup. The profile id is `UUID().uuidString` (`Learner.swift:99` says "never a real name").
- **Claims match the code.** The privacy statements in `ParentDataView.swift:46-47` ("No analytics", "No links out of the app", "Stored on this Apple TV only") are true for the code as read. One qualifier: "Stored on this Apple TV only" is no longer true once the parent opts into backup. The iCloud page does explain that separately.
- **Child area:** `RouterView` routes only to onboarding, home, baseline, session, summary, parent. No chat, store, rating prompt, share sheet or link exists. The only door out is `HomeView.swift:88` -> `.parent` -> `ParentGateView`.

No findings in this section, other than F-11 (missing privacy manifest) and F-13 (no entitlements file).

---

## 2. Parent gate

Flow (`Parent/ParentGate.swift`, `ParentGateView.swift`, `ParentAreaView.swift`): 3-second Select hold (`.onLongPressGesture`), then a 4-choice adult question (`AdultChallengeFactory`: either `a x b - c` or a spelled-out "Add forty-seven and sixty-two, then take away eleven"). After 3 wrong answers the gate locks for 30 s, then 60 s, 120 s ... up to 900 s. The lockout is persisted to UserDefaults on every answer (`ParentGateView.swift:201,252-254`) and reloaded in `init` (`:36-37`), so quitting the app does not reset it. Menu or Back leaves; backgrounding re-locks (`ParentAreaView.swift:62-63`). Parent-only screens are reachable only through `unlocked`, with no alternative route found in `App/`.

### F-1 [MAJOR] The adult question is guessable: 25% per attempt, about 58% per lockout round
`ParentGate.swift:85-93` offers exactly 4 options and one correct. `GateLockout.failuresBeforeLock = 3` (`:110`), and each wrong answer gets a fresh question (`:179`). A child who holds Select for 3 s and then clicks at random passes with probability 1-(3/4)^3 = 57.8% in the first round. Each later round has the same odds after a 30 s, 60 s, 120 s ... wait, so the expected time to break in is a couple of minutes. `failures` resets after each lock and `lockRounds` only lengthens the wait; there is no permanent escalation. The gate protects reset, delete-everything, restore-from-iCloud and the backup toggle.
- Scenario: a 5-year-old taps the remote at random in the "Grown-ups only" screen and reaches "Delete everything", which still needs one more confirm click (`ParentConfirmView`), and "Restore from iCloud".
- Fix (any combination): use 6-9 options in a grid; require 2 consecutive correct answers from independent questions; or drop to 2 attempts before lockout with a longer base lock (e.g. 60 s doubling). A better design for tvOS is a numeric answer entered on an on-screen keypad (10 digits, 2-digit answer, about 1% by chance). Keep the "answer cannot be read by a 4-7 year old" property; the number-words variant is good for that.
- Apple's Kids Category guideline wants a gate that "requires adult skill"; a 25% coin-flip is a likely review rejection reason.

### F-2 [MINOR] `-uitest-*` launch arguments are compiled into the shipping binary
Locations: `AppEnvironment.swift:25-47` (LaunchOptions, `-uitest-reset`, `-uitest-inmemory`, `-uitest-no-audio`, `-uitest-reduce-motion`, `-uitest-fast-review`, `-uitest-day-offset N`, `-uitest-session-minutes N`, `-uitest-parent-gate-pass`), `ParentGateView.swift:24` (`skipHoldForTests = CommandLine.arguments.contains("-uitest-parent-gate-pass")`), `RootView.swift:10-17`. There is no `#if DEBUG` anywhere in the app target (grep confirms).
- Honest severity: **MINOR (not exploitable by a child on a retail Apple TV).** `CommandLine.arguments` on tvOS are set only by Xcode, `xcrun devicectl`, or XCUITest `launchArguments`. There is no URL scheme, no `.onOpenURL`, no deep link, no environment-variable read, and no Settings-bundle path that injects them. A child cannot supply them. A person with a dev-signed build and a Mac could, but such a person already has the device.
- What each flag would do if triggered: `-uitest-parent-gate-pass` skips only the hold (the question stays); `-uitest-reset` wipes all local data (but not the iCloud copy, because `backup: nil`); `-uitest-day-offset` shifts planning time by days (not the gate clock); `-uitest-inmemory` makes the app write nothing and use throwaway storage; `-uitest-no-audio` silences everything.
- Still worth fixing: it is dead attack surface in a children's app, App Review reviewers can read it with `strings`, and the `-uitest-reset` wipe is destructive. Fix: wrap `LaunchOptions` parsing and `skipHoldForTests` in `#if DEBUG`, or add a custom `STORYSOUNDS_UITEST` Swift compilation condition set only on the UITest scheme/configuration (the UI tests need it, so a plain `#if DEBUG` works only if the tests run against Debug builds). In release builds `LaunchOptions.init` should ignore its arguments.

### F-3a [MINOR] Gate relies on wall-clock time
`GateLockout.lockedUntil` is a `Date` (`ParentGate.swift:116`). Setting the Apple TV clock forward clears a lock, and a large clock error can lengthen one. A child is very unlikely to do this; tvOS date is automatic by default. Optionally also persist a monotonic uptime snapshot, or treat a `lockedUntil` more than 15 min in the future as invalid and clamp it to `maxSeconds` (this also covers corrupt data).

### F-3b [MINOR] VoiceOver "Continue to the question" skips the hold
`ParentGateView.swift:145` exposes a named accessibility action that bypasses the 3 s hold for assistive-technology users. The adult question remains, so after F-1 is fixed this is acceptable. Noted so the question's strength is not reduced further on the assumption that the hold is a real barrier for every user.

### Observations (no action)
- The lock is persisted for each answer, and leaving with Menu cannot reset it (verified `answer()` always calls `saveLockout`).
- "Delete everything" intentionally clears the stored lockout (`ParentDataView.swift:155`, also swept by the `storysounds.` prefix). That requires passing the gate first, so it is not a bypass.

---

## 3. Deletion completeness

`DataDeletionService.deleteEverything` (`Backup.swift:203-215`) runs four steps, attempts all even if one fails, and rethrows the first error: (1) `store.deleteAll()` for this scope's learner keys; (2) a sweep of every key beginning `storysounds.` in the local key-value store (this catches other scopes, orphaned snapshot generations, the privacy key, `storysounds.ui.soundOn` and `storysounds.parentgate.lockout`); (3) `privacy.delete()`; (4) `backup.deleteBackup()`, which removes every iCloud key beginning `storysounds.backup.` (`Backup.swift:167-169`). `AppEnvironment.deleteEverything` (`:278`) cancels pending saves first, then replaces in-memory state with a fresh unsaved profile. The UI then calls `ParentGateView.clearStoredLockout()` (`ParentDataView.swift:155`).

Result: **every key the app writes is removed**; I found no surviving key. Because everything written is under `storysounds.`, future keys are covered if the prefix rule is kept (add a unit test asserting this for any new key).

### F-4 [MINOR] Deletion message over-claims for iCloud
`ParentDataView.swift:157` says "Everything has been deleted from this Apple TV and from iCloud." `ICloudKeyValueStore.setData(nil)` writes locally and calls `synchronize()` (`StorageSupport.swift:76-78`), whose result is ignored; the read-back check at `:78` verifies only the local mirror. If the TV is offline or not signed in, the removal is queued, not complete. Also `deleteBackup()` does not check `availability()`. Fix: soften to "...and the iCloud copy will be removed when this Apple TV is next online", or check `isAvailable` and say so.

### F-5 [MINOR] Turning iCloud backup OFF does not remove the copy
`ParentBackupAdapter.setOptedIn(false)` (`ParentBackupController.swift:49-53`) only flips the flag. The existing iCloud payload stays until the parent finds "Delete the iCloud copy". The toggle hint ("Saves progress only") does not say this. Fix: when switching off, offer "Also delete the iCloud copy?" or state it in the hint.

### Notes on `resetProgress` (`AppEnvironment.swift:261`)
It clears skills, attempts, confusions, sessions, stickers, overrides and baseline flags, keeps id, nickname and settings, then `flushNow()`. It does not touch the iCloud copy, so an old backup still contains the pre-reset progress and "Restore from iCloud" would bring it back. This is probably intended, but the Reset confirmation text (`ParentConfirmView.swift:19`) should say "The iCloud copy is not changed". Recordings: none exist (no recording feature), so there is nothing to delete.

---

## 4. iCloud backup

- **Default OFF, explicit opt-in:** `PrivacySettings.iCloudBackupEnabled = false` (`Backup.swift:9`). `backUp()` throws `.notOptedIn` unless the flag is true (`:146`). Corrupt or missing privacy data falls back to defaults (OFF) (`:26`). There is no automatic backup: the only call site is the "Back up now" button (`ParentDataView.swift:115`). **Good.**
- **Payload contents:** `BackupPayload` = format version, `createdAt`, and the compacted `LearnerSnapshot` list. That is a random UUID, preset nickname, settings and progress. **No other PII.** Nickname is the only name-like field (see F-9 about no length cap).
- **Size limits:** backup compactor budget 150 KB / 150 attempts / 40 sessions / 40 confusions (`Backup.swift:129`), encoded cap `defaultMaxBytes = 700_000` (`:51`, checked at `:69`), under the 1 MB iCloud KVS total. Local store cap 400 KB (`LearnerStore.swift:defaultMaxBytes`). `restore` writes through `store.save`, which enforces the 400 KB cap again (so an oversize snapshot throws `.tooLarge` instead of being stored).
- **Decode robustness:** `BackupCodec.decode` (`Backup.swift:73-94`) checks magic and header length, rejects version > current (`.unsupportedBackupFormat`) and unknown compression method, wraps decompression and JSON decode in `do/catch`. Swift `Codable` rejects unknown enum cases, wrong types and NaN, so a tampered payload throws `.corrupt`, never traps. No force unwraps on this path.

### F-6 [MAJOR] Restore can select the wrong profile (and appears to do nothing) on a second device
`AppEnvironment.swift:293-300`. After `BackupRestoration.apply`, the app reloads `ids.contains(snapshot.profile.id) ? current : ids.first`. On a new Apple TV the parent typically completes onboarding first, which creates and saves a fresh UUID profile; the backup has a different UUID. Both now exist, `ids.contains(current)` is true, so the in-memory profile stays the **new empty one**, the dialog reports "Restored 1 learner profile", and nothing visible changes. On the next launch `listProfileIds().first` (sorted by UUID text, `AppEnvironment.swift:163`) picks one of the two at random. This is a correctness bug in the headline restore feature and leads to apparent data loss.
- Fix: after a successful restore, switch to the restored profile (the first id written, `written.first`), persist that choice, and make a single-active-profile policy explicit (delete the other profile or store an `activeProfileId` key). Add a test: onboard -> restore backup with different id -> active profile equals restored.

### F-7 [MINOR] Restore applies no semantic validation, rollback or partial-failure handling
`BackupRestoration.apply` (`Backup.swift:176-186`) saves each snapshot in turn and throws on the first failure, leaving earlier profiles written. There is no check of field ranges (negative `reviewStage`, huge arrays, 100k-char nickname, `Date`s in the far future), no schema/downgrade comparison between the snapshot and the running build (`profile.schemaVersion` is just overwritten by `reconcile`, `Envelope.swift` `reconcile`), and `overwrite: true` is hard-coded so an older backup silently replaces newer local progress (the confirmation text does say "replaces matching progress"). Fix: sanitize on restore (clamp nickname to <= 24 chars, clamp counters >= 0, clamp stage/dates, drop unknown sticker ids), refuse if `snapshot.profile.schemaVersion` > current, and prefer the snapshot with the newer last attempt date.

### F-8 [MAJOR] A tampered or corrupt snapshot can crash the app on launch or in the sticker book
`App/Shared/Stickers.swift:29-31`: `if id.hasPrefix("effort-"), let n = Int(id.dropFirst(7)) { let p = effortPool[n % effortPool.count] ...`. A sticker id `"effort--3"` parses to -3 and `-3 % count` is negative, so `effortPool[-3]` traps. `practice-` is safe (uses `firstIndex ?? 0`). `masteryPool[(unit?.order ?? 0) % masteryPool.count]` (`:41`) is the same pattern if a unit `order` were ever negative. Sticker ids come from persisted/restored data (`profile.stickers`, `SessionSummary.stickersEarned`), which is externally influenced via the iCloud payload. Because the snapshot is reloaded every launch, a crash in Home/Sticker Book becomes a crash loop that only "Delete everything" (behind the gate) or a reinstall fixes.
- Exploitability is low (needs a tampered iCloud KVS value or a corrupted store that still decodes), but impact is a persistent crash.
- Fix: `let n = Int(...), n >= 0` and use `((n % c) + c) % c`; same for `masteryPool`. Add a unit test with ids `effort--1`, `effort-9223372036854775807`, `mastery-<unknown>`.

---

## 5. Persistence robustness

Design (`LearnerStore.swift`): save writes a NEW generation key, reads it back, flips a pointer key, reads that back, then deletes the old generation (`:58-85`). A failure before the flip leaves the previous generation intact; the pointer is restored on failure. This is a sound design. Corrupt data is surfaced as `StorageError.corrupt`/`.newerSchema` rather than traps (`Envelope.swift` decodeEnvelope: `JSONSerialization` in `do/catch`, `guard` for version, `try` decode). `Migrator.standard` has no migrations yet and `currentSchemaVersion = 1`, so a downgrade to an older app build is refused with `.newerSchema` (never guesses). The coordinator debounces 2 s and `flushNow()` runs when the scene leaves the foreground (`RootView.swift`, `sceneLeftForeground`).

### F-9 [MAJOR] A failed load silently becomes a brand-new profile; the old one is orphaned and may be loaded next launch
`AppEnvironment.swift:162-166`:
`if let id = (try? store.listProfileIds())?.first, let s = try? store.load(profileId: id) { loaded = ... }`, and `let snap = loaded ?? freshSnapshot(...)`.
- `try?` hides `.corrupt`, `.newerSchema` and "pointer without data". The fresh snapshot gets a new random UUID, and onboarding starts as if nothing were wrong. The parent is never told.
- The unreadable profile's keys stay on disk. The next save creates a second pointer, so `listProfileIds()` now returns two ids, and `.first` (lexicographic by UUID) decides which one loads on each later launch. The child may see progress alternate between two profiles, or the corrupt one may "win" and reset progress again.
- With a newer-schema snapshot (user installs an older build) the same thing happens, and the new profile's first save then lives next to the data the newer build wrote.
- Fix: (a) distinguish `nil` (no data) from a thrown error; on error, show a parent-readable "We couldn't read the saved progress" state, keep the bytes untouched and do not write a new profile until the grown-up chooses "Start again" (which deletes) or "Try again"; (b) store `activeProfileId` explicitly instead of `.first`; (c) iterate remaining ids if the first fails. This also fixes F-6.

### F-10 [MAJOR] UserDefaults budget: peak use can exceed the ~500 KB tvOS limit, and verification does not prove durability
- `defaultMaxBytes = 400_000` for one snapshot (`LearnerStore.swift`) but compactor `defaultBudget = 350_000` (`SnapshotCompactor.swift:14`). Because old and new generations coexist during a save (acknowledged in the class comment), peak usage is up to **2 x 350 KB = 700 KB** for one profile, above the documented ~500 KB tvOS UserDefaults ceiling (plus the other keys and any system keys in the same domain). Realistic sizes are smaller (500 attempts x about 250 B plus skills and sessions is about 150-250 KB), so a typical peak of 300-500 KB is close to the limit, and heavy use will cross it. tvOS reacts to over-quota writes by dropping data or terminating, not by returning an error.
- `UserDefaultsKeyValueStore.setData` (`StorageSupport.swift:55-62`) "verifies" by reading back through `defaults.data(forKey:)`, which reads the in-process cache, not disk. A write that the system later discards passes verification, so the "never damage the previous value" guarantee is weaker than it looks.
- Orphans: if the app is killed between the pointer flip and `setData(nil, old)` (`LearnerStore.swift:85`, which uses `try?`), the old generation is never reclaimed until `deleteAll`. Each such event permanently costs up to one snapshot of the budget.
- Fix: lower `SnapshotCompactor.defaultBudget` to about 150 KB and `defaultMaxBytes` to about 200 KB so peak (2x) stays under about 400 KB; on every save sweep stale generations (`snap.<id>.*` other than the one the pointer names); consider one fixed key with two slots (A/B) instead of an ever-growing generation counter. Longer term, tvOS Caches is purgeable, so UserDefaults (or CloudKit) is the right store; keep it small.

### F-11 [MINOR] No privacy manifest, so App Store submission will warn
There is no `PrivacyInfo.xcprivacy` in the repo. The app calls `UserDefaults`, a required-reason API (`NSPrivacyAccessedAPICategoryUserDefaults`). Add a manifest with reason `CA92.1`, `NSPrivacyTracking = false`, no tracking domains, and no collected data types. Not a code-safety defect, but a submission blocker for the Kids Category in practice.

### F-12 [MINOR] Minor load-path and API-use details
- `Bundle.module` is used in `Curriculum.loadBundled` (`Curriculum.swift:118`), `AudioManifest.loadBundled` and `AudioLibrary.init` (`AudioLibrary.swift` `.module`). `Bundle.module` traps if the resource bundle is missing, so the friendly "stories could not be opened" path (`AppEnvironment.swift:~145`) cannot catch that case. Very unlikely in a built app; fine to leave, but the `LoadError.missingResource` path is partly dead code.
- `AppEnvironment.swift:132` `fatalError("Built-in constant manifest must decode")`: constant, safe in practice. Replace with a throwing-free initializer (`AudioManifest(version:statement:entries:)`) so there is no `fatalError` at all in the app.
- `PersistenceCoordinator.flushNow()` uses `queue.sync` (`PersistenceCoordinator.swift:48`), which deadlocks if called from `onError`/`onSaved`; this is documented and no caller does it.
- Migrations: the framework (ordered steps, monotonic check `m.to > m.from`, `.newerSchema`) is correct, but there are none yet and no test with a real v0->v1 fixture beyond the unit tests. Add one before the first schema bump.

---

## 6. Audio, TTS and provenance claims

- **No TTS of isolated phonemes:** enforced in three layers. `SpeechPolicy.isSpeechAllowed` is false for `.phoneme` and `.sfx` (`AudioModels.swift:16-22`); `PlaybackPlanner` only returns `.speak` for allowed kinds (`:91`); `AudioPlaybackController.play` re-checks at the point of speaking ("defence in depth", `AudioPlayer.swift:98`); and `AVSpeechFallback.speak` itself refuses (`AVFoundationAudio.swift:118`). Failure to play a phoneme file degrades to a caption (`AudioPlayer.swift:90-95`). The app only calls `speak` through the audio controller; `spokenPrompt` and the "modelled steps" strings (which contain letter sequences like "s ... a ... t") are shown as on-screen text, never sent to TTS (grep: `spokenPrompt` is not read anywhere in `App/`). Tests exist (`AudioTests.swift:137,173,276,386`). **Pass.**
- **Placeholder labelling:** all 1,471 manifest entries have `status: "placeholder"` and `file: null` (manifest counts: 94 phoneme, 1,353 word, 18 instruction, 6 sfx). The Sound & audio parent page leads with "Development placeholders - not approved recordings" (`ParentAudioView.swift:25`). Word and instruction audio is currently system TTS, flagged `isPlaceholderSpeech`. Parents are told. **Pass.**
- **Little Wandle claims:** `grep -ri 'little wandle|approved|endorse|affiliat|official'` over App/ and Sources/ shows only negations: `ParentLearnPages.swift:37` ("not affiliated with or endorsed by Little Wandle or any school"), `ParentReport.swift:160`, `AudioLibrary.swift:85` disclaimer, `audio-manifest.json` statement, and "not approved recordings" in `ParentAudioView.swift:25`. No UI string claims approval or alignment. The only positive uses of the name are in internal docs: `reading-app/docs/curriculum-map.md:1` heading ("Little Wandle Letters and Sounds Revised style") and `:61` (a citation URL). Those docs also state that the pages could not be fetched and everything is `source: "inferred"`. **Pass for the app**; see F-14 for the docs.

### F-13 [MINOR] No entitlements file for iCloud key-value storage
`project.yml` generates the Info.plist but declares no `CODE_SIGN_ENTITLEMENTS` and there is no `.entitlements` file. `NSUbiquitousKeyValueStore` needs `com.apple.developer.ubiquity-kvstore-identifier`. Without it the backup silently does not sync, yet "Back up now" can still report success because the local KVS mirror read-back passes (`StorageSupport.swift:78`), and `isICloudAccountAvailable` only checks the account token (`:84`). Fix: add the entitlement (and the iCloud capability), and make `backUp` verify with `synchronize()`'s result; until then keep the backup UI hidden (it already hides when no controller is injected, but `AppEnvironment.parentBackup` is always provided).

### F-14 [MINOR] Provenance wording in docs
`reading-app/docs/curriculum-map.md:1` calls the sequence "Little Wandle ... style" while the same file says no official page was read. If any of this reaches a store listing, screenshots, or marketing, replace with neutral wording ("a systematic synthetic phonics order, independently authored; not affiliated with Little Wandle"). Trademark and endorsement risk only.

---

## 7. Crash risks

Searches covered `try!`, `as!`, `fatalError`, `precondition`, `assert`, `.first!`, `.last!`, unguarded subscripts, `removeFirst/removeLast`, `.random(in:)` ranges, modulo by array counts and `Dictionary(uniqueKeysWithValues:)`.

- `try!` / `as!` / force-unwrap `!` on optionals: **none found** in App/ or Sources/ (only `!=` and string literals).
- `fatalError`: one, constant JSON (`AppEnvironment.swift:132`), see F-12.
- **Real crash:** negative modulo in `Stickers.swift:30` (F-8).
- Guarded and safe on inspection: `Feedback.choose` (empty check), `Scheduler.intervalDays` (clamped index, empty ladder handled), `SeededRNG.int(below:)` (n <= 1 returns 0), `shuffled`/`pick`, `ActivityGenerator.shuffledTiles` (`tiles[0]` only when `Set(target).count > 1`), `SessionPlanner` loops (`order[i % order.count]` is inside `!focusTracks.isEmpty`; candidates guarded), `BaselinePlan.plan` (`eligible.count - 1` inside `!eligible.isEmpty`, bounded `while`), `ParentSettingsView.stepSession` (clamped), `ParentComponents.slice` (bounds checked), `SessionRunnerView.current` and `BaselineView` (`indices.contains`), `ActivityContainerView` step lookup (`indices.contains`), Gate `Int.random` ranges are constant and valid, `AdultChallenge.correctIndex` uses `?? 0`.
- Not fully proven: `ActivityKinds.swift:196,289,301,330` index `graphemes[i]`/`tiles[placed[k]]` from view state; indices come from `ForEach(0..<count)` and a `placed` array built from tile indices, so they are safe unless the tile list changes while placed holds old indices (activities are recreated per activity via `.id`). Low risk.
- Untrusted-input crash surface is therefore: stickers (F-8) and nothing else of note. `JSONDecoder` of persisted data throws, never traps.

---

## 8. Dependencies / supply chain

- `Package.swift`: no `dependencies:`. One library target (`StorySoundsCore`, resources only) and one test target. `project.yml`: the only package is the local `StorySoundsCore` (`path: .`). No `Package.resolved`, no CocoaPods/Carthage, no scripts, no Run Script build phases, no remote binaries.
- System frameworks only: Foundation, SwiftUI, AVFoundation, Darwin conditional imports. **Zero third-party runtime dependencies. Pass.**
- Repo-level note: the same repository also contains an unrelated JavaScript tree (`package.json`, `yarn.lock`, `reading-app/node_modules`). That is not part of the tvOS binary and is out of scope, but keep the tvOS target's source list limited to `tvos/App` so nothing from it is bundled.

---

## Prioritised fixes

1. **F-9 / F-6 (MAJOR)** Stop swallowing load errors; add an explicit active-profile id; make restore switch to the restored profile. Data-loss class bugs, easy to unit test.
2. **F-1 (MAJOR)** Strengthen the parent gate beyond a 25% guess (numeric keypad answer, or 6+ options plus 2 consecutive correct answers, 2 failures before lock). Required for a Kids Category claim.
3. **F-10 (MAJOR)** Cut snapshot budgets (about 150 KB budget / 200 KB max) so the 2x generation peak stays well under 500 KB; sweep stale generations on save.
4. **F-8 (MAJOR)** Fix negative-modulo indexing in `Stickers.swift`; add tests with hostile sticker ids; sanitize on restore (F-7).
5. **F-2 (MINOR, do before release)** Gate all `-uitest-*` handling behind `#if DEBUG` or a UITest-only compilation condition; make release `LaunchOptions` ignore arguments.
6. **F-11 / F-13 (MINOR, submission)** Add `PrivacyInfo.xcprivacy` (UserDefaults CA92.1, no tracking) and the iCloud KVS entitlement; make `backUp` honest about sync failure.
7. **F-4 / F-5 (MINOR)** Make the deletion and backup-off copy truthful about iCloud (queued deletion, existing copy remains).
8. **F-3a, F-7, F-12, F-14 (MINOR)** Clamp `lockedUntil`, add restore sanitization and downgrade check, remove the last `fatalError`, soften the docs' Little Wandle wording.

What is already good and should be preserved: no network or analytics code at all, preset-only nickname, backup default OFF and manual only, `storysounds.` prefix sweep that makes deletion complete, atomic generation/pointer save, versioned envelope with `.newerSchema` refusal, layered phoneme-TTS ban with tests, honest placeholder and non-affiliation labelling, zero third-party dependencies.
