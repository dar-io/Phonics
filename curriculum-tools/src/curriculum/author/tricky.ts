/**
 * AUTHORING SOURCE: tricky words. `unit` is the unit key at which the word is introduced.
 * Phase and term placement is from the cited school overview PDFs (seen only via search summaries);
 * the spread across individual units is INFERRED. Tricky-word lists differ between versions of the programme.
 */
export interface TrickyDef { text: string; unit: string; part: string; known?: boolean }

const T = (unit: string, rows: Array<[string, string, boolean?]>): TrickyDef[] =>
  rows.map(([text, part, known]) => ({ text, unit, part, ...(known ? { known } : {}) }));

export const TRICKY: TrickyDef[] = [
  ...T('s', [
    ['is', "the 's' says /z/", true],
    ['I', 'the letter name sound /igh/'],
    ['the', "the 'e' is a quick, weak sound"],
  ]),
  ...T('ff', [
    ['as', "the 's' says /z/", true],
    ['and', "the 'a' is quick and weak", true],
  ]),
  ...T('ll', [
    ['has', "the 's' says /z/", true],
    ['his', "the 's' says /z/", true],
    ['her', "the 'er' says a weak /uh/-r sound"],
  ]),
  ...T('j', [
    ['go', "the 'o' says /oa/"],
    ['no', "the 'o' says /oa/"],
  ]),
  ...T('v', [
    ['to', "the 'o' says /oo/"],
    ['into', "the 'o' says /oo/"],
  ]),
  ...T('x', [
    ['put', "the 'u' says a short /oo/ (accent dependent)"],
    ['pull', "the 'u' says a short /oo/ (accent dependent)"],
    ['full', "the 'u' says a short /oo/ (accent dependent)"],
    ['push', "the 'u' says a short /oo/ (accent dependent)"],
  ]),
  ...T('z', [
    ['he', "the 'e' says /ee/"],
    ['we', "the 'e' says /ee/"],
    ['me', "the 'e' says /ee/"],
    ['be', "the 'e' says /ee/"],
  ]),
  ...T('zz', [['of', "the 'f' says /v/"]]),
  ...T('sh', [['she', "the 'e' says /ee/ (sh is already known)", true]]),
  ...T('ai', [
    ['was', "the 'a' says /o/ and the 's' says /z/"],
    ['you', "the 'ou' says /oo/"],
  ]),
  ...T('igh', [['they', "the 'ey' says /ai/"]]),
  ...T('oa', [
    ['my', "the 'y' says /igh/"],
    ['by', "the 'y' says /igh/"],
  ]),
  ...T('oo-long', [['all', "the 'a' says /or/"]]),
  ...T('ar', [['are', "the 'are' says /ar/"]]),
  ...T('ur', [
    ['sure', "the 'su' says /sh/ and 're' says /or/"],
    ['pure', "the 'u' says /yoo/ and 're' says /or/"],
  ]),
  ...T('p4-cvcc', [
    ['said', "the 'ai' says /e/"],
    ['so', "the 'o' says /oa/"],
    ['have', "the final 'e' is silent and a is short"],
    ['like', "the split 'i_e' is taught later in Year 1", true],
  ]),
  ...T('p4-ccvc', [
    ['some', "the 'o' says /u/ and the 'e' is silent"],
    ['come', "the 'o' says /u/ and the 'e' is silent"],
    ['love', "the 'o' says /u/ and the 'e' is silent"],
    ['do', "the 'o' says /oo/"],
  ]),
  ...T('p4-long', [
    ['were', "the 'ere' says /er/"],
    ['here', "the 'e_e' says /ear/"],
    ['little', 'the -le ending'],
    ['says', "the 'ay' says /e/"],
  ]),
  ...T('p4-suffix', [
    ['there', "the 'ere' says /air/"],
    ['when', "the 'wh' says /w/ (taught later)", true],
    ['what', "the 'wh' says /w/ and 'a' says /o/"],
    ['one', "the 'o' says /w-u/"],
    ['out', "the 'ou' says /ow/ (taught later in Year 1)"],
    ['today', "the 'a' says /ai/ (taught later)"],
  ]),
  ...T('ir', [
    ['their', "the 'eir' says /air/"],
    ['people', "the 'eo' says /ee/"],
    ['oh', "the 'oh' says /oa/"],
  ]),
  ...T('u-yoo', [
    ['your', "the 'our' says /or/"],
    ['Mr', 'written short for Mister'],
    ['Mrs', 'written short for Missus'],
    ['Ms', 'written short for Miz'],
  ]),
  ...T('e-ee', [
    ['ask', "the 'a' may say /ar/ in some accents"],
    ['could', "the 'ou' says /oo/ and the 'l' is silent"],
    ['would', "the 'ou' says /oo/ and the 'l' is silent"],
    ['should', "the 'ou' says /oo/ and the 'l' is silent"],
  ]),
  ...T('ew', [
    ['our', "the 'our' says /ow-uh/"],
    ['house', "the final 'se' says /s/ and 'ou' says /ow/"],
    ['mouse', "the final 'se' says /s/ and 'ou' says /ow/"],
  ]),
  ...T('au', [
    ['water', "the 'a' says /or/ and 'er' is weak"],
    ['want', "the 'a' says /o/"],
  ]),
];
