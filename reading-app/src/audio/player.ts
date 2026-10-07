import { AudioManifestSchema, type AudioEntry, type AudioManifest } from '../domain/schema';
import { getDB } from '../storage/db';

/**
 * Audio is looked up by id in public/audio/manifest.json (kept separate from activities).
 * Resolution order: parent recording (IndexedDB) -> manifest file -> placeholder.
 * Placeholder behaviour: isolated phonemes are NEVER spoken by text-to-speech (it mispronounces them);
 * the UI shows a caption instead. Words and instructions may use browser speech as a clearly labelled stand-in.
 */
export interface PlayOptions { slow?: boolean; muted?: boolean; allowSpeechFallback?: boolean }
export interface PlayResult { source: 'recording' | 'file' | 'speech' | 'caption-only' | 'muted'; caption: string }

let manifest: AudioManifest | null = null;
const byId = new Map<string, AudioEntry>();
let current: HTMLAudioElement | null = null;

export async function loadManifest(url = `${import.meta.env.BASE_URL}audio/manifest.json`): Promise<AudioManifest> {
  if (manifest) return manifest;
  const res = await fetch(url);
  setManifest(AudioManifestSchema.parse(await res.json()));
  return manifest!;
}
export function setManifest(m: AudioManifest) { manifest = m; byId.clear(); m.entries.forEach((e) => byId.set(e.id, e)); }
export function getEntry(id: string) { return byId.get(id); }
export function getManifest() { return manifest; }
export function captionFor(id: string): string { return byId.get(id)?.label ?? id; }

export function stopAudio() { current?.pause(); current = null; if (typeof speechSynthesis !== 'undefined') speechSynthesis.cancel(); }

function playUrl(url: string, rate: number): Promise<void> {
  return new Promise((resolve) => {
    const a = new Audio(url); a.playbackRate = rate; current = a;
    a.onended = () => resolve(); a.onerror = () => resolve();
    a.play().catch(() => resolve());
  });
}

export async function playAudio(id: string, opts: PlayOptions = {}): Promise<PlayResult> {
  const entry = byId.get(id);
  const caption = entry?.label ?? id;
  if (opts.muted) return { source: 'muted', caption };
  stopAudio();
  const rate = opts.slow ? 0.7 : 1;
  try {
    const rec = await getDB().recordings.get(id);
    if (rec) { const url = URL.createObjectURL(rec.blob); await playUrl(url, rate); URL.revokeObjectURL(url); return { source: 'recording', caption }; }
  } catch { /* IndexedDB unavailable: fall through */ }
  const file = opts.slow ? entry?.slowFile ?? entry?.file : entry?.file;
  if (file) { await playUrl(`${import.meta.env.BASE_URL}audio/${file}`, opts.slow && !entry?.slowFile ? 0.7 : 1); return { source: 'file', caption }; }
  const speakable = entry && entry.kind !== 'phoneme' && entry.kind !== 'sfx' && opts.allowSpeechFallback !== false;
  if (speakable && typeof speechSynthesis !== 'undefined' && typeof SpeechSynthesisUtterance !== 'undefined') {
    await new Promise<void>((resolve) => {
      const u = new SpeechSynthesisUtterance(caption); u.lang = 'en-GB'; u.rate = opts.slow ? 0.6 : 0.85;
      u.onend = () => resolve(); u.onerror = () => resolve(); speechSynthesis.speak(u);
    });
    return { source: 'speech', caption };
  }
  return { source: 'caption-only', caption };
}

/** Parent recording workflow: save a recorded/imported blob for an audio id; it overrides the manifest. */
export async function saveRecording(audioId: string, blob: Blob) { await getDB().recordings.put({ audioId, blob, updatedAt: Date.now() }); }
export async function removeRecording(audioId: string) { await getDB().recordings.delete(audioId); }
export async function listRecordingIds(): Promise<string[]> { return (await getDB().recordings.toArray()).map((r) => r.audioId); }
