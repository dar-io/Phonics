# Privacy and child safety

Scope: what the code does, found by reading it and searching it. Nothing here has been tested on a real Apple TV, no legal or App Store review has taken place, and nothing in this document is a claim of compliance with COPPA, UK GDPR, the Children's Code or Apple's Kids Category rules. It is an engineering description to support those reviews.

## 1. What is stored, and where

All learner data is local by default. Every key the app writes begins with `storysounds.` (see [ARCHITECTURE.md](ARCHITECTURE.md) section 3.2).

| Store | Content |
|---|---|
| `UserDefaults` | The learner snapshot: a random UUID, a preset nickname, creation date, settings (volumes, Gentle mode, captions, mastery thresholds, session length), a sticker list, parent overrides, per-skill mastery state, and a capped log of attempts (item key, correct or not, support level, the letters or word chosen and expected, response time in milliseconds, time), sessions, and a table of often-confused pairs |
| `UserDefaults` | Privacy settings (iCloud backup on or off, last backup date), parent-gate lockout state, sound on or off, and an active-profile pointer |
| iCloud key-value store | Only if a grown-up opts in and presses "Back up now": one compressed copy of the snapshot (progress only) under `storysounds.backup.v1` |

The nickname is chosen from eight presets on first launch ("Reader", "Star", "Sunny", "Pip", "Fox", "Bear", "Moon", "Maple"); there is no text field anywhere in the app. The profile id is `UUID().uuidString`. The nickname is shown on screen and is never spoken by text-to-speech or sent anywhere unless the grown-up opts into the iCloud backup, which includes it.

**Never collected** (no code exists for any of these): real name, date of birth, photo, voice or microphone input, location, contacts, device identifiers, advertising identifiers, free text, purchase data, usage analytics, crash reports, logs. The app has no microphone, camera or location permission strings.

## 2. No network, analytics, ads or external links

Verified by searching `App/`, `Sources/` and the build files on 2026-10-08:

- No use of `URLSession`, `URL(string:`, `http://` or `https://` strings (the only hits are Apple's DOCTYPE lines in the two `.plist` files), `WebKit`, `SafariServices`, `openURL`, `Link(`, `ShareLink`, `mailto`, `CoreLocation`, `AVAudioRecorder`, speech recognition, `AdSupport`, `AppTrackingTransparency`, `StoreKit`, `CloudKit`, `Network`, `NWConnection`, `os_log`, `Logger`, `NSLog` or `print(`.
- The bundled `curriculum.json`, `word-requirements.json` and `audio-manifest.json` contain no `http` strings. The unit `citation` field is plain text that the UI never reads.
- Imports are Foundation, SwiftUI, AVFoundation and UIKit (VoiceOver announcements) only. `Package.swift` has no dependencies and `project.yml` references only the local package: no third-party SDKs and no run-script build phases.
- The child area has no chat, store, rating prompt, share sheet or link. The only way out of it is Home, then "Grown-ups", then the parent gate.
- The one network-adjacent feature is the opt-in iCloud key-value backup, which the operating system performs (see section 6). The text-to-speech used for words and instructions is the system's `AVSpeechSynthesizer`; the app passes it only vocabulary and instruction text.

The statements shown to grown-ups in "Your data" ("No accounts and no sign-in", "No ads", "No analytics or tracking", "No links out of the app") are true for the code as read. One line, "Stored on this Apple TV only", is no longer true once a grown-up turns on iCloud backup; the iCloud page explains that separately (open item).

## 3. The parent gate

The gate protects the whole grown-ups' area (progress, settings, practice choices, audio information, backup, reset and delete), not only the destructive actions. Implemented in `Parent/ParentGate.swift` (logic, unit-tested) and `App/Parent/ParentGateView.swift` (UI).

Design:
1. **Press and hold** Select for 3 seconds (`ParentGateSession`/`HoldGate`). Alternatively, "I can't hold the button" skips the hold and uses harder, three-step questions. VoiceOver users get a named action that skips only the hold.
2. **Two adult questions in a row**, each with six answers, answered with the remote's focus and click (no keyboard). Questions are written arithmetic ("What is 17 x 8 - 21?") or words ("Add forty-seven and sixty-two, then take away eleven."); the harder variant is "Multiply 14 by 7, take away 20, then add 9." A wrong answer resets the streak and gives a new question.
3. **Lockout**: after two wrong answers the gate locks for 30 seconds, then 60, 120 and so on up to 900 seconds. The lockout is saved after every answer and reloaded at launch, so quitting does not reset it. The code detects the clock being set backwards and keeps the remaining lock; a clock moved forwards cannot be told from time passing.
4. Leaving the foreground or pressing Menu or Back re-arms the gate. A successful unlock does not persist.

Limits, stated honestly:
- It is a speed bump, not a security boundary. By my own arithmetic, a child pressing at random passes one six-way question one time in six, so the chance of passing two in a row before a lockout is about 5.5 percent per lockout round; the locks lengthen but there is no permanent escalation. This was calculated, not tested.
- The "I can't hold" route and the VoiceOver action exist for accessibility and let a person skip the hold; only the questions then stand in the way.
- A child who can do the arithmetic can pass. The questions were chosen so a 4 to 7 year old cannot, but no child has been tried against it.
- The 3-second hold uses `onLongPressGesture` on a focusable view. One UI test (`ParentAreaTests`) exercises the real hold in the simulator (see the CI logs for its result), but it has never run on a real Apple TV with a Siri Remote, and its source file says so.
- Wall-clock forward changes can clear a lock.

## 4. Deletion and reset semantics

All behind the gate and a second confirmation whose safe option (Cancel) has the default focus; Menu cancels.

- **Reset progress** (`AppEnvironment.resetProgress`): clears skills, attempts, confusions, sessions, stickers, overrides and the baseline flags. Keeps the profile id, nickname, creation date and settings. Does not touch an iCloud backup; the confirmation says so.
- **Delete everything** (`DataDeletionService`): attempts four steps and reports the first error: (1) delete the learner store for this scope; (2) remove every `UserDefaults` key that begins with `storysounds.`, which also removes the privacy settings, sound setting, active-profile pointer and gate lockout; (3) delete the privacy settings; (4) remove every iCloud key beginning `storysounds.backup.`. Pending debounced saves are cancelled first and restored if deletion fails. On success the app returns to first-launch onboarding with a new, unsaved profile (a new active-profile pointer holding that new random id is written, with no data behind it). The message tells the grown-up that iCloud finishes removal when it can, and says so plainly if iCloud could not be reached. Removal from iCloud is requested, not confirmed.
- There are no recordings, exports or caches to delete: the app has no recording feature and no file output.
- If saved progress cannot be read, "Start fresh" creates a new profile and sets the unreadable data aside; it does not delete it. The only way to remove it is "Delete everything" (or reinstalling).

## 5. Persistence safety

Corrupt, truncated or newer-schema data throws a typed error and is never overwritten or silently replaced (section 3.5 of the architecture document). Restore from iCloud validates the payload, refuses a newer schema, sanitises each snapshot (unknown units dropped; counts, dates, text lengths and settings clamped) and rolls back if a later profile fails. The sticker view is safe for any id, including negative numbers. These paths have unit tests (`RestoreTests`, `StorageHardeningTests`, `LearnerStoreTests`, `BackupAndCoordinatorTests`, `SnapshotCompactorTests`, `MigratorTests`).

## 6. iCloud backup

- **Off by default** and opt-in per device (`PrivacySettings.iCloudBackupEnabled = false`; corrupt or missing settings fall back to off). There is no automatic backup: the only call site is the "Back up now" button.
- **Contents**: a format version, a date and the compacted learner snapshot(s): a random id, a preset nickname, settings and progress. It stays under about 150 KB per profile and 700 KB in total, below the roughly 1 MB iCloud key-value limit.
- "Back up now" reads the copy back and reports failure if it is missing. That check uses the local mirror, so it cannot prove that iCloud received it.
- Needs a signed build with the iCloud key-value capability and the entitlement `com.apple.developer.ubiquity-kvstore-identifier` (present in `App/StorySounds.entitlements`, applied to device builds only). In unsigned simulator builds the app reports iCloud as unavailable. **Never exercised end to end.**
- Turning backup off does not remove the existing copy; the toggle's hint says so and a separate "Also delete the iCloud copy" button exists.
- Restore overwrites matching local progress (the confirmation says so) and switches to the most recently active restored profile.
- tvOS has no file sharing, so there is deliberately no file export. The on-screen progress summary and this backup are the only records.

## 7. Privacy manifest

`App/PrivacyInfo.xcprivacy` (bundled as a resource): `NSPrivacyTracking` false; no tracking domains; no collected data types; one accessed API category, `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` (data read and written only by the app itself). The code was searched for other required-reason categories (file timestamps, system boot time, disk space, active keyboards) and none were found. Whether it passes App Store validation has not been tested.

## 8. Remaining risks

Findings from `docs/reviews/privacy-security-review.md` are listed with their status in the code today. "Fixed in code" means the change is present and covered by tests where noted; it does not mean verified on a device.

| Id | Review finding | Status |
|---|---|---|
| F-1 | Gate answer was a 1-in-4 guess | Fixed in code (6 options, two in a row, lock after 2). Residual: about 5.5% per lockout round for random pressing (calculated) |
| F-2 | `-uitest-*` arguments active in release | Fixed in code: parsing and hold-skip are `#if DEBUG`. Not tested against a Release build |
| F-3a | Gate relies on wall-clock | Partly fixed: backward clock jumps and far-future locks handled; a forward jump can still clear a lock |
| F-3b | VoiceOver skips the hold | Unchanged, accepted; the questions remain. The "I can't hold" route adds a second way to skip it |
| F-4 | Delete message over-claimed iCloud removal | Fixed: wording now says removal is requested and may take time |
| F-5 | Backup off leaves a copy | Fixed in wording and with a delete-copy button |
| F-6 | Restore selected the wrong profile | Fixed: restore activates the most recently active restored profile |
| F-7 | Restore had no validation or rollback | Fixed (sanitiser, schema check, rollback). Restore still always overwrites matching profiles by design |
| F-8 | Negative modulo crash in sticker lookup | Fixed (total `wrap` function) |
| F-9 | Failed load silently created a new profile | Fixed: unreadable progress shows a recovery screen; nothing is overwritten |
| F-10 | UserDefaults peak could exceed ~500 KB | Budgets lowered (150 KB snapshot, 200 KB cap) and stale generations are swept. Peak on a device not measured; the read-back still proves acceptance, not durability |
| F-11 | No privacy manifest | Fixed (section 7) |
| F-12 | `Bundle.module` trap; one `fatalError` | Open, minor: `AppEnvironment.blankManifest` still has a `fatalError` on a constant string that cannot fail in practice |
| F-13 | No iCloud entitlement | Entitlement file added. Still unverified end to end |
| F-14 | Docs wording "Little Wandle ... style" | Open: `curriculum-tools/docs/curriculum-map.md` line 1 still reads "Little Wandle Letters and Sounds Revised style". Reword before it can reach a listing, screenshots or marketing |

Other risks not in the review:

- The parent-gate hold and the backup have never run on a real device.
- "Stored on this Apple TV only" in the privacy page is not qualified for the iCloud case.
- The comment at the top of `ParentBackupController.swift` is stale (it says the controller still needs wiring; it is wired).
- A household with several children shares one profile (no `TVUserManager` support), so progress and the baseline placement are shared.
- Placeholder text-to-speech voices come from the operating system; the app cannot control what the system does with them.
- No privacy policy, age-rating answers or App Store privacy questionnaire have been prepared.
