# Mastery and progression

This describes the algorithm as implemented in `Sources/StorySoundsCore/Engine/` (`Mastery.swift` which also holds `Scheduler`, `Progression.swift`, `SessionPlanner.swift` which also holds `Baseline`, `ActivityGenerator.swift`, `CurriculumIndex.swift`) and in the coordinators that feed it (`App/Child/ActivityCoordinator.swift`, `SessionRunnerView.swift`). Numbers are the code defaults (`MasterySettings` in `Models/Learner.swift`). The mastery thresholds were never validated against real children; they are reasonable engineering defaults, not research results. The unit tests cover the rules (`MasteryTests`, `SchedulerTests`, `ProgressionTests`, `SessionPlannerTests`, `EngineReviewFixesTests`, `EngineHardeningTests`); the evidence in this file is reading the code, not a re-run.

## 1. Vocabulary

- **Unit**: one teaching step, a sound and the letters that spell it (99 units).
- **Track**: `recognise`, `blend`, `segment`, `read`. A **skill** is a unit plus a track. Which tracks apply to a unit depends on what content exists for it (`ActivityGenerator.applicableTracks`).
- **Gate track**: the track that must be passed to move on: `recognise` if the unit has it, otherwise the first applicable track (the phase 4 consolidation units have no sound of their own).
- **Support level** of an attempt: `independent` (first try, nothing shown), `prompted` (a second or later try after a miss), `modelled` (the "do it together" path, or an item the planner marked as an introduction).

## 2. Evidence: what counts

Every answer is logged in `LearnerSnapshot.attempts`, but only `independent` attempts move mastery.

- `Mastery.update` ignores prompted and modelled attempts for score, counts, sessions, days, activity types and recent results. A wrong prompted or modelled attempt can lower the score by at most 0.02. A correct one changes nothing (and moves a `new` skill to `learning`).
- In an activity (`ActivityCoordinator.submit`): the first answer is independent. After a miss the card is disabled and "Good try! Have another look." is shown; the next answer is prompted. After a second miss the activity enters the "do it together" path (narrated steps, then the child finishes with the right answer highlighted); that finish is recorded as modelled. So a failed activity costs exactly one independent miss.
- Story reading and fluency word lists are self-reports: recorded as prompted (or modelled), never independent, so they can never make a skill secure.
- **Guessable items are never evidence.** A recognition item with fewer than three choices (`ActivityGenerator.minChoicesForEvidence`) can be passed by guessing. This happens only for units 1 and 2 (one or two letters taught so far). The planner marks such activities as modelled from the start (`SessionPlan.modelledKeys`), and `ActivityGenerator.evidenceSupport` downgrades an independent answer to modelled for them.
- **Homophones and same-meaning words** (built-in table of about 80 groups plus the `homophones` and `sameMeaningAs` data fields) are never offered as answer and distractor together. Cloze (sentence) items need a picture and a distractor at least two graphemes away from the answer, so a near miss such as mop/map cannot also fit.

## 3. Secure, learning, review due

States (`SkillStatus`): `new`, `learning`, `secure`, `reviewDue`.

A skill **becomes secure** when all of these hold after an independent attempt (`Mastery.meetsEvidence`; defaults in brackets):

| Rule | Default |
|---|---|
| Independent attempts | at least 6 (`minAttempts`) |
| Score | at least 0.85 (`secureScore`) |
| Different sessions | at least 2 (`minSessions`) |
| Different calendar days | at least 2 (`minDays`); a day is the learner's local date (`DayKey`) |
| Different activity types | at least 2 (`minActivityTypes`) |
| Errors in the last 8 independent results | at most 1 (`maxRecentErrors`) |

The score is an exponential moving average: `score = base + 0.3 * (result - base)` where `result` is 1 or 0 and `base` is the previous score, or 0.5 before the first independent attempt. For a child who is always right, the score is about 0.92 after 5 attempts and 0.94 after 6 (figures from the independent pedagogy review, consistent with the formula). So a competent child is secure after about 7 attempts across two days; nobody can be secure in one sitting.

**Response-time rule** (`useResponseTime`, default true, not exposed in the grown-ups' settings): when every other rule is met and the score is within 0.02 of the bar, a correct answer in under 3 seconds can tip the skill to secure, provided there are no errors in the window and the last three answers were right. It can only help, never penalise slowness. Caveat: the time is measured from when the activity is shown, which includes the spoken prompt, so a sub-3-second answer is unlikely in practice.

When a skill becomes secure, its recent-results window is cleared, so mistakes made while learning never count against it, and the first review is set one day ahead.

**Secure skill, wrong answer**: one error lowers the review stage by one and brings the next look to at most one day away. Two or more errors since it became secure (within the last 8) reset the stage to zero and, because that exceeds `maxRecentErrors`, set `reviewDue`.

**`reviewDue` skill**: a wrong answer resets the stage and sets the next look to one day. It becomes secure again when the score is at least 0.85 and the last three independent results were all correct.

Parent-adjustable (Settings, Mastery pages): score needed 70% to 95% in 5% steps, tries needed 4 to 12, sessions needed 1 to 4, days needed 1 to 4, session length 5, 7 or 10 minutes (the app clamps to 3 to 10). `minActivityTypes`, `maxRecentErrors`, the review ladder and the soft-pass values are not exposed.

## 4. Spaced review

`Scheduler`, ladder `[1, 3, 7, 14, 30, 60]` days.

- A skill is **due** when its status is `reviewDue`, or its `nextReviewAt` has passed. `new` skills are never due.
- The stage advances only when a secure skill is answered correctly **while due** (`wasDue` is taken from the skill before the update), so extra practice does not inflate the interval.
- For a child who is correct on the day each review falls due, reviews come about 1, 4, 11, 25, 55 and 115 days after the skill became secure; the stage then stays at the top rung.
- Due skills are listed most overdue first, ties broken by unit id then track (deterministic).

## 5. Passing a unit, and no-trap guarantees

There are three different ideas, deliberately separate:

- **Secure** (a skill): section 3.
- **Mastered** (a unit): every applicable track is secure now. Used for the parent's "Secure" status and for mastery stickers.
- **Passed** (`Progression.isUnitPassed`): enough to introduce the next unit. Every gate track must be one of: established (secure, or `reviewDue` after having been secure, so a refresher never re-locks later units); a few-choice recognition track that the child has met at all (units 1 and 2, whose items cannot be evidence); or **soft-passed**.

**Soft pass** (`Progression.meetsSoftPass`): at least 12 independent attempts, in at least 3 sessions, with a score of at least 0.6. It is latched (`softPassedAt`), so a later dip cannot pull the child back and forth. It is steady effort, not mastery: the unit is shown as in progress ("Moving on gently"), is not mastered, earns no mastery sticker, and stays in review at the shortest interval (one day) every time it is practised.

`nextUnit` returns the earliest not-yet-passed unit, from the baseline placement onward, whose prerequisites are passed (prerequisites below the placement count as met). There is one new unit at a time.

Ways a child is not trapped, all in the code:

1. soft pass (above);
2. guessable items are not evidence, and units 1 and 2 pass once met;
3. a unit with nothing practicable never blocks, and the consolidation units do not add graphemes;
4. a grown-up can steer the next session (section 8);
5. a run of difficulty triggers gentler material (section 7) and the "do it together" path (section 2);
6. leaving a session or skipping the baseline is always possible and never penalised.

Not guaranteed: nothing stops a child who never reaches soft-pass conditions (for example by playing very rarely) from staying on a unit; the parent screens show where they are.

## 6. Baseline placement

Purpose: avoid starting a child who already knows many sounds at the very beginning. It is optional ("Skip for now" starts from the first sound).

**Plan** (`Baseline.plan`): the units of the Reception stage that have a sound of their own (not consolidation, not instruction audio) are sampled evenly: 16 positions across the list, one item per unit, easiest first. The first three use sound recognition (listen and choose, or find the letter); from the fourth they alternate blend-to-word and read-to-picture, falling back to recognition. Guessable items are skipped. The seed is a stable hash of the profile id, so a profile always gets the same baseline.

**Presentation** (`BaselineView`): the plan is cut off at 10 items, or earlier after two consecutive evidence misses (`Baseline.shouldStop`; modelled items are not evidence and neither extend nor break a run). So in the UI the last six of the sixteen planned samples are never reached. No score or correctness is shown, and no attempts are written to the learner's history in baseline mode.

**Placement** (`Progression.placeFromBaseline`): a unit's verdict is "known" only for a correct independent answer; help counts as a miss; modelled items are ignored.
- If there is a miss: the lowest-order sampled miss marks where knowledge ends, and placement is **3 units earlier** (`baselineStepBackUnits`, never before the first unit). Samples above the first miss are ignored because they may be guesses.
- If there is no miss: placement is the highest sampled unit, provided at least 2 of the last 3 samples are known; otherwise the first unit.
- With no usable result (skipped), placement is the first unit and nothing is provisional.
- Units below the placement get provisional skills on their gate track only: status `learning`, score 0.7 if their sample was correct else 0.5, first review after `1 + (order mod 7)` days. They are never `secure` (that needs sessions and days of evidence), and they come back as gentle reviews.

## 7. Session composition

`SessionPlanner.plan` builds the whole session up front from the snapshot, the time and a seed.

- **Length**: `total = max(4, minutes * 60 / 25)` activities (25 seconds each is an optimistic planning figure): 12 for 5 minutes, 16 for the default 7, 24 for 10. One slot is reserved for the ending. The session also ends at `(minutes + 3)` minutes, checked between activities and only after the fourth. The step counter ("Step 3 of 16") can therefore promise more steps than are played.
- **Focus unit**: an explicit focus unit, else the unit a grown-up unlocked, else `nextUnit`. If none (everything passed), the session is review and reading.
- **Buckets** of the remaining slots: about 40% focus unit, 40% due review, 20% mixed review (sounds from all units up to the focus). If there is no review candidate, the review share goes to the focus unit. Review candidates: grown-up "revisit" requests, then due skills (most overdue first), then unfinished `learning` skills of earlier units.
- **Focus items**: the gate track first, twice in the rotation, while it is not secure; then the other tracks, least secure first.
- **Interleaving** pattern: review, focus, focus, mixed, review, focus, mixed, repeating.
- **Ending**: a short decodable story if one exists at the focus unit, otherwise a fluency word list. Both are self-reported, not evidence.
- **Repeats**: an item may appear at most 3 times in a session (`maxRepeatsPerItem`); activities are chosen least-used type first.
- **Content limits**: everything in an activity comes from content at or below the session's known order; words must be decodable (graphemes taught plus word requirements), tricky words must be introduced, sentences and stories must be unlocked.
- **Struggle lead-in**: if the focus unit's skill has a struggle streak of 3 or more independent misses in a row (reset by any independent correct answer), the session starts with items from up to two prerequisite units and then up to two easier, guided versions of the focus items (`ActivityGenerator.simplify`), shown as "do it together".
- **Mid-session recovery**: if three activities in a row contain a miss, an easier guided version of the last activity and one item from its prerequisite unit are spliced in next; at most twice per session.

## 8. Parent overrides

Overrides are stored on the profile (`ParentOverride`: unit id, mode, time) and never change a `SkillState`.

- `unlocked` (set from the Skills screen for a locked unit): the unit becomes the session focus even though earlier units are still open.
- `revisit` (set for any other unit): the unit is added to the review candidates; if it lies ahead of the learner's frontier and the learner has met it, it is allowed content up to its own order, and it becomes the focus.
- The newest request wins. After the unit has been practised in 3 sessions the request stops steering, so an old override cannot pin the child forever.
- The explanations (locked, ready, in progress, due) honour overrides. There are two implementations of the focus choice: `Progression.overrideFocusUnit` in the package (unlocked only, "not secure on its gate track") and `SessionModel.overrideFocusUnit` in the app (both modes, "not mastered on all tracks"); the app passes its result as an explicit `focusUnitId`, so the app's version is the one that applies.

## 9. Determinism

All randomness comes from `SeededRNG` (SplitMix64, salted with the profile id): no system randomness in the engine. The same snapshot, time and seed produce the same plan. In the app the session seed is the Unix time at start (or `-uitest-seed` in DEBUG). The baseline seed is a hash of the profile id. Ordering ties are broken by unit id, track name or array position, never by dictionary order.

## 10. Known limitations

From `docs/reviews/pedagogy-review.md`, checked against the current code. Items that review raised and that have since been fixed are listed in [REMAINING_WORK.md](REMAINING_WORK.md) and not repeated.

- **Evidence ignores item variety.** `Mastery` does not look at `itemKey`, so the same item can supply several of the six attempts (an item may repeat 3 times per session). The review's simulation (old code, same defaults) found a child answering correctly 50% of the time became "secure" within 60 attempts 47% of the time, and a pure guesser with three choices 5.5%. Not fixed.
- **No "read aloud to an adult" mode.** Reading tasks are multiple choice on screen. Real fluency needs an adult listening; the story and fluency tasks only model and self-report.
- **Pace.** With the defaults a unit takes at least two calendar days, so the whole sequence needs roughly 200 sessions. Parents can reduce days and tries.
- **Alternative pronunciations gate on isolated recognition.** Units such as the second sound for `ow` or `ea` are gated on choosing the letter for a sound, not on choosing the right pronunciation inside a word. Unchanged by design.
- **Plural `-s` as /z/** (for example `dogs`) is not taught; the tile plays /s/ while the word is said with /z/.
- **Baseline.** Only 10 of 16 planned samples are presented; a child who knows more than about the first 30 Reception units is placed from fewer samples than planned. It is still one item per sampled unit, with a three-unit step back.
- **Year 1 tricky words** such as `where`, `who`, `once`, `friend`, `any`, `many`, `again`, `two`, `from` are not in the tricky list.
- **Accent.** Words whose vowel depends on accent are flagged `accentNote` in the data but the app does not use the flag; the sound model is a UK, non-rhotic one.
- **Everything above rests on an inferred curriculum order** (see [CONTENT_AND_LICENSING.md](CONTENT_AND_LICENSING.md)) and placeholder audio; none of it has been reviewed by a phonics lead or tried with a child.
