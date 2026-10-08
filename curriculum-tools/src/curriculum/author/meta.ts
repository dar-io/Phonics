/**
 * AUTHORING SOURCE: curated word relationships that the engine needs to avoid unfair "two right answers".
 * Applied by build.ts to the generated curriculum. See docs/curriculum-authoring.md.
 */

/**
 * Homophones: words that SOUND identical but are spelled differently. Members may be decodable words or tricky
 * words (be/bee, no/know, to/too, their/there, here/hear). The engine must never offer one as a distractor for
 * another in an audio-led task (sea/see). Built into `homophones` on each member (both Word and TrickyWord).
 * Every member must exist in the word list or the tricky list (the validator checks).
 */
export const HOMOPHONES: string[][] = [
  ['be', 'bee'],
  ['blew', 'blue'],
  ['cent', 'sent'],
  ['chord', 'cord'],
  ['dew', 'due'],
  ['fir', 'fur'],
  ['hear', 'here'],
  ['knew', 'new'],
  ['knight', 'night'],
  ['knot', 'not'],
  ['know', 'no'],
  ['passed', 'past'],
  ['right', 'write'],
  ['sea', 'see'],
  ['their', 'there'],
  ['to', 'too'],
  ['which', 'witch'],
  ['wood', 'would'],
];

/**
 * Same meaning / same picture groups. Two words with the SAME emoji are only allowed when they are inflections of
 * one stem (pin/pins, jump/jumped) or listed together here (cup/mug). Inflected forms of a member are included
 * automatically by the build. The engine must not offer words of one group as distractors for each other.
 */
export const SAME_MEANING: string[][] = [
  ['nap', 'sleep', 'catnap'],
  ['tag', 'label'],
  ['dog', 'pup', 'puppy'],
  ['cog', 'gear'],
  ['kid', 'child'],
  ['cup', 'mug'],
  ['run', 'jog', 'rush', 'sprint'],
  ['rock', 'boulder'],
  ['hen', 'fowl'],
  ['bag', 'handbag'],
  ['bin', 'dustbin'],
  ['bus', 'coach'],
  ['tub', 'bath', 'bathtub'],
  ['log', 'wood'],
  ['web', 'cobweb'],
  ['quill', 'feather'],
  ['chip', 'fries'],
  ['song', 'music'],
  ['mail', 'letter'],
  ['see', 'look'],
  ['foot', 'feet'],
  ['tooth', 'teeth'],
  ['coat', 'raincoat'],
  ['road', 'street'],
  ['loaf', 'bread'],
  ['farm', 'farmyard'],
  ['cart', 'trolley'],
  ['clap', 'applaud'],
  ['gown', 'dress'],
  ['brush', 'toothbrush'],
  ['string', 'thread'],
  ['globe', 'world'],
  ['jewel', 'gem'],
  ['tin', 'can'],
  ['pan', 'wok'],
  ['dish', 'plate'],
  ['dinner', 'supper'],
];

/**
 * Accent-dependent vowels (northern/Scottish short a versus southern long a in the TRAP/BATH split, and
 * short/long oo in room and roof). They stay in the word list (so sentences and stories keep working) and carry
 * `accentNote: true`. They are never chosen as a unit's example words and the audio brief should record accepted variants.
 */
export const ACCENT_WORDS: string[] = [
  'bath', 'bathtub', 'path', 'fast', 'fastest', 'past', 'passed', 'pass', 'class', 'grass', 'dance', 'graph', 'giraffe', 'room', 'roof', 'bedroom',
];
