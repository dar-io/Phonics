import { beforeEach, describe, expect, it } from 'vitest';
import { resetDBForTests } from '../../src/storage/db';
import { deleteAllData, exportData, importData, ImportError, loadSnapshot, newProfile, replaceSnapshot, saveProfile, saveSkill, recordConfusion } from '../../src/storage/repo';
import type { LearnerSnapshot, SkillState } from '../../src/domain/learner';

const skill = (unitId: string): SkillState => ({ unitId, track: 'recognise', score: 0.9, attempts: 8, independentCorrect: 7, sessionsSeen: ['a', 'b'], daysSeen: ['2026-01-01', '2026-01-02'], activityTypesSeen: ['find-grapheme'], lastAttemptAt: 1, recentResults: [true], status: 'secure', secureAt: 1, reviewStage: 1, nextReviewAt: 99, struggleStreak: 0 });
const snap = (): LearnerSnapshot => ({ profile: newProfile(1, '1.0.0'), skills: [skill('g-s'), skill('g-gone')], confusions: [], sessions: [], attempts: [{ at: 1, sessionId: 'a', unitId: 'g-s', track: 'recognise', activityType: 'find-grapheme', itemKey: 's', correct: true, support: 'independent', responseMs: 900 }] });

beforeEach(async () => { await resetDBForTests('t' + Math.random()); });

describe('persistence', () => {
  it('round-trips a snapshot', async () => {
    await replaceSnapshot(snap());
    const s = await loadSnapshot();
    expect(s?.skills).toHaveLength(2); expect(s?.attempts).toHaveLength(1); expect(s?.profile.id).toBe('learner');
  });
  it('returns undefined before first launch', async () => { expect(await loadSnapshot()).toBeUndefined(); });
  it('exports and re-imports, dropping units that no longer exist', async () => {
    await replaceSnapshot(snap());
    const file = await exportData(5);
    await deleteAllData();
    expect(await loadSnapshot()).toBeUndefined();
    const out = await importData(JSON.stringify(file), new Set(['g-s']), '1.1.0');
    expect(out.skills.map((s) => s.unitId)).toEqual(['g-s']);
    expect(out.attempts).toHaveLength(1);
    expect(out.profile.contentVersion).toBe('1.1.0');
  });
  it('rejects bad files without touching existing data', async () => {
    await replaceSnapshot(snap());
    await expect(importData('nope', new Set(), '1')).rejects.toBeInstanceOf(ImportError);
    await expect(importData(JSON.stringify({ format: 'x' }), new Set(), '1')).rejects.toBeInstanceOf(ImportError);
    await expect(importData(JSON.stringify({ format: 'story-sounds-export', exportVersion: 99, data: {} }), new Set(), '1')).rejects.toBeInstanceOf(ImportError);
    expect((await loadSnapshot())?.skills).toHaveLength(2);
  });
  it('delete-all removes every table', async () => {
    await replaceSnapshot(snap()); await recordConfusion('s', 'a', 1); await saveSkill(skill('g-t'));
    await deleteAllData();
    expect(await loadSnapshot()).toBeUndefined();
    await saveProfile(newProfile(2, '1'));
    expect((await loadSnapshot())?.skills).toHaveLength(0);
  });
});
