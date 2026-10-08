import { describe, expect, it } from 'vitest';
import { curriculum, wordRequirements } from '../../../src/curriculum/load';
import { firstTaughtOrder, unlockOrder } from '../../../src/curriculum/lookup';
import { auditCurriculum } from '../../../src/curriculum/audit';
import { isInflection } from '../../../src/curriculum/pictures';
import { minimalPairRisks, validateCurriculum } from '../../../src/curriculum/validate';

const unit = (id: string) => curriculum.units.find((u) => u.id === id)!;
const word = (t: string) => curriculum.words.find((w) => w.text === t);
const taught = firstTaughtOrder(curriculum.units);
const orderOf = (t: string) => {
  const w = word(t)!;
  return unlockOrder(w.graphemes, t, curriculum.units, wordRequirements, taught).order;
};

describe('M3: unvoiced /th/ and voiced /dh/ are separate units', () => {
  it('has two adjacent th units with their own audio ids and phoneme labels', () => {
    const th = unit('g-th');
    const dh = unit('g-th-voiced');
    expect(dh.order).toBe(th.order + 1);
    expect(th.phoneme).toBe('/th/');
    expect(dh.phoneme).toBe('/dh/');
    expect(th.audioId).toBe('ph-g-th');
    expect(dh.audioId).toBe('ph-g-th-voiced');
    expect(dh.prerequisites).toContain('g-th');
    expect(dh.pronunciation).toMatch(/buzz/i);
  });

  it('gates every voiced-th word behind the voiced unit and every unvoiced one at the unvoiced unit', () => {
    for (const t of ['this', 'that', 'then', 'them', 'with', 'than', 'those', 'these', 'feather', 'weather']) {
      expect(orderOf(t), t).toBeGreaterThanOrEqual(unit('g-th-voiced').order);
      expect(wordRequirements[t], t).toContain('g-th-voiced');
    }
    for (const t of ['thin', 'thick', 'moth', 'bath', 'path', 'thud']) expect(orderOf(t), t).toBe(unit('g-th').order);
    expect(unit('g-th').exampleWords.some((w) => ['this', 'that', 'then', 'them', 'with', 'than'].includes(w))).toBe(false);
    expect(unit('g-th-voiced').exampleWords.every((w) => ['this', 'that', 'then', 'them', 'with', 'than'].includes(w))).toBe(true);
  });

  it('keeps orders contiguous and ascending and the stage boundary consistent', () => {
    curriculum.units.forEach((u, i) => expect(u.order).toBe(i + 1));
    expect(curriculum.units.filter((u) => u.stage === 'reception').length).toBe(55);
    expect(unit('g-ai').prerequisites).toContain('g-th-voiced');
  });
});

describe('M7: gnaw, gene, monk and the pronunciation audit', () => {
  it('segments gnaw as gn-aw and gates gene behind soft g', () => {
    expect(word('gnaw')!.graphemes).toEqual(['gn', 'aw']);
    expect(wordRequirements['gene']).toContain('g-g-j');
    expect(orderOf('gene')).toBeGreaterThanOrEqual(unit('g-g-j').order);
  });

  it('removed words whose vowel the taught grapheme does not make', () => {
    for (const t of ['monk', 'chalet', 'sachet', 'chic']) expect(word(t), t).toBeUndefined();
    for (const t of ['son', 'ton', 'month', 'love', 'come', 'some', 'done']) expect(word(t), t).toBeUndefined();
  });

  it('has zero unresolved audit findings', () => {
    expect(auditCurriculum(curriculum, wordRequirements).filter((f) => f.level === 'error')).toEqual([]);
  });
});

describe('M6: pictures', () => {
  it('has no wrong or adult-coded emoji left', () => {
    const bad = new Set(['💋', '💊', '💅', '🦋']);
    for (const w of curriculum.words) if (w.emoji) expect(bad.has(w.emoji), w.text).toBe(false);
    for (const t of ['kiss', 'pill', 'nail', 'moth', 'plum', 'weed']) expect(word(t)!.emoji, t).toBeUndefined();
    for (const t of ['hat', 'pet', 'tail', 'cab', 'jeep']) expect(word(t)!.emoji, t).toBeUndefined();
  });

  it('never gives a picture to a word without marking concrete, and never shares a picture without a relation', () => {
    for (const w of curriculum.words) expect(w.concrete).toBe(w.emoji !== undefined);
    expect(validateCurriculum(curriculum).filter((p) => p.startsWith('picture '))).toEqual([]);
  });

  it('flags a shared picture between unrelated words (validator negative case)', () => {
    const c = structuredClone(curriculum);
    const cat = c.words.find((w) => w.text === 'cat')!;
    c.words.find((w) => w.text === 'pig')!.emoji = cat.emoji;
    expect(validateCurriculum(c).some((p) => p.includes('shared by'))).toBe(true);
  });

  it('recognises regular inflections', () => {
    expect(isInflection('pin', 'pins')).toBe(true);
    expect(isInflection('jump', 'jumped')).toBe(true);
    expect(isInflection('run', 'running')).toBe(true);
    expect(isInflection('cry', 'cried')).toBe(true);
    expect(isInflection('cup', 'mug')).toBe(false);
  });
});

describe('M2: homophones and accent notes', () => {
  it('lists homophones symmetrically for decodable and tricky words', () => {
    expect(word('sea')!.homophones).toEqual(['see']);
    expect(word('see')!.homophones).toEqual(['sea']);
    expect(word('cent')!.homophones).toEqual(['sent']);
    expect(word('bee')!.homophones).toEqual(['be']);
    expect(curriculum.trickyWords.find((t) => t.text === 'be')!.homophones).toEqual(['bee']);
    expect(word('know')!.homophones).toEqual(['no']);
  });

  it('validator rejects a homophone that does not exist or is not mutual', () => {
    const c = structuredClone(curriculum);
    c.words.find((w) => w.text === 'sea')!.homophones = ['nonexistent'];
    expect(validateCurriculum(c).some((p) => p.includes('not in the word or tricky word list'))).toBe(true);
    const d = structuredClone(curriculum);
    d.words.find((w) => w.text === 'sea')!.homophones = ['see', 'tea'];
    expect(validateCurriculum(d).some((p) => p.includes('does not list'))).toBe(true);
  });

  it('flags accent-dependent words and keeps them out of example words', () => {
    for (const t of ['bath', 'path', 'fast', 'pass', 'dance']) expect(word(t)!.accentNote, t).toBe(true);
    const flagged = new Set(curriculum.words.filter((w) => w.accentNote).map((w) => w.text));
    for (const u of curriculum.units) for (const ex of u.exampleWords) expect(flagged.has(ex), `${u.id}:${ex}`).toBe(false);
  });

  it('produces minimal-pair risk notes', () => {
    const notes = minimalPairRisks(curriculum, wordRequirements);
    expect(notes.some((n) => n.startsWith('homophones sea/see'))).toBe(true);
    expect(notes.some((n) => n.includes('accent-dependent'))).toBe(true);
  });
});
