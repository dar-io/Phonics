# Story Sounds tvOS: independent code-quality and correctness review

Scope: `tvos/App`, `tvos/Sources/StorySoundsCore`, `tvos/Tests`, `tvos/UITests`, `tvos/project.yml`, `.github/workflows/tvos.yml`.
Method: read-only review. There is no Swift compiler in this environment. Every finding was checked against the code. The bundled JSON (`curriculum.json`, `audio-manifest.json`, `word-requirements.json`) was cross-checked with Python.
Anything I could not substantiate by reading was dropped. Items that need a device or simulator to confirm are marked VERIFY.

Severity key: BLOCKER = crash or data loss on a reachable path. MAJOR = feature broken or wrong result for real users. MINOR = latent, cosmetic or low probability.

What I checked and found sound:
- Mastery EMA and prior handling (`Mastery.swift:93-95`).
- Scheduler stage advance (`wasDue` is taken from the pre-update skill).
- Placement and `nextUnit`.
- Session interleaving and top-up loops. All are bounded and no `% 0` is reachable.
- `SessionRecovery` splice index (`position + 1`).
- All UITest identifiers exist in the app (see section 5).
- JSON and Codable agree: all 98 units, 1288 words and 306 sentences decode, and prerequisite orders are valid.
- No `try!`, `as!` or force unwraps in Sources or App. The only `fatalError` is a constant-JSON decode.

---

## 1. BLOCKER

### B1. The load-failure screen crashes because `StoryButton` needs an `AppEnvironment` that is never injected
- `App/Child/RootView.swift:30` renders `LoadErrorView` outside `RouterView().environmentObject(host.env)` (line 32).
- `LoadErrorView` uses `StoryButton(prominent: true, action: onRetry)` (line 83).
- `StoryButton` declares `@EnvironmentObject private var env: AppEnvironment` and reads `env.calmMotion` (`App/Shared/AppComponents.swift:27, 39`).
- Scenario: the bundled curriculum fails to load (missing resource, schema mismatch). `AppEnvironment.make` sets `loadFailure`, `RootView` shows `LoadErrorView`, and SwiftUI traps with "No ObservableObject of type AppEnvironment found". The screen documented as "Never crashes" crashes on appearing.
- No test covers this path.
- Fix, minimal: in `RootView`, change the first branch to `LoadErrorView(onRetry: { host.retry() }).environmentObject(host.env)`.
- Better: make `StoryButton` read `@Environment(\.accessibilityReduceMotion)` and an `isCalm` value from a plain environment key, so it has no hard dependency on `AppEnvironment`.

---

## 2. MAJOR

### M1. Restore-from-backup loads the wrong profile on the main use case, a new Apple TV
- `App/Shared/AppEnvironment.swift:293-303`:
  ```swift
  let target = ids.contains(snapshot.profile.id) ? snapshot.profile.id : ids.first
  ```
- Scenario:
  1. The new Apple TV already has its own saved profile B (onboarding saves it).
  2. The backup holds profile A.
  3. `BackupRestoration.apply` writes A. Now `ids = [A, B]` and `ids.contains(B)` is true, so `target = B`.
  4. The in-memory snapshot is re-loaded from B. The UI says "Restored 1 learner profile" and nothing visible changes.
  5. On the next launch, `AppEnvironment.init` (line 163) picks `listProfileIds().first`, which is the lexicographically smallest UUID. That is A or B at random.
- Same root cause as M2.
- Fix:
  - Prefer the restored id: `let target = written.first ?? (ids.contains(snapshot.profile.id) ? snapshot.profile.id : ids.first)`.
  - If restoring over a different active profile, `try store.delete(profileId: oldId)`.
  - Make `init` choose the profile with the newest `savedAt` instead of `.first`.

### M2. Profile selection at launch is order-dependent, and a corrupt first profile silently orphans the live one
- `AppEnvironment.swift:163`: `if let id = (try? store.listProfileIds())?.first, let s = try? store.load(profileId: id)`.
- Scenario: `load` throws (`.corrupt` or `.newerSchema` after a downgrade). `try?` turns that into `nil`, so `loaded == nil`. The app shows onboarding with a fresh `UUID` profile, and the first save creates a second profile.
- On every later launch, if the corrupt id sorts first, the app shows onboarding again and the child's new progress is orphaned. If the good id sorts first, it works by luck.
- Fix:
  - Iterate all ids and take the first that decodes. Prefer the newest `savedAt`.
  - Surface a "could not read saved progress" state instead of silently replacing it.

### M3. Parent "Unlock this sound" and "Practise this next" do nothing for what the child actually plays
- `Progression.nextUnit` (`Progression.swift:199-218`) never consults overrides. Only `explainUnits` reads `.unlocked` (line 165).
- `SessionRunnerView.swift:97` always passes `focusUnitId: nil`.
- `SessionPlanner.reviewCandidates` skips a revisit unit when `unit.order > knownOrder` (`SessionPlanner.swift:333`).
- Result: a locked unit marked `.unlocked` shows as "Ready" in the parent UI but is never taught. A revisit unit ahead of the focus is silently dropped. `ParentPracticeView` still says "Saved. X will come up in the next session." (line 92).
- Fix:
  - In `SessionModel.start`, compute `focusUnitId` as the latest `.unlocked` override whose unit is not yet secure, if any.
  - Or make `nextUnit` treat an `.unlocked` unit as satisfying prerequisites.
  - For revisit, allow `unit.order <= max(knownOrder, unit.order)`, or raise `knownOrder` to include the revisit unit.

### M4. Placeholder speech (TTS) is the only audible narration today, and it is never interrupted
- All 1471 manifest entries are `placeholder`, so every word and instruction goes through the `.speak` branch.
- `AudioPlayer.swift:96-103`: that branch calls `backend.stop(channel: .narration)` but never `speech.stop()`. Only the `.playFile` branch does (line 69).
- `AVSpeechFallback.speak` (`AVFoundationAudio.swift:117`) calls `synth.speak`, which enqueues.
- Scenarios:
  - Pressing "Hear it again" three times queues three full instruction sequences.
  - Advancing to the next activity leaves the previous activity's speech playing and queues the new one behind it.
  - `SessionRunnerView.endSession` and `cancelSequence()` cancel only the Swift `Task`. The summary screen is read over stale speech.
- Related: `AppEnvironment.playSequence` (lines 375-386) waits fixed 1.0, 1.2 or 1.8 s per id. It does not wait for the clip to finish, so a real recording longer than 1.8 s is cut off by the next `backend.stop(channel: .narration)`.
- Fix:
  - Call `sp.stop()` before `sp.speak()` in the `.speak` case.
  - Call `audio.stopAll()` in `cancelSequence` and on activity `onDisappear`.
  - Drive `playSequence` from `onChannelFinished` or an `AVSpeechSynthesizerDelegate` instead of timers.

### M5. Two on-disk generations can exceed the documented ~500 KB tvOS UserDefaults limit
- `KeyValueLearnerStore` writes the new generation, flips the pointer, then deletes the old generation (`LearnerStore.swift:58-93`). The class comment admits "peak usage is about 2x".
- Limits: `SnapshotCompactor.defaultBudget = 350_000`, `defaultMaxBytes = 400_000`, and the compactor comment says "tvOS UserDefaults is documented as ~500 KB in total".
- Peak is up to ~700 to 800 KB.
- Estimated snapshot size at the caps (VERIFY on device):
  - 500 attempts at roughly 350 B is about 175 KB.
  - Skill states carry up to 40 `sessionsSeen` ids. Plan ids look like `plan-<hex>-<unix>` (about 25 chars), so about 2 KB per practised skill.
  - 100 or more skills is about 200 KB.
- Failure scenario: writes fail or the process is killed once the snapshot is over ~250 KB.
- Fix:
  - Lower `defaultBudget` to about 180 KB and `defaultMaxBytes` to about 200 KB.
  - Shorten session ids (store a counter or an 8-char hash).
  - Or, when the old generation is large, delete it after the pointer flip and accept a brief single-copy window.

### M6. UI-test reliability: the full-lesson test plays a 16-activity lesson, content is time-seeded, and one test can pass by skipping
- `ChildFlowTests.testFullLessonEndsInCalmSummary` (`:35`) uses `launchApp()` with no `-uitest-session-minutes`. The hook exists (`AppEnvironment.swift:42`) but no UI test passes it (grep for `session-minutes` in `UITests/` is empty).
- Default is 7 minutes, so `total = 16` activities. `drive()` makes about 8 XCUI queries per step with 0.3 to 0.6 s settles, up to 700 steps.
- CI limits are `-default-test-execution-time-allowance 240 -maximum-test-execution-time-allowance 420` (`tvos.yml:31`). This test is likely to be killed by the timeout or be very slow. `SessionModel.start` also ends on wall-clock `maxSeconds`.
- `SessionModel.start` seeds from `Date()` (`SessionRunnerView.swift:88`), so every run plays different activities. `testTwoMissesShowModelledStepsAndLearnerCanFinish` ends in `XCTSkip` when no double miss occurs in 500 steps. CI counts a skip as success because the workflow only greps `TEST SUCCEEDED`.
- Fix:
  - Add `"-uitest-session-minutes", "1"` (4 activities) to the default `launchApp` arguments for lesson tests.
  - Add `-uitest-seed N` and use `UInt64(N)` when present.
  - Add a deterministic wrong-answer hook (for example `-uitest-always-wrong`) so the modelled-path test cannot skip.
  - Fail the workflow on skips for that test.

### M7. Audio id mismatches: `w-I`, `w-Mr`, `w-Mrs`, `w-Ms` and sentence names do not exist in the manifest
- `buildTricky` uses `"w-" + target` (`ActivityGenerator.swift:522-528`).
- The manifest ids are lower-case (`w-i`, `w-mr`, `w-mrs`, `w-ms`). Tricky words in the curriculum are `I`, `Mr`, `Mrs`, `Ms`. The first unit's own tricky list is `["is","I","the"]`.
- Scenario: the `identifyTricky` activity for `I` has `audioIds = ["i-tricky-word","w-I"]`. `w-I` is `unknownId`, so playback degrades to a caption. The key narration for the activity target is silent.
- Also missing as lower-case ids: the sentence names `Zak, Jim, Ben, Pam, Max, Dan, Meg, Kate, Nan, Tom, Tim, Jen, Jack, Sam, Viv`. In `buildSentence` the correct choice uses `"w-" + targetText.lowercased()` (line 547) and the distractor uses `"w-" + d.text`.
- No test checks that every `Activity.audioIds` and `Choice.audioId` resolves in the manifest.
- Fix:
  - Lower-case every `"w-" + ...` in the generator, and in `AudioLibrary.resolve` fall back to `id.lowercased()`.
  - Add a test that sweeps generated activities, asserts `library.entry(for:) != nil`, and fails otherwise.
  - Add name entries to the manifest or exclude them.

### M8. Dead or misleading parent settings
- `LearnerSettings.showCaptions` is only written, never read (grep: the only readers are the model and the toggle in `ParentSettingsView.swift:44`). The toggle claims "shows the spoken words on screen" and does nothing.
- The Music stepper (`ParentSettingsView.swift:66`) controls a channel that nothing plays. `startMusic` and `stopMusic` have zero callers in App.
- `GraphemeUnit.reviewIntervalsDays` is never populated (absent from the JSON) and never read. It is dead.
- Fix: wire captions into `ActivityContainerView` and `SoundCaptionPill`, or remove the toggle and the music stepper until they work.

### M9. iCloud backup is unlikely to function as built (VERIFY)
- `project.yml` declares no entitlements file, so there is no `com.apple.developer.ubiquity-kvstore-identifier`.
- `ICloudKeyValueStore.isICloudAccountAvailable` only checks `ubiquityIdentityToken`.
- Without the KVS entitlement, `NSUbiquitousKeyValueStore` writes read back locally, so `setData`'s read-back verification passes while nothing syncs. The UI then reports "Last backup: ..." for a backup that never leaves the device.
- Fix: add the entitlement (`com.apple.developer.ubiquity-kvstore-identifier`) in `project.yml` (`entitlements:` / `CODE_SIGN_ENTITLEMENTS`). Verify with a second device or reinstall.

### M10. Destructive actions drop the pending save even when they then fail
- `deleteEverything()` (`AppEnvironment.swift:279`) and `restoreFromBackup()` (line 294) call `coordinator.cancelPending()` first. If the service then throws, the in-memory snapshot is unchanged, but the debounced write containing the last attempts is gone. Nothing re-arms it until the next `update`.
- Fix: cancel only after success, or re-arm with `coordinator.update(snapshot)` in the catch path.

---

## 3. MINOR

Correctness and logic
1. `Mastery.swift:123-152`: one error after securing can drop the skill straight to `.reviewDue` with stage 0.
   - `errors` counts the 8-result window, which includes pre-secure misses. Securing is allowed with 1 error in the window.
   - A skill secured with one earlier miss in the window is therefore demoted on its first post-mastery error, which contradicts "one occasional error never erases progress".
   - Fix: count only errors recorded after `secureAt`, or require `errors > maxRecentErrors + 1` for demotion.
2. `Mastery.swift:111` and `DayKey`: the day key is a UTC date, but users play in local time. In Australia, 8 am and 6 pm local fall on two different UTC dates. In the US evening, a single session can span UTC midnight. `minDays` is satisfied by one family day. Fix: have the caller pass a local-day key (`Calendar.current`), keeping the UTC pure function for tests.
3. `ActivityCoordinator.swift:136, 180`: `responseMs` is measured from `begin()`, which includes the 3 to 5 s narration. `fastResponseMs = 3000` therefore almost never fires, so the speed tiebreak is effectively dead code. Fix: start the clock when the narration finishes or the choices are enabled.
4. Single-choice items at the first unit: `ActivityGenerator.supports` (`:161-163`) only checks `unitGraphemes`.
   - At order 1 there is nothing to distract with, so `listenChooseSound`, `findGrapheme` and `matchSoundGrapheme` all produce a single correct choice.
   - `ActivityGeneratorTests:143-148` asserts `choices.count == 1`. The baseline's item 0 is the same.
   - These count as independent correct attempts (vacuous evidence) and can mark `g-s` secure. At unit 2 the choice is 50/50.
   - Fix: require `>= 2` choices (skip the type, or lower `minAttempts` weight for single-choice items).
5. `SessionRunnerView.swift:132-135, 230-237`: `endSession` calling `finish` twice (for example the last Next press racing "Take a break") routes to `.home` and drops the summary.
   - Fix: keep a cached `finalSummary` and return it on repeat calls.
   - Also, `wasFinished = true` is set before the `activitiesDone > 0` guard, so a break at activity 1 leaves attempts recorded under a `sessionId` with no session row.
6. `ParentPracticeActions.unmark` (`ParentPracticeView.swift:17-19`) removes all overrides for the unit, including a parent's earlier `.unlocked` override. A relocked unit can lose its availability. `mark` also timestamps with `Date()` rather than `env.now`. Fix: remove only `.revisit` entries.
7. `Progression.placeFromBaseline` (`:259`): `lastCorrectBelow` defaults to 0 and the placement step-back compares `p.order > lastCorrectBelow`. This is fine only because unit orders start at 1. Use `Int.min` as the default.
8. `SnapshotCompactor.fold` only re-adds a confusion when no record exists, and `keepConfusions` prunes low counts. The same pair can be pruned, then re-added as `count: 1` by folding from older attempts on a later pass, so it churns. Fold into the existing record or skip folding.
9. `Mastery.swift:121`: `Mastery.update` is not the only reader of `Scheduler.isDue`. `SessionPlanner.reviewCandidates` uses `Scheduler.dueSkills` without the `secureAt != nil` filter that `explainUnits` applies (`Progression.swift:143`). Provisional (placement) skills show up as "due reviews" after 1 to 7 days. This is probably intended, but it is inconsistent with the parent view, which hides them.

Concurrency, lifecycle and SwiftUI
10. Dozens of `DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focus = X }` (Root, Baseline, Home, Onboarding, Summary, StickerBook, ConfirmOverlay, ActivityContainer, ActivityKinds `afterTick`) are redundant with `.defaultFocus`. They can steal focus from a user who navigated within 100 ms, and they write `@FocusState` from an escaping closure. Fix: one `.task { try? await Task.sleep(...); focus = ... }` helper, or rely on `defaultFocus`.
11. `AppComponents.swift:39`: `StoryButton` swaps between two different `Button` styles with `if env.calmMotion`. This changes view identity when Gentle mode is toggled on Home, so the focused button is rebuilt and focus can be lost. Fix: a single `Button` with one `ButtonStyle` that reads the environment.
12. `RootView.swift:41`: `phase != .active` also fires on `.inactive`, which tvOS enters for Siri, system alerts and HDMI-CEC events. `sceneLeftForeground()` then stops audio and cancels the sequence, and nothing resumes it on `.active`.
13. `ParentGateView.swift:24` and `RootView.swift`: `-uitest-parent-gate-pass` and `-uitest-reset` (which wipes all data) are honoured in release builds. A retail tvOS device cannot pass launch arguments, so the risk is low. Wrap in `#if DEBUG`.
14. `AVAudioSessionObserver.deinit` (`AVFoundationAudio.swift:146`) removes observers from `NotificationCenter.default` even if a custom `center` was injected, so the injected center leaks tokens.
15. `AudioPlaybackController`: a new `play()` while `.pausedByInterruption` flips the machine to `.playing` without resuming paused players, so the later `interruptionEnded` resume is lost.
16. `PersistenceCoordinator.flushNow` bumps the debounce token. After a failed flush there is no retry until the next `update` (`pending` is kept, but no timer). An idle child after a failed save keeps `saveProblem == true` indefinitely.
17. Session ids (`plan-<seed hex>-<unix>`) are stored in every skill's `sessionsSeen` (up to 40 to 50 per skill), which is the main snapshot-size driver (see M5).

Codable and migration
18. Synthesized Codable ignores property defaults. Adding a field to `SkillState`, `LearnerProfile` and so on fails to decode old data (`keyNotFound`) with `schemaVersion` still 1 and no migrations. Per M2 this becomes silent data loss. Add a custom `init(from:)` using `decodeIfPresent ?? default`, or bump `currentSchemaVersion` with a migration for every model change. There is no test for forward-compatible decoding.
19. `Curriculum.SentenceToken.init(from:)` treats any unknown `kind` as `.word` and then fails on missing `graphemes`. This is fine today, but the failure is "word needs graphemes" rather than "unknown kind".

Dead code and duplication
20. Two identical SplitMix64 implementations: `SeededRNG` (`Engine/SeededRNG.swift`) and `SeededGenerator` (`Parent/ParentGate.swift:37`). `SeededGenerator` has no test. Make the gate use `SeededRNG(seed:)`.
21. `Mastery.isUnitMastered(unitId:tracks:skills:settings:)` duplicates `Progression.isUnitMastered`. It has zero callers outside tests.
22. `GraphemeText.join` is used only by tests and `Scheduler.overdueSeconds` only internally. `AudioPlaybackController.replay/userResume/startMusic/stopMusic`, `InMemoryRecordingStore`, `deleteEverythingInAllScopes`, `Feedback.staticPhrases` and `CurriculumIndex.units(upToOrder:)` (outside the engine) have no App callers.
23. `Curriculum.loadBundled` and `AudioManifest.loadBundled` each do their own `Bundle.module` lookup. Share one helper.

Module boundaries
- Mostly clean: Core has no SwiftUI import, `ParentReport` is decoupled through `ReportInputs`, and App owns all UI.
- One leak: `AppEnvironment` is simultaneously storage, audio and navigation owner, and every view depends on it (`StoryButton` included, which is what caused B1). Splitting `AppEnvironment` into `LearnerSession` (snapshot and recording), `AudioEngine` and `Router` would let leaf components stay environment-free.

---

## 4. Test quality

- Core engine tests are strong and cover the major boundaries. Real-data sweeps exist (`testEverySessionAcrossTheSequenceIsValid`, all-wrong simulations).
- Weak or missing:
  - No test pins the scenario where a pre-secure error sits in the window and demotion follows (Minor 1).
  - `ActivityGeneratorTests:143-148` pins the single-choice behaviour as correct (Minor 4).
  - No audio-id resolution sweep (M7).
  - No test that overrides affect `nextUnit` or the planner (M3). `testOverridesChangeAvailabilityButNeverTouchSkills` only checks `explainUnits`.
  - No Codable forward-compatibility test (Minor 18).
  - No `restoreFromBackup` test with two profiles (M1). The `AppEnvironment` layer has no unit tests at all.
  - `testSlowAnswersAreNeverPenalised` has a stray `_ = i`.
  - `testChoiceCountIsHonouredAndClamped` and `exactlyOneCorrect` allow `>= 1` choices.
- `PersistenceCoordinatorTests.testDebouncedSaveCoalescesUpdates` waits on a 0.2 s timer with a 3 s timeout. It is okay but time-coupled, and there is no test for flush-then-late-debounce.
- XCTSkip as pass (M6).

## 5. UITests: reliability and identifier cross-check

- Bounded loops: yes. All loops are bounded (`drive` maxSteps, `focusElement` 2 x 4 x maxMoves, `waitForFocus` deadlines). There are no unbounded waits.
- Identifier cross-check, every id used in `UITests/` against `App/`. All resolve:
  - `parent.*.next/prev/back` come from `ParentPageScaffold` (`idPrefix + ".next"`).
  - `parent.settings.*.plus/minus` come from `ParentStepperRow`.
  - `parent.skills.cat.review` comes from `cat.\(c.rawValue)` where `Category.review` exists.
  - `session.*` and `baseline.*` come from `coord.idPrefix`.
  - `session.feedback` comes from `FeedbackBannerView(identifier:)`.
  - `session.soundCaption` comes from `SoundCaptionPill`.
  - `parentgate.*`, `home.*`, `stickers.back` and `summary.*` are literal.
- Brittle points:
  - String labels such as "Take a break?" and "Not quite. Here is another question." are tied to copy.
  - `ParentChallengeSolver` duplicates the gate prompt grammar (`×`, `−`, "Add ... then take away ...").
  - `strictSingleFocus = true` may flake if containers report focus (the authors already note this).
  - `drive()` counts a "completion" every time `*.next` exists and Select is pressed, even if the press did not register. It can overcount.
  - `relaunchKeepingData` relies on a fixed `Thread.sleep(2.5)` and the Home button producing a scene-phase flush.
- CI: `xcodebuild ... | grep ... || true` followed by `grep -q "TEST SUCCEEDED"` is correct. The `|| true` only protects the pipe. A skipped test still reports success.

---

## 6. Top 10 fixes, ranked

1. **B1**: inject `AppEnvironment` into `LoadErrorView` (or de-couple `StoryButton` from it). One line, removes a guaranteed crash on the recovery screen.
2. **M1 + M2**: make restore load the restored profile, and make launch choose the newest profile that actually decodes instead of `listProfileIds().first`. Surface "could not read saved progress" instead of silently replacing it.
3. **M3**: make Parent "Unlock" / "Practise this next" change what is played (`focusUnitId` or `nextUnit` honouring `.unlocked`, and let revisit units ahead of the focus through).
4. **M4**: stop TTS before speaking, stop audio on activity change and session end, and drive `playSequence` off playback completion instead of fixed sleeps.
5. **M5**: cut the snapshot byte budget so two generations stay well under the tvOS limit, and shorten session ids. VERIFY on a device.
6. **M6**: make the UITests deterministic and fast: pass `-uitest-session-minutes 1`, add `-uitest-seed`, add a wrong-answer hook, and stop treating `XCTSkip` as success.
7. **M7**: fix audio id casing for tricky words and sentence names, add a generator-wide manifest-resolution test.
8. **M10**: do not `cancelPending()` before a destructive operation succeeds. Re-arm the save on failure.
9. **M8 + M9**: remove or wire the dead settings (captions, music), and add the iCloud KVS entitlement before shipping backup.
10. **Minor 1, 2 and 4** (engine evidence): demotion window includes pre-secure errors, UTC day key counts one family day as two, and single-choice items at unit 1 inflate evidence. Fix in `Mastery.update`, in the day-key caller, and in `ActivityGenerator.supports`.
