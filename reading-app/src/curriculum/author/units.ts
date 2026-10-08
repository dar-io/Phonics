/**
 * AUTHORING SOURCE (not bundled into the app): grapheme unit definitions.
 * Run `npx tsx src/curriculum/author/build.ts` to regenerate data/curriculum.json,
 * data/word-requirements.json and public/audio/manifest.json. See docs/curriculum-authoring.md.
 *
 * Order in this array IS the global teaching order (order = index + 1).
 */
export type Kind = 'single' | 'digraph' | 'trigraph' | 'split' | 'alternative';
export interface UnitDef {
  /** id without the "g-" prefix (consolidation units keep their "p4-" id). */
  key: string;
  graphemes: string[];
  phoneme: string;
  kind: Kind;
  pron: string;
  /** prerequisite keys (default: the previous unit). */
  pre?: string[];
  mis?: Array<[string, string]>;
}

const u = (key: string, graphemes: string[], phoneme: string, kind: Kind, pron: string, pre?: string[], mis?: Array<[string, string]>): UnitDef =>
  ({ key, graphemes, phoneme, kind, pron, ...(pre ? { pre } : {}), ...(mis ? { mis } : {}) });

export const UNITS: UnitDef[] = [
  // ---------------- Phase 2, Reception Autumn 1 ----------------
  u('s', ['s'], '/s/', 'single', "A short, crisp hiss 'sss' like a leaking tyre. Stop it cleanly - no 'uh' on the end.", [],
    [['z', "s is a quiet hiss; z buzzes. Put a hand on your throat: for 's' it stays still, for 'z' it buzzes."]]),
  u('a', ['a'], '/a/', 'single', "A short 'a' as at the start of 'ant'. Open your mouth wide and keep it quick.", undefined,
    [['e', "For 'a' the mouth opens wide; for 'e' it is a smaller smile."]]),
  u('t', ['t'], '/t/', 'single', "A tiny, quiet tap of the tongue behind the top teeth - 't'. A puff of air, no voice, no 'tuh'.", undefined,
    [['d', "t is whispered; d has a voice. Hand on throat: 'd' buzzes a little, 't' does not."]]),
  u('p', ['p'], '/p/', 'single', "A quick pop of air from closed lips - 'p'. Hold a tissue in front of your mouth: it should flutter. No 'puh'.", undefined,
    [['b', "p is a whispered pop; b is the same pop with your voice switched on."]]),
  u('i', ['i'], '/i/', 'single', "A short 'i' as at the start of 'in'. Relaxed and quick - not the letter name 'eye'.", undefined,
    [['e', "For 'i' the mouth is small and the tongue high; for 'e' the mouth opens a little more."]]),
  u('n', ['n'], '/n/', 'single', "A steady hum 'nnn' with the tongue tip behind the top teeth. Stop it cleanly - not 'nuh'.", undefined,
    [['m', "For 'n' the lips stay apart and the tongue touches the top; for 'm' the lips close. Use a mirror."]]),
  u('m', ['m'], '/m/', 'single', "A hum 'mmm' with the lips together, like tasting something yummy. Stop cleanly - not 'muh'.", undefined,
    [['n', "m = lips together. n = lips apart, tongue up. Hum both and notice the difference."],
     ['w', "m and w both use the lips, but m hums with the lips shut; w is open and moving."]]),
  u('d', ['d'], '/d/', 'single', "A short voiced tap of the tongue behind the top teeth - 'd'. No 'duh'.", undefined,
    [['b', "b and d look alike. For 'b' the stick comes first, then the round belly (like a bat and ball). For 'd' the round part comes first, then the stick (like a drum and drumstick)."],
     ['t', "d has a voice; t is a quiet puff."]]),
  u('g', ['g'], '/g/', 'single', "A short, voiced 'g' from the back of the throat, as in 'go'. No 'guh'.", undefined,
    [['c', "g buzzes in the throat; the /k/ sound of c and k is quiet."],
     ['j', "g is hard and from the throat; j is the 'jelly' sound made with the front of the tongue."]]),
  u('o', ['o'], '/o/', 'single', "A short 'o' as at the start of 'on'. Round the lips and keep it quick.", undefined,
    [['a', "o has round lips; a has a wide mouth."], ['u', "o has rounded lips; u is relaxed with a small jaw drop."]]),
  u('c', ['c'], '/k/', 'single', "The letter c says /k/ here: a quick, quiet click at the back of the throat. No 'kuh'.", undefined,
    [['k', "c and k make the same /k/ sound at this stage. Say them together to hear it."],
     ['s', "Later c can say /s/ but for now it is always /k/."]]),
  u('k', ['k'], '/k/', 'single', "The same quick, quiet /k/ click at the back of the throat. No 'kuh'.", ['c'],
    [['c', "k and c say the same /k/ here. k tends to start words before i and e (kit, kid)."]]),
  u('ck', ['ck'], '/k/', 'digraph', "Two letters, one /k/ sound. Same quick click as c and k. We see ck at the end of words after a short vowel (duck, pick).", ['c', 'k'],
    [['k', "ck is the same sound as k; the two letters sit together at the end after a short vowel."]]),
  u('e', ['e'], '/e/', 'single', "A short 'e' as at the start of 'egg'. Mouth slightly open, quick.", undefined,
    [['a', "e is a small smile; a opens wider."], ['i', "e opens the mouth a little more than i."]]),
  u('u', ['u'], '/u/', 'single', "A short 'u' as at the start of 'up'. Relaxed and quick - not 'you'.", undefined,
    [['o', "u is relaxed with the lips neutral; o has round lips."]]),
  u('r', ['r'], '/r/', 'single', "A smooth, growly 'rrr' with the tongue pulled back and lips slightly rounded. Not 'ruh' and not 'w'.", undefined,
    [['w', "r pulls the tongue back; w only uses the lips."]]),
  u('h', ['h'], '/h/', 'single', "A soft breath of air 'h', like fogging a mirror. Quiet - no 'huh'.", undefined,
    [['n', "h is just breath; n hums."]]),
  u('b', ['b'], '/b/', 'single', "A short voiced pop of the lips - 'b'. No 'buh'.", undefined,
    [['d', "b: the stick first, then the belly (bat and ball). d: belly first, then the stick (drum, drumstick)."],
     ['p', "b has a voice; p is the same pop whispered."]]),
  u('f', ['f'], '/f/', 'single', "Top teeth on the bottom lip and blow - 'fff'. Quiet, no 'fuh'.", undefined,
    [['v', "f is whispered; v buzzes."], ['th', "f uses teeth on the lip; th puts the tongue between the teeth."]]),
  u('l', ['l'], '/l/', 'single', "Tongue tip up behind the top teeth with your voice on - 'lll'. Hold it, then stop cleanly - not 'luh'.", undefined,
    [['r', "l touches the tongue to the top; r keeps the tongue pulled back."]]),

  // ---------------- Phase 2, Reception Autumn 2 ----------------
  u('ff', ['ff'], '/f/', 'digraph', "Two letters, one /f/ sound - the same 'fff' as f. We usually see ff at the end of a short word (puff, off).", ['f']),
  u('ll', ['ll'], '/l/', 'digraph', "Two letters, one /l/ sound - the same 'lll' as l. Usually at the end of a short word (bell, hill).", ['l']),
  u('ss', ['ss'], '/s/', 'digraph', "Two letters, one /s/ sound - the same hissing 'sss' as s. Usually at the end of a short word (mess, kiss).", ['s']),
  u('j', ['j'], '/j/', 'single', "A short voiced 'j' - jaw drops, tongue taps and releases. No 'juh'.", undefined,
    [['g', "j is the jelly sound at the front of the mouth; g is from the throat."],
     ['ch', "j has a voice; ch is whispered."]]),
  u('v', ['v'], '/v/', 'single', "Top teeth on the bottom lip with your voice on - 'vvv' buzzes. No 'vuh'.", undefined,
    [['f', "v buzzes; f is quiet. Hand on throat to feel it."]]),
  u('w', ['w'], '/w/', 'single', "Round the lips, then relax them - 'w'. No 'wuh', and not the letter name 'double-u'.", undefined,
    [['r', "w uses only the lips; r pulls the tongue back."]]),
  u('x', ['x'], '/ks/', 'single', "Two sounds squeezed together: /k/ then /s/, as at the end of 'box'. Say it as 'ks' in one quick go.", undefined,
    [['s', "x ends words and has a /k/ in front of the /s/."]]),
  u('y', ['y'], '/y/', 'single', "A quick 'y' as at the start of 'yes'. No 'yuh'. Here y is a consonant at the start of a word.", undefined),
  u('z', ['z'], '/z/', 'single', "A buzzing 'zzz' like a bee. Voice on, stop cleanly - not 'zuh'.", undefined,
    [['s', "z buzzes; s hisses quietly. Feel your throat."]]),
  u('zz', ['zz'], '/z/', 'digraph', "Two letters, one /z/ buzz - the same as z. Usually at the end of a short word (buzz, fizz).", ['z']),
  u('qu', ['qu'], '/kw/', 'digraph', "Two sounds blended together: /k/ then /w/, as in 'quick'. The letter q always travels with u.", ['u', 'ck']),
  u('ch', ['ch'], '/ch/', 'digraph', "A short, sharp 'ch' like the start of a sneeze, 'ch'. Two letters, one sound. Keep it crisp - no 'chuh'.", ['h', 'c'],
    [['sh', "ch starts with a tiny stop (tongue taps) and is short; sh is a long smooth hush."],
     ['th', "ch is a sharp tap; th puts the tongue between the teeth."]]),
  u('sh', ['sh'], '/sh/', 'digraph', "A long, smooth, quiet 'shhh' like telling someone to be quiet. Two letters, one sound.", ['s', 'h'],
    [['ch', "sh is a long smooth sound you can hold; ch is a short sharp one."],
     ['s', "sh is rounder and has the lips pushed forward; s is a thin hiss."]]),
  u('th', ['th'], '/th/', 'digraph', "Unvoiced th, as in 'thin', 'thumb' and 'path': tongue tip between the teeth and blow gently - 'thhh'. Only air comes out, so nothing buzzes in your throat. No 'thuh'.", ['t', 'h'],
    [['f', "th keeps the tongue between the teeth; f puts the top teeth on the lip."],
     ['t', "th lets air flow past the tongue tip; t is a quick tap."],
     ['th-voiced', "The same two letters also have a buzzing sound (this, that), taught next. For 'thin' and 'path' the throat stays still."]]),
  u('th-voiced', ['th'], '/dh/', 'digraph', "Voiced th, as in 'this', 'that', 'then' and 'with': the same tongue-between-the-teeth position as in 'thin', but switch your voice on so your throat buzzes - 'dhhh'. Hold it briefly. No 'duh'.", ['th'],
    [['th', "Put a hand on your throat: 'this' buzzes, 'thin' does not. Same two letters, same tongue, one is voiced and one is whispered."],
     ['d', "dh keeps the tongue between the teeth; d is a quick tap behind the top teeth."],
     ['v', "dh keeps the tongue between the teeth; v puts the top teeth on the lip."]]),
  u('ng', ['ng'], '/ng/', 'digraph', "The sound at the end of 'ring': the back of the tongue lifts and you hum - 'ng'. It is ONE sound, not 'n' then 'g'.", ['n', 'g'],
    [['n', "n has the tongue tip up; ng uses the back of the tongue."]]),
  u('nk', ['nk'], '/ngk/', 'digraph', "The 'ng' hum followed straight away by a quick /k/, as at the end of 'pink'. Say 'ngk' as one chunk.", ['ng', 'k']),

  // ---------------- Phase 3, Reception Spring 1 ----------------
  u('ai', ['ai'], '/ai/', 'digraph', "The long 'ai' sound as in 'rain' - say 'ay' with a smile. Two letters, one sound. Usually in the middle of a word.", ['nk', 'th-voiced']),
  u('ee', ['ee'], '/ee/', 'digraph', "A long, smiling 'eee' as in 'see'. Two letters, one sound.", undefined,
    [['e', "ee is the long 'eee' sound; the single letter e is the short 'e' of 'egg'."]]),
  u('igh', ['igh'], '/igh/', 'trigraph', "Three letters, one sound: the long 'igh' as in 'high' (the same as the letter name 'I'). The g and h are silent partners.", undefined),
  u('oa', ['oa'], '/oa/', 'digraph', "The long 'oa' sound as in 'boat' - round lips, glide to 'oh'. Two letters, one sound.", undefined),
  u('oo-long', ['oo'], '/oo/ (long)', 'digraph', "A long 'oo' as in 'moon' - lips round and pushed forward. Two letters, one sound.", undefined,
    [['oo-short', "oo makes two sounds: long as in 'moon' and short as in 'book'. Try both and see which makes a real word."]]),
  u('oo-short', ['oo'], '/oo/ (short)', 'digraph', "A short 'oo' as in 'book' - lips only a little rounded, quick and relaxed. The same two letters as 'moon', but shorter.", ['oo-long'],
    [['oo-long', "Same two letters, two sounds. If the long one does not make a real word, try the short one."]]),
  u('ar', ['ar'], '/ar/', 'digraph', "The 'ar' sound as in 'car' - mouth wide open, like at the doctor saying 'aah'. Two letters, one sound.", ['oo-short']),
  u('or', ['or'], '/or/', 'digraph', "The 'or' sound as in 'fork' - round lips, 'or'. Two letters, one sound.", undefined),
  u('ur', ['ur'], '/ur/', 'digraph', "The 'ur' sound as in 'burn' - relaxed lips, a purring 'ur'. Two letters, one sound.", undefined,
    [['er', "ur is the full, stressed sound in 'burn'; er (next) is the short, weak sound at the end of 'letter'."]]),
  u('ow', ['ow'], '/ow/', 'digraph', "The 'ow' sound as in 'cow' - the sound you make when something hurts: 'ow!'. Two letters, one sound.", undefined,
    [['oa', "Later ow can also say /oa/ as in 'snow'. For now it is always the 'cow' sound."]]),
  u('oi', ['oi'], '/oi/', 'digraph', "The 'oi' sound as in 'coin' - start round and glide to 'ee'. Two letters, one sound.", undefined),
  u('ear', ['ear'], '/ear/', 'trigraph', "The 'ear' sound as in 'hear' - glide from 'ee' to a soft 'uh'. Three letters, one sound.", undefined,
    [['air', "ear and air both have three letters but different sounds: 'hear' vs 'hair'."]]),
  u('air', ['air'], '/air/', 'trigraph', "The 'air' sound as in 'hair' - an open 'air' with no trailing 'r' push. Three letters, one sound.", ['ear'],
    [['ear', "'hair' (air) and 'hear' (ear) sound different - listen for the glide in 'hear'."]]),
  u('er', ['er'], '/er/', 'digraph', "The short, weak sound at the end of 'letter' - a light 'uh' with a hint of r. Two letters, one sound. It is quick and not stressed.", ['air', 'ur'],
    [['ur', "er is quick and weak at the end of words (letter); ur is the full 'ur' of burn."]]),

  // ---------------- Phase 4 (consolidation, no new graphemes) ----------------
  u('p4-cvcc', ['nd', 'nt', 'mp', 'st', 'lt', 'lp', 'lk', 'ft', 'sk'], 'adjacent consonants at the end (CVCC)', 'alternative',
    "No new letters. Blend each sound in turn without adding 'uh': h-a-n-d, t-e-n-t. Keep both final consonants crisp.", ['er']),
  u('p4-ccvc', ['fr', 'dr', 'cr', 'sw', 'sl', 'sp', 'tr', 'pl', 'cl', 'fl', 'gl', 'bl', 'sn', 'sm', 'sk'], 'adjacent consonants at the start (CCVC)', 'alternative',
    "No new letters. Two sounds sit side by side at the start: f-r-o-g. Say each one separately and crisply - no 'uh' between them.", ['p4-cvcc']),
  u('p4-long', ['str', 'spl', 'spr', 'scr'], 'longer words and compound words', 'alternative',
    "No new letters. Blend longer words (CCVCC and CCCVC) and compound words (sun + set). Break compounds into two chunks, then say them together.", ['p4-ccvc', 'p4-cvcc']),
  u('p4-suffix', ['ed'], '/t/ /d/ /id/ (-ed) and -ing, -est endings', 'alternative',
    "Endings: -ing is the sounds 'i' + 'ng'; -est is 'e' + 's' + 't'. The ending -ed makes /t/ (jumped), /d/ (played) or /id/ (lifted) - say the word to hear which.", ['p4-long']),

  // ---------------- Phase 5, Year 1 Autumn 1 ----------------
  u('ay', ['ay'], '/ai/', 'digraph', "The long 'ay' sound as in 'day' - the same sound as 'ai'. Two letters, one sound. We usually see ay at the end of a word or syllable.", ['ai', 'p4-suffix'],
    [['ai', "ai and ay say the same sound. ai is usually in the middle (rain); ay at the end (day)."]]),
  u('ou', ['ou'], '/ow/', 'digraph', "The 'ow!' sound as in 'cloud' - the same sound as the ow in 'cow'. Two letters, one sound.", ['ow']),
  u('oy', ['oy'], '/oi/', 'digraph', "The 'oy' sound as in 'boy' - the same sound as 'oi'. Two letters, one sound, usually at the end of a word.", ['oi'],
    [['oi', "oi is in the middle of a word (coin); oy is usually at the end (boy)."]]),
  u('ea', ['ea'], '/ee/', 'digraph', "The long 'eee' sound as in 'sea' - the same as 'ee'. Two letters, one sound.", ['ee'],
    [['ee', "ea and ee can sound the same: 'sea' and 'see'. Look at the whole word to decide."]]),
  // ---------------- Year 1 Autumn 2 ----------------
  u('ir', ['ir'], '/ur/', 'digraph', "The 'ur' sound as in 'girl' - the same as ur. Two letters, one sound.", ['ur'],
    [['ur', "ir and ur say the same sound; look at the word to read it."]]),
  u('ie', ['ie'], '/igh/', 'digraph', "The long 'igh' sound as in 'pie'. Two letters, one sound, usually at the end of a short word.", ['igh']),
  u('ue', ['ue'], '/oo/ or /yoo/', 'digraph', "The 'oo' sound as in 'blue' - and sometimes 'yoo' as in 'cue'. Two letters, one sound.", ['oo-long']),
  u('u-yoo', ['u'], '/yoo/', 'alternative', "The letter u can say 'yoo' as in 'unit' or 'music'. Say it with a quick 'y' then a long 'oo'.", ['ue'],
    [['u', "Short u says /u/ as in 'up'; here u says 'yoo' (unit). Try both."]]),
  u('o-oa', ['o'], '/oa/', 'alternative', "The letter o can say the long 'oa' sound as in 'old' or 'hello'. Try the short sound first, then the long one.", ['oa'],
    [['o', "o can be short (hot) or long (old). If the short sound is not a real word, try the long one."]]),
  u('i-igh', ['i'], '/igh/', 'alternative', "The letter i can say the long 'igh' sound as in 'find' or 'child'. Try the short sound first, then the long one.", ['igh'],
    [['i', "i can be short (tin) or long (find). Try both."]]),
  u('a-ai', ['a'], '/ai/', 'alternative', "The letter a can say the long 'ai' sound as in 'paper' or 'baker'. Try the short sound first, then the long one.", ['ai'],
    [['a', "a can be short (cat) or long (paper). Try both."]]),
  u('e-ee', ['e'], '/ee/', 'alternative', "The letter e can say the long 'eee' sound as in 'even' or 'zero'. Try the short sound first, then the long one.", ['ee'],
    [['e', "e can be short (red) or long (even). Try both."]]),
  u('split-a', ['a_e'], '/ai/', 'split', "A split digraph: a ... e makes the long 'ai' sound, as in 'cake'. The e at the end is silent but changes the a: the 'magic e' is a team with the a, split apart by a consonant.", ['a-ai'],
    [['a', "cap (short a) vs cape (a_e, long ai). The e at the end changes the sound."]]),
  u('split-i', ['i_e'], '/igh/', 'split', "A split digraph: i ... e makes the long 'igh' sound, as in 'bike'. The e is silent but changes the i.", ['split-a', 'i-igh'],
    [['i', "bit (short i) vs bite (i_e, long igh)."]]),
  u('split-o', ['o_e'], '/oa/', 'split', "A split digraph: o ... e makes the long 'oa' sound, as in 'home'.", ['split-i', 'o-oa'],
    [['o', "hop (short o) vs hope (o_e, long oa)."]]),
  u('split-u', ['u_e'], '/oo/ or /yoo/', 'split', "A split digraph: u ... e makes 'oo' or 'yoo', as in 'rule' and 'cube'.", ['split-o', 'ue'],
    [['u', "cub (short u) vs cube (u_e, long)."]]),
  u('split-e', ['e_e'], '/ee/', 'split', "A split digraph: e ... e makes the long 'eee' sound, as in 'these'.", ['split-u', 'e-ee'],
    [['e', "pet (short e) vs Pete (e_e, long ee)."]]),
  u('ew', ['ew'], '/oo/ or /yoo/', 'digraph', "The 'oo' sound as in 'grew' and 'yoo' as in 'few'. Two letters, one sound, usually at the end of a word.", ['ue']),
  u('ie-ee', ['ie'], '/ee/', 'alternative', "The letters ie can also say a long 'eee' as in 'field' and 'chief'. Try 'igh' first, then 'eee'.", ['ie', 'ee'],
    [['ie', "ie says 'igh' in 'pie' but 'ee' in 'field'."]]),
  u('aw', ['aw'], '/or/', 'digraph', "The 'or' sound as in 'saw' - the same as 'or'. Two letters, one sound, usually at the end of a word or before n/l.", ['or']),
  // ---------------- Year 1 Spring 1 ----------------
  u('wh', ['wh'], '/w/', 'digraph', "The 'w' sound, as in 'wheel'. Two letters, one sound - round your lips, no extra puff.", ['w', 'th'],
    [['w', "wh and w say the same sound in most accents."]]),
  u('oe', ['oe'], '/oa/', 'digraph', "The long 'oa' sound as in 'toe'. Two letters, one sound.", ['oa']),
  u('ou-oa', ['ou'], '/oa/', 'alternative', "The letters ou can say the long 'oa' sound too, as in 'shoulder'. Try the 'ow' sound first, then 'oa'.", ['ou', 'oa'],
    [['ou', "ou says 'ow' in 'cloud' and 'oa' in 'shoulder'."]]),
  u('ph', ['ph'], '/f/', 'digraph', "The 'f' sound as in 'phone'. Two letters, one sound - top teeth on the lip, blow.", ['f', 'sh'],
    [['f', "ph says the same /f/ sound as f."]]),
  u('au', ['au'], '/or/', 'digraph', "The 'or' sound as in 'launch' - the same as 'or'. Two letters, one sound.", ['aw']),
  u('ey', ['ey'], '/ee/', 'digraph', "The 'eee' sound at the end of a word as in 'key' and 'valley'. Two letters, one sound.", ['ee', 'ie-ee']),
  // ---------------- Year 1 Spring 2 / Summer ----------------
  u('ow-oa', ['ow'], '/oa/', 'alternative', "The letters ow can say the long 'oa' sound as in 'snow' and 'window'. Try 'ow!' (cow) first, then 'oa'.", ['ow', 'oa'],
    [['ow', "ow says 'ow' in 'cow' but 'oa' in 'snow'. Read the word both ways to find the real one."]]),
  u('ea-e', ['ea'], '/e/', 'alternative', "The letters ea can say a short 'e' as in 'head' and 'bread'. Try the long 'ee' first, then the short 'e'.", ['ea', 'e'],
    [['ea', "ea says 'ee' in 'sea' but 'e' in 'head'."]]),
  u('y-igh', ['y'], '/igh/', 'alternative', "At the end of a short word y can say the long 'igh' sound as in 'fly' and 'cry'.", ['igh'],
    [['y', "y is a consonant at the start (yes), but the 'igh' sound at the end of short words (fly)."]]),
  u('y-ee', ['y'], '/ee/', 'alternative', "At the end of a longer word y can say a long 'eee' as in 'happy' and 'funny'.", ['ee', 'y-igh'],
    [['y-igh', "y at the end of a short word says 'igh' (fly); at the end of a longer word it says 'ee' (happy)."]]),
  u('c-s', ['c'], '/s/', 'alternative', "Before e, i or y the letter c can say /s/ as in 'city', 'cent' and 'face'. A soft, quiet hiss.", ['c', 'ss'],
    [['c', "c says /k/ before a, o, u (cat) and /s/ before e, i, y (city)."]]),
  u('g-j', ['g'], '/j/', 'alternative', "Before e, i or y the letter g can say /j/ as in 'gem', 'giant' and 'page'. A quick voiced 'j'.", ['g', 'j'],
    [['g', "g says /g/ in 'got' but /j/ in 'gem'. Not every ge/gi word follows this rule, so check it makes a real word."]]),
  u('dge', ['dge'], '/j/', 'trigraph', "Three letters, one /j/ sound after a short vowel, as in 'bridge' and 'badge'. The d is silent.", ['g-j', 'j']),
  u('tch', ['tch'], '/ch/', 'trigraph', "Three letters, one /ch/ sound after a short vowel, as in 'catch' and 'match'.", ['ch']),
  u('kn', ['kn'], '/n/', 'digraph', "Two letters, one /n/ sound. The k is silent: 'knee', 'knit', 'knock'.", ['n']),
  u('wr', ['wr'], '/r/', 'digraph', "Two letters, one /r/ sound. The w is silent: 'write', 'wrap', 'wren'.", ['r']),
  u('mb', ['mb'], '/m/', 'digraph', "Two letters, one /m/ sound at the end of a word. The b is silent: 'lamb', 'thumb', 'climb'.", ['m']),
  u('gn', ['gn'], '/n/', 'digraph', "Two letters, one /n/ sound. The g is silent: 'gnat', 'gnaw', 'sign'.", ['kn', 'n']),
  u('ch-k', ['ch'], '/k/', 'alternative', "The letters ch can say /k/ in some words, as in 'school', 'echo' and 'ache'.", ['ch', 'k'],
    [['ch', "ch says /ch/ in 'chip' but /k/ in 'school'."]]),
  u('ch-sh', ['ch'], '/sh/', 'alternative', "The letters ch can say /sh/ in some words (mostly from French) as in 'chef' and 'machine'.", ['ch', 'sh'],
    [['ch', "ch says /ch/ in 'chip' but /sh/ in 'chef'."]]),
  u('a-o', ['a'], '/o/', 'alternative', "After the letter w the letter a often says a short /o/ sound as in 'wash', 'swan' and 'wasp'.", ['a', 'w'],
    [['a', "a says /a/ in 'cat' but /o/ after w in 'swan'."]]),
  u('or-ur', ['or'], '/ur/', 'alternative', "After the letter w the letters or often say /ur/ as in 'word', 'work' and 'world'.", ['or', 'ur'],
    [['or', "or says /or/ in 'fork' but /ur/ after w in 'word'."]]),
  u('ture', ['ture'], '/cher/', 'alternative', "The ending -ture says 'cher', as in 'picture' and 'nature'. A quick, light ending.", ['ch-sh', 'er']),
  u('tion-sion', ['tion', 'sion'], '/shun/ or /zhun/', 'alternative', "The endings -tion and -sion say 'shun' (station) or 'zhun' (television). They are quick, light endings.", ['sh', 'ture']),
];

/** Term label per 1-based order (inferred week split; term level is search-corroborated per docs/curriculum-map.md). */
export function termFor(rawOrder: number): string {
  // The voiced-th unit (order 35) shares the unvoiced-th week; later orders are shifted by one.
  const order = rawOrder >= 35 ? rawOrder - 1 : rawOrder;
  if (order <= 4) return 'Reception Autumn 1, week 1';
  if (order <= 8) return 'Reception Autumn 1, week 2';
  if (order <= 12) return 'Reception Autumn 1, week 3';
  if (order <= 16) return 'Reception Autumn 1, week 4';
  if (order <= 20) return 'Reception Autumn 1, week 5';
  if (order <= 23) return 'Reception Autumn 2, week 1';
  if (order <= 27) return 'Reception Autumn 2, week 2';
  if (order <= 31) return 'Reception Autumn 2, week 3';
  if (order <= 36) return 'Reception Autumn 2, week 4';
  if (order <= 40) return 'Reception Spring 1, week 1';
  if (order <= 44) return 'Reception Spring 1, week 2';
  if (order <= 48) return 'Reception Spring 1, week 3';
  if (order <= 50) return 'Reception Spring 1, week 4';
  if (order <= 52) return 'Reception Spring 2';
  if (order <= 54) return 'Reception Summer 1';
  if (order <= 58) return 'Year 1 Autumn 1';
  if (order <= 74) return 'Year 1 Autumn 2';
  if (order <= 78) return 'Year 1 Spring 1';
  if (order <= 80) return 'Year 1 Spring 2';
  return 'Year 1 Spring 2 / Summer (placement inferred)';
}
