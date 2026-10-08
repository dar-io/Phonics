# Story Sounds (tvOS)

Story Sounds is a native Apple TV app (Swift, SwiftUI, tvOS 17 and later) that helps children aged 4 to 7 practise phonics: hearing sounds, matching them to letters, blending sounds into words, splitting words into sounds, and reading short sentences and stories. It is driven entirely by the Siri Remote, stores everything on the device by default, and has no network code.

The app is independent. It is not affiliated with, endorsed by or approved by Little Wandle, any school or any publisher, and it does not "follow" any named programme. The order in which sounds are taught is inferred (see [docs/CONTENT_AND_LICENSING.md](docs/CONTENT_AND_LICENSING.md)).

## Status (read this first)

This is a pre-release build. It has not been used by a child and has not been run on a real Apple TV.

| Area | Evidence |
|---|---|
| App and Swift package build | Verified by CI (GitHub Actions macOS runner, Xcode 26.6, Apple TV 4K tvOS Simulator) |
| 319 XCTest unit tests (engine, mastery, persistence, audio, parent gate) | Verified by CI: pass |
| UI tests with `XCUIRemote` against the simulator: first launch, baseline, full lesson, Menu/Back, intervention after two misses, Reduce Motion, audio disabled, accessibility labels, persistence across terminate and relaunch | Verified by CI |
| Real Apple TV, real Siri Remote (including the 3-second press-and-hold in the parent gate) | Not verified |
| Real VoiceOver behaviour | Not verified (only that elements have non-empty labels in the simulator) |
| Audio | All audio is placeholder: no recordings are bundled. Isolated sounds are never synthesised; a caption is shown instead. Words and instructions use system text-to-speech labelled as placeholder. Nothing audible has been reviewed by a phonics specialist |
| Overscan and safe-area layout on a real TV | Not verified |
| Anything visual | No screenshots have been inspected |
| iCloud backup | Not verified (needs a signed build with the iCloud key-value capability) |
| tvOS Human Interface Guidelines compliance | Only the independent review in [docs/reviews](docs/reviews) (a reading of the code, not a device test) |
| Curriculum order and pronunciation guidance | Inferred; not verified against official sources, not reviewed by a phonics lead |

See [docs/REMAINING_WORK.md](docs/REMAINING_WORK.md) for what must happen before any child uses it or it is submitted to the App Store.

## Documentation

| File | Contents |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Modules, layering, data model, persistence constraints, lifecycle, launch arguments, focus and navigation |
| [docs/MASTERY_AND_PROGRESSION.md](docs/MASTERY_AND_PROGRESSION.md) | The mastery, review, placement and session-planning algorithms as implemented |
| [docs/PRIVACY_AND_CHILD_SAFETY.md](docs/PRIVACY_AND_CHILD_SAFETY.md) | What is stored, what is not, parent gate, deletion, iCloud, privacy manifest, remaining risks |
| [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md) | What is implemented, what is tested, what is not verified, status of review findings |
| [docs/CONTENT_AND_LICENSING.md](docs/CONTENT_AND_LICENSING.md) | Originality, provenance, audio status and recording workflow, non-affiliation |
| [docs/REMAINING_WORK.md](docs/REMAINING_WORK.md) | Prioritised list of open work |
| [docs/reviews](docs/reviews) | Four independent review reports (pedagogy, privacy and security, accessibility and HIG, code quality). They describe an earlier state of the code; many findings have since been fixed. Each document above says which are still open |

## Requirements

- A Mac with Xcode 26 (CI uses Xcode 26.6) including the tvOS SDK and an Apple TV simulator runtime.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`. The Xcode project is generated from `project.yml` and is not committed.
- For the curriculum tools only: Node.js 22 and npm (CI uses Node 22).
- Deployment target: tvOS 17.0. `SWIFT_VERSION` is 5.9 for all targets.

## Set up and run

```sh
cd tvos
xcodegen generate
open StorySounds.xcodeproj
```

In Xcode choose the `StorySounds` scheme and an Apple TV 4K simulator, then Run. Use the Simulator's Apple TV remote controls to move focus, select and press Menu. No signing is needed for the simulator.

The Swift package `StorySoundsCore` (`Package.swift`, tvOS 17 and macOS 13 declared) is also referenced by the app project as a local package. CI builds and tests it through the Xcode project on the tvOS simulator only; running `swift test` on macOS directly is not part of CI and has not been verified.

## Tests

Find a simulator id and run one of the groups CI uses (all from `tvos/` after `xcodegen generate`):

```sh
UDID=$(xcrun simctl list devices available | grep "Apple TV 4K" | head -1 | grep -oE '[0-9A-F-]{36}')

# unit tests (319 tests: engine, mastery, persistence, audio, parent gate)
xcodebuild test -project StorySounds.xcodeproj -scheme StorySounds -destination "id=$UDID" \
  -only-testing:StorySoundsCoreTests

# UI tests, grouped as in CI
xcodebuild test -project StorySounds.xcodeproj -scheme StorySounds -destination "id=$UDID" \
  -only-testing:StorySoundsUITests/LaunchTests -only-testing:StorySoundsUITests/ChildFlowTests \
  -only-testing:StorySoundsUITests/AccessibilityTests
xcodebuild test ... -only-testing:StorySoundsUITests/FocusNavigationTests
xcodebuild test ... -only-testing:StorySoundsUITests/ParentAreaTests
xcodebuild test ... -only-testing:StorySoundsUITests/PersistenceTests
```

CI also passes `-test-timeouts-enabled YES -default-test-execution-time-allowance 240 -maximum-test-execution-time-allowance 420`. The UI tests drive the app with `XCUIRemote` and rely on DEBUG-only launch arguments (see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)), so they must run against a Debug build, which is the default for `xcodebuild test`.

## Continuous integration

Two workflows touch this project (the repository also contains an unrelated Framer workflow, `publish.yml`).

`.github/workflows/tvos.yml` ("tvOS build and test"): runs on push to the branch `claude/story-sounds-phonics-app` when `tvos/**` or the workflow changes, and on manual dispatch. It runs five jobs in parallel on `macos-latest` (45 minute limit each), one per matrix entry:

| Job | `-only-testing` |
|---|---|
| `unit` | `StorySoundsCoreTests` |
| `ui-child` | `LaunchTests`, `ChildFlowTests`, `AccessibilityTests` |
| `ui-focus` | `FocusNavigationTests` |
| `ui-parent` | `ParentAreaTests` |
| `ui-persist` | `PersistenceTests` |

Each job installs XcodeGen, generates the project, picks the first "Apple TV 4K" simulator, runs `xcodebuild test`, passes only if the log contains `TEST SUCCEEDED`, and uploads the `xcodebuild` log as an artifact. Only the log is uploaded; the `.xcresult` bundle is written but not uploaded.

`.github/workflows/curriculum.yml` ("curriculum tools", Ubuntu, Node 22): runs `npm ci`, `npm run verify`, fails if regenerated files differ from what is committed (`git diff --exit-code` over `curriculum-tools` and the tvOS `Resources` folder), then `npx tsc --noEmit`.

## Curriculum tooling

The lessons are data. They are authored and validated in `curriculum-tools/` and copied into the app bundle.

```sh
cd curriculum-tools
npm ci
npm run verify      # build:curriculum, sync:tvos, validate:curriculum, audit:curriculum, test (vitest)
npm run sync:tvos   # copies curriculum.json, word-requirements.json and the audio manifest into tvos/Sources/StorySoundsCore/Resources
```

Never hand-edit the generated JSON. Edit `curriculum-tools/src/curriculum/author/*.ts` and rebuild; see [curriculum-tools/docs/curriculum-authoring.md](../curriculum-tools/docs/curriculum-authoring.md) and [curriculum-tools/docs/curriculum-map.md](../curriculum-tools/docs/curriculum-map.md). Commit the regenerated files, or the CI drift check fails.

Known gap: `build:curriculum` regenerates the audio manifest with every entry as a placeholder, so a manifest edited by hand to point at recordings would be overwritten by the next build. See [docs/CONTENT_AND_LICENSING.md](docs/CONTENT_AND_LICENSING.md).

## Deployment notes

Nothing here claims App Store or Kids Category approval. These are the facts found in the repository.

- **Signing**: `project.yml` sets no development team. Set one in Xcode (or add `DEVELOPMENT_TEAM`). The bundle identifier `dev.storysounds.app` and its prefix `dev.storysounds` are placeholders; the owner must choose and register a real one. No explicit version or build number is set in `project.yml`.
- **iCloud backup**: uses `NSUbiquitousKeyValueStore`. `App/StorySounds.entitlements` declares `com.apple.developer.ubiquity-kvstore-identifier`, applied only to device builds (`CODE_SIGN_ENTITLEMENTS[sdk=appletvos*]`). It needs a signed build, and the iCloud key-value storage capability on the App ID. Without these the app reports iCloud as unavailable. Unverified end to end.
- **Icons**: the layered tvOS brand asset (small and App Store icons, Top Shelf and Top Shelf Wide images, an accent colour) is present in `App/Assets.xcassets`, with the pixel sizes tvOS expects (400x240, 1280x768, 1920x720, 2320x720, plus @2x). Whether they look right has not been inspected. They are original artwork made for this project.
- **Privacy manifest**: `App/PrivacyInfo.xcprivacy` is bundled as a resource. It declares no tracking, no tracking domains, no collected data types, and one required-reason API: `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`. The code was searched for other required-reason APIs (file timestamps, system uptime, disk space, active keyboard); none were found. Re-check at submission, because Apple changes the list.
- **App Privacy answers**: the app collects nothing and has no third-party SDKs, but the App Store Connect questionnaire has to be answered by the owner. If the iCloud backup is kept, consider how to describe it.
- **Kids Category considerations** (not claims): there are no ads, analytics, links out, purchases or web views; a parent gate protects the grown-ups' area. Apple's review of the gate and of the Kids Category requirements has not been attempted. The gate's strength against random pressing is limited (see [docs/PRIVACY_AND_CHILD_SAFETY.md](docs/PRIVACY_AND_CHILD_SAFETY.md)). The submission also needs a privacy policy, screenshots and metadata, none of which exist in this repository.
- **Audio**: the shipped build has no recordings. Do not release a children's learning app whose letter sounds are captions only.

## Repository layout

```
tvos/
  project.yml                 XcodeGen spec (app, unit-test and UI-test targets, scheme)
  Package.swift               Swift package StorySoundsCore (no dependencies)
  App/                        SwiftUI app target
    StorySoundsApp.swift      @main
    Child/                    onboarding, home, baseline, session runner, activities, summary, sticker book
    Parent/                   gate and the six grown-ups' sections
    Shared/                   AppEnvironment, theme, components, stickers, debug hooks
    Assets.xcassets/          App icon, Top Shelf images, accent colour
    PrivacyInfo.xcprivacy, StorySounds.entitlements
  Sources/StorySoundsCore/    UI-free logic and bundled data
    Models/ Engine/ Audio/ Persistence/ Parent/
    Resources/                curriculum.json, word-requirements.json, audio-manifest.json (generated; do not edit)
  Tests/StorySoundsCoreTests/ 319 unit tests
  UITests/                    XCUIRemote UI tests
  docs/                       this documentation and docs/reviews
curriculum-tools/             TypeScript authoring, validation and audit of the curriculum (Node 22)
.github/workflows/            tvos.yml, curriculum.yml (and an unrelated Framer publish.yml)
design-system/, design-system.framerfx/, package.json, yarn.lock
                              unrelated Framer starter-kit files that share the repository
```

## Licence

No licence has been chosen. See [docs/CONTENT_AND_LICENSING.md](docs/CONTENT_AND_LICENSING.md).
