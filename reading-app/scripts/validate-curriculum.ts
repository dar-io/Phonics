/**
 * CLI: validate the shipped curriculum + audio manifest and print a coverage table.
 * Usage: npx tsx scripts/validate-curriculum.ts      (exit code 1 on any problem)
 */
import { curriculum } from '../src/curriculum/load';
import { coverage, unitCoverage, validateCurriculum } from '../src/curriculum/validate';

declare const process: { exitCode?: number };

const problems = validateCurriculum(curriculum);
const rows = coverage(curriculum);
const pad = (s: string | number, n: number): string => String(s).padEnd(n);

console.log(`Story Sounds curriculum v${curriculum.contentVersion} (schema ${curriculum.schemaVersion})`);
console.log(`${pad('Stage', 20)}${pad('Units', 7)}${pad('Words', 7)}${pad('Sentences', 11)}Stories`);
for (const r of rows) console.log(`${pad(r.label, 20)}${pad(r.units, 7)}${pad(r.words, 7)}${pad(r.sentences, 11)}${r.stories}`);
const total = rows.reduce((a, r) => ({ units: a.units + r.units, words: a.words + r.words, sentences: a.sentences + r.sentences, stories: a.stories + r.stories }), { units: 0, words: 0, sentences: 0, stories: 0 });
console.log(`${pad('Total', 20)}${pad(total.units, 7)}${pad(total.words, 7)}${pad(total.sentences, 11)}${total.stories}   (+ ${curriculum.trickyWords.length} tricky words)`);

const gaps = unitCoverage(curriculum).filter((u) => u.words < 3 || (u.unit.order > 8 && u.sentences === 0 && u.unit.phase <= 4));
if (gaps.length) {
  console.log('\nCoverage notes (not errors): units whose own new content is thin');
  for (const g of gaps) console.log(`  #${g.unit.order} ${g.unit.id}: ${g.words} word(s), ${g.sentences} sentence(s) unlock here`);
}

if (problems.length) {
  console.error(`\n${problems.length} problem(s):`);
  for (const p of problems.slice(0, 200)) console.error(`  - ${p}`);
  process.exitCode = 1;
} else {
  console.log('\nOK: curriculum is valid (0 problems).');
}
