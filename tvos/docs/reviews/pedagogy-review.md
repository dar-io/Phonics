# Story Sounds - Independent Phonics Pedagogy Review

Reviewer role: independent systematic-synthetic-phonics reviewer (UK Reception / Year 1). I did not write this content.
Scope: `tvos/Sources/StorySoundsCore/Resources/curriculum.json` (identical to `reading-app/src/curriculum/data/curriculum.json`, verified), `word-requirements.json`, `audio-manifest.json`, `tvos/Sources/StorySoundsCore/Engine/*.swift`, `tvos/App/Child/*.swift`.
Read-only review: no source was edited. Analysis scripts were run with `python3 -I` (scratchpad: `verify.py` plus ad-hoc simulations; every number below came from running them).

Important limits and honesty notes
- Official Letters and Sounds / Little Wandle pages are blocked. All comparisons are from my memory of that family of programmes and are marked "(from memory)". I do NOT claim the sequence matches any specific programme. The repo's own manifest says the same (`audio-manifest.json` statement), which is correct and should stay.
- There is no pronunciation dictionary in the sandbox (no CMUdict, nltk, etc.). Word-level pronunciation judgements are my own and are listed explicitly so a human phonics lead can confirm them.
- Audio is 100% placeholder (1,353 word, 94 phoneme, 18 instruction, 6 sfx entries, all `file: null`). Nothing audible was reviewed; audio-dependent findings are about what the engine will ask the audio layer to play.

---

## 1. Summary table

| Id | Sev | Area | One-line |
|----|-----|------|----------|
| B1 | BLOCKER | Engine/audio | Sound tiles and blend/segment audio play the FIRST-taught phoneme for a grapheme, contradicting the word for 201 of 1,288 words (incl. all oo-short words) |
| B2 | BLOCKER | Engine | A child can be stuck on a unit with no exit; parent "Unlock and practise" is a no-op for the child's sessions |
| M1 | MAJOR | Engine | Baseline placement is the earliest SAMPLED miss, not the earliest insecure prerequisite; one lucky guess skips 8-16 units |
| M2 | MAJOR | Distractors | Homophones and plausible-sentence near-misses are offered as distractors, creating two correct answers |
| M3 | MAJOR | Content | One `th` unit and one phoneme audio, but 6 of the 12 words taught in that unit are voiced |
| M4 | MAJOR | Content/Engine | `p4-suffix` is gated on a "recognise" task whose audio is the instruction clip `i-blend` |
| M5 | MAJOR | Engine | First two units have degenerate recognise tasks (1 and 2 choices) so "secure" evidence is meaningless |
| M6 | MAJOR | Content | Emoji: near-synonym pairs with different emoji, and several wrong/ambiguous emoji, cause false "wrong" answers in picture tasks |
| M7 | MAJOR | Data | `gnaw` is segmented `gn-a-w` (should be `gn-aw`); `gene` soft-g is not gated; `monk` mis-decodes |
| m1-m14 | MINOR | various | see section 7 |

Everything else I tested was clean (section 2), which is a genuinely good result for a 1,288-word / 306-sentence / 18-story data set.

---

## 2. Independent decodability verification (script re-run, not trusting the repo validator)

I re-implemented the unlock logic from scratch (taught set = graphemes of units with order <= N, excluding the three consolidation units `p4-cvcc/p4-ccvc/p4-long` exactly as `CurriculumIndex` does; word unlock = max first-taught order of its graphemes, plus any `word-requirements.json` unit orders).

| Check | Result |
|---|---|
| Units / words / tricky / sentences / stories / requirement entries | 98 / 1,288 / 65 / 306 / 18 / 374 |
| Duplicate word texts | 0 |
| Word whose joined graphemes (incl. split `a_e`) != its spelling | 0 |
| Word using an untaught grapheme | 0 |
| Word that is also a tricky word (decodable before introduction) | 0 |
| requirement entries naming an unknown word or unit | 0 |
| requirement unit that shares no grapheme with its word | 0 |
| Sentence word token: join mismatch / untaught grapheme | 0 / 0 |
| Sentence `unlockedByOrder` lower than independently recomputed unlock | 0 (engine also takes the max, so safe either way) |
| Sentence tricky token not in tricky list, or introduced after the sentence unlocks | 0 |
| Sentence text vs token sequence differ | 0 |
| Story referencing a missing sentence | 0 (stories unlock at orders 8, 10, 20, 27, 34, 36, 40, 41, 42, 49, 52, 54 x3, 61, 69, 84, 90) |
| Tricky word `introducedAtOrder` != the unit that lists it | 0 |
| Every unit `audioId`, every `w-<word>` and tricky `w-<word>` present in manifest | yes (only `i-blend` is shared, by the 4 phase-4 units) |
| Example words: not decodable at unit order / missing | 0 (2 informational: `jumping`, `singing` are `-ing` examples of `p4-suffix`, which lists `ed`) |
| Words by unlocking unit phase | P2: 400, P3: 215, P4: 172, P5: 501 |
| Sentences by unlock phase | P2: 93, P3: 57, P4: 50, P5: 106 |
| Misconception `confusedWith` that fails to resolve to a taught grapheme/unit | 0 (21 point at LATER units; harmless because the generator filters by taught order) |

Segmentation sanity (a second, independent test): 15 words contain adjacent single-letter graphemes that spell a taught digraph. Fourteen are legitimate syllable boundaries (`around`, `zero`, `hero`, `circus`, `orange`, `ginger`, `danger`, `character`, `parachute`, `direction`, `giraffe`...). One is a real error: `gnaw` (see M7).

wordRequirements gating (the mechanism that stops `snow` unlocking at the `cow` sound): 374 words carry requirements. Grapheme-ambiguity audit: 15 graphemes are taught by more than one unit (a, i, g, o, c, e, u, y, ch, oo, or, ow, ou, ea, ie). I listed every word using one of these without a requirement for an alternative unit and read them. Findings:
- Correctly gated by my reading: all `ow`/`ou`/`ea`/`ie`/`or`/`ch`/`oo` words in the "no requirement" list take the base sound, except as noted. Words such as `old cold gold both hello open robot child blind find tiger spider unit music human student menu cent city gem gentle ginger giant orange book look good cook wood bread head heavy ready word work world wash swan watch` all carry the right requirement.
- Defects: `gene` (soft g, no `g-g-j`, unlocks at 71 but soft g is taught at 86), `monk` (`o` says /u/, unlocks at 36), `dinosaur` (requirement lists `g-o-oa` but the real issue is long `i` and a schwa `o`), `gnaw` (M7).
- Accent-dependent but ungated (see m3).

Conclusion for decodability: structurally excellent. The remaining decodability defects are three words plus the systematic issue of what the audio plays (B1) and the `s` = /z/ plural pattern (m5).

---

## 3. Curriculum data review

### 3.1 GPC sequence plausibility (from memory, uncertain; no programme-match claim)

Reception core (units 1-50) reads as the familiar Letters-and-Sounds-family order, as I remember it:
- Set order `s a t p | i n m d | g o c k | ck e u r | h b f ff l ll ss | j v w x | y z zz qu | ch sh th ng nk` - consistent with that family.
- Vowel digraph order `ai ee igh oa oo(long) oo(short) ar or ur ow oi ear air er` - consistent. `ure` (as in "pure/cure") is absent as a grapheme (m2).
- Phase 4 as consolidation (no new GPCs) with CVCC, CCVC, longer words, suffixes - consistent in spirit.
- Year 1 (units 55-98): alternative spellings (`ay ou oy ea ir ie ue ew aw wh ph oe au ey`), alternative pronunciations (`u o i a e` long, `ow`=/oa/, `ou`=/oa/, `ea`=/e/, `y`=/igh/ and /ee/, soft `c`, soft `g`, `ch`=/k/ /sh/, `a`=/o/ after w, `or`=/ur/ after w), `dge tch kn wr mb gn`, `ture`, `tion/sion`. Coverage is sensible and wider than many schemes.

Concerns:
1. Phase labels: all of units 1-37 carry `phase: 2`, including `j v w x y z zz qu ch sh th ng nk`. In the programme family I remember, those are Phase 3 graphemes (the *term* placement, Autumn 2, is plausible; the *phase number* is probably wrong). Cosmetic unless the UI or reports show "Phase 2". (MINOR m1, uncertain.)
2. Year 1 dependency design: `g-split-a` has prerequisites `g-a-ai`, `g-split-i` needs `g-i-igh`, etc. So the single-letter open-syllable long vowels (`baby`, `hello`, `find`, `zero`) are taught BEFORE split digraphs, and are prerequisites of them. Most schemes I know teach split digraphs first and the open-syllable letters later; split digraphs do not logically need `paper/baker`. This also lengthens the critical path. (MINOR m6, uncertain.)
3. The prerequisite graph is essentially a linear chain (each unit needs the previous one, occasionally two). That is why a baseline "step back to direct prerequisites" only steps back one unit (M1).
4. Pace: gate needs 2 calendar days per unit (default `minDays = 2`), so the sequence takes at least 98 x 2 = 196 sessions: about 39 school weeks at 5 sessions/week, about 65 weeks at 3/week. Parents can lower days (1-4) and tries (4-12) in `ParentSettingsView`, so this is configurable; the default is on the cautious side for Phase 2 (about 2.5 new GPCs/week at 5 days/week versus the roughly 4/week I remember) (MINOR m7).

### 3.2 Pronunciation guidance quality

Strengths: every consonant (s t p n m d g c k h b f l j v w y z r ch th) carries an explicit "no 'uh'" instruction, b/d, p/b, m/n, s/z, c/k, g/j, ch/sh, ear/air, oo/oo, ur/er misconceptions are the right ones and the b/d "stick first/belly first" cue is classic. `x` ("/k/ then /s/ in one go"), `qu` ("/k/ then /w/, q always travels with u") and `ng` ("ONE sound, not n then g") are all correct. `wh` honestly says "same sound in most accents". `air`: "no trailing r push" is right for a non-rhotic model.

Findings:
- **M3 (voiced/unvoiced th)** - `g-th` describes /th/ (thin) and tacks on "can be voiced... 'this', 'that'" in the same string; one audio (`ph-g-th`) and one phoneme label `/th/`. The unit's own word bundle at order 34 contains this, that, then, them, with, than (voiced, 6) and thin, thick, moth, bath, path, thud (unvoiced, 6). Across the whole word list: 40 `th` words, 10 voiced by my judgement (`this that then them with than those these feather weather`), plus 8 sentences that contain a voiced-th word. A child taught one sound will mis-blend half the first words.
  Fix: add a second unit (or a `th-voiced` sound id) taught immediately after, with its own `ph-` audio and words; tag each word's `th` with the voiced/unvoiced unit via `wordRequirements` so the blend tile plays the right sound. At minimum split the 34-order bundle into unvoiced-first and move voiced words behind the voiced unit.
- `g-er` says "a light 'uh' with a hint of r" while `g-air` says "no trailing r push" and `g-ear` "soft 'uh'". For a non-rhotic UK model "hint of r" invites a rhotic /r/. (MINOR m8.)
- `g-e-ee` lists `zero` as an example; the `e` in zero is /ɪə/ (a diphthong), not a clean /ee/ (MINOR, in m8).
- `g-igh` says it is "the same as the letter name 'I'" while `g-i`/`g-w`/`g-y` repeatedly say "not the letter name". Not wrong (the /igh/ sound is the name of "I") but a literal 5-year-old could be confused; reword to "the sound in 'high' and 'light'". (MINOR.)
- `g-c` "quick, quiet click at the back of the throat": "click" may tempt a true click consonant; say "a quick, quiet sound made at the back of the mouth". (MINOR.)
- `g-oo-short` and `g-oo-long` share the phoneme key `oo` (see M5/"recognise tests nothing" below); the guidance is good but the engine cannot tell the two units apart in recognition tasks.
- `g-h` misconception "h vs n" is odd; a more useful confusion is "h vs wh/ch" later. (negligible.)
- Examples to confirm with a phonics lead: `room`, `roof` classed long /oo/ (some northern speakers use short); `launch` (au = /or/ in RP, /o/ elsewhere).

### 3.3 Misconceptions
Good set. Missing but valuable: b/d visual cue appears on both units (good), p/q and u/n visual confusions, `w`/`m` mirror, `ai/ay` and `au/aw` placement rules, `ow` as /ow/ vs /oa/ (present on `g-ow-oa`), `ie` vs `ei`, and "the letter name vs the sound" for every vowel. Not defects.

### 3.4 Tricky words per phase (from memory)
Introduced at: `is I the` (1), `as and` (21), `has his her` (22), `go no` (24), `to into` (25), `put pull full push` (27), `he we me be` (29), `of` (30), `she` (33), `was you` (37), `they` (39), `my by` (40), `all` (41), `are` (43), `sure pure` (45), `said so have like` (51), `some come love do` (52), `were here little says` (53), `there when what one out today` (54), `their people oh` (59), `your Mr Mrs Ms` (62), `ask could would should` (66), `our house mouse` (72), `water want` (79).
- Introduced before use: verified (section 2).
- Matches the family of lists I remember for Phase 2-4 closely. Year 1 is thin: missing statutory-style common exception words `where`, `who`, `once`, `friend(s)`, `any`, `many`, `again`, `because` (here decodable via `au`, acceptable), `school` (decodable via `ch`=/k/, fine), `two`, `from`. (MINOR m9.)
- `decodablePartsKnown` flags are inconsistent with the field notes: `is` (true, but `i` is not taught until order 5), `like` (true, note says "split i_e taught later"), `when` (true, note says "wh taught later"). The engine does not read this field (grep), so cosmetic, but a future UI may. (MINOR m10.)
- `should/could/would`: note says "'l' is silent" - fine for children. `says`: "'ay' says /e/" correct.
- Tricky words are introduced at order 1 (`is`, `I`, `the`) when only `s` is known; `identifyTricky` then asks the child to match audio to a whole word. That is whole-word recognition, appropriate for tricky words, but worth a parent note that this is not decoding.

### 3.5 Content safety, culture, homophones, accent

Run: keyword scan of 1,288 words and 306 sentences plus manual read of all sentences and 18 stories. No scary, violent, sexual, or frightening sentences found. Items to adjust:
- Vocabulary with adult/health connotations: `pill` (emoji 💊 - normalises pills to a 4-6-year-old), `weed` (emoji 🌿; also cannabis slang), `smoke`, `fat` (body-shaming risk), `kiss` with 💋 (lipstick kiss mark, adult-coded; use a plain face), `nail` with 💅 (nail-polish emoji, not a hammer nail; the sentence `Sam hit the nail with a hammer` pairs with it), `monk` (religious term, and mis-decodes), `witch` 🧙 and `potion`/`wand` (fine for most; some families object), `whip`, `hit`, `rude`, `trap`, `cage`, `shark`, `snake`, `spider`. None is a blocker; remove or soften the first six. (MINOR m11)
- Names and families: all names are Anglo (Pip, Tim, Nan, Dad, Mum, Ben, Meg, Kit, Pam, Tom, Sam, Max, Jim, Zak, Viv, Kate). Roles lean stereotyped (Dad fixes the van; Mum kisses the pup). Add some varied names (for example Ali, Asha, Kofi, Mei, Sol) - they are decodable. (MINOR m12)
- UK-isms (`Mum`, `tin`, `bin`, `trolley`, `crisps`-style) fit a UK product; state the target market.
- Homophones present in the word list: `sea/see`, `bee/be`(tricky), `night/knight`, `write/right`, `new/knew`, `which/witch`, `not/knot`, `cent/sent`, `dew/due`, `fur/fir`, `cord/chord`, `past/passed`, `hear/here`(tricky), `to/too`(tricky), `no/know`(tricky), `wood/would`(tricky), `their/there`(both tricky). 17 pairs. Consequences in M2.
- Homographs/ambiguous reading: not present as far as my scan went (`read`, `live`, `wind`, `lead`, `tear` absent). Good.
- Accent-dependent words present (all treated as short /a/ or /oo/ - a northern/Scottish assumption): `bath path past pass passed fast fastest dance graph bathtub giraffe` (TRAP/BATH split), `bus cup mum sun` etc. (STRUT/FOOT split), `room roof`, `put pull full push` (already flagged accent-dependent in the tricky data - good). Rhotic accents: `ar or ur er ir air ear` units. Add a per-word "accepted variants" note in the audio brief and the parent guide; `bath/path` appear in three sentences and a story (`Mud Bath`). (MINOR m3)
- Plural `-s` is /z/ in 126 words (`dogs bags beds pigs...`) and `rose nose` have /z/: nothing teaches this. (MINOR m5)

---

## 4. Engine review (read through the Swift, reasoned with scenarios and simulations)

### 4.1 Mastery thresholds (`Mastery.swift`, `Learner.swift:71-80`)
Defaults: EMA alpha 0.3, prior 0.5, secureScore 0.85, minAttempts 6, minSessions 2, minDays 2, minActivityTypes 2, maxRecentErrors 1 (window 8), review ladder 1/3/7/14/30/60 days.

Simulation (independent attempts only, 6 focus attempts per session, one session per day, 4,000 trials each):

| True accuracy p | P(secure within 60 attempts) | Median attempts to secure | Median days | P(secure by day 2) |
|---|---|---|---|---|
| 0.33 (pure guess, 3 choices) | 5.5% | 30 | 5-6 | 0.9% |
| 0.50 | 47% | 28 | 5 | 8.6% |
| 0.60 | 82% | 22 | 4 | 21% |
| 0.70 | 98% | 14 | 3 | 42% |
| 0.80 | 100% | 9 | 2 | 68% |
| 0.90 | 100% | 7 | 2 | 92% |
| 1.00 | 100% | 7 | 2 | 100% |

Deterministic checks: all correct -> EMA after 5 attempts 0.916, after 6 0.941; one early miss still reaches 0.85 by attempt 6-9. So thresholds are individually sensible, and a competent child passes in 2 days.

Observations:
- Prompted/modelled attempts never count as evidence and cap at -0.02 score: correct and kind. A failed activity costs exactly one independent miss (first wrong), the second wrong is "prompted" and the finish is "modelled". Good.
- **Weakness**: a half-knowing child (p = 0.5) becomes "secure" 47% of the time within 60 attempts, and a pure guesser 5.5%, because security is sticky once the EMA touches 0.85 with at most one error in the last 8. No check that the evidence spans distinct items: `maxRepeatsPerItem = 3` lets the same item appear three times per session and `Mastery` never looks at `itemKey`. Add "at least 4 distinct item keys among the last 8 independent attempts" and "at least 5 of the last 6 correct". (MINOR m4, cheap fix.)
- `useResponseTime = true` by default: a sub-3-second correct answer can tip a near-threshold skill (margin 0.02). It only helps, but it rewards fast tapping on a TV remote, which conflicts with the "no pressure" stance. Default it to false. (MINOR m13)
- `Mastery.swift:149-152`: a secure skill with ONE old error still in the last-8 window drops to `reviewDue` on its next single miss (errors = 2 -> `repeated` -> `errors > maxRecentErrors`). The comment promises "one occasional error never erases progress". `isEstablished` keeps later units unlocked, so no harm to progression, only to the review burden. Count only post-secure errors for the demotion. (MINOR)
- `DayKey` uses UTC. For UK summer time a session after 23:00 BST is counted on the previous UTC day only in the other direction (00:00-01:00 BST is yesterday). Rare; use the learner's calendar if a second day matters. (negligible)

### 4.2 Spaced review ladder
1/3/7/14/30/60 days is a reasonable expanding schedule: a perfect child is reviewed on cumulative days 1, 4, 11, 25, 55, 115. The stage only advances on a correct answer when the skill was actually due (good: early practice does not inflate the interval). After an error the next look is at most 1 day away and stage drops by one (or to zero on repeats). Recovery from `reviewDue` needs score >= 0.85 and the last three correct (from 0.63 after one miss, three correct gives 0.74, 0.82, 0.87: reachable). Sound design.

### 4.3 Struggle intervention and "does it trap a child" (**B2**)
What exists: per-skill `struggleStreak` (3 independent misses) triggers a lead-in at the next session (prerequisite recognition items plus easier, modelled versions via `simplify`); mid-session, 3 consecutive activities with a miss splices an easy modelled version plus a prerequisite item (max 2 recoveries per session); after two misses in an activity the model is shown and the child finishes with the star highlighted; the break dialog never penalises. All good.

What is missing:
- **B2 No way forward for a child who genuinely cannot pass the gate.** The gate is `recognise` secure (`Progression.gateTracks`). From the table above a child at p = 0.5 has a 53% chance of never passing in 60 attempts (about 10 sessions). `Progression.nextUnit` (lines 194-218) never reads overrides and has no "advance anyway after N sessions" rule. `SessionRunnerView.swift:97` calls the planner with `focusUnitId: nil`, so nobody can steer the focus. The parent "Unlock and practise X" button (`ParentSkillsView.swift:139`, `ParentPracticeView.swift:13,91-92`) writes an `.unlocked` override that is read only by `explainUnits` (status text); the message it shows, "X will come up in the next session", is false. A `.revisit` override works for earlier units only because `reviewCandidates` requires `unit.order <= knownOrder` (`SessionPlanner.swift:332-336`), so an unlocked LATER unit can never appear.
  Scenario: Unit `g-b` (b/d confusion). Child answers 3/6 correctly each session. Day 1-10 each session ends with struggle lead-ins, no advancement, parent presses Unlock on `g-f`, nothing changes. The only exit is "reset progress".
  Fix: (a) make `nextUnit` honour `.unlocked` (choose the earliest unlocked-and-not-secure unit when the natural focus is stuck), and let SessionModel pass the parent-chosen `focusUnitId`; (b) add an automatic "park and move on" rule: if a unit has >= 5 sessions and >= 24 independent attempts without reaching secure, mark it `parked`, continue with the next unit, and keep the parked unit in the review pool; (c) surface "stuck on X" in the parent report (the report already lists confusions but has no stuck flag).
- Related **M4**: `p4-suffix` (units 54) is gated on `recognise` because its grapheme `ed` is not in the consolidation set (`CurriculumIndex.swift:36`), but its `audioId` is `i-blend` (an instruction clip, shared with the other three phase-4 units). The `listenChooseSound` activity will play "listen" + the blend instruction, and the sound is three different sounds (/t/ /d/ /id/). The task is unanswerable by listening; it is passable only by elimination. Treat `p4-suffix` as a consolidation unit (gate on blend), or give `ed` a real clip per variant and gate on reading words with `-ed`.
- **M5 degenerate first units.** Distractors come only from taught graphemes (correct), so unit 1 (`s`, taught set {s}) shows ONE choice, and unit 2 (`a`) shows two. Recognise evidence for `s` is 100% automatic, and the baseline's first item (`g-s`) is auto-correct. I computed available choices for every non-consolidation unit: only orders 1 and 2 are under 3 choices. Fix: teach/gate `s a t p` as one block (Set 1) with mixed-review items across the block, or skip the gate for orders 1-2.

### 4.4 Placement from baseline (**M1**)
`Baseline.plan` samples 9 units at fractions 0, .06, .14, .24, .36, .5, .64, .78, .92 of the 95 teachable units: orders 1, 6, 14, 23, 34, 48, 64, 77, 90 (gaps of 5-15 units), one item each, stopping after two consecutive misses. `placeFromBaseline` places at the first sampled miss, stepping back only to DIRECT prerequisites newer than the last correct sample. Because the prerequisite graph is a chain, that is at most one unit back. Units between the last correct sample and the miss are marked provisional "learning" (score 0.5), unlocked via `prerequisiteMet`, and the planner starts new teaching at the placement.

Simulation of the exact algorithm (child knows units 1..K perfectly, guesses 1/3 elsewhere, 6,000 trials per K):

| K (units known) | mean placement order | mean unknown units skipped | P(skip >= 3 unknown) | P(skip >= 8) | P(under-place) |
|---|---|---|---|---|---|
| 0 | 3.9 | 2.9 | 33.7% | 11.2% | 0 |
| 4 | 9.1 | 4.2 | 31.9% | 31.9% | 3% |
| 8 | 17.6 | 9.0 | 94% | 32% | 6% |
| 12 | 17.6 | 5.2 | 31.7% | 31.7% | 5.5% |
| 24 | 37.5 | 14.3 | 88% | 88% | 12% |
| 36 | 49.0 | 15.0 | 86% | 86% | 14% |

So it does NOT choose the earliest insecure prerequisite. Example: a child who knows only `s a t p i n` (K = 6) misses at order 14 (`e`), is placed at order 13 (`ck`), and `m d g o c k` (6 unknown letters) become "learning" and are skipped; the next sessions then use words built from them. A non-reader has a 33% chance of being placed past unit 1 and 3.7% past unit 14 purely by guessing.
Fix: (1) place at `lastDemonstratedSample + 1` (the earliest unsampled unit after the last correct sample), not at the miss; (2) require 2 correct items per sampled unit, or add a follow-up probe on the 2-3 units immediately before the first miss; (3) walk prerequisites transitively; (4) do not unlock units whose only evidence is "assumed", or order the provisional skills so the first review sessions probe them. Also treat a single miss on the very first items with caution (a careless slip places a capable child at order 5; this under-placement is benign).

### 4.5 Activity mix and generator (`SessionPlanner`, `ActivityGenerator`)
Session plan: 7 min default -> `max(4, 7*60/25)` = 16 activities; 40% focus, 40% due review, 20% mixed, a story or fluency finish (not available for units 1-3), lead-in on struggle. Gate track first (twice) while insecure. Strengths: one new unit at a time; review before novelty; recognise/blend/segment/read tracks; self-reported story and fluency never become evidence; blending is done properly (tap each grapheme sound, then pick the word); every activity is generated only from content with order <= `knownOrder`; sentence cloze, picture, tricky tasks draw only on introduced tricky words and unlocked sentences.
Concerns:
- Mix: reading is dominated by multiple-choice recognition (picture match, cloze). There is no "read this word aloud and the adult confirms" mode on the TV. Acceptable for a self-run TV app, but state in the parent guide that real reading needs aloud practice with an adult (the fluency task plays each word when tapped, which is modelling, not reading).
- Units with few focus items repeat: for orders 1-2 there are 3 recognise items per grapheme and `maxRepeatsPerItem = 3`, so a 15-slot body repeats the same card. For orders 3-4 too (2 and 5 focus words).
- 25 s/activity is optimistic. Blend tasks need 4+ taps plus choice plus Next. Real sessions will hit the soft 10-minute cut-off (`SessionModel.start`, `maxSeconds = (minutes+3)*60`, checked only after activity 4) and the story/fluency finish is the activity most likely to be skipped. Consider planning 12 activities for the default and putting the story earlier in the order when `elapsed > planned`.
- **M2 Distractor generation** (`wordDistractors`, `ActivityGenerator.swift:240-264`): preferred distractors are "near misses" (one grapheme different). That is pedagogically right for blending, but the pool has no homophone or semantic filter. For homophone pairs the near-miss rule makes the partner the preferred distractor: `sea/see` (both unlock by order 58; near pool 4 words, so about 50% chance the partner is among the two distractors), `cent/sent` (50-67%), `fur/fir` (33-40%), `dew/due` (33-50%), `new/knew` (29-33%), `night/knight` (18-22%), `not/knot` (14-17%), `cord/chord` (33-100%). In blend tasks the child sees the SOUND tiles, not the meaning, so two answers are correct. In cloze (`buildSentence`) sentences have no emoji, and near misses are often also valid sentences: "Tom got a mop." offers `map/top/pop`; "Dad can hug Mum." offers `mug/rug/tug`; "Mum can kiss the pup." offers `cup/pop/pip`. In `buildWord` the `tier1` extra tiles include misconception partners (`ea` unit -> extra tile `ee`), so for audio "sea/tea" the child can legitimately build `see/tee`.
  Fix: build a homophone table (the 17 pairs above) and exclude partners from distractor pools; for cloze, only use sentences where a picture or a strongly constrained slot (verb/noun class) removes ambiguity, or ask the child to pick the word the narrator reads; in `buildWord`, never offer a homophone-forming extra tile unless the word has an emoji.
- Distractor grapheme soundness (`graphemeDistractors`): I re-implemented `phonemeKeys` and `graphemesSharingSound` and checked all 94 grapheme-bearing units: no distractor shares the target's phoneme key, none is untaught at the activity order. Good. Known gap: `g-oo-short` shares key `oo` with `g-oo-long`, so recognise for the short oo is structurally identical to the long one (the same grapheme `oo` against unrelated letters); the long/short distinction is never tested at the gate. 18 units have all graphemes already taught earlier (`g-oo-short g-u-yoo g-o-oa g-i-igh g-a-ai g-e-ee g-ie-ee g-ou-oa g-ow-oa g-ea-e g-y-igh g-y-ee g-c-s g-g-j g-ch-k g-ch-sh g-a-o g-or-ur`). For most, "which letter makes this other sound" is still informative (the usual letter is excluded as a distractor). The real skill (choose the correct pronunciation in a word) is exercised only in non-gating tracks. Consider gating these on a two-pronunciation word task. (MINOR m14)
- **B1 Audio for graphemes with alternative pronunciations.** `CurriculumIndex.audioId(forGrapheme:atOrder:)` (`CurriculumIndex.swift:349-354`) returns the audio of the FIRST unit teaching that grapheme. It is used by `ActivityGenerator.soundAudio` (lines 302-308, builds blend/order/segment audio sequences), by `BlendActivityView.lightUp` (`ActivityKinds.swift:196`, with `atOrder: maxOrder`) and by the tile views (`ActivityKinds.swift:330`). Result: when the child taps `o` in `cold` the app plays /o/ (on); `ow` in `snow` plays /ow/ (cow); `oo` in `book` plays the long /oo/; `c` in `city` plays /k/; `g` in `gem` plays /g/; `y` in `fly` plays /y/; `ch` in `school` plays /ch/; `i` in `child` plays short /i/; `or` in `work`, `a` in `swan`, `ea` in `bread`, `ie` in `field`, `ou` in `shoulder`, `u` in `music`, `e` in `zero`, `a` in `baby`. I counted every word whose requirement points to an alternative unit for some grapheme: **201 of 1,288 words (15.6%)**, e.g. o (22 words), y->/ee/ (19), ow->/oa/ (17), i->/igh/ (16), c->/s/ (16), a->/ai/ (14), g->/j/ (14), oo->/oo/ short (14), ea->/e/ (12), ch->/k/ (10), y->/igh/ (10), u->/yoo/ (10), a->/o/ (10). The sound the child hears for the tile contradicts the word. The first affected unit is `g-oo-short` itself (order 42: all 14 words). Fix: attach to each word, per grapheme, the unit id it realises (the requirement already encodes it; extend `Word.graphemes` or add `graphemeUnits`) and resolve audio from that unit; fall back to first-taught only when the grapheme has a single reading.

### 4.6 Feedback wording (`Feedback.swift`, `ActivityCoordinator`)
Warm and accurate: banned-word list enforced by tests and by `safe()` (a decodable word like `bad` is never echoed as "this word... is bad"); support lines say "Let's ... together"; correct-after-help says "We found X together" rather than praising independence; first miss: "Good try! Have another look."; guided wrong: "Let's follow the star together." Baseline: "Thank you! Let's try the next one." with no correctness cue. No failure language found. One nit: feedback prints raw grapheme labels such as `a_e` into captions ("You matched the sound to a_e!"); use "a ... e". (MINOR)

---

## 5. Child UX flow review (`tvos/App/Child`)

- Session length: default 7 minutes (3-10 allowed), 16 planned activities, soft cut-off at `(minutes+3)*60` s = 10 min applied only between activities and only after activity 4. Within the 5-10 minute brief. "Step 3 of 16" is shown as text; if the 10-minute cut-off ends the session at step 12 the counter promised 16. Consider showing "Part 1 of 3" or dots, or plan fewer activities. (MINOR m7)
- Modelling after two misses: correct. `ActivityCoordinator.submit`: miss 1 -> wrong card disabled, "Good try!"; miss 2 -> narrated steps (`modelledSteps`) then guided completion with the right card highlighted; these are recorded as `prompted`/`modelled`, never as independent evidence.
- No pressure: no countdown, no timers visible; fluency `softTargetSeconds` exists in the payload but is not used by the view (confirmed by grep: only the "no timer, no ranking" comment). Next is a manual button. Menu button opens a calm "Take a break?" overlay ("Your stars and stickers are safe"); partial sessions of >= 3 activities still earn an effort sticker and are saved.
- Rewards (`Stickers.swift`, `SummaryView`, `StickerBookView`): effort sticker once per session (>= 3 activities), practice milestones at sessions 1, 3, 5, 10, 20, 30, 50, 75, 100, mastery sticker per unit. No streaks, no loss, no ranking, no scores shown, nothing removed. Fixed (non-random) schedule, so not a variable-ratio hook. Design is non-manipulative. Notes: the effort sticker for only 3 activities is a very low bar (acceptable, but consider 5); mastery stickers named "Sound /s/" read oddly for a pre-reader (a picture-only title is better); the sticker book uses emoji whose rendering depends on tvOS font coverage (m14).
- Autoplay prompts with "Hear it again" and "Slowly" and Play/Pause: good. Captions on by default.
- Things I could not assess: actual audio, focus movement with the Siri Remote, VoiceOver (a separate accessibility review exists in `accessibility-hig-review.md`).

---

## 6. Emoji and picture ambiguity (**M6**)

599 words carry an emoji (351 distinct emoji). `readPickPicture` deduplicates distractors by emoji and label, which prevents identical pictures, but does not stop two DIFFERENT emoji both being right.
Plausible-double-answer pairs (different emoji, same concept): `pet 🐕 / dog 🐶 / tail 🐕` (and `pup 🐶`), `hat 🎩 / cap 🧢 / sunhat 👒`, `car 🚗 / cab 🚕 / jeep 🚙 / van 🚐`, `tick ✔️ / check ✅` (tick is also an insect), `grin 😁 / smile 😊 / happy 😊`, `day 🌞 / sun ☀️`, `moon 🌙 / moonlight 🌕`, `bunny 🐰 / hopped 🐇`, `boat ⛵ / ship 🚢`, `ham 🍖 / meat 🥩`, `sheep 🐑 / ram 🐏`, `jam 🍓 / plum 🍑`, `king 👑 / crown 👑 / queen-like royal 👑` (same emoji so de-duplicated, fine).
Wrong or misleading emoji: `moth 🦋` (butterfly), `gnome 🧙` (a mage, also reused for `witch`), `plum 🍑` (peach), `head 🗣️` (speaking head), `back 🔙` and `top 🔝` (arrow buttons), `nail 💅` (nail polish), `gas 💨` (dash/puff, also fart), `jump 🦘` (kangaroo), `play 🎮` (video game), `kick ⚽` (ball), `wedge 🧀` (cheese), `soil 🌱` (seedling), `pad 📓`, `gig 🎸` (guitar; also an unfamiliar word), `pit 🕳️` (hole), `hay 🌾`, `cool 😎`, `pink 💗` (heart), `blue 💙` and `yellow 💛` (hearts) versus `red 🔴 brown 🟤 green 🟢` (circles), `kiss 💋`, `pill 💊`, `weed 🌿`. Also newer/ZWJ emoji that may not render on older tvOS fonts (`crow 🐦‍⬛`, `cook 🧑‍🍳`, `astronaut 🧑‍🚀`, `chef 👩‍🍳`, `lung 🫁`, `fizz 🫧`, `pail 🪣`, `hut 🛖`, `sign 🪧`); deployment target is tvOS 17 so most are present, but test the ZWJ ones.
Story picture: `Sit in the Tin` uses 🥫 on all four pages for "Pip/Tim/Nan/Dad sitting in a tin" - the picture cannot show a child in a tin and four identical pages gives no cue.
Fix: add `exclusivePictureGroup` or a `confusableWith` list in the data and enforce it in `buildPicture`; replace the wrong emoji with drawn assets (the app has a mascot art style) for the 30 or so worst; mark `pictureLabel` as the spoken alt text.

---

## 7. Minor findings

- m1 Phase tags for `j..nk` look like Phase 3 (from memory). Verify against your chosen reference; update `phase`.
- m2 No `ure` grapheme (`pure/cure`); `sure/pure` handled as tricky at order 45.
- m3 Accent-dependent words not tagged (`bath path past pass fast dance graph giraffe`, `room roof`, `bus cup` FOOT/STRUT). Add `accentNotes` and record accepted variants in the audio brief; avoid showing `bath` in a Reception story if you want a neutral set.
- m4 Mastery evidence ignores item diversity (see 4.1).
- m5 No teaching of `s` = /z/ in plurals (126 decodable words end in a voiced `s`); the blend tile plays /s/ then the word audio says /z/. Add a Phase 3 unit ("s says /z/ at the end of words") or exclude those words from blend/segment until taught.
- m6 Year 1 ordering: single-letter long vowels before split digraphs (see 3.1).
- m7 Pace: 2 days per unit minimum (about 39-65 weeks); planned 16 activities at an optimistic 25 s each.
- m8 `er` "hint of r" vs `air` "no r"; `zero` as /ee/ example.
- m9 Year 1 tricky words missing: `where who once friend any many again two from`.
- m10 `decodablePartsKnown` wrong for `is`, `like`, `when`.
- m11 Vocabulary to soften: `pill weed smoke fat kiss nail monk` and emoji listed in section 6.
- m12 Name and family diversity.
- m13 Default `useResponseTime` true.
- m14 18 alternative-pronunciation units gate on isolated grapheme-sound recognition; the in-word choice of pronunciation is not gating.
- m15 `wrinkle` is segmented `i-n-k` (nk is /ŋk/ and `nk` is taught at 36); `change/ache/giraffe/orange/gentle` use a lone `e` for a silent final e (the engine treats it as the /e/ grapheme; harmless for decodability but visually teaches a sounded `e`). Mark silent-e as its own non-sounded token.

---

## 8. What is genuinely good (keep)
- Decodability machinery is sound: monotone unlock orders, sentences and stories recomputed from tokens, tricky words gated, requirement gating for 374 ambiguous words, zero data errors on the 8 structural checks.
- Evidence rules are conservative about prompting, spacing and days, and avoid punishing errors.
- Feedback and break/exit flows are warm, with no failure language, timers, streaks, or loss mechanics.
- Honest provenance (`source: inferred`, citations, manifest disclaimer): do not remove.

---

## 9. Verdict

**Not ready for children as-is; ready for a focused fix cycle.** The Reception data set (units 1-54) is strong and almost entirely safe; the Year 1 data is also well structured. Two things must be fixed before a real child uses it:
1. **B1**: sound tiles/blend/segment audio contradict the target word for 201 words (including every oo-short word).
2. **B2**: no exit from a unit the child cannot pass, and the parent "Unlock" control does nothing for the child's sessions.

Then, before a general release: **M1** baseline placement (skips up to 8-16 unknown units on a single lucky guess), **M2** homophone and ambiguous-cloze distractors, **M3** voiced th, **M4** the `p4-suffix` gate, **M5** the degenerate first two units, **M6** emoji ambiguity, **M7** the three bad words. All are small, local changes (mostly data plus `audioId` resolution, `Progression.nextUnit`, `placeFromBaseline`, `wordDistractors`). After B1, B2 and M1-M5 I would call it fit for supervised pilot use with the Reception units (1-54), with Year 1 content following once its audio and homophone handling are verified by a phonics specialist and a recorded-audio check.
