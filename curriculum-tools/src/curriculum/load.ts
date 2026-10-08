/**
 * Loads and parses the shipped curriculum at module load. Throws if the data does not satisfy CurriculumSchema,
 * so a bad content edit fails loudly (tests, build, first import) rather than silently corrupting lessons.
 * Content is DATA: edit src/curriculum/data/*.json (generated from src/curriculum/author/*, see docs/curriculum-authoring.md).
 */
import { CurriculumSchema } from '../domain/schema';
import type { Curriculum } from '../domain/schema';
import curriculumJson from './data/curriculum.json';
import requirementsJson from './data/word-requirements.json';
import type { WordRequirements } from './lookup';

const parsed = CurriculumSchema.safeParse(curriculumJson);
if (!parsed.success) {
  throw new Error(`Invalid curriculum data: ${parsed.error.issues.slice(0, 5).map((i) => `${i.path.join('.')}: ${i.message}`).join('; ')}`);
}

export const curriculum: Curriculum = parsed.data;
export const CONTENT_VERSION: string = curriculum.contentVersion;
/** Pronunciation-aware gating for words (e.g. "old" needs the long-o unit). Pass to lookup.unlockOrder. */
export const wordRequirements: WordRequirements = requirementsJson as WordRequirements;
