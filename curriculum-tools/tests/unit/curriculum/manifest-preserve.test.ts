import { describe, expect, it } from 'vitest';
import type { AudioEntry } from '../../../src/domain/schema';
import { mergeRecordedAudio } from '../../../src/curriculum/audioMerge';

const entry = (over: Partial<AudioEntry> = {}): AudioEntry => ({
  id: 'ph-g-s', kind: 'phoneme', label: '/s/', file: null, status: 'placeholder', note: 'Placeholder: no recording yet.', ...over,
});

describe('regenerating the audio manifest keeps recordings', () => {
  it('keeps the file, status and note of a recorded entry', () => {
    const { entries, kept } = mergeRecordedAudio(
      [entry({ label: '/s/ (new label)' })],
      [entry({ file: 'phonemes/s.m4a', slowFile: 'phonemes/s-slow.m4a', status: 'recorded', note: 'Recorded by a parent' })],
    );
    expect(kept).toBe(1);
    expect(entries[0]).toMatchObject({ file: 'phonemes/s.m4a', slowFile: 'phonemes/s-slow.m4a', status: 'recorded', note: 'Recorded by a parent', label: '/s/ (new label)' });
  });
  it('keeps a verified entry even if the file is null', () => {
    const { entries } = mergeRecordedAudio([entry()], [entry({ status: 'verified' })]);
    expect(entries[0]!.status).toBe('verified');
  });
  it('leaves placeholders as the generator made them and ignores entries that no longer exist', () => {
    const { entries, kept } = mergeRecordedAudio([entry()], [entry({ id: 'ph-gone', file: 'x.m4a', status: 'recorded' })]);
    expect(kept).toBe(0);
    expect(entries).toEqual([entry()]);
  });
});
