/**
 * Pure helpers shared by the validator, the authoring build script and (optionally) the engine:
 * grapheme joining (incl. split digraphs), taught-grapheme lookup and word/sentence unlock orders.
 * No I/O here.
 */
import type { GraphemeUnit } from '../domain/schema';

/** Word text -> extra unit ids that must be taught before the word is allowed (pronunciation-aware gating). */
export type WordRequirements = Record<string, string[]>;

/** Consolidation units list practice clusters, not new graphemes; they do not add to the taught set. */
export const CONSOLIDATION_UNIT_IDS: ReadonlySet<string> = new Set(['p4-cvcc', 'p4-ccvc', 'p4-long']);

const SPLIT_RE = /^([a-z])_e$/;

/**
 * Join a grapheme segmentation back to the written word.
 * Split-digraph convention: a token like "a_e" stands for the vowel at its position; the silent "e"
 * is emitted right AFTER the next token (the consonant grapheme). cake = [c, a_e, k] -> "cake".
 * Returns null when a split token has no following consonant token.
 */
export function joinGraphemes(tokens: readonly string[]): string | null {
  let out = '';
  let pendingE = false;
  for (const t of tokens) {
    const m = SPLIT_RE.exec(t);
    if (m) {
      if (pendingE) return null; // two split digraphs overlapping
      out += m[1];
      pendingE = true;
    } else {
      out += t;
      if (pendingE) {
        out += 'e';
        pendingE = false;
      }
    }
  }
  return pendingE ? null : out;
}

export function isSplitToken(t: string): boolean {
  return SPLIT_RE.test(t);
}

/** grapheme -> lowest order of a (non-consolidation) unit that teaches it. */
export function firstTaughtOrder(units: readonly GraphemeUnit[]): Map<string, number> {
  const m = new Map<string, number>();
  for (const u of units) {
    if (CONSOLIDATION_UNIT_IDS.has(u.id)) continue;
    for (const g of u.graphemes) {
      const prev = m.get(g);
      if (prev === undefined || u.order < prev) m.set(g, u.order);
    }
  }
  return m;
}

export interface Unlock {
  /** Lowest unit order at which every grapheme (and every required unit) is taught; 0 if nothing needed. */
  order: number;
  /** graphemes not taught by any unit */
  missing: string[];
  /** required unit ids that do not exist */
  badRequirements: string[];
}

export function unlockOrder(
  graphemes: readonly string[],
  text: string,
  units: readonly GraphemeUnit[],
  requirements: WordRequirements,
  taught: Map<string, number> = firstTaughtOrder(units),
): Unlock {
  let order = 0;
  const missing: string[] = [];
  const badRequirements: string[] = [];
  for (const g of graphemes) {
    const o = taught.get(g);
    if (o === undefined) missing.push(g);
    else order = Math.max(order, o);
  }
  const byId = new Map(units.map((u) => [u.id, u.order] as const));
  for (const req of requirements[text.toLowerCase()] ?? []) {
    const o = byId.get(req);
    if (o === undefined) badRequirements.push(req);
    else order = Math.max(order, o);
  }
  return { order, missing, badRequirements };
}

/** Normalise sentence text for comparison with its tokens: letters only, lower-case, single spaces. */
export function normaliseSentence(s: string): string {
  return s.toLowerCase().replace(/[^a-z\s]/g, ' ').replace(/\s+/g, ' ').trim();
}
