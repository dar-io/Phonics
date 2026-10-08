/**
 * CLI: pronunciation / segmentation audit (pedagogy review M7).
 * Usage: npx tsx scripts/audit-curriculum.ts [--verbose]     (exit code 1 when any unresolved error remains)
 */
import { curriculum } from '../src/curriculum/load';
import { auditCurriculum } from '../src/curriculum/audit';

declare const process: { exitCode?: number; argv: string[] };

const findings = auditCurriculum(curriculum);
const verbose = process.argv.includes('--verbose');
const errors = findings.filter((f) => f.level === 'error');
const info = findings.filter((f) => f.level === 'info');

console.log(`Pronunciation audit: ${errors.length} unresolved, ${info.length} reviewed/gated note(s)`);
if (errors.length) {
  console.log('\nUNRESOLVED (fix, gate, make tricky, or allowlist with a reason in src/curriculum/audit.ts):');
  for (const f of errors) console.log(`  [${f.rule}] ${f.word}: ${f.detail}`);
}
const byRule = new Map<string, string[]>();
for (const f of info) byRule.set(f.rule, [...(byRule.get(f.rule) ?? []), f.word]);
console.log('\nReviewed / correctly gated (info):');
for (const [rule, words] of byRule) console.log(`  ${rule}: ${verbose ? [...new Set(words)].join(', ') : `${new Set(words).size} word(s)`}`);
if (errors.length) process.exitCode = 1;
else console.log('\nOK: no unresolved pronunciation or segmentation findings.');
