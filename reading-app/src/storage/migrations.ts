import { CURRICULUM_SCHEMA_VERSION } from '../domain/schema';
import type { LearnerSnapshot } from '../domain/learner';

export const EXPORT_FORMAT = 'story-sounds-export';
export const EXPORT_VERSION = 1;

export interface ExportFile { format: typeof EXPORT_FORMAT; exportVersion: number; exportedAt: number; data: LearnerSnapshot }

type Migration = (s: any) => any;
/** Ordered migrations keyed by the export version they upgrade FROM. Add an entry when the snapshot shape changes. */
export const MIGRATIONS: Record<number, Migration> = {};

export function migrateSnapshot(raw: any, fromVersion: number): LearnerSnapshot {
  let v = fromVersion; let data = raw;
  while (v < EXPORT_VERSION) { const m = MIGRATIONS[v]; if (!m) throw new Error(`No migration from export version ${v}`); data = m(data); v++; }
  return data as LearnerSnapshot;
}

/** Content migration hook: units that vanished from a newer curriculum are dropped from skills/overrides; attempts are kept as history. */
export function reconcileWithCurriculum(snap: LearnerSnapshot, unitIds: Set<string>, contentVersion: string): LearnerSnapshot {
  return {
    ...snap,
    profile: {
      ...snap.profile,
      schemaVersion: CURRICULUM_SCHEMA_VERSION,
      contentVersion,
      overrides: snap.profile.overrides.filter((o) => unitIds.has(o.unitId)),
    },
    skills: snap.skills.filter((s) => unitIds.has(s.unitId)),
  };
}
