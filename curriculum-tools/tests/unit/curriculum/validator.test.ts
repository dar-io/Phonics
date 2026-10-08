import { describe, expect, it } from 'vitest';
import type { Curriculum } from '../../../src/domain/schema';
import { curriculum } from '../../../src/curriculum/load';
import { defaultAudio, validateCurriculum } from '../../../src/curriculum/validate';

const fresh = (): Curriculum => structuredClone(curriculum);
const has = (problems: string[], re: RegExp): boolean => problems.some((p) => re.test(p));

describe('validateCurriculum negative cases', () => {
  it('baseline is clean', () => {
    expect(validateCurriculum(fresh())).toEqual([]);
  });

  it('catches an untaught grapheme in a word', () => {
    const c = fresh();
    c.words.push({ text: 'zqip', graphemes: ['zq', 'i', 'p'], concrete: false });
    expect(has(validateCurriculum(c), /word zqip: graphemes not taught/)).toBe(true);
  });

  it('catches a word whose graphemes do not join to its text', () => {
    const c = fresh();
    const cat = c.words.find((w) => w.text === 'cat')!;
    cat.graphemes = ['c', 'a', 'p'];
    expect(has(validateCurriculum(c), /word cat: graphemes \[c,a,p\] join to "cap"/)).toBe(true);
  });

  it('catches a broken split digraph', () => {
    const c = fresh();
    c.words.push({ text: 'cak', graphemes: ['c', 'a_e'], concrete: false });
    expect(has(validateCurriculum(c), /invalid split-digraph segmentation/)).toBe(true);
  });

  it('catches an example word that is not decodable yet or not in the word list', () => {
    const c = fresh();
    c.units[0]!.exampleWords = ['cat']; // cat needs c and a and t
    c.units[1]!.exampleWords = ['nonexistentword'];
    const p = validateCurriculum(c);
    expect(has(p, /unit g-s: example word "cat" is not decodable until order/)).toBe(true);
    expect(has(p, /example word "nonexistentword" is not in the words list/)).toBe(true);
  });

  it('catches a prerequisite with a higher order, a missing prerequisite and a cycle', () => {
    const c = fresh();
    c.units[2]!.prerequisites = ['g-p']; // order 3 depends on order 4
    c.units[3]!.prerequisites = ['g-t', 'g-nope'];
    const p = validateCurriculum(c);
    expect(has(p, /unit g-t: prerequisite g-p has order 4 which is not lower than 3/)).toBe(true);
    expect(has(p, /prerequisite g-nope does not exist/)).toBe(true);
    expect(has(p, /prerequisite cycle/)).toBe(true);
  });

  it('catches duplicate ids and non-ascending orders', () => {
    const c = fresh();
    c.units[5]!.id = c.units[4]!.id;
    c.units[7]!.order = c.units[6]!.order;
    const p = validateCurriculum(c);
    expect(has(p, /duplicate id/)).toBe(true);
    expect(has(p, /duplicate order/)).toBe(true);
    expect(has(p, /not ascending/)).toBe(true);
  });

  it('catches missing audio for a unit phoneme and for a word', () => {
    const audio = structuredClone(defaultAudio);
    audio.entries = audio.entries.filter((e) => e.id !== 'ph-g-s' && e.id !== 'w-cat');
    const p = validateCurriculum(fresh(), { audio });
    expect(has(p, /no manifest entry for unit g-s \(ph-g-s\)/)).toBe(true);
    expect(has(p, /no manifest entry for word cat/)).toBe(true);
  });

  it('catches a manifest statement that does not disclaim approval', () => {
    const audio = structuredClone(defaultAudio);
    audio.statement = 'All recordings are final.';
    expect(has(validateCurriculum(fresh(), { audio }), /statement must say/)).toBe(true);
  });

  it('catches an undecodable sentence (untaught grapheme in a token)', () => {
    const c = fresh();
    c.sentences.push({
      id: 's-bad-1',
      text: 'Zqip sat.',
      tokens: [
        { kind: 'word', text: 'Zqip', graphemes: ['zq', 'i', 'p'] },
        { kind: 'word', text: 'sat', graphemes: ['s', 'a', 't'] },
      ],
    });
    expect(has(validateCurriculum(c), /sentence s-bad-1 token "Zqip": graphemes not taught/)).toBe(true);
  });

  it('catches a sentence that claims to unlock before its words are taught', () => {
    const c = fresh();
    const s = c.sentences.find((x) => x.text === 'The king sang a song.')!;
    s.unlockedByOrder = 3;
    expect(has(validateCurriculum(c), new RegExp(`sentence ${s.id}: unlockedByOrder 3 but tokens require order`))).toBe(true);
  });

  it('catches a tricky word used before it is introduced', () => {
    const c = fresh();
    c.sentences.push({
      id: 's-bad-2',
      text: 'Pip said hello.',
      tokens: [
        { kind: 'word', text: 'Pip', graphemes: ['p', 'i', 'p'] },
        { kind: 'tricky', text: 'said' },
      ],
      unlockedByOrder: 5, // 'said' is introduced much later
    });
    expect(has(validateCurriculum(c), /sentence s-bad-2: unlockedByOrder 5 but tokens require order/)).toBe(true);
  });

  it('catches a tricky token that is not in the tricky list, and a tricky word written as a decodable token', () => {
    const c = fresh();
    c.sentences.push({
      id: 's-bad-3',
      text: 'Pip zork.',
      tokens: [
        { kind: 'word', text: 'Pip', graphemes: ['p', 'i', 'p'] },
        { kind: 'tricky', text: 'zork' },
      ],
    });
    c.sentences.push({
      id: 's-bad-4',
      text: 'Pip the.',
      tokens: [
        { kind: 'word', text: 'Pip', graphemes: ['p', 'i', 'p'] },
        { kind: 'word', text: 'the', graphemes: ['t', 'h', 'e'] },
      ],
    });
    const p = validateCurriculum(c);
    expect(has(p, /sentence s-bad-3 token 1 "zork": not in the tricky word list/)).toBe(true);
    expect(has(p, /sentence s-bad-4 token 1 "the": tricky word must use kind "tricky"/)).toBe(true);
  });

  it('catches sentence text that differs from its tokens', () => {
    const c = fresh();
    c.sentences[0]!.text = 'Completely different words.';
    expect(has(validateCurriculum(c), /does not equal its tokens/)).toBe(true);
  });

  it('catches a story that references a missing sentence', () => {
    const c = fresh();
    c.stories[0]!.pages[0]!.sentenceIds = ['s-missing'];
    expect(has(validateCurriculum(c), /sentence s-missing does not exist/)).toBe(true);
  });

  it('catches tricky-word bookkeeping errors', () => {
    const c = fresh();
    c.units[0]!.trickyWords.push('flibber');
    c.trickyWords.find((t) => t.text === 'was')!.introducedAtOrder = 9999;
    const p = validateCurriculum(c);
    expect(has(p, /tricky word "flibber" is not in the tricky word list/)).toBe(true);
    expect(has(p, /tricky word was: introducedAtOrder 9999 is not a unit order/)).toBe(true);
  });

  it('catches banned terms and source "fetched"', () => {
    const c = fresh();
    c.units[0]!.pronunciation = 'Study the phonetics of this sound.';
    c.units[1]!.source = 'fetched';
    const p = validateCurriculum(c);
    expect(has(p, /banned term/)).toBe(true);
    expect(has(p, /source "fetched" is not allowed/)).toBe(true);
  });

  it('catches a pronunciation-gated word whose requirement unit is unknown', () => {
    const p = validateCurriculum(fresh(), { requirements: { book: ['g-nope'] } });
    expect(has(p, /requirement unit\(s\) do not exist/)).toBe(true);
  });
});
