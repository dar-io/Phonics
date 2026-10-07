/**
 * Authoring build: turns the compact sources in this folder into
 *   src/curriculum/data/curriculum.json, src/curriculum/data/word-requirements.json, public/audio/manifest.json
 * Run:  npx tsx src/curriculum/author/build.ts
 * (Not imported by the app. The JSON files are the shipped, reviewable artefacts.)
 */
// @ts-ignore - no @types/node in this project; only used by this authoring script
import { writeFileSync } from 'node:fs';
// @ts-ignore
import { fileURLToPath } from 'node:url';
import { AudioManifestSchema, CURRICULUM_SCHEMA_VERSION, CurriculumSchema } from '../../domain/schema';
import type { AudioEntry, Curriculum, GraphemeUnit, Sentence, Story, TrickyWord, Word } from '../../domain/schema';
import { joinGraphemes, unlockOrder, firstTaughtOrder } from '../lookup';
import type { WordRequirements } from '../lookup';
import { UNITS, termFor } from './units';
import { WORDS } from './words';
import { TRICKY } from './tricky';
import { NAMES, SENTENCES, STORIES } from './text';

export const CONTENT_VERSION_BUILT = '0.1.0';

const unitId = (key: string): string => (key.startsWith('p4-') ? key : `g-${key}`);
const fail = (msg: string): never => { throw new Error(msg); };
const problems: string[] = [];
const attempt = (fn: () => void): void => {
  try { fn(); } catch (e) { problems.push(e instanceof Error ? e.message : String(e)); }
};

// ------------------------------------------------------------------ units (without derived fields)
const CITE_RECEPTION = 'Term placement: Reception Overview PDF (herrick.leicester.sch.uk) and Phonics Curriculum Overview PDF (elmridge.bright-futures.co.uk), seen only via search summaries (official pages were unreachable). Week split, pronunciation guidance and misconceptions: general Letters and Sounds family knowledge (inferred).';
const CITE_P4 = 'Phase 4 shape (no new GPCs, adjacent consonants, suffixes) per Reception Overview PDF (herrick.leicester.sch.uk) via search summary; unit split and guidance inferred from general Letters and Sounds family knowledge.';
const CITE_Y1 = 'Placement: Year 1 Overview PDF (herrick.leicester.sch.uk) and LW Phase 5 Overview Dec 23 PDF (files.schudio.com/walmsleyprimary) via search summaries; order within terms and later items inferred from general Letters and Sounds family knowledge.';

const units: GraphemeUnit[] = UNITS.map((d, i) => {
  const order = i + 1;
  const id = unitId(d.key);
  const phase = order <= 36 ? 2 : order <= 50 ? 3 : order <= 54 ? 4 : 5;
  const pre = d.pre ?? (i === 0 ? [] : [UNITS[i - 1]!.key]);
  const consolidation = d.key.startsWith('p4-');
  return {
    id,
    order,
    phase,
    stage: order <= 54 ? 'reception' : 'year1',
    term: termFor(order),
    phoneme: d.phoneme,
    graphemes: d.graphemes,
    kind: d.kind,
    audioId: consolidation ? 'i-blend' : `ph-${id}`,
    pronunciation: d.pron,
    prerequisites: pre.map(unitId),
    exampleWords: [],
    trickyWords: [],
    misconceptions: (d.mis ?? []).map(([confusedWith, guidance]) => ({ confusedWith, guidance })),
    source: 'inferred',
    citation: order <= 50 ? CITE_RECEPTION : order <= 54 ? CITE_P4 : CITE_Y1,
  } satisfies GraphemeUnit;
});
const unitByKey = new Map(UNITS.map((d, i) => [d.key, units[i]!] as const));
for (const d of UNITS) for (const p of d.pre ?? []) if (!unitByKey.has(p)) fail(`unit ${d.key}: unknown prerequisite ${p}`);

// ------------------------------------------------------------------ tricky
const tricky: TrickyWord[] = TRICKY.map((t) => {
  const unit = unitByKey.get(t.unit) ?? fail(`tricky ${t.text}: unknown unit ${t.unit}`);
  unit.trickyWords.push(t.text);
  return { text: t.text, introducedAtOrder: unit.order, trickyPart: t.part, decodablePartsKnown: !!t.known };
});
const trickyByLower = new Map(tricky.map((t) => [t.text.toLowerCase(), t] as const));

// ------------------------------------------------------------------ words
const taught = firstTaughtOrder(units);
const requirements: WordRequirements = {};
const words: Word[] = [];
const wordOrder = new Map<string, number>();
const wordGroupOrder: Array<{ word: Word; group: string }> = [];

for (const [group, entries] of Object.entries(WORDS)) {
  const gUnit = unitByKey.get(group) ?? fail(`word group ${group}: unknown unit`);
  for (const raw of entries) attempt(() => {
    const [segPart, emoji, label] = raw.split('|');
    const [seg, reqPart] = segPart!.split('@');
    const graphemes = seg!.split('-');
    const text = joinGraphemes(graphemes) ?? fail(`word ${raw}: bad split digraph`);
    if (trickyByLower.has(text)) fail(`word ${text} is a tricky word; remove from word list`);
    if (wordOrder.has(text)) fail(`duplicate word ${text}`);
    const reqs = (reqPart ? reqPart.split('+') : []).map(unitId);
    if (reqs.length) requirements[text] = reqs;
    const u = unlockOrder(graphemes, text, units, requirements, taught);
    if (u.missing.length) fail(`word ${text}: graphemes not taught: ${u.missing.join(',')}`);
    if (u.badRequirements.length) fail(`word ${text}: unknown requirement ${u.badRequirements.join(',')}`);
    if (group.startsWith('p4-')) {
      if (u.order > gUnit.order) fail(`word ${text} in ${group} unlocks later (${u.order}) than its group (${gUnit.order})`);
      requirements[text] = [...reqs, gUnit.id];
      u.order = gUnit.order;
    } else if (u.order !== gUnit.order) {
      fail(`word ${text} listed under ${group} (order ${gUnit.order}) but unlocks at ${u.order}`);
    }
    const word: Word = emoji
      ? { text, graphemes, emoji, pictureLabel: label ?? text, concrete: true }
      : { text, graphemes, concrete: false };
    words.push(word);
    wordOrder.set(text, u.order);
    wordGroupOrder.push({ word, group });
  });
}

// ------------------------------------------------------------------ example words per unit
for (const u of units) {
  const cand = wordGroupOrder
    .filter(({ word }) => wordOrder.get(word.text) === u.order)
    .map(({ word }) => word);
  const rank = (w: Word): number => (w.emoji ? 0 : 100) + (w.text.endsWith('s') && w.text.length > 3 ? 50 : 0) + w.text.length;
  u.exampleWords = [...cand].sort((a, b) => rank(a) - rank(b)).slice(0, 8).map((w) => w.text);
}

// ------------------------------------------------------------------ sentences & stories
const wordByText = new Map(words.map((w) => [w.text, w] as const));
const nameSeg = new Map(Object.entries(NAMES).map(([n, s]) => [n.toLowerCase(), s.split('-')] as const));
for (const [n, seg] of nameSeg) {
  const joined = joinGraphemes(seg);
  if (joined !== n) fail(`name ${n}: segmentation joins to ${String(joined)}`);
}

const sentences: Sentence[] = [];
const sentenceByText = new Map<string, Sentence>();

function ensureSentence(text: string): Sentence {
  const hit = sentenceByText.get(text);
  if (hit) return hit;
  const pieces = text.split(/\s+/).filter(Boolean);
  const tokens: Sentence['tokens'] = [];
  let order = 0;
  for (const piece of pieces) {
    const surface = piece.replace(/^[^A-Za-z]+|[^A-Za-z]+$/g, '');
    if (!surface) fail(`sentence "${text}": empty token in "${piece}"`);
    const lc = surface.toLowerCase();
    const tw = trickyByLower.get(lc);
    if (tw) {
      tokens.push({ kind: 'tricky', text: surface });
      order = Math.max(order, tw.introducedAtOrder);
      continue;
    }
    const w = wordByText.get(lc);
    const graphemes = w ? w.graphemes : nameSeg.get(lc);
    if (!graphemes) return fail(`sentence "${text}": unknown word "${surface}" (add to words or NAMES)`);
    const un = unlockOrder(graphemes, lc, units, requirements, taught);
    if (un.missing.length) fail(`sentence "${text}": ${surface} uses untaught ${un.missing.join(',')}`);
    order = Math.max(order, un.order);
    tokens.push({ kind: 'word', text: surface, graphemes });
  }
  const s: Sentence = {
    id: `s-${String(sentences.length + 1).padStart(3, '0')}`,
    text,
    tokens,
    unlockedByOrder: order,
  };
  sentences.push(s);
  sentenceByText.set(text, s);
  return s;
}

for (const t of SENTENCES) attempt(() => { ensureSentence(t); });
if (problems.length) {
  console.error(problems.join('\n'));
  throw new Error(`${problems.length} authoring problem(s)`);
}
const stories: Story[] = STORIES.map((st) => ({
  id: st.id,
  title: st.title,
  pages: st.pages.map((p) => ({
    sentenceIds: p.s.map((t) => ensureSentence(t).id),
    ...(p.e ? { emoji: p.e } : {}),
    ...(p.l ? { pictureLabel: p.l } : {}),
  })),
}));

// ------------------------------------------------------------------ curriculum
const curriculum: Curriculum = CurriculumSchema.parse({
  schemaVersion: CURRICULUM_SCHEMA_VERSION,
  contentVersion: CONTENT_VERSION_BUILT,
  units,
  words,
  trickyWords: tricky,
  sentences,
  stories,
});

// ------------------------------------------------------------------ audio manifest
const PLACEHOLDER_NOTE = 'Placeholder: no recording yet.';
const entries: AudioEntry[] = [];
const seen = new Set<string>();
const add = (e: AudioEntry): void => {
  if (seen.has(e.id)) return;
  seen.add(e.id);
  entries.push(e);
};
for (const u of curriculum.units) {
  if (!u.audioId.startsWith('ph-')) continue;
  add({
    id: u.audioId,
    kind: 'phoneme',
    label: u.phoneme,
    file: null,
    status: 'placeholder',
    note: `Isolated sound for ${u.graphemes.join(' / ')}. ${PLACEHOLDER_NOTE} Record as a pure, crisp sound with no added 'uh'.`,
  });
}
for (const w of curriculum.words) {
  add({ id: `w-${w.text}`, kind: 'word', label: w.text, file: null, status: 'placeholder', note: PLACEHOLDER_NOTE });
}
for (const t of curriculum.trickyWords) {
  add({ id: `w-${t.text.toLowerCase()}`, kind: 'word', label: t.text, file: null, status: 'placeholder', note: `Tricky word. ${PLACEHOLDER_NOTE}` });
}
const INSTRUCTIONS: Array<[string, string]> = [
  ['i-lets-sound-it-out', "Let's sound it out together"],
  ['i-listen', 'Listen'],
  ['i-find-the-sound', 'Find the sound'],
  ['i-blend', 'Now blend the sounds together'],
  ['i-well-done', 'Well done!'],
  ['i-great-job', 'Great job!'],
  ['i-try-again', "Let's try that again"],
  ['i-say-the-sound', 'Say the sound'],
  ['i-read-the-word', 'Read the word'],
  ['i-read-the-sentence', 'Read the sentence'],
  ['i-tricky-word', 'This is a tricky word'],
  ['i-touch-and-say', 'Touch each letter and say its sound'],
  ['i-match-the-picture', 'Match the word to the picture'],
  ['i-point-to', 'Point to the sound you hear'],
  ['i-ready', 'Are you ready?'],
  ['i-story-time', "It's story time"],
  ['i-turn-the-page', 'Turn the page'],
  ['i-all-done', "That's all for today. See you soon!"],
];
for (const [id, label] of INSTRUCTIONS) {
  add({ id, kind: 'instruction', label, file: null, status: 'placeholder', note: PLACEHOLDER_NOTE });
}
const SFX: Array<[string, string]> = [
  ['sfx-correct', 'Soft chime (correct)'],
  ['sfx-gentle-retry', 'Gentle low tone (try again, never a buzzer)'],
  ['sfx-tap', 'Light tap'],
  ['sfx-star', 'Sparkle (star earned)'],
  ['sfx-page-turn', 'Page turn'],
  ['sfx-celebrate', 'Short celebration'],
];
for (const [id, label] of SFX) {
  add({ id, kind: 'sfx', label, file: null, status: 'placeholder', note: PLACEHOLDER_NOTE });
}

const manifest = AudioManifestSchema.parse({
  version: 1,
  statement:
    'PLACEHOLDER MANIFEST. Every entry is a temporary development placeholder with no recording (file is null, status is "placeholder"). ' +
    'Ordinary text-to-speech is NOT authoritative for isolated phonemes: it adds an extra "uh" and cannot be trusted to produce pure sounds, so it must never be treated as the real audio. ' +
    'This manifest and the curriculum data are not Little Wandle-approved or endorsed; the sequence and guidance are inferred from general Letters and Sounds knowledge and school overview documents. ' +
    'Replace entries by recording the sounds and editing this file only; set status to "recorded", then "verified" after an adult has checked the pronunciation.',
  entries,
});

// ------------------------------------------------------------------ write
/** Compact JSON: one line per array element so diffs stay reviewable. */
function pretty(obj: Record<string, unknown>): string {
  const parts: string[] = [];
  for (const [k, v] of Object.entries(obj)) {
    if (Array.isArray(v)) {
      parts.push(`  ${JSON.stringify(k)}: [\n${v.map((x) => '    ' + JSON.stringify(x)).join(',\n')}\n  ]`);
    } else {
      parts.push(`  ${JSON.stringify(k)}: ${JSON.stringify(v)}`);
    }
  }
  return `{\n${parts.join(',\n')}\n}\n`;
}

const root = fileURLToPath(new URL('../../../', import.meta.url)) as string;
const sortedReq = Object.fromEntries(Object.entries(requirements).sort(([a], [b]) => a.localeCompare(b)));
writeFileSync(`${root}src/curriculum/data/curriculum.json`, pretty(curriculum as unknown as Record<string, unknown>));
writeFileSync(
  `${root}src/curriculum/data/word-requirements.json`,
  `{\n${Object.entries(sortedReq).map(([k, v]) => `  ${JSON.stringify(k)}: ${JSON.stringify(v)}`).join(',\n')}\n}\n`,
);
writeFileSync(`${root}public/audio/manifest.json`, pretty(manifest as unknown as Record<string, unknown>));

console.log(
  `built: ${curriculum.units.length} units, ${curriculum.words.length} words, ${curriculum.trickyWords.length} tricky, ` +
    `${curriculum.sentences.length} sentences, ${curriculum.stories.length} stories, ${manifest.entries.length} audio entries, ` +
    `${Object.keys(requirements).length} word requirements`,
);
