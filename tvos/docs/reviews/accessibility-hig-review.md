# Story Sounds (tvOS) - Independent Accessibility and tvOS HIG Review

Reviewer: independent (did not write the code). Read-only review; no source files were changed.
Scope: every file in `tvos/App/**` (Child, Parent, Shared, `StorySoundsApp.swift`) plus the audio/settings types in `tvos/Sources/StorySoundsCore` that the UI depends on (`AudioPlayer.swift`, `AudioModels.swift`, `Learner.swift`), and `tvos/project.yml`.

## Method and honesty notes

- Guidance source: I fetched Apple's HIG through the `developer.apple.com/tutorials/data/design/human-interface-guidelines/*.json` endpoint (the normal HTML pages are JavaScript-rendered, but the JSON endpoint worked). Pages read: designing-for-tvos, layout, focus-and-selection, accessibility, typography, motion. The "remotes-and-controllers" and "siri-remote" slugs returned 404, so the Menu/Play-Pause statements below come from my own knowledge of the tvOS HIG, not from a fetched page.
- Facts taken from the fetched HIG: safe area is "60 points from the top and bottom ... 80 points from the sides"; tvOS type default 29 pt, minimum 23 pt; WCAG-AA contrast (4.5:1 up to 17 pt, 3:1 at 18 pt+ or bold); Reduce Motion should reduce "zooming, scaling and peripheral motion" and "replace transitions in x-, y-, z-axes with fades"; "Avoid changing focus without people's interaction" (exception: the focused item disappeared); "Rely on system-provided focus effects ... custom only if absolutely necessary"; Dynamic Type is listed as a system feature on tvOS; ask for confirmation twice for hard-to-recover actions.
- There is no Swift toolchain or Apple TV here. Nothing below was run. Findings marked (UNVERIFIED ON DEVICE) are derived from reading SwiftUI code and known framework behaviour and need a simulator or device check. I did not invent any issue; each cites file:line that I read.
- Line numbers are for the files as they exist on the current branch.

---

## 1. Contrast (WCAG 2.x relative luminance, computed from the `Color(red:green:blue:)` values in `Theme.swift:7-15`)

Text pairings (threshold: 4.5:1 normal; all app text is >= 32 pt, so the 3:1 large-text threshold would also apply, but every pairing below clears 4.5:1 anyway):

| Foreground | Background | Ratio | Result |
|---|---|---|---|
| text (warm white) | background | 14.20 | pass |
| text | surface | 10.42 | pass |
| text | surfaceRaised | 7.73 | pass |
| textSecondary | background | 11.67 | pass |
| textSecondary | surface | 8.56 | pass |
| textSecondary | surfaceRaised | 6.35 | pass |
| accent (lantern yellow) | background | 10.09 | pass |
| accent | surface | 7.40 | pass |
| accent | surfaceRaised | 5.49 | pass |
| onAccent | accent (prominent button) | 10.58 | pass |
| positive (green) | background | 9.02 | pass |
| positive | surface | 6.62 | pass |
| positive | surfaceRaised | 4.91 | pass (tight) |
| white (focusRing) | background | 15.13 | pass (non-text 3:1) |
| white | surface | 11.11 | pass |
| white | surfaceRaised | 8.24 | pass |
| white | accent | 1.50 | see note A |
| text | accent | 1.41 | never used together (code uses onAccent on accent) |

Non-text and state pairings:

| Item | Ratio | Note |
|---|---|---|
| surfaceRaised fill vs background (unfocused secondary button edge) | 1.84 | below 3:1; label text carries identity, so not a hard failure, see m-9 |
| surface vs background (cards, banners) | 1.36 | decorative grouping only |
| Hold-ring track (surfaceRaised) vs ring backing (surface) | 1.35 | track is decorative; the progress arc (accent vs raised, 5.49) and the "Hold" text carry meaning |
| Wren sun / accent on sticker-sky top | 4.98 | decorative |
| Disabled "tried" choice at 0.45 opacity (`ActivityKinds.swift:87`), text vs its own fill | 3.11 | passes only as large text; the "Tried" label (32 pt) sits in this state, see m-8 |
| Prominent disabled at 0.45 opacity (onAccent on accent) | 3.21 | same |
| Used tile at 0.25 opacity (`ActivityKinds.swift:316`) | 1.90 | informational; see m-8 |
| Pressed state (0.85 opacity) text/raised | 6.36 | pass |
| text on the 65% black `DimLayer` | 18.22 | pass |

Note A: the 8 pt white focus ring is stroked centred on the button edge, so its outer half sits on `background` (15.13:1) even around yellow prominent buttons. Focus is therefore perceivable. It is also reinforced by scale and shadow, so it is not colour-only.

Verdict on colour: every text pairing in `Theme.swift` meets AA with margin. The `Theme.swift` header comment claim ("every pairing used for text meets WCAG AA") is true. Increase Contrast is not specifically handled (see m-9) but the baseline already clears the HIG minimums.

---

## 2. Findings

Severity key: BLOCKER = cannot ship / breaks a core accessible path; MAJOR = material guidance violation or broken control; MINOR = polish or low-impact deviation.

### BLOCKER

**B-1. No app icon or Top Shelf assets exist (release blocker, outside the Swift code but HIG-required).**
- Evidence: `find` for `*.xcassets`, `*.brandassets`, `*.imagestack`, `AppIcon*` across the whole repo returns nothing; `tvos/project.yml:10-20` sets no asset catalog and no `ASSETCATALOG_COMPILER_APPICON_NAME`. `INFOPLIST_KEY_UILaunchScreen_Generation: YES` is the only launch config.
- Why: tvOS requires a layered App Icon (small and large, parallax) and a Top Shelf image; App Store Connect validation fails without them, and the Home Screen would show a blank tile.
- Fix: add `Assets.xcassets` with a tvOS "App Icon & Top Shelf Image" brand asset (layered `.imagestack` front/middle/back, 400x240 and 1280x768, plus Top Shelf 1920x720 and wide 2320x720), reference it from `project.yml` (`ASSETCATALOG_COMPILER_APPICON_NAME`, `ASSETCATALOG_COMPILER_LAUNCHIMAGE_NAME` if used), and add an `AccentColor` set.

(No accessibility BLOCKER found in the Swift UI itself: every screen is reachable and exitable with the remote only; see section 3.)

### MAJOR

**M-1. The "Captions" setting is a dead control.**
- Evidence: `ParentSettingsView.swift:43-44` toggles `LearnerSettings.showCaptions` (`Learner.swift:93`). A repo-wide grep shows `showCaptions` is never read by any view or by `AppEnvironment`. `SoundCaptionPill` (`AppComponents.swift:189-211`) and the prompt text (`ActivityContainerView.swift:98-103`) are shown unconditionally.
- Why: a visible control that does nothing violates predictable behaviour, and the hint text ("Recommended: shows the spoken words on screen") tells a parent that turning it Off hides captions when it does not. A parent who needs captions off for sensory reasons cannot get that.
- Fix: either gate `SoundCaptionPill` (and the optional speech-bubble text) on `env.settings.showCaptions` while keeping the always-visible prompt as a non-removable baseline, or delete the toggle until it works. Add a UI test for both states.

**M-2. Feedback, captions and tutoring steps are never announced to VoiceOver; focus does not move to them.**
- Evidence: no `AccessibilityNotification` / `UIAccessibility.post` anywhere (grep). `FeedbackBannerView` (`AppComponents.swift:161-185`) appears below the content after every answer ("Good try! Have another look.", "Lovely...") but focus is moved elsewhere: to the first remaining card (`ActivityKinds.swift:56-61`) or to Next (`ActivityContainerView.swift:80-82`). `modelledPanel` step text changes on each press (`ActivityContainerView.swift:187-210`) while focus stays on the "Next step" button. `SoundCaptionPill` appears and disappears on a timer (`AppEnvironment.swift:393-400`).
- Why: correct/incorrect result and the "let's do it together" explanation are the core teaching content. A VoiceOver user hears only the sfx, then must swipe back through the tree to find the text. HIG accessibility guidance expects status changes to be perceivable by all input and output modes.
- Fix: when `coord.feedback` changes, post `AccessibilityNotification.Announcement(text).post()` (tvOS 17 API, deployment target is 17.0); on each `.modelled(step:)` change announce `coord.steps[step]`; announce the sound caption. Alternatively move accessibility focus to the banner with `@AccessibilityFocusState`.

**M-3. `StoryButton` swaps button style by changing view structure, which re-creates the button and can drop focus when Gentle mode is toggled (UNVERIFIED ON DEVICE).**
- Evidence: `AppComponents.swift:38-44` renders two different `Button` branches under `if env.calmMotion`. On Home, pressing the "Gentle mode" button (`HomeView.swift:77-86`) flips `calmMotion`, which changes the branch for every `StoryButton` on screen including the one that has focus. The conditional gives the buttons different structural identity, so SwiftUI removes and re-inserts them.
- Why: HIG focus guidance: do not move focus without the person's action, and focus restoration should be reliable. The likely symptom is focus jumping to the default (`.start`) after the toggle press, and VoiceOver re-announcing. It also resets any pressed or focus animation state.
- Fix: keep one `Button` and pass the flag into the style: `Button(...).buttonStyle(FocusCardStyle(prominent: prominent, calm: env.calmMotion))`, with `FocusCardStyle` skipping the scale and animation when `calm || reduceMotion`. `CalmFocusStyle` can then be deleted.

**M-4. Text can shrink below the HIG minimum of 23 pt via `minimumScaleFactor` (parent area).**
- HIG (fetched): tvOS default 29 pt, minimum 23 pt. Nominal sizes are fine (smallest text style is `captionFont` 32 pt, `Theme.swift:28`), but these shrink rules push the rendered size below 23 pt when the string is long:
  - `ParentSkillsView.swift:63` category buttons: 32 x 0.7 = 22.4 pt
  - `ParentSkillsView.swift:102` row reason line: 32 x 0.7 = 22.4 pt
  - `ParentAreaView.swift:80` menu card subtitle: 32 x 0.7 = 22.4 pt
- Below the 29 pt default but above 23 pt: `ParentComponents.swift:148` (24 pt), `ParentPracticeView.swift:98` (24 pt), `ParentComponents.swift:181`, `ParentProgressView.swift:115`, `ParentSkillsView.swift:135` (25.6 pt), `ParentProgressView.swift:112`, `ParentPracticeView.swift:96`, `ParentSkillsView.swift:101`, `ParentLearnPages.swift:76` (26.6 pt).
- Why: viewed from 8 ft+ these are the strings a parent most needs to read (why a sound is locked, what a setting does). Shrink-to-fit hides overflow instead of fixing layout.
- Fix: remove `minimumScaleFactor` below 0.9 on caption/body; allow two lines (`lineLimit(2)`) or shorten the copy; for the category filter use a segmented `Picker` or shorter titles ("Next", "Learning", "Review", "Secure" with the count as a separate badge).

**M-5. All text uses fixed point sizes, so Dynamic Type is ignored.**
- Evidence: every font is `Font.system(size:)` (`Theme.swift:25-31` and ~25 call sites, e.g. `HomeView.swift:44`, `ActivityKinds.swift:16,179,296,312,439,479`, `ParentAreaView.swift:77`). No `@ScaledMetric`, `dynamicTypeSize`, or text styles anywhere (grep). The comment at `Theme.swift:24` ("tvOS text styles scale with the system") is inaccurate for this code.
- Why: the fetched HIG lists tvOS among platforms where Dynamic Type "lets people adjust the size of visible text". Fixed sizes opt out. Impact is limited because the base sizes are large, but it is still a guidance deviation, and layouts (e.g. `Theme.minTarget` 120, fixed 150x140 slots at `ActivityKinds.swift:299`) would need to cope with scaling.
- Fix: define the Theme fonts as scalable (`Font.system(.largeTitle, design: .rounded)` or `.custom` with `relativeTo:`), use `@ScaledMetric` for the paddings and slot sizes, and test at the largest size. Keep the child "glyph" fonts (110-140 pt) fixed or capped with `.dynamicTypeSize(...DynamicTypeSize.accessibility1)`.

**M-6. Press-and-hold parent gate has no non-VoiceOver alternative and is unverified on tvOS.**
- Evidence: `ParentGateView.swift:130-140` relies on `onLongPressGesture(minimumDuration: 3)` on a `.focusable()` view; the file's own header (lines 7-12) says "UNVERIFIED on a real device/simulator". The only bypass is the VoiceOver accessibility action at line 145 (also reachable by Switch Control), and a UI-test launch flag (`ParentGateView.swift:24`).
- Why: a 3-second hold on the clickpad is a motor-access barrier for an adult with limited dexterity who is not using VoiceOver or Switch Control, and if tvOS does not deliver the long-press for a `focusable` non-Button view the whole grown-ups area is unreachable for everyone. The adult question that follows already provides the child-resistance.
- Fix: verify on device now. Provide a second path that needs no hold: e.g. accept 6 deliberate Select presses with a progress ring, or drop the hold and keep only the question. Keep the lockout.

**M-7. Safe area is likely double-inset on every screen (UNVERIFIED ON DEVICE).**
- Evidence: `screenContainer()` (`Theme.swift:57-63`) adds 80 pt horizontal and 60 pt vertical padding inside the view, and only the background uses `ignoresSafeArea()`. SwiftUI lays tvOS content out inside the system safe area, which is already 60 pt top/bottom and 80 pt sides (fetched HIG: "Inset primary content 60 points from the top and bottom ... 80 points from the sides"). The Theme comment at line 17 says as much, but the padding is then added on top.
- Why: effective margins become about 160 pt (sides) and 120 pt (top/bottom), leaving a content area of roughly 1600 x 840 pt instead of 1760 x 960. My estimates of the busiest screens: the 2x2 choose-sound activity needs about 810 pt of content height plus header (about 120 pt) and footer (about 230 pt when feedback and Next show), so the content `ScrollView` (`ActivityContainerView.swift:47-53`) scrolls in the common case, and the Parent "mastery" settings page (4 stepper rows at >= 120 pt + reset row + title + pager, `ParentSettingsView.swift:83-112`, no scroll view) needs roughly 910 pt and can overflow into the overscan region.
- Fix: print `GeometryReader` + `safeAreaInsets` on device. If the safe area is already applied, set the container padding to 0 (or add only extra breathing room of 20-30 pt), and keep the full-bleed background. If the layout is tight, drop the `Spacer`/spacing values and make the parent pages scrollable (`ScrollView` with focusable rows) or split into more pages.

**M-8. Several controls have no useful VoiceOver state or trait.**
- Evidence: toggles are plain `Button`s with `accessibilityValue("On"/"Off")` but no `.isToggle` trait: `HomeView.swift:66-86` (Sound, Gentle mode), `ParentComponents.swift:169-195` (`ParentToggleRow`). Steppers expose "Decrease"/"Increase" buttons plus a separate non-focusable text (`ParentComponents.swift:136-166`) instead of one adjustable element. The "lit" state of blend tiles (`ActivityKinds.swift:176-191`) and the "Next" star on the guided tile (`ActivityKinds.swift:320-322`) are shown with icons/labels that are `accessibilityHidden` or outside the button, so VoiceOver gets no equivalent state.
- Why: Apple's accessibility guidance expects the control type and value to be exposed; VoiceOver users cannot tell which sounds they already played.
- Fix: add `.accessibilityAddTraits(.isToggle)` (iOS/tvOS 17); for steppers use `accessibilityElement(children:.ignore)` + `accessibilityAdjustableAction` with a value label; add `.accessibilityValue(isLit ? "played" : "not played")` to blend tiles and "next sound" to the guided tile.

### MINOR

**m-1. Home focus jumps twice when closing the Sticker book.** `HomeView.swift:103` (`onAppear` sets focus to Start after 0.1 s) and `HomeView.swift:114-118` (`closeStickers` sets focus to Stickers after 0.15 s). Re-creating `mainPanel` fires `onAppear`, so focus visibly goes Start then Stickers and VoiceOver reads both. Fix: make `onAppear` set `focus = lastFocus ?? .start`, or only set initial focus once with a `@State` flag, and drop the delayed second assignment.

**m-2. Story "Back a page" can become disabled while it has focus, with no focus reassignment.** `ActivityKinds.swift:519` disables the button at `page == 0`, and `previous()` (lines 543-547) sets `page -= 1` without moving focus. The parent area already avoids this ("Buttons never get disabled", `ParentComponents.swift:134`). Fix: in `previous()`, when `page` becomes 0, `afterTick { focus.wrappedValue = .pageNext }`.

**m-3. Programmatic focus moves after a selection where the selected item is still present.** `BlendActivityView.lightUp` (`ActivityKinds.swift:199-205`) moves focus to the next unlit sound after every press; `TileActivityView.refocus` (359-369) likewise. HIG: "Avoid changing focus without people's interaction" (exception: the focused item disappears). The tile case is within the exception (the used tile is disabled) but the blend case is not. It is a deliberate scaffold for 4-7-year-olds, so I mark it MINOR; at least keep it out of Gentle mode and when VoiceOver is running (`UIAccessibility.isVoiceOverRunning`), where unexpected focus moves are disorienting.

**m-4. Sound captions are short-lived and can overlap the header.** `AppEnvironment.swift:393-400` clears the caption after 2.2 s while a phoneme sequence replaces it every 1.0 s (`AppEnvironment.swift:382`), which is faster than a 4-7-year-old (or a parent) can read. `ActivityContainerView.swift:59` overlays the pill at `.top` with 20 pt padding on the full-height frame, while the header content starts 60 pt below the top (`screenVerticalPadding`), so the pill covers the "Step X of Y" line and the top of the prompt for up to 2.2 s. Fix: keep the caption until the next sound starts or at least 3.5 s, and reserve a fixed caption slot in the layout instead of an overlay.

**m-5. Stale VoiceOver label on the sentence activity.** `ActivityKinds.swift:449` always labels the blank as "blank", even after `coord.isComplete` shows the answer visually (line 430-431). Fix: pass `coord.isComplete ? answer : "blank"`.

**m-6. Tricky-word information is lost in VoiceOver.** `ActivityKinds.swift:504` joins token text without saying which words are tricky (visual cue is underline + accent colour, so it is not colour-only for sighted users). Fix: append "(tricky word)" to those tokens in the label.

**m-7. Gentle mode and Reduce Motion are only partly shared with the grown-ups' area.** `StoryButton` honours `env.calmMotion` (`AppComponents.swift:39`), but the parent screens call `FocusCardStyle` / `ParentRowStyle` directly (`ParentAreaView.swift:84,97`, `ParentComponents.swift:78,86,96,152,160,189`, `ParentConfirmView.swift:61,68,96`, `ParentGateView.swift:49,186`) which honour only the system `accessibilityReduceMotion`. Parents who switch on Gentle mode still see a 1.08x scale (1.03x for `ParentRowStyle`). Fix after M-3: have one style that reads both.

**m-8. Disabled and "used" states are low contrast.** Tried choices at 0.45 opacity render their text at 3.11:1 (`ActivityKinds.swift:87`), including the meaning-bearing "Tried" label (line 79); used tiles at 0.25 opacity are 1.90:1 (line 316). Disabled controls are exempt from WCAG, but "Tried" is information. Fix: keep the label at full opacity (apply opacity only to the card background) and use a stronger, not fainter, signal for "used" (checkmark plus 0.5 opacity).

**m-9. Increase Contrast is not handled.** No use of `\.colorSchemeContrast`, `accessibilityDifferentiateWithoutColor` or `legibilityWeight` (grep). Unfocused secondary buttons are 1.84:1 against the background. Text already passes AA; the improvement is to add a 2 pt `textSecondary` border to buttons and cards when `colorSchemeContrast == .increased`.

**m-10. Settings controls that do nothing visible, or give no feedback.** "Music" volume (`ParentSettingsView.swift:66-69`) is a dead control: `startMusic` is never called by the app (grep). Changing Narration/Effects volume plays no sample, so a parent cannot judge the new level. Fix: remove "Music" until music exists; on narration/effects change play a short sample (`env.playAudio("sfx-tap")` or an instruction clip).

**m-11. Phonemes are voiced by VoiceOver even though the app forbids synthetic phonemes.** Labels such as `"The sound \(AccessibilityText.spoken(...))"` (`ActivityKinds.swift:126`, `AppComponents.swift:204`) and choice labels (`ActivityKinds.swift:94-98`) pass "sh", "a", "s" to VoiceOver, which will say them as words or letter names. The parent audio page promises "Letter sounds are never made by a computer voice" (`ParentAudioView.swift`). Fix: label phoneme tiles as letters ("the letters S H") for VoiceOver, and rely on the recorded audio for the sound itself.

**m-12. Custom focus effect instead of system effects; double effect possible (UNVERIFIED ON DEVICE).** HIG: rely on system focus effects. `FocusCardStyle` (`Theme.swift:36-53`) draws its own scale, ring and shadow. If tvOS also applies its default lift to the styled `Button`, focused items can be larger than the spacing allows (40 pt choice-grid gaps vs 1.08x of ~500 pt cards = about 20 pt per side, plus the 4 pt ring, which still fits). Check on device; if doubled, add `.focusEffectDisabled()` or use `.buttonStyle(.card)` and keep only the ring.

**m-13. Possible tile/ring overlap and tight spacing in two rows.** Category filter row spacing 16 pt (`ParentSkillsView.swift:58`) with 1.03x scale + 4 pt outer ring is 10-12 pt on each side, which fits; `TileActivityView` tiles use 24 pt spacing (`ActivityKinds.swift:264`) with 1.08x scale of about 200 pt tiles = 8 pt + 4 pt ring, which fits. No overlap found, but the margin is small if M-5 (Dynamic Type) is adopted.

**m-14. Minor semantic points.** `FeedbackBannerView` and `SoundCaptionPill` do not set `.accessibilityAddTraits(.updatesFrequently)`/`isStaticText`; the gate's locked screen exposes a fixed label rather than a live countdown (`ParentGateView.swift:210-223`); `HillsDecoration` (`AppComponents.swift:226`) is unused code.

---

## 3. Specific questions asked

### Focus Engine, focus restoration, traps
- Focus groups are well structured: `focusSection()` on grids, button rows, and pager bars (`OnboardingView.swift:36`, `HomeView.swift:96`, `ActivityKinds.swift:49,155,269,534,594`, `ParentComponents.swift:64-65`, etc.).
- Default focus is declared everywhere with both `defaultFocus` and a delayed `focus =` assignment (redundant but harmless, except m-1).
- Restoration after overlays is explicit: `ActivityContainerView.swift:66-75` remembers `lastFocus` and restores it when the break/skip confirmation closes; `ParentAreaView.swift:121-124` and `ParentSkillsView.swift:151-154` return focus to the row/card that opened a sub-screen.
- Disabled-while-focused cases are handled for choice cards (`ActivityKinds.swift:56-61`) and the tile "Back one" (`:353-357`); exceptions are m-2 and M-3.
- No focus traps found. I traced each route: Onboarding (names, Menu exits app), Home (Menu exits app), Sticker book (Back + Menu), Baseline intro/outro (buttons + Menu to Home), Baseline/Session activity (Menu opens a two-button confirmation; every phase has at least one focusable control: Hear/Slow always, the step button in `.modelled`, Next in `.complete`), Summary (Done + Menu), Parent gate (Back + Menu, lockout screen keeps Back), Parent menu and all six sections (pager Back + Menu), confirmations (Cancel default + Menu cancels), outcome (OK + Menu), Load error (Retry; Menu exits app).

### Menu/Back and Play/Pause
- Home Menu leaves the app: correct. HIG: Menu at the root of the hierarchy must return to the tvOS Home Screen. `HomeView.swift:4-5` documents the choice and there is no `onExitCommand` on `mainPanel`. The same applies to Onboarding (`OnboardingView.swift`, no handler) and Load Error. This is the right behaviour because there is nothing to lose there. One consideration: after "Delete everything" the route becomes `.onboarding`, so Menu there leaves the app, which is also fine.
- Non-root screens consistently map Menu to "go up one level": Sticker book (`StickerBookView.swift:47`), Baseline (`BaselineView.swift:77,122`), Summary (`SummaryView.swift:59`), Session empty (`SessionRunnerView.swift:222`), Parent (all). In an activity Menu opens "Take a break?" / "Skip the games?" with "Keep playing" as default and Menu = keep (`SessionRunnerView.swift:60`), which is a good, forgiving pattern for children.
- Play/Pause replays the prompt only inside activities (`ActivityContainerView.swift:87`), the hint says so (line 113). Acceptable use of the button (primary media action); elsewhere it does nothing, which is fine.

### Safe areas and overscan
- Background colour correctly extends full-bleed (`Theme.swift:61`, `RootView.swift:68`, `AppComponents.swift:241`). Content margin: see M-7 (probable double inset).

### Type sizes
- Nominal minimum 32 pt (caption); child reading content 60-150 pt. Below-minimum shrink cases: M-4. Dynamic Type: M-5.

### Target size and spacing
- `Theme.minTarget` 120 pt (`Theme.swift:22`, enforced in both focus styles); `ParentRowStyle` minimum 88 pt (`ParentComponents.swift:16`). Grid gaps 28-40 pt. All comfortably above tvOS norms. Children's controls are very large (200+ pt cards).

### VoiceOver
- Good: decorative art hidden (`AppComponents.swift:135,196,234`, emoji labels), headers marked (`HomeView.swift:38`, `ActivityContainerView.swift:102`, etc.), explicit labels and hints on almost every button, `.isModal` on the confirmation overlay (`SessionRunnerView.swift:61`), sort priority from prompt to controls to content to footer (`ActivityContainerView.swift:54-56,105,125`), grouped composite elements, "already tried"/"already used" labels, sticker scene exposed as one element with a value (`StickerBookView.swift:73-76`).
- Gaps: M-2 (announcements), M-8 (traits/state), m-5, m-6, m-11.

### Reduce Motion: every animation and transition
No continuous, bouncing, parallax, zoom, or looping animation exists (grep for `repeatForever`, `withAnimation`, `rotation` animation, `matchedGeometry`: none). All animations are 0.15-0.25 s ease-in/out or opacity fades.

| Location | What | Honours `accessibilityReduceMotion`? |
|---|---|---|
| `Theme.swift:48,51` | focus scale 1.08 + ease-out | Yes (scale and animation skipped) |
| `AppComponents.swift:8-21` | `CalmFocusStyle` | n/a (no motion) |
| `ParentComponents.swift:20,23` | focus scale 1.03 + ease-out | Yes |
| `ParentGateView.swift:127` | hold ring scale 1.06 | Yes |
| `RootView.swift:50-64,67` | opacity transitions + `easeInOut(0.25)` between routes | No gate, but opacity-only cross-fade, which the fetched HIG recommends as the Reduce Motion replacement |
| `HomeView.swift:24,27` | opacity + `easeInOut(0.2)` | same (fade) |
| `BaselineView.swift:40,43,44` | opacity | same (fade) |
| `SessionRunnerView.swift:180,199,202` | opacity | same (fade) |
| `ActivityContainerView.swift:167,184` | opacity | same (fade) |
| `AppComponents.swift:206,209` | caption pill opacity | same (fade) |
| `AppComponents.swift:101` | wing `rotationEffect` | static pose, not animated |
| `ParentGateView.swift:115-117` | ring `trim` driven by a 20 Hz timer | progress indicator, not decorative motion |

Offenders (strict reading): none move content. The only gap is that the focus scale in the **parent area** ignores Gentle mode (m-7) and that the style swap in `StoryButton` can disturb focus (M-3). Optionally gate the cross-fades on `reduceMotion` (`transaction.animation = nil`) for the strictest users; not required by the HIG.

### Captions for spoken prompts
- Every spoken instruction has an always-visible text equivalent (`activity.prompt` as a header, Wren speech bubbles as real text in `WrenSays`, feedback banners), and missing phoneme recordings fall back to a visible caption instead of speech synthesis. Good. The "Captions" setting does not control any of it (M-1). Caption timing: m-4. No video content exists.

### Audio-only and colour-only cues
- Correct/incorrect: sfx plus banner text plus a different icon (star vs lightbulb) plus coloured border; not colour-only, but not VoiceOver-announced (M-2).
- Guided answer: prominent fill plus "Try this one" label; tried choice: dimming plus "Tried" label; tricky words: underline plus colour plus legend; heard words: fill plus checkmark; used tile: dimming plus checkmark. Good.
- Page-turn sfx is redundant with the changing page.

### Volume controls
- Child-facing Sound on/off (`HomeView.swift:66`) and parent narration/music/effects steppers (`ParentSettingsView.swift:59-76`) exist, and the text reminds adults the TV volume also applies. Gaps: Music control is dead and no sample on change (m-10). Gentle mode scales music to 0.5 and effects to 0.6 (`AudioModels.swift:100-106`).

### Gentle mode
- Child-reachable on Home and in Parent Settings; calms button animation and lowers sfx/music. Hint says "no movement" and fades remain, which is acceptable. See M-3 and m-7.

### Drag, touch, hover, keyboard, text entry
- No drag, hover, pointer, keyboard, text field, swipe handler or tap-gesture dependence anywhere (grep: `DragGesture`, `TextField`, `onMoveCommand`, `onTapGesture`, `hoverEffect` all absent). The only gesture is the gate's long press (M-6). Ordering tasks use tile selection ("never dragging", `ActivityKinds.swift:209`). Nicknames are presets only (`OnboardingView.swift:7`). Excellent text-entry minimisation.

---

## 4. Done well

- Focus is never colour-only: 8 pt white ring + scale + shadow, kept in the calm variant (`Theme.swift:34-53`, `AppComponents.swift:6-21`).
- All text-on-colour pairings clear AA by a wide margin (ratios in section 1).
- Remote-only completeness: every screen has a focusable control and a Menu path; Menu semantics are thoughtful (root screens exit the app, nested screens go up, mid-activity asks gently).
- Destructive actions are guarded twice, with the safe option default-focused and Menu = cancel (`ParentConfirmView.swift`), as HIG recommends.
- Gate design is child-resistant and still non-text: hold + multiple-choice adult question, persisted lockout, VoiceOver bypass for the hold only (`ParentGateView.swift`).
- Large targets (>= 120 pt in the child UI, >= 88 pt in the parent UI), generous spacing, one obvious primary action per screen.
- No timers, no scores, no streaks, no failure language; wrong answers move to scaffolded help rather than penalty.
- Decorative art hidden from VoiceOver, composite elements grouped, headers marked, hints written for non-obvious actions.
- Multiple stable accessibility identifiers (`a11yID`) so the above can be regression-tested.
- Sound-off and missing-recording cases degrade to visible captions instead of silence.

---

## 5. Prioritised fix list

1. (B-1) Add the tvOS brand asset catalog: layered App Icon, Top Shelf images, AccentColor; wire it in `project.yml`.
2. (M-3) Replace the `if env.calmMotion` button branches in `StoryButton` with a single `Button` and a style that takes `calm`; verify focus stays on the Gentle mode button after pressing it.
3. (M-7) Log `safeAreaInsets` on device; remove the duplicated 80/60 padding if the system already applies it; then re-check the 2x2 choose screen and the Parent "mastery" settings page for overflow.
4. (M-2) Post VoiceOver announcements for feedback, modelled steps and sound captions.
5. (M-1) Wire `showCaptions` to the sound caption (and any optional captions) or remove the toggle; remove the dead "Music" stepper (m-10).
6. (M-6) Test the long-press gate on a real Apple TV; add a no-hold alternative (6 Select presses with a ring, or drop the hold).
7. (M-4) Remove shrink-to-fit below 0.9, re-flow the Skills category buttons and reason lines so rendered text is never below 29 pt (never below 23 pt).
8. (M-5) Move `Theme` fonts to scalable styles and `@ScaledMetric` metrics; test the largest size.
9. (M-8) Add `.isToggle`, adjustable stepper semantics, "played" state on blend tiles.
10. (m-1, m-2) Fix focus restoration: Home sticker close double jump; Story "Back a page" at page 0.
11. (m-4) Caption lifetime and layout slot.
12. (m-5, m-6, m-11) VoiceOver label accuracy (sentence blank, tricky words, phoneme-as-letters).
13. (m-7, m-8, m-9, m-12) Gentle mode in parent area, state contrast, Increase Contrast borders, confirm the system focus effect is not doubled.

## 6. Verdict

Material HIG violations remain. No BLOCKER exists in the interaction code itself, and the core design (remote-only navigation, safe Menu handling, large targets, AA contrast, non-colour focus, no text entry) is strong. But the build is not HIG-compliant yet because of: the missing app icon / Top Shelf assets (release blocker); one dead accessibility/caption setting; no VoiceOver announcements of feedback and tutoring steps; a likely focus-dropping style swap on the Gentle mode toggle; a probable double safe-area inset that forces the busiest screens to scroll or overflow; text that can shrink below the HIG 23 pt minimum; no Dynamic Type support; and an unverified, hold-only parent gate with no alternative for non-VoiceOver users. Items marked UNVERIFIED must be confirmed on a simulator or Apple TV before this review can be closed.
