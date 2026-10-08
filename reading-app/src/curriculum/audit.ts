/**
 * Pronunciation / segmentation audit (pedagogy review M7).
 *
 * Flags decodable words (and sentence tokens, including names) whose real vowel or consonant sound differs from the
 * grapheme the unit taught, or whose segmentation looks wrong, unless the word is gated behind the right
 * alternative-sound unit via `word-requirements.json`, is a tricky word, or has been reviewed and allowlisted
 * below WITH a reason. Pure functions; the CLI is scripts/audit-curriculum.ts and a vitest asserts 0 errors.
 *
 * It is a heuristic net, not a pronunciation dictionary: the IRREGULAR lexicon is curated (British pronunciation),
 * the pattern rules catch regular families (o before m/n/v/th, a after w/qu, ea before r, soft c/g ...).
 */
import type { Curriculum } from '../domain/schema';
import type { WordRequirements } from './lookup';
import { defaultRequirements } from './validate';

export interface AuditFinding {
  level: 'error' | 'info';
  word: string;
  rule: string;
  detail: string;
}

/** Irregular words: real sound, and the unit that makes the word legitimately decodable (if any). */
interface Irregular { sound: string; gate?: string; ok?: string }
const IRREGULAR: Record<string, Irregular> = {
  // o says /u/
  son: { sound: "o says /u/" }, ton: { sound: "o says /u/" }, won: { sound: "o says /u/" }, none: { sound: "o says /u/" },
  done: { sound: "o says /u/" }, month: { sound: "o says /u/" }, monk: { sound: "o says /u/" }, monkey: { sound: "o says /u/" },
  mother: { sound: "o says /u/" }, brother: { sound: "o says /u/" }, other: { sound: "o says /u/" }, another: { sound: "o says /u/" },
  nothing: { sound: "o says /u/" }, money: { sound: "o says /u/" }, honey: { sound: "o says /u/" }, front: { sound: "o says /u/" },
  wonder: { sound: "o says /u/" }, shove: { sound: "o says /u/" }, oven: { sound: "o says /u/" }, cover: { sound: "o says /u/" },
  discover: { sound: "o says /u/" }, onion: { sound: "o says /u/" }, among: { sound: "o says /u/" }, Monday: { sound: "o says /u/" },
  sponge: { sound: "o says /u/" }, glove: { sound: "o says /u/" }, dove: { sound: "o says /u/" }, above: { sound: "o says /u/" },
  come: { sound: "o says /u/" }, some: { sound: "o says /u/" }, love: { sound: "o says /u/" }, one: { sound: "o says /w-u/" }, once: { sound: "o says /w-u/" },
  // other irregular vowels
  young: { sound: "ou says /u/" }, touch: { sound: "ou says /u/" }, country: { sound: "ou says /u/" }, couple: { sound: "ou says /u/" },
  double: { sound: "ou says /u/" }, trouble: { sound: "ou says /u/" }, cousin: { sound: "ou says /u/" }, enough: { sound: "ou says /u/" },
  rough: { sound: "ou says /u/" }, tough: { sound: "ou says /u/" }, soup: { sound: "ou says /oo/" }, group: { sound: "ou says /oo/" },
  through: { sound: "ough says /oo/" }, though: { sound: "ough says /oa/" }, thought: { sound: "ough says /or/" }, bought: { sound: "ough says /or/" },
  brought: { sound: "ough says /or/" }, cough: { sound: "ough says /off/" },
  blood: { sound: "oo says /u/" }, flood: { sound: "oo says /u/" }, door: { sound: "oor says /or/" }, floor: { sound: "oor says /or/" }, poor: { sound: "oor says /or/" },
  said: { sound: "ai says /e/" }, again: { sound: "ai says /e/" }, against: { sound: "ai says /e/" }, any: { sound: "a says /e/" }, many: { sound: "a says /e/" },
  friend: { sound: "ie says /e/" }, bury: { sound: "u says /e/" }, busy: { sound: "u says /i/" }, great: { sound: "ea says /ai/" }, steak: { sound: "ea says /ai/" },
  break: { sound: "ea says /ai/" }, bear: { sound: "ear says /air/" }, pear: { sound: "ear says /air/" }, wear: { sound: "ear says /air/" }, tear: { sound: "ear says /air/ or /ear/" },
  heart: { sound: "ear says /ar/" }, earth: { sound: "ear says /ur/" }, early: { sound: "ear says /ur/" }, learn: { sound: "ear says /ur/" }, heard: { sound: "ear says /ur/" }, search: { sound: "ear says /ur/" },
  war: { sound: "ar after w says /or/" }, warm: { sound: "ar after w says /or/" }, warn: { sound: "ar after w says /or/" }, dwarf: { sound: "ar after w says /or/" }, swarm: { sound: "ar after w says /or/" }, quarter: { sound: "ar after qu says /or/" },
  father: { sound: "a says /ar/" }, banana: { sound: "a says /ar/" }, ball: { sound: "a says /or/" }, call: { sound: "a says /or/" }, fall: { sound: "a says /or/" }, tall: { sound: "a says /or/" },
  wall: { sound: "a says /or/" }, small: { sound: "a says /or/" }, talk: { sound: "a says /or/" }, walk: { sound: "a says /or/" }, half: { sound: "a says /ar/, l silent" }, calf: { sound: "a says /ar/, l silent" },
  salt: { sound: "a says /or/" }, bald: { sound: "a says /or/" }, false: { sound: "a says /or/" }, also: { sound: "a says /or/" }, almost: { sound: "a says /or/" }, always: { sound: "a says /or/" },
  have: { sound: "a_e is short" }, give: { sound: "i_e is short" }, live: { sound: "i_e is short (verb)" }, move: { sound: "o_e says /oo/" }, prove: { sound: "o_e says /oo/" }, lose: { sound: "o_e says /oo/" }, gone: { sound: "o_e is short" },
  were: { sound: "ere says /er/" }, where: { sound: "ere says /air/" }, here: { sound: "e_e says /ear/" }, there: { sound: "ere says /air/" },
  pint: { sound: "i says /igh/" }, ski: { sound: "i says /ee/" }, police: { sound: "i says /ee/" }, machine: { sound: "i says /ee/" }, eye: { sound: "eye says /igh/" },
  they: { sound: "ey says /ai/" }, grey: { sound: "ey says /ai/" }, prey: { sound: "ey says /ai/" }, gym: { sound: "y says /i/, g soft" }, myth: { sound: "y says /i/" }, system: { sound: "y says /i/" },
  doctor: { sound: "or is weak /er/" }, actor: { sound: "or is weak /er/" }, visitor: { sound: "or is weak /er/" }, sailor: { sound: "or is weak /er/" }, motor: { sound: "or is weak /er/" }, mirror: { sound: "or is weak /er/" },
  collar: { sound: "ar is weak /er/" }, dollar: { sound: "ar is weak /er/" }, sugar: { sound: "ar is weak /er/, s says /sh/" },
  four: { sound: "our says /or/" }, your: { sound: "our says /or/" }, court: { sound: "our says /or/" }, pour: { sound: "our says /or/" }, tour: { sound: "our says /oor/" },
  could: { sound: "ou says /oo/" }, would: { sound: "ou says /oo/" }, should: { sound: "ou says /oo/" }, who: { sound: "wh says /h/" }, whole: { sound: "wh says /h/" }, whose: { sound: "wh says /h/" },
  two: { sound: "tw- says /t/" }, buy: { sound: "uy says /igh/" }, guy: { sound: "uy says /igh/" }, ghost: { sound: "gh says /g/" }, island: { sound: "s is silent" }, aisle: { sound: "ais is /igh/" },
  sure: { sound: "s says /sh/" }, pure: { sound: "ure says /yoor/" }, cure: { sound: "ure says /yoor/" }, put: { sound: "u says /oo/" }, pull: { sound: "u says /oo/" }, push: { sound: "u says /oo/" },
  full: { sound: "u says /oo/" }, bull: { sound: "u says /oo/" }, bush: { sound: "u says /oo/" }, woman: { sound: "o says /oo/" }, women: { sound: "o says /i/, e says /i/" },
  people: { sound: "eo says /ee/" }, minute: { sound: "i says /i/, u says weak" }, wind: { sound: "i says /i/ (noun) or /igh/ (verb)" }, wound: { sound: "ou says /oo/ (noun)" },
  // reviewed, accepted words in the list (sound differs slightly but the unit/gate makes the word legitimate)
  bath: { sound: "a is short (north) or long (south)", ok: "accentNote flagged; accent-dependent" },
  path: { sound: "a is short (north) or long (south)", ok: "accentNote flagged; accent-dependent" },
  fast: { sound: "a is short (north) or long (south)", ok: "accentNote flagged; accent-dependent" },
  pass: { sound: "a is short (north) or long (south)", ok: "accentNote flagged; accent-dependent" },
  dance: { sound: "a is short (north) or long (south)", ok: "accentNote flagged; accent-dependent" },
  head: { sound: "ea says /e/", gate: 'g-ea-e' }, bread: { sound: "ea says /e/", gate: 'g-ea-e' },
  away: { sound: "initial a is a weak vowel", ok: "reviewed: weak vowel in an unstressed first syllable, taught with ay" },
  around: { sound: "initial a is a weak vowel", ok: "reviewed: weak vowel in an unstressed first syllable, taught with ou" },
  about: { sound: "initial a is a weak vowel" }, ago: { sound: "initial a is a weak vowel" }, alone: { sound: "initial a is a weak vowel" },
  author: { sound: "final or is weak /er/", ok: "reviewed: unstressed -or ending, introduced with au" },
  chalet: { sound: "silent t, et says /ay/" }, sachet: { sound: "silent t, et says /ay/" }, chic: { sound: "i says /ee/" },
  dinosaur: { sound: "i says /igh/, o is weak", gate: 'g-i-igh' },
};

/** g before e/i/y that is HARD (get, gift ...): decodable with the first-taught hard g; reported as info. */
const HARD_G_BEFORE_EIY = new Set(['get', 'gear', 'gig', 'gift', 'girl', 'tiger', 'bigger', 'biggest', 'digging', 'hugging', 'begin', 'finger', 'anger', 'target']);

/** Adjacent single letters that spell a taught digraph legitimately (syllable or compound boundary). Reviewed. */
const BOUNDARY_OK = new Set([
  'around', 'zero', 'hero', 'circus', 'orange', 'ginger', 'danger', 'character', 'parachute', 'direction', 'giraffe', 'astronaut', 'dinosaur',
  'bedroom', 'catnap', 'laptop', 'sunset', 'sunhat', 'sunlight', 'handbag', 'dustbin', 'popcorn', 'cobweb', 'pigpen', 'zigzag', 'hotdog', 'backpack',
  'bathtub', 'toothbrush', 'moonlight', 'raincoat', 'airport', 'farmyard', 'starfish', 'away', 'change', 'morning', 'nephew', 'phonics', 'dolphin',
]);

const SOFT_NEXT = new Set(['e', 'i', 'y']);
const isSplit = (t: string): boolean => /^[a-z]_e$/.test(t);

interface Subject { text: string; graphemes: string[]; requirements: string[]; source: 'word' | 'sentence' }

export function auditSubjects(c: Curriculum): Subject[] {
  const tricky = new Set(c.trickyWords.map((t) => t.text.toLowerCase()));
  const seen = new Map<string, Subject>();
  for (const w of c.words) seen.set(w.text.toLowerCase(), { text: w.text, graphemes: w.graphemes, requirements: [], source: 'word' });
  for (const s of c.sentences) {
    for (const t of s.tokens) {
      if (t.kind !== 'word') continue;
      const k = t.text.toLowerCase();
      if (!seen.has(k) && !tricky.has(k)) seen.set(k, { text: t.text, graphemes: t.graphemes, requirements: [], source: 'sentence' });
    }
  }
  return [...seen.values()];
}

export function auditCurriculum(c: Curriculum, requirements: WordRequirements = defaultRequirements): AuditFinding[] {
  const out: AuditFinding[] = [];
  const add = (level: AuditFinding['level'], word: string, rule: string, detail: string): void => { out.push({ level, word, rule, detail }); };
  const unitIds = new Set(c.units.map((u) => u.id));
  const digraphs = new Set(c.units.filter((u) => !u.id.startsWith('p4-')).flatMap((u) => u.graphemes).filter((g) => g.length >= 2 && !isSplit(g) && !g.includes('_')));
  for (const [word, req] of Object.entries(requirements)) for (const r of req) if (!unitIds.has(r)) add('error', word, 'requirement', `unknown unit ${r}`);

  for (const sub of auditSubjects(c)) {
    const lc = sub.text.toLowerCase();
    const g = sub.graphemes;
    const req = requirements[lc] ?? [];
    const has = (u: string): boolean => req.includes(u);
    const flag = (rule: string, detail: string, allow = false): void => { add(allow ? 'info' : 'error', sub.text, rule, detail); };

    // 1. curated irregular lexicon
    const irr = IRREGULAR[lc] ?? IRREGULAR[sub.text];
    if (irr) {
      if (irr.gate && has(irr.gate)) add('info', sub.text, 'irregular (gated)', `${irr.sound}; gated behind ${irr.gate}`);
      else if (irr.ok) add('info', sub.text, 'irregular (reviewed)', `${irr.sound}; ${irr.ok}`);
      else flag('irregular', `${irr.sound}${irr.gate ? ` (needs gate ${irr.gate})` : ''}; remove, make tricky, or gate`);
    }

    // 2. soft c / soft g
    g.forEach((tok, i) => {
      if (tok !== 'c' && tok !== 'g') return;
      const pendingE = i > 0 && isSplit(g[i - 1]!);
      const next = pendingE ? 'e' : g[i + 1]?.[0];
      if (!next || !SOFT_NEXT.has(next)) return;
      if (tok === 'c') {
        if (!has('g-c-s')) flag('soft-c', `c before ${next} says /s/ but the word is not gated behind g-c-s`);
        else add('info', sub.text, 'soft-c (gated)', 'gated behind g-c-s');
      } else if (HARD_G_BEFORE_EIY.has(lc) && !has('g-g-j')) {
        add('info', sub.text, 'hard-g exception', `g before ${next} is hard here (decodable as /g/; exception to the later soft-g rule)`);
      } else if (!has('g-g-j')) {
        flag('soft-g', `g before ${next} says /j/ but the word is not gated behind g-g-j`);
      } else add('info', sub.text, 'soft-g (gated)', 'gated behind g-g-j');
    });

    // 3. vowel pattern families
    g.forEach((tok, i) => {
      const prev = g[i - 1];
      const next = g[i + 1];
      const after = g[i + 2];
      if (tok === 'o' && !has('g-o-oa') && next && ['m', 'n', 'v', 'th'].includes(next) && (after === undefined || after === 'e' || after === 'th' || after === 'ng')) {
        const reviewed = ['on', 'tom', 'strong', 'long', 'song', 'gong', 'wrong', 'moth'].includes(lc); // o before ng/th is short /o/ in British English
        if (!irr) flag('o-before-m/n/v/th', 'o before m/n/v/th is often /u/ (son, come, month); confirm the short /o/ is right', reviewed);
      }
      if (tok === 'a' && next === 'll' && after === undefined && !irr && !has('g-a-o')) flag('a-before-ll', 'a before ll at the end of a word may say /or/ (all, ball)', ['valley', 'alley'].includes(lc) || g.length > 3);
      if (tok === 'a' && next === 'l' && after && ['k', 't', 'd'].includes(after) && !irr) flag('a-before-l+cons', 'a before l+k/t/d may say /or/ (talk, salt, bald)');
      if (tok === 'a' && (prev === 'w' || prev === 'qu') && !has('g-a-o')) flag('a-after-w/qu', 'a after w or qu usually says /o/ (wash, quad)', ['wag', 'wax', 'quack'].includes(lc));
      if (tok === 'ar' && (prev === 'w' || prev === 'qu')) flag('ar-after-w', 'ar after w says /or/ (war, warm)');
      if (tok === 'or' && prev === 'w' && !has('g-or-ur')) flag('or-after-w', 'or after w says /ur/ (word, work)');
      if (tok === 'ea' && next === 'r' && !irr) flag('ea-before-r', 'ea before r is usually not /ee/ (bear, heart, learn)');
      if (tok === 'oo' && next === 'r' && !irr) flag('oo-before-r', 'oo before r is /or/ (door, floor)');
      if (tok === 'u' && prev && ['p', 'b', 'f'].includes(prev) && next && ['ll', 'sh', 't'].includes(next) && after === undefined && !irr) {
        flag('u-after-labial', 'u after p/b/f before ll/sh/t is often /oo/ (pull, push, put)', ['but', 'butt', 'putt'].includes(lc));
      }
      if (tok === 'y' && i > 0 && i < g.length - 1) flag('medial-y', 'a single y inside a word usually says /i/ (gym, myth) or is a mis-segmentation', ['farmyard'].includes(lc)); // farmyard: y starts the compound's second word 'yard'
      if (tok === 'y' && i === g.length - 1 && g.length > 1 && !has('g-y-igh') && !has('g-y-ee') && !irr) flag('final-y', 'final y says /ee/ or /igh/ and the word is not gated behind g-y-ee / g-y-igh');
    });

    // 4. segmentation: adjacent single letters that spell a taught digraph (crude boundary test)
    for (let i = 0; i + 1 < g.length; i++) {
      const a = g[i]!;
      const b = g[i + 1]!;
      if (a.length === 1 && b.length === 1 && !isSplit(a) && !isSplit(b) && digraphs.has(a + b)) {
        const ok = BOUNDARY_OK.has(lc);
        add(ok ? 'info' : 'error', sub.text, 'segmentation', `adjacent graphemes ${a}+${b} spell the digraph "${a + b}"${ok ? ' (reviewed syllable/compound boundary)' : ' - merge them into one grapheme if this is one sound'}`);
      }
    }
  }
  return out;
}
