# Accessibility

Status in one paragraph: the app is designed to be fully usable with the Siri Remote alone, with large targets, a focus indicator that is not colour-only, captions for anything spoken, a Gentle mode and Reduce Motion support. Most findings from the independent accessibility and HIG review have been fixed in code. **None of it has been checked on a real Apple TV, with real VoiceOver, on a real TV (overscan), or by looking at the screens**: the evidence is the code, the simulator UI tests, and the review. The independent review itself was a reading of the code, not a device test.

## 1. What is implemented

### Input and focus
- Siri Remote only. No text field, drag, hover, keyboard, swipe handler or tap-only gesture exists. The single gesture is the parent gate's 3-second press-and-hold, which has a no-hold alternative. Ordering tasks use tile selection, not dragging; nicknames are presets.
- Focus: `@FocusState`, `.defaultFocus`, `.focusSection()` on grids, button rows and pager bars; one delayed assignment per appearance to set the initial target. Focus is restored to the opener after overlays and sub-screens, handed on explicitly when the focused control becomes disabled, and never trapped: every screen has at least one focusable control and a Menu route (see [ARCHITECTURE.md](ARCHITECTURE.md) section 6).
- Focus appearance (`FocusCardStyle`, `ParentRowStyle`): scale, an 8 pt white outline and a shadow, so focus is not colour-only. With Gentle mode or Reduce Motion the scale and animation are removed and the outline stays. `StoryButton` is always one `Button`; Gentle mode only changes an environment value (`\.calmMotion`) that the style reads, so toggling it does not rebuild the focused button. The grown-ups' area reads the same value.
- Target sizes: child controls at least 120 pt (scaled with Dynamic Type), choice cards 170 pt or more, parent rows at least 88 pt; grid gaps 28 to 40 pt.

### Labels and VoiceOver
- Decorative art (the Wren character, emoji pictures, hills) is hidden from VoiceOver. Headers are marked. Almost every button has an explicit label and a hint. Grouped elements use `.contain` or `.combine`. The break and skip overlays are modal. Sort priority puts the prompt first.
- States are spoken: tried choices ("already tried"), used tiles ("already used"), tricky words ("tricky word") in story pages, the blank in a sentence activity reads "blank" until answered and then the answer, toggles in the grown-ups' area have the toggle trait and an On/Off value, steppers are adjustable (swipe up and down) as well as having buttons.
- Status changes are announced when VoiceOver is running (`AppEnvironment.announce`, via `UIAccessibility.post(.announcement)`): the feedback line after each answer, each "do it together" step (the first one together with the feedback that led to it), the sound caption, and the gate's "One more" notice.
- Stable accessibility identifiers (`a11yID`, for example `home.start`, `parent.menu.settings`) exist for tests.

### Captions and audio
- Every spoken instruction has an always-visible written equivalent (prompt text in the activity header, Wren's speech bubbles, feedback banners).
- A letter sound with no recording (all of them today) is never synthesised; it is shown as a caption pill in a reserved slot under the header (so it never covers the step label or the prompt) and stays until the next sound or prompt, or about 4.5 seconds. The Captions setting in the grown-ups' area switches this pill off; instructions and prompts are always shown. If the whole app is muted, requests fall back to captions.
- Sound on/off on the Home screen; narration and effects volumes for grown-ups (a "Music" control was removed because the app plays no music). Gentle mode lowers effects to 60% and music to 50%.
- No fixed timers, scores, streaks or failure wording are shown to the child; wrong answers lead to scaffolding.

### Motion
- No continuous, looping, parallax or zoom animation. All animations are 0.15 to 0.25 second ease or opacity fades. The focus scale and its animation respect the system Reduce Motion setting and Gentle mode. Route and panel changes are opacity cross-fades; they are not gated on Reduce Motion (the HIG suggests fades as the replacement for movement).
- Gentle mode is reachable from Home and Settings; `-uitest-reduce-motion` (DEBUG) forces it for tests.

### Type
- Text uses Dynamic Type styles (`largeTitle`, `title2`, `title3`, `headline`, `callout`, rounded design) and `@ScaledMetric` for minimum target sizes. No `minimumScaleFactor` is used anywhere in the app (searched); long text wraps with `lineLimit`. The theme's comment says every reading style is at least 29 pt at the default size; that was not measured. The review's HIG facts: default 29 pt, minimum 23 pt.
- The big letters and words children read (140, 110, 90 pt and similar) are deliberately fixed sizes, and emoji pictures are fixed (120 pt).

### Contrast
Computed from the colours in `Theme.swift` (WCAG relative luminance; the review's figures, which I recomputed and which match):

| Foreground on background | Ratio |
|---|---|
| text on background / surface / raised | 14.20 / 10.42 / 7.73 |
| secondary text on background / surface / raised | 11.67 / 8.56 / 6.35 |
| accent on background / surface / raised | 10.09 / 7.40 / 5.49 |
| dark text on accent (prominent buttons) | 10.58 |
| positive green on background / surface / raised | 9.02 / 6.62 / 4.91 (tightest text pairing) |
| white focus ring on background | 15.13 |

Every text pairing used clears 4.5:1. Weaker, non-text pairings: an unfocused button's fill against the background is 1.84:1 (the label carries the meaning); cards against the background 1.36:1 (decoration); tried choices at 45% opacity about 3.1:1; used tiles at 25% opacity about 1.9:1; white ring on yellow 1.50:1 (the ring's outer half sits on the dark background, 15.13:1).

## 2. What the UI tests check

All run with `XCUIRemote` in the Apple TV simulator in CI (`UITests/`). They are regression checks, not an accessibility audit.

- `AccessibilityTests`: on Onboarding, Home and the parent menu, every button and static text has a non-empty label, and the main Home and parent-menu controls have labels.
- `FocusNavigationTests`: Home always has focus; Menu from the sticker book returns to its opener; the parent menu and a section page restore focus to the opener; settings page focus; the confirm screen defaults to Cancel and Menu cancels.
- `ChildFlowTests`: first launch, baseline, a full short lesson to a calm summary (with a check that feedback text contains no failure words), Menu mid-session showing the break overlay with focus restored, the "do it together" path after two misses, Reduce Motion still navigates, and audio disabled still shows captions.
- `LaunchTests`, `ParentAreaTests`, `PersistenceTests`: first-launch focus, the load-error and unreadable-progress screens, the parent gate (including lockout and the no-hold route), settings persistence, and persistence across terminate and relaunch.

For pass/fail results use the CI logs and `TEST_RESULTS.md`; this document does not restate them.

## 3. Not verified

- A real Apple TV and a real Siri Remote: focus movement, the press-and-hold, Play/Pause, Menu.
- Real VoiceOver: whether labels are sensible to listen to, whether announcements are heard and in the right order, whether the adjustable steppers and toggles behave as intended. Announcements are posted only when `UIAccessibility.isVoiceOverRunning`; that path has not run.
- Switch Control, Voice Control, Increase Contrast, Bold Text, larger accessibility text sizes.
- Overscan and the safe area on a real TV. The container adds only 20 pt horizontal and 10 pt vertical on top of the system safe area, on the assumption that SwiftUI already insets content by the system safe area. If that assumption is wrong, content may sit too close to the edge. Activity content scrolls vertically; the parent settings pages are split so that each fits without scrolling, but this was reasoned, not seen.
- Anything visual: layouts, truncation, emoji rendering (some newer or ZWJ emoji may be missing on older tvOS fonts), the app icon, the contrast of the real rendered output.
- That Gentle mode keeps focus on the toggled button on a real device.
- Pronunciation and audio quality: there are no recordings.

## 4. Open and closed findings from the review

Source: [reviews/accessibility-hig-review.md](reviews/accessibility-hig-review.md). "Fixed in code" means the change is present and the code was read; it does not mean device-verified.

| Id | Finding | Status |
|---|---|---|
| B-1 | No app icon or Top Shelf assets | Fixed in code: layered brand assets with the right pixel sizes in `App/Assets.xcassets`, wired in `project.yml`. Appearance not inspected |
| M-1 | Captions setting did nothing | Fixed: it gates the caption pill. Instructions and prompts stay visible |
| M-2 | No VoiceOver announcements for feedback, steps, captions | Fixed in code (`announce`). Not heard on a device |
| M-3 | `StoryButton` swapped view structure on Gentle toggle | Fixed in code (single button, environment value). Device behaviour unverified |
| M-4 | `minimumScaleFactor` shrank text below 23 pt | Fixed in code: no `minimumScaleFactor` remains |
| M-5 | Fixed font sizes, no Dynamic Type | Fixed in code for UI text (text styles, `@ScaledMetric` targets). Child glyphs stay fixed by design. Not tested at large sizes |
| M-6 | Hold-only gate | Partly fixed: a no-hold route with harder questions, and the VoiceOver action. The hold on a real device is unverified |
| M-7 | Probable double safe-area inset | Partly fixed: padding cut from 80/60 to 20/10 pt on the assumption that the system already insets. Unverified on a TV |
| M-8 | Toggles, steppers and tile states lacked semantics | Partly fixed: grown-ups' toggles have the toggle trait and steppers are adjustable. Still open: Home "Sound" and "Gentle mode" are plain buttons with a value but no toggle trait; blend sound tiles show "lit" only through an icon hidden from VoiceOver; the guided tile's "Next" star is visual only |
| m-1 | Home focus jumped twice after the sticker book | Fixed in code (one assignment via a `landing` target) |
| m-2 | Story "Back a page" disabled while focused | Fixed in code (focus handed to "Next page") |
| m-3 | Programmatic focus moves after a selection (blend tiles) | Open: the next sound still takes focus automatically, also in Gentle mode and with VoiceOver |
| m-4 | Short-lived captions that covered the header | Fixed in code (reserved slot, about 4.5 s) |
| m-5 | Stale "blank" label | Fixed |
| m-6 | Tricky words lost in VoiceOver | Fixed ("tricky word" in the story label) |
| m-7 | Gentle mode not shared with the grown-ups' area | Fixed in code |
| m-8 | Low contrast for "tried" and "used" states | Open: opacity 0.45 and 0.25 are unchanged, including the "Tried" label |
| m-9 | Increase Contrast not handled | Open: no use of `colorSchemeContrast` |
| m-10 | Dead "Music" setting; no sample on volume change | Partly fixed: Music control removed. Open: no sound sample plays when narration or effects volume changes |
| m-11 | VoiceOver pronounces phonemes as words | Open: labels such as "Sound 1: sh" are still read by VoiceOver's own voice, although the app promises that letter sounds are never computer-made. Label them as letters ("S H") instead |
| m-12 | Custom focus effect may double the system one | Not re-assessed; needs a device |
| m-13 | Tight spacing in two rows | No defect found by the review; recheck if text sizes grow |
| m-14 | Minor semantics | Not re-checked in full. `HillsDecoration` is unused code |

## 5. Suggested manual pass (not done)

On a real Apple TV with the Siri Remote: walk every screen with VoiceOver on; hold-test the parent gate with the hold and with the alternative; try Reduce Motion, Bold Text and larger text; check the edges of the picture on a TV with overscan; confirm Menu behaviour at each level; read the screens at 3 metres.
