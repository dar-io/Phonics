import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

const here = (p: string) => new URL(`../../../${p}`, import.meta.url);
const tvos = (p: string) => new URL(`../../../../tvos/Sources/StorySoundsCore/Resources/${p}`, import.meta.url);

/** The tvOS app bundles COPIES of the generated JSON. If they drift, the app teaches different content than was validated. */
describe('tvOS bundled resources match the generated curriculum', () => {
  const pairs: Array<[string, URL, URL]> = [
    ['curriculum.json', here('src/curriculum/data/curriculum.json'), tvos('curriculum.json')],
    ['word-requirements.json', here('src/curriculum/data/word-requirements.json'), tvos('word-requirements.json')],
    ['audio-manifest.json', here('public/audio/manifest.json'), tvos('audio-manifest.json')],
  ];
  for (const [name, source, copy] of pairs) {
    it(`${name} is identical (run "npm run sync:tvos" after "npm run build:curriculum")`, () => {
      expect(readFileSync(copy, 'utf8')).toBe(readFileSync(source, 'utf8'));
    });
  }
});
