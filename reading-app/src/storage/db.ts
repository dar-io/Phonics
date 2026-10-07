import Dexie, { type Table } from 'dexie';
import type { Attempt, ConfusionRecord, LearnerProfile, SessionSummary, SkillState } from '../domain/learner';

/** All learner data lives only in this on-device IndexedDB database. Nothing is sent anywhere. */
export class AppDB extends Dexie {
  profile!: Table<LearnerProfile, string>;
  skills!: Table<SkillState, [string, string]>;
  attempts!: Table<Attempt & { id?: number }, number>;
  confusions!: Table<ConfusionRecord, [string, string]>;
  sessions!: Table<SessionSummary, string>;
  meta!: Table<{ key: string; value: unknown }, string>;
  /** Parent-recorded audio, kept locally. Blobs never leave the device. */
  recordings!: Table<{ audioId: string; blob: Blob; updatedAt: number }, string>;

  constructor(name = 'story-sounds') {
    super(name);
    this.version(1).stores({
      profile: 'id',
      skills: '[unitId+track], unitId, status, nextReviewAt',
      attempts: '++id, sessionId, unitId, at',
      confusions: '[expected+chosen]',
      sessions: 'id, startedAt',
      meta: 'key',
      recordings: 'audioId',
    });
  }
}

let _db: AppDB | null = null;
export function getDB(): AppDB { return (_db ??= new AppDB()); }
/** test helper */
export async function resetDBForTests(name: string): Promise<AppDB> { if (_db) { _db.close(); } _db = new AppDB(name); await _db.delete(); _db = new AppDB(name); return _db; }
