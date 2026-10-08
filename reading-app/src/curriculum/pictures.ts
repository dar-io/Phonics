/** Helpers for the "one picture, one answer" rule (validator + authoring build). No I/O. */

const SUFFIXES = ['s', 'es', 'ed', 'd', 'ing', 'est', 'ies', 'ied'];

/** Stem spellings a suffix can attach to: run -> runn, dance -> danc, cry -> cri. */
function stemVariants(stem: string): string[] {
  const out = [stem, stem + stem.slice(-1)];
  if (stem.endsWith('e')) out.push(stem.slice(0, -1));
  if (stem.endsWith('y')) out.push(stem.slice(0, -1) + 'i');
  return out;
}

/** True when `a` and `b` are the same word with a regular inflection (pin/pins, jump/jumped, run/running). */
export function isInflection(a: string, b: string): boolean {
  if (a === b) return false;
  const [s, l] = a.length <= b.length ? [a, b] : [b, a];
  return stemVariants(s).some((v) => SUFFIXES.some((suf) => l === v + suf));
}
