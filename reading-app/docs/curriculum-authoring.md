# Curriculum authoring guide

Curriculum content is DATA validated by `CurriculumSchema` and `AudioManifestSchema` (`src/domain/schema.ts`). The engine and UI never hard-code lessons.

## Provenance (read first)

Every unit is `source: "inferred"`. The official programme pages could not be fetched, so the sequence comes from school-hosted overview PDFs seen only through search summaries (cited per unit and in `docs/curriculum-map.md`) plus general Letters and Sounds family knowledge. Nothing here is Little Wandle-approved or endorsed. Never mark content `fetched` unless a page was actually read (the validator rejects `fetched`). All words, sentences and stories are original.

## Files

| File | Role |
|---|---|
| `src/curriculum/author/*.ts` | Compact authoring sources: `units.ts`, `words.ts`, `tricky.ts`, `text.ts` (sentences, stories, names), `build.ts` |
| `src/curriculum/data/curriculum.json` | Generated, shipped curriculum (units, words, tricky words, sentences, stories) |
| `src/curriculum/data/word-requirements.json` | Generated pronunciation-aware gating (see below) |
| `public/audio/manifest.json` | Generated placeholder audio manifest |
| `src/curriculum/load.ts` | `curriculum`, `CONTENT_VERSION`, `wordRequirements` (parses with Zod at import, throws on failure) |
| `src/curriculum/lookup.ts` | Pure helpers: `joinGraphemes`, `firstTaughtOrder`, `unlockOrder`, `normaliseSentence` |
| `src/curriculum/validate.ts` | `validateCurriculum(c, opts?) : string[]`, `coverage`, `unitCoverage` |
| `scripts/validate-curriculum.ts` | CLI: prints coverage table, exit code 1 on any problem |

Workflow: edit `src/curriculum/author/*`, run `npx tsx src/curriculum/author/build.ts` (fails with a list of authoring problems), then `npx tsx scripts/validate-curriculum.ts` and `npx vitest run tests/unit/curriculum`. Bump `CONTENT_VERSION_BUILT` in `build.ts` when content changes in a way learner state could depend on (unit ids/orders). Do not hand-edit the generated JSON.

## Units and ids

- `id` is `g-<key>` (`g-s`, `g-oo-short`, `g-split-a`, `g-ow-oa`). Phase 4 consolidation units are `p4-cvcc`, `p4-ccvc`, `p4-long`, `p4-suffix`.
- `order` is the global, unique, ascending teaching order (1-98 now). `phase` 2/3/4/5, `stage` reception (orders 1-54) or year1 (55-98).
- `audioId` is `ph-<unit id>` (for example `ph-g-s`). Phase 4 consolidation units have no isolated sound and point at the instruction clip `i-blend`.
- The same grapheme can be taught twice with different sounds (oo long/short, ow, ie, ou, ea, y, c, g, ch, a, o, i, e, u, or). Each is its own unit.
- `prerequisites` are the one or two earlier units the unit's words depend on (an alternative spelling depends on its base GPC, for example `ay` needs `ai`). All prerequisites must exist and have a lower order.
- Phase 4 adds no new letters. Its units list practice clusters in `graphemes` (CVCC, CCVC, longer words and compounds); those clusters do NOT enter the taught-grapheme set. `p4-suffix` genuinely adds the suffix grapheme `ed` (-ing and -est are decoded as i+ng and e+s+t).
- Pronunciation text uses pure sounds: short, crisp phonemes with no added "uh". Misconceptions (b/d, m/n, sh/ch, ...) carry guidance for the parent or teacher.

## Words and the split-digraph convention

A word stores `graphemes`, one entry per written unit, and `graphemes.join('')` must equal the text, except for split digraphs:

- A split digraph is written `a_e`, `i_e`, `o_e`, `u_e`, `e_e` and sits at the vowel's position.
- The silent `e` is NOT stored as its own token. It is emitted right after the NEXT token (the consonant grapheme).
- `cake` = `["c","a_e","k"]`; `slide` = `["s","l","i_e","d"]`; `shake` = `["sh","a_e","k"]`; `age` = `["a_e","g"]`; `complete` = `["c","o","m","p","l","e_e","t"]`.
- Exactly one following token must exist (a dangling `a_e` is invalid). `joinGraphemes` in `lookup.ts` implements and documents this.

Decodability: a word unlocks at the highest `order` of the units that first teach each of its graphemes (`firstTaughtOrder`), raised further by `word-requirements.json`.

### Pronunciation-aware gating (`word-requirements.json`)

Knowing the letters is not always enough: `book` uses the SHORT oo (taught after long oo), `old` uses long o, `happy` uses y as /ee/. The map `word -> [unit ids]` lists extra units that must be taught first. In `words.ts` write `b-oo-k@oo-short`; combine with `+` (`b-a-b-y@a-ai+y-ee`). Phase 4 words (CVCC, CCVC, longer, compounds, suffixes) are all gated at their Phase 4 unit even when the letters are known earlier. The engine should compute availability with `unlockOrder(graphemes, text, units, wordRequirements)` from `src/curriculum/lookup.ts` and `wordRequirements` from `load.ts`.

Do not put tricky words (is, the, was, ...) in the word list; the validator rejects it.

## Tricky words

`trickyWords` entries have `introducedAtOrder` (a unit order) and are also listed in exactly one unit's `trickyWords`. The spread across units within a phase is inferred. Tricky words may appear in sentences only as `kind: "tricky"` tokens, and only at or after their introduction.

## Sentences and stories

- Sentence tokens: decodable words as `{kind:"word", text, graphemes}`, tricky words as `{kind:"tricky", text}`. The sentence `text` must equal the tokens joined by spaces ignoring punctuation and case.
- `unlockedByOrder` = the highest order needed by any token (grapheme units, word requirements, tricky introduction). The validator recomputes it and rejects a mismatch.
- Names are decodable proper nouns defined in `NAMES` (`text.ts`) with explicit segmentation (`Kate` = `k-a_e-t`).
- Keep text kind and neutral; avoid frightening content. Use plain straight quotes in dialogue; no apostrophes inside sentence words (the token model has no apostrophe support).
- A story has 2 or more pages, each with one or more sentence ids, an optional emoji and a picture label. Reception stories here are 3-4 pages.

## Audio manifest

Generated by `build.ts`: one `ph-*` entry per isolated-sound unit, `w-<text>` for every word and every tricky word, instruction clips (`i-lets-sound-it-out`, `i-listen`, `i-find-the-sound`, `i-blend`, `i-well-done`, ...) and `sfx-*`. All entries are `file: null`, `status: "placeholder"`. The manifest `statement` says placeholders are temporary development entries, ordinary text-to-speech is NOT authoritative for isolated phonemes (it adds an extra "uh"), and nothing is Little Wandle-approved. Swap in recordings by editing only `public/audio/manifest.json` (set `file`, then `status: "recorded"`, then `"verified"` after an adult check).

## What the validator checks

Unique ids and orders; ascending order; stage/phase consistency; no `source: "fetched"`; audioId format; prerequisites exist, have lower order, no cycles; tricky words unique, introduced at a unit order, listed by exactly one unit; every word joins to its text (split digraphs handled), uses only taught graphemes, is not a tricky word; example words exist and are decodable by the unit's order; every sentence token joins and is decodable, tricky tokens are in the list, text equals tokens, `unlockedByOrder` is correct; story sentence ids exist; audio manifest has an entry for every unit audioId, word and tricky word, is duplicate-free, and its statement disclaims Little Wandle approval; banned terms (`phonetics`) absent.

## Known limits

- Accent: words such as bath, path, fast, pass and class are read with a short or a long a depending on accent; they are included as decodable and flagged here.
- `a` as a word is treated as decodable (the sounds /a/ or a weak vowel are both acceptable in practice).
- Voiced and unvoiced th share one unit; the pronunciation text explains both.
- Week-by-week placement in Reception, Year 1 Spring 2 and Summer ordering are inferred.
