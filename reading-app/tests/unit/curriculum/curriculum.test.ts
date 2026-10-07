import { describe, expect, it } from 'vitest';
import { AudioManifestSchema, CurriculumSchema } from '../../../src/domain/schema';
import { CONTENT_VERSION, curriculum, wordRequirements } from '../../../src/curriculum/load';
import { coverage, defaultAudio, unitCoverage, validateCurriculum } from '../../../src/curriculum/validate';
import { firstTaughtOrder, joinGraphemes, unlockOrder } from '../../../src/curriculum/lookup';

const unit = (id: string) => curriculum.units.find((u) => u.id === id)!;

describe('shipped curriculum data', () => {
  it('passes the full validator with no problems', () => {
    expect(validateCurriculum(curriculum)).toEqual([]);
  });

  it('parses against the Zod schemas and exposes a content version', () => {
    expect(CurriculumSchema.safeParse(curriculum).success).toBe(true);
    expect(AudioManifestSchema.safeParse(defaultAudio).success).toBe(true);
    expect(CONTENT_VERSION).toMatch(/^\d+\.\d+\.\d+$/);
    expect(curriculum.contentVersion).toBe(CONTENT_VERSION);
  });

  it('covers the full Reception + Year 1 sequence in ascending order', () => {
    expect(curriculum.units.length).toBe(98);
    const orders = curriculum.units.map((u) => u.order);
    expect(orders).toEqual([...orders].sort((a, b) => a - b));
    expect(new Set(orders).size).toBe(orders.length);
    expect(curriculum.units[0]!.id).toBe('g-s');
    expect(curriculum.units.slice(0, 4).map((u) => u.graphemes[0])).toEqual(['s', 'a', 't', 'p']);
    expect(curriculum.units.filter((u) => u.stage === 'reception').length).toBe(54);
    expect(curriculum.units.filter((u) => u.stage === 'year1').length).toBe(44);
    expect(unit('g-ai').phase).toBe(3);
    expect(unit('p4-cvcc').phase).toBe(4);
    expect(unit('g-split-a').kind).toBe('split');
  });

  it('is honest about provenance: nothing is marked fetched and phoneme audio ids are ph-<unit id>', () => {
    for (const u of curriculum.units) {
      expect(u.source).toBe('inferred');
      expect(u.citation ?? '').not.toMatch(/^$/);
      if (u.audioId.startsWith('ph-')) expect(u.audioId).toBe(`ph-${u.id}`);
    }
  });

  it('gives every pure-sound unit pronunciation guidance without suggesting an added "uh" sound', () => {
    for (const u of curriculum.units.filter((x) => x.phase === 2 && x.kind === 'single')) {
      expect(u.pronunciation.length).toBeGreaterThan(20);
    }
    expect(unit('g-s').pronunciation).toMatch(/no 'uh'/i);
  });

  it('records the b/d, m/n and sh/ch misconceptions', () => {
    expect(unit('g-d').misconceptions.some((m) => m.confusedWith === 'b')).toBe(true);
    expect(unit('g-b').misconceptions.some((m) => m.confusedWith === 'd')).toBe(true);
    expect(unit('g-m').misconceptions.some((m) => m.confusedWith === 'n')).toBe(true);
    expect(unit('g-n').misconceptions.some((m) => m.confusedWith === 'm')).toBe(true);
    expect(unit('g-sh').misconceptions.some((m) => m.confusedWith === 'ch')).toBe(true);
    expect(unit('g-ch').misconceptions.some((m) => m.confusedWith === 'sh')).toBe(true);
  });

  it('keeps the first units honest: no invented words before enough letters are taught', () => {
    expect(unitCoverage(curriculum).find((u) => u.unit.id === 'g-s')!.words).toBe(0);
    expect(unit('g-s').exampleWords).toEqual([]);
    expect(unit('g-a').exampleWords.every((w) => w === 'a')).toBe(true);
  });
});

describe('content depth targets', () => {
  const cov = unitCoverage(curriculum);
  const rows = Object.fromEntries(coverage(curriculum).map((r) => [r.label, r]));

  it('has deep Reception content (Phase 2, 3, 4)', () => {
    expect(rows['Reception Phase 2']!.words).toBeGreaterThanOrEqual(300);
    expect(rows['Reception Phase 3']!.words).toBeGreaterThanOrEqual(150);
    expect(rows['Reception Phase 4']!.words).toBeGreaterThanOrEqual(100);
    expect(rows['Reception Phase 2']!.sentences).toBeGreaterThanOrEqual(60);
    expect(rows['Reception Phase 3']!.sentences).toBeGreaterThanOrEqual(30);
    expect(rows['Reception Phase 4']!.sentences).toBeGreaterThanOrEqual(25);
    const receptionStories = rows['Reception Phase 2']!.stories + rows['Reception Phase 3']!.stories + rows['Reception Phase 4']!.stories;
    expect(receptionStories).toBeGreaterThanOrEqual(8);
  });

  it('gives at least 3 decodable words to each Year 1 unit and some Year 1 sentences and stories', () => {
    for (const c of cov.filter((x) => x.unit.stage === 'year1')) {
      expect(c.words, `${c.unit.id} words`).toBeGreaterThanOrEqual(3);
    }
    expect(rows['Year 1 (Phase 5)']!.sentences).toBeGreaterThanOrEqual(40);
    expect(rows['Year 1 (Phase 5)']!.stories).toBeGreaterThanOrEqual(3);
  });

  it('gives each Reception unit from the 4th onward at least 3 new words, and most units after order 8 a new sentence', () => {
    const phase23 = cov.filter((c) => c.unit.order >= 4 && c.unit.phase <= 3);
    for (const c of phase23) expect(c.words, `${c.unit.id} words`).toBeGreaterThanOrEqual(3);
    const after8 = cov.filter((c) => c.unit.order > 8 && c.unit.phase <= 4);
    const withSentence = after8.filter((c) => c.sentences > 0).length;
    expect(withSentence / after8.length).toBeGreaterThanOrEqual(0.9);
  });

  it('has Reception stories of 2-5 pages made only of decodable sentences', () => {
    const byId = new Map(curriculum.sentences.map((s) => [s.id, s]));
    for (const st of curriculum.stories) {
      expect(st.pages.length).toBeGreaterThanOrEqual(2);
      expect(st.pages.length).toBeLessThanOrEqual(5);
      for (const p of st.pages) for (const id of p.sentenceIds) expect(byId.has(id)).toBe(true);
    }
  });
});

describe('split digraph convention and pronunciation gating', () => {
  it('joins split digraphs so the silent e follows the consonant: cake = c, a_e, k', () => {
    expect(joinGraphemes(['c', 'a_e', 'k'])).toBe('cake');
    expect(joinGraphemes(['s', 'l', 'i_e', 'd'])).toBe('slide');
    expect(joinGraphemes(['sh', 'a_e', 'k'])).toBe('shake');
    expect(joinGraphemes(['a_e', 'g'])).toBe('age');
    expect(joinGraphemes(['c', 'a_e'])).toBeNull();
    expect(joinGraphemes(['ch', 'a', 't'])).toBe('chat');
  });

  it('stores split-digraph words with the a_e style token', () => {
    const cake = curriculum.words.find((w) => w.text === 'cake')!;
    expect(cake.graphemes).toEqual(['c', 'a_e', 'k']);
  });

  it('gates alternative pronunciations on the unit that teaches them (book needs short oo, old needs long o)', () => {
    const taught = firstTaughtOrder(curriculum.units);
    const book = curriculum.words.find((w) => w.text === 'book')!;
    const old = curriculum.words.find((w) => w.text === 'old')!;
    expect(unlockOrder(book.graphemes, 'book', curriculum.units, wordRequirements, taught).order).toBe(unit('g-oo-short').order);
    expect(unlockOrder(old.graphemes, 'old', curriculum.units, wordRequirements, taught).order).toBe(unit('g-o-oa').order);
    // without the requirement map, the plain grapheme knowledge would let 'book' in a unit too early
    expect(unlockOrder(book.graphemes, 'book', curriculum.units, {}, taught).order).toBeLessThan(unit('g-oo-short').order);
  });

  it('does not let Phase 4 patterns (CVCC etc.) appear before the Phase 4 unit', () => {
    const taught = firstTaughtOrder(curriculum.units);
    const ant = curriculum.words.find((w) => w.text === 'ant')!;
    expect(unlockOrder(ant.graphemes, 'ant', curriculum.units, wordRequirements, taught).order).toBe(unit('p4-cvcc').order);
  });
});

describe('tricky words', () => {
  it('introduces the programme tricky words at sensible orders', () => {
    const at = (t: string) => curriculum.trickyWords.find((x) => x.text.toLowerCase() === t)!.introducedAtOrder;
    expect(at('the')).toBe(1);
    expect(at('i')).toBe(1);
    expect(at('is')).toBe(1);
    expect(at('was')).toBe(unit('g-ai').order);
    expect(at('said')).toBe(unit('p4-cvcc').order);
    expect(at('their')).toBe(unit('g-ir').order);
  });

  it('keeps every tricky word out of the decodable word list', () => {
    const words = new Set(curriculum.words.map((w) => w.text.toLowerCase()));
    for (const t of curriculum.trickyWords) expect(words.has(t.text.toLowerCase())).toBe(false);
  });
});

describe('content guidelines', () => {
  it('contains no banned terms and no frightening vocabulary in stories', () => {
    const text = JSON.stringify(curriculum) + JSON.stringify(defaultAudio);
    expect(text).not.toMatch(/phonetics/i);
    const storyText = curriculum.sentences.map((s) => s.text).join(' ');
    expect(storyText).not.toMatch(/\b(kill|dead|blood|scary|monster|ghost|gun)\b/i);
  });

  it('marks every audio entry as a placeholder with no file, and says so in the statement', () => {
    expect(defaultAudio.entries.every((e) => e.file === null && e.status === 'placeholder')).toBe(true);
    expect(defaultAudio.statement).toMatch(/placeholder/i);
    expect(defaultAudio.statement).toMatch(/not authoritative/i);
    expect(defaultAudio.statement).toMatch(/not Little Wandle-approved/i);
    for (const id of ['i-lets-sound-it-out', 'i-listen', 'i-find-the-sound', 'i-blend', 'i-well-done']) {
      expect(defaultAudio.entries.some((e) => e.id === id && e.kind === 'instruction')).toBe(true);
    }
    expect(defaultAudio.entries.some((e) => e.kind === 'sfx')).toBe(true);
  });
});
