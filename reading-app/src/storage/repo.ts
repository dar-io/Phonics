import { DEFAULT_MASTERY_SETTINGS, type Attempt, type LearnerProfile, type LearnerSnapshot, type SessionSummary, type SkillState } from '../domain/learner';
import { CURRICULUM_SCHEMA_VERSION } from '../domain/schema';
import { getDB } from './db';
import { EXPORT_FORMAT, EXPORT_VERSION, migrateSnapshot, reconcileWithCurriculum, type ExportFile } from './migrations';

export function newProfile(now: number, contentVersion: string, displayName = 'Reader'): LearnerProfile {
  return {
    id: 'learner', displayName, createdAt: now, baselineDone: false, baselinePlacementOrder: null,
    settings: { muted: false, reducedMotion: false, narration: true, highContrast: false, largeText: false, mastery: { ...DEFAULT_MASTERY_SETTINGS } },
    stickers: [], overrides: [], schemaVersion: CURRICULUM_SCHEMA_VERSION, contentVersion,
  };
}

export async function loadProfile(): Promise<LearnerProfile | undefined> { return getDB().profile.get('learner'); }
export async function saveProfile(p: LearnerProfile): Promise<void> { await getDB().profile.put(p); }

export async function loadSnapshot(): Promise<LearnerSnapshot | undefined> {
  const db = getDB();
  const profile = await db.profile.get('learner');
  if (!profile) return undefined;
  const [skills, confusions, sessions, attempts] = await Promise.all([
    db.skills.toArray(), db.confusions.toArray(), db.sessions.orderBy('startedAt').toArray(), db.attempts.toArray(),
  ]);
  return { profile, skills, confusions, sessions, attempts: attempts.map(({ id: _id, ...a }) => a as Attempt) };
}

export async function saveSkill(s: SkillState): Promise<void> { await getDB().skills.put(s); }
export async function saveAttempt(a: Attempt): Promise<void> { await getDB().attempts.add(a); }
export async function saveSession(s: SessionSummary): Promise<void> { await getDB().sessions.put(s); }
export async function recordConfusion(expected: string, chosen: string, at: number): Promise<void> {
  const db = getDB();
  const cur = await db.confusions.get([expected, chosen]);
  await db.confusions.put({ expected, chosen, count: (cur?.count ?? 0) + 1, lastAt: at });
}

/** Replace the entire stored learner state in one transaction (used by import and tests). */
export async function replaceSnapshot(snap: LearnerSnapshot): Promise<void> {
  const db = getDB();
  await db.transaction('rw', [db.profile, db.skills, db.attempts, db.confusions, db.sessions], async () => {
    await Promise.all([db.profile.clear(), db.skills.clear(), db.attempts.clear(), db.confusions.clear(), db.sessions.clear()]);
    await db.profile.put(snap.profile);
    await db.skills.bulkPut(snap.skills);
    await db.attempts.bulkAdd(snap.attempts);
    await db.confusions.bulkPut(snap.confusions);
    await db.sessions.bulkPut(snap.sessions);
  });
}

/** Delete everything, including parent recordings and metadata. Irreversible. */
export async function deleteAllData(): Promise<void> {
  const db = getDB();
  await db.transaction('rw', db.tables, async () => { await Promise.all(db.tables.map((t) => t.clear())); });
}

export async function exportData(now: number): Promise<ExportFile | undefined> {
  const data = await loadSnapshot();
  return data ? { format: EXPORT_FORMAT, exportVersion: EXPORT_VERSION, exportedAt: now, data } : undefined;
}

export class ImportError extends Error {}

/** Parse + validate an exported JSON string, migrate, reconcile with current curriculum, then replace local state. */
export async function importData(json: string, unitIds: Set<string>, contentVersion: string): Promise<LearnerSnapshot> {
  let parsed: any;
  try { parsed = JSON.parse(json); } catch { throw new ImportError('That file is not valid JSON.'); }
  if (parsed?.format !== EXPORT_FORMAT || typeof parsed.exportVersion !== 'number') throw new ImportError('That file is not a Story Sounds backup.');
  if (parsed.exportVersion > EXPORT_VERSION) throw new ImportError('That backup is from a newer version of the app.');
  const d = parsed.data;
  if (!d || !d.profile || d.profile.id !== 'learner' || !Array.isArray(d.skills) || !Array.isArray(d.attempts) || !Array.isArray(d.sessions) || !Array.isArray(d.confusions) || !Array.isArray(d.profile.overrides))
    throw new ImportError('That backup is missing learner data.');
  const snap = reconcileWithCurriculum(migrateSnapshot(d, parsed.exportVersion), unitIds, contentVersion);
  await replaceSnapshot(snap);
  return snap;
}
