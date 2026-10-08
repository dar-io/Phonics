import type { AudioEntry } from '../domain/schema';

/**
 * Regenerating the manifest must NEVER wipe a recording. Entries that a person has recorded or verified (a file is set,
 * or the status is beyond "placeholder") keep their file, slow file, status and note; ids and labels still come from the
 * curriculum. Returns the merged entries and how many were preserved.
 */
export function mergeRecordedAudio(generated: AudioEntry[], previous: AudioEntry[]): { entries: AudioEntry[]; kept: number } {
  const byId = new Map(previous.map((e) => [e.id, e] as const));
  let kept = 0;
  const entries = generated.map((g) => {
    const old = byId.get(g.id);
    if (old && (old.status !== 'placeholder' || old.file !== null)) {
      kept++;
      return { ...g, file: old.file, slowFile: old.slowFile, status: old.status, note: old.note };
    }
    return g;
  });
  return { entries, kept };
}
