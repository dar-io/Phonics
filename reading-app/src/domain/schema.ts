/**
 * Domain contract: curriculum content schema (Zod) + inferred types.
 * Curriculum content is DATA validated against these schemas; the engine and UI never hard-code lessons.
 * Bump CURRICULUM_SCHEMA_VERSION when the shape changes and add a migration in src/storage/migrations.ts.
 */
import { z } from 'zod';

export const CURRICULUM_SCHEMA_VERSION = 1;

const id = z.string().regex(/^[a-z0-9][a-z0-9_-]*$/, 'lowercase id');

/** A written unit of a word: one grapheme (e.g. "s", "sh", "ai", "a_e" split digraph shown as "a_e"). */
export const graphemeText = z.string().min(1).max(5);

export const GraphemeUnitSchema = z.object({
  id, // e.g. "g-s"
  order: z.number().int().positive(), // global teaching order (unique, ascending)
  phase: z.union([z.literal(2), z.literal(3), z.literal(4), z.literal(5)]),
  stage: z.enum(['reception', 'year1']),
  term: z.string(), // e.g. "Reception Autumn 1"
  phoneme: z.string(), // ASCII label e.g. "/s/"
  graphemes: z.array(graphemeText).min(1), // graphemes taught in this unit (usually 1)
  kind: z.enum(['single', 'digraph', 'trigraph', 'split', 'alternative']),
  audioId: z.string(), // key into audio manifest (phoneme sound)
  pronunciation: z.string(), // child/adult-friendly guidance, e.g. "a short, crisp 'sss' - no 'uh' on the end"
  prerequisites: z.array(id), // unit ids that must be secure first
  exampleWords: z.array(z.string()).max(8), // must be decodable from taught knowledge (validated)
  trickyWords: z.array(z.string()), // tricky words introduced with this unit
  misconceptions: z.array(z.object({ confusedWith: z.string(), guidance: z.string() })),
  reviewIntervalsDays: z.array(z.number().positive()).min(1).optional(), // overrides global schedule
  source: z.enum(['fetched', 'inferred']),
  citation: z.string().optional(),
});
export type GraphemeUnit = z.infer<typeof GraphemeUnitSchema>;

export const WordSchema = z.object({
  text: z.string().min(1),
  graphemes: z.array(graphemeText).min(1), // segmentation; join('') (ignoring split markers) must equal text
  emoji: z.string().optional(), // picture; emoji only (original, no third-party art)
  pictureLabel: z.string().optional(), // accessible description
  concrete: z.boolean().default(true), // can be pictured
  /** Words that sound identical but are spelled differently (sea/see). Never offer these as distractors for each other. */
  homophones: z.array(z.string()).optional(),
  /** Words that name the same picture or concept (cup/mug). Never offer these as distractors for each other. */
  sameMeaningAs: z.array(z.string()).optional(),
  /** True when the vowel depends on accent (bath/path: short vs long a). Kept out of unit example words. */
  accentNote: z.boolean().optional(),
});
export type Word = z.infer<typeof WordSchema>;

export const SentenceSchema = z.object({
  id,
  text: z.string(),
  /** tokens in order: decodable words reference Word.graphemes; tricky words are plain text from taught tricky list */
  tokens: z.array(z.union([
    z.object({ kind: z.literal('word'), text: z.string(), graphemes: z.array(graphemeText) }),
    z.object({ kind: z.literal('tricky'), text: z.string() }),
  ])).min(2),
  emoji: z.string().optional(),
  pictureLabel: z.string().optional(),
  unlockedByOrder: z.number().int().positive().optional(), // computed by validator if omitted
});
export type Sentence = z.infer<typeof SentenceSchema>;

export const StorySchema = z.object({
  id,
  title: z.string(),
  pages: z.array(z.object({ sentenceIds: z.array(id).min(1), emoji: z.string().optional(), pictureLabel: z.string().optional() })).min(2),
});
export type Story = z.infer<typeof StorySchema>;

export const TrickyWordSchema = z.object({
  text: z.string(),
  introducedAtOrder: z.number().int().nonnegative(),
  trickyPart: z.string().optional(), // e.g. "the 'o' in 'to'"
  decodablePartsKnown: z.boolean().default(false),
  /** Words that sound identical but are spelled differently (be/bee, to/too). */
  homophones: z.array(z.string()).optional(),
});
export type TrickyWord = z.infer<typeof TrickyWordSchema>;

export const CurriculumSchema = z.object({
  schemaVersion: z.literal(CURRICULUM_SCHEMA_VERSION),
  contentVersion: z.string(), // semver of content, stored with learner state for migrations
  units: z.array(GraphemeUnitSchema).min(1),
  words: z.array(WordSchema).min(1),
  trickyWords: z.array(TrickyWordSchema),
  sentences: z.array(SentenceSchema),
  stories: z.array(StorySchema),
});
export type Curriculum = z.infer<typeof CurriculumSchema>;

/** Audio manifest: separate from activities. Swap recordings by editing public/audio/manifest.json only. */
export const AudioEntrySchema = z.object({
  id: z.string(),
  kind: z.enum(['phoneme', 'word', 'instruction', 'sfx']),
  label: z.string(), // text shown/for captions, e.g. "/s/" or "Let's sound it out together"
  file: z.string().nullable(), // path under /audio/ ; null = no recording yet
  slowFile: z.string().nullable().optional(),
  status: z.enum(['placeholder', 'recorded', 'verified']),
  note: z.string().optional(),
});
export const AudioManifestSchema = z.object({
  version: z.number().int(),
  statement: z.string(), // must state placeholders are not Little Wandle-approved
  entries: z.array(AudioEntrySchema),
});
export type AudioEntry = z.infer<typeof AudioEntrySchema>;
export type AudioManifest = z.infer<typeof AudioManifestSchema>;
