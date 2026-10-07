/**
 * Curriculum validator: returns a list of human-readable problems ([] = valid).
 * Used by scripts/validate-curriculum.ts (CLI) and tests/unit/curriculum.
 * It re-derives decodability from the data itself; it does not trust `unlockedByOrder`.
 */
import { AudioManifestSchema } from '../domain/schema';
import type { AudioManifest, Curriculum, GraphemeUnit } from '../domain/schema';
import { firstTaughtOrder, joinGraphemes, normaliseSentence, unlockOrder } from './lookup';
import type { WordRequirements } from './lookup';
import requirementsJson from './data/word-requirements.json';
import manifestJson from '../../public/audio/manifest.json';

export interface ValidateOptions {
  /** Audio manifest to check against (default: public/audio/manifest.json). */
  audio?: AudioManifest;
  /** Pronunciation-aware word gating (default: data/word-requirements.json). */
  requirements?: WordRequirements;
}

export const defaultRequirements: WordRequirements = requirementsJson as WordRequirements;
export const defaultAudio: AudioManifest = AudioManifestSchema.parse(manifestJson);

const BANNED_TERMS: RegExp[] = [/phonetics/i];

function collectStrings(v: unknown, out: string[]): void {
  if (typeof v === 'string') out.push(v);
  else if (Array.isArray(v)) v.forEach((x) => collectStrings(x, out));
  else if (v && typeof v === 'object') Object.values(v as Record<string, unknown>).forEach((x) => collectStrings(x, out));
}

export function validateCurriculum(c: Curriculum, opts: ValidateOptions = {}): string[] {
  const audio = opts.audio ?? defaultAudio;
  const requirements = opts.requirements ?? defaultRequirements;
  const problems: string[] = [];
  const err = (m: string): void => { problems.push(m); };

  // ---- units: unique ids/orders, ascending, consistency
  const unitIds = new Set<string>();
  const unitById = new Map<string, GraphemeUnit>();
  const orders = new Set<number>();
  let prevOrder = 0;
  for (const u of c.units) {
    if (unitIds.has(u.id)) err(`unit ${u.id}: duplicate id`);
    unitIds.add(u.id);
    unitById.set(u.id, u);
    if (orders.has(u.order)) err(`unit ${u.id}: duplicate order ${u.order}`);
    orders.add(u.order);
    if (u.order <= prevOrder) err(`unit ${u.id}: order ${u.order} is not ascending (previous ${prevOrder})`);
    prevOrder = Math.max(prevOrder, u.order);
    if ((u.stage === 'reception') !== (u.phase <= 4)) err(`unit ${u.id}: stage ${u.stage} inconsistent with phase ${u.phase}`);
    if (u.source === 'fetched') err(`unit ${u.id}: source "fetched" is not allowed (official sources were not fetched; use "inferred")`);
    if (u.audioId.startsWith('ph-') && u.audioId !== `ph-${u.id}`) err(`unit ${u.id}: audioId ${u.audioId} should be ph-${u.id}`);
    if (!u.audioId.startsWith('ph-') && !u.audioId.startsWith('i-')) err(`unit ${u.id}: audioId ${u.audioId} should start with ph- or i-`);
  }

  // ---- prerequisites: exist, lower order, no cycles
  for (const u of c.units) {
    for (const p of u.prerequisites) {
      const pu = unitById.get(p);
      if (!pu) err(`unit ${u.id}: prerequisite ${p} does not exist`);
      else if (pu.order >= u.order) err(`unit ${u.id}: prerequisite ${p} has order ${pu.order} which is not lower than ${u.order}`);
    }
  }
  const state = new Map<string, 0 | 1 | 2>();
  const visit = (id: string, trail: string[]): void => {
    if (state.get(id) === 2) return;
    if (state.get(id) === 1) { err(`prerequisite cycle: ${[...trail, id].join(' -> ')}`); return; }
    state.set(id, 1);
    for (const p of unitById.get(id)?.prerequisites ?? []) if (unitById.has(p)) visit(p, [...trail, id]);
    state.set(id, 2);
  };
  for (const u of c.units) visit(u.id, []);

  // ---- tricky words
  const trickyByLower = new Map<string, Curriculum['trickyWords'][number]>();
  for (const t of c.trickyWords) {
    const k = t.text.toLowerCase();
    if (trickyByLower.has(k)) err(`tricky word ${t.text}: duplicate`);
    trickyByLower.set(k, t);
  }
  for (const t of c.trickyWords) {
    if (t.introducedAtOrder !== 0 && !orders.has(t.introducedAtOrder)) {
      err(`tricky word ${t.text}: introducedAtOrder ${t.introducedAtOrder} is not a unit order`);
    }
  }
  const unitTrickyCount = new Map<string, number>();
  for (const u of c.units) {
    for (const tw of u.trickyWords) {
      const t = trickyByLower.get(tw.toLowerCase());
      if (!t) { err(`unit ${u.id}: tricky word "${tw}" is not in the tricky word list`); continue; }
      if (t.introducedAtOrder !== u.order) err(`unit ${u.id}: tricky word "${tw}" is introduced at order ${t.introducedAtOrder}, not ${u.order}`);
      unitTrickyCount.set(t.text, (unitTrickyCount.get(t.text) ?? 0) + 1);
    }
  }
  for (const t of c.trickyWords) {
    if (t.introducedAtOrder !== 0 && unitTrickyCount.get(t.text) !== 1) err(`tricky word ${t.text}: should be listed by exactly one unit (found ${unitTrickyCount.get(t.text) ?? 0})`);
  }

  // ---- words
  const taught = firstTaughtOrder(c.units);
  const wordsByText = new Map<string, number>(); // text -> unlock order
  const wordGraphemes = new Map<string, string[]>();
  for (const w of c.words) {
    if (wordsByText.has(w.text)) { err(`word ${w.text}: duplicate`); continue; }
    if (trickyByLower.has(w.text.toLowerCase())) err(`word ${w.text}: is a tricky word and must not be in the decodable word list`);
    const joined = joinGraphemes(w.graphemes);
    if (joined === null) err(`word ${w.text}: invalid split-digraph segmentation [${w.graphemes.join(',')}]`);
    else if (joined !== w.text) err(`word ${w.text}: graphemes [${w.graphemes.join(',')}] join to "${joined}"`);
    const un = unlockOrder(w.graphemes, w.text, c.units, requirements, taught);
    if (un.missing.length) err(`word ${w.text}: graphemes not taught by any unit: ${un.missing.join(',')}`);
    if (un.badRequirements.length) err(`word ${w.text}: requirement unit(s) do not exist: ${un.badRequirements.join(',')}`);
    wordsByText.set(w.text, un.order);
    wordGraphemes.set(w.text, w.graphemes);
  }
  for (const key of Object.keys(requirements)) {
    if (!wordsByText.has(key) && !c.sentences.some((s) => s.tokens.some((t) => t.kind === 'word' && t.text.toLowerCase() === key))) {
      err(`word requirement for "${key}": no such word`);
    }
  }

  // ---- example words
  for (const u of c.units) {
    for (const ex of u.exampleWords) {
      const o = wordsByText.get(ex);
      if (o === undefined) err(`unit ${u.id}: example word "${ex}" is not in the words list`);
      else if (o > u.order) err(`unit ${u.id}: example word "${ex}" is not decodable until order ${o} (> ${u.order})`);
    }
  }

  // ---- sentences
  const sentenceIds = new Set<string>();
  for (const s of c.sentences) {
    if (sentenceIds.has(s.id)) err(`sentence ${s.id}: duplicate id`);
    sentenceIds.add(s.id);
    let unlock = 0;
    const parts: string[] = [];
    s.tokens.forEach((t, i) => {
      parts.push(t.text.toLowerCase());
      if (t.kind === 'tricky') {
        const tw = trickyByLower.get(t.text.toLowerCase());
        if (!tw) err(`sentence ${s.id} token ${i} "${t.text}": not in the tricky word list`);
        else unlock = Math.max(unlock, tw.introducedAtOrder);
        return;
      }
      if (trickyByLower.has(t.text.toLowerCase())) err(`sentence ${s.id} token ${i} "${t.text}": tricky word must use kind "tricky"`);
      const joined = joinGraphemes(t.graphemes);
      if (joined === null || joined !== t.text.toLowerCase()) err(`sentence ${s.id} token ${i} "${t.text}": graphemes [${t.graphemes.join(',')}] join to "${String(joined)}"`);
      const un = unlockOrder(t.graphemes, t.text, c.units, requirements, taught);
      if (un.missing.length) err(`sentence ${s.id} token "${t.text}": graphemes not taught: ${un.missing.join(',')}`);
      if (un.badRequirements.length) err(`sentence ${s.id} token "${t.text}": requirement unit(s) missing: ${un.badRequirements.join(',')}`);
      unlock = Math.max(unlock, un.order);
    });
    if (normaliseSentence(s.text) !== parts.join(' ')) err(`sentence ${s.id}: text "${s.text}" does not equal its tokens "${parts.join(' ')}"`);
    if (s.unlockedByOrder !== undefined && s.unlockedByOrder !== unlock) {
      err(`sentence ${s.id}: unlockedByOrder ${s.unlockedByOrder} but tokens require order ${unlock}`);
    }
  }

  // ---- stories
  const storyIds = new Set<string>();
  for (const st of c.stories) {
    if (storyIds.has(st.id)) err(`story ${st.id}: duplicate id`);
    storyIds.add(st.id);
    st.pages.forEach((p, pi) => {
      for (const sid of p.sentenceIds) if (!sentenceIds.has(sid)) err(`story ${st.id} page ${pi + 1}: sentence ${sid} does not exist`);
    });
  }

  // ---- audio manifest
  const audioIds = new Set<string>();
  for (const e of audio.entries) {
    if (audioIds.has(e.id)) err(`audio: duplicate entry ${e.id}`);
    audioIds.add(e.id);
  }
  if (!/little wandle/i.test(audio.statement) || !/not/i.test(audio.statement) || !/placeholder/i.test(audio.statement)) {
    err('audio manifest statement must say entries are placeholders and not Little Wandle-approved');
  }
  for (const u of c.units) if (!audioIds.has(u.audioId)) err(`audio: no manifest entry for unit ${u.id} (${u.audioId})`);
  for (const w of c.words) if (!audioIds.has(`w-${w.text}`)) err(`audio: no manifest entry for word ${w.text} (w-${w.text})`);
  for (const t of c.trickyWords) if (!audioIds.has(`w-${t.text.toLowerCase()}`)) err(`audio: no manifest entry for tricky word ${t.text}`);

  // ---- banned terms
  const strings: string[] = [];
  collectStrings(c, strings);
  collectStrings(audio, strings);
  for (const re of BANNED_TERMS) {
    const hit = strings.find((s) => re.test(s));
    if (hit) err(`banned term ${re} found in: "${hit.slice(0, 80)}"`);
  }

  return problems;
}

// --------------------------------------------------------------------------- coverage report
export interface CoverageRow { label: string; units: number; words: number; sentences: number; stories: number }

export function coverage(c: Curriculum, requirements: WordRequirements = defaultRequirements): CoverageRow[] {
  const taught = firstTaughtOrder(c.units);
  const bucketOf = (order: number): string => {
    const u = [...c.units].reverse().find((x) => x.order <= order) ?? c.units[0]!;
    return u.stage === 'year1' ? 'Year 1 (Phase 5)' : `Reception Phase ${u.phase}`;
  };
  const labels = ['Reception Phase 2', 'Reception Phase 3', 'Reception Phase 4', 'Year 1 (Phase 5)'];
  const rows = new Map(labels.map((l) => [l, { label: l, units: 0, words: 0, sentences: 0, stories: 0 }] as const));
  const row = (l: string): CoverageRow => rows.get(l)!;
  for (const u of c.units) row(bucketOf(u.order)).units++;
  for (const w of c.words) row(bucketOf(unlockOrder(w.graphemes, w.text, c.units, requirements, taught).order)).words++;
  const sOrder = new Map<string, number>();
  for (const s of c.sentences) {
    const o = s.unlockedByOrder ?? 0;
    sOrder.set(s.id, o);
    row(bucketOf(o)).sentences++;
  }
  for (const st of c.stories) {
    const o = Math.max(...st.pages.flatMap((p) => p.sentenceIds.map((id) => sOrder.get(id) ?? 0)));
    row(bucketOf(o)).stories++;
  }
  return labels.map(row);
}

export interface UnitCoverage { unit: GraphemeUnit; words: number; sentences: number }

/** Per-unit counts of content that unlocks exactly at that unit (used to report gaps). */
export function unitCoverage(c: Curriculum, requirements: WordRequirements = defaultRequirements): UnitCoverage[] {
  const taught = firstTaughtOrder(c.units);
  const wordAt = new Map<number, number>();
  for (const w of c.words) {
    const o = unlockOrder(w.graphemes, w.text, c.units, requirements, taught).order;
    wordAt.set(o, (wordAt.get(o) ?? 0) + 1);
  }
  const sentAt = new Map<number, number>();
  for (const s of c.sentences) sentAt.set(s.unlockedByOrder ?? 0, (sentAt.get(s.unlockedByOrder ?? 0) ?? 0) + 1);
  return c.units.map((unit) => ({ unit, words: wordAt.get(unit.order) ?? 0, sentences: sentAt.get(unit.order) ?? 0 }));
}
