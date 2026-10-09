import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { validateTasks, safePath } from './task-schema.mjs';
export { validateTasks, statuses } from './task-schema.mjs';

const ownPath = fileURLToPath(import.meta.url);
if (process.argv[1] && resolve(process.argv[1]) === ownPath) {
  try {
    const dataPath = resolve(process.argv[2] || resolve(dirname(ownPath), 'tasks.json'));
    const data = JSON.parse(readFileSync(dataPath, 'utf8'));
    const errors = validateTasks(data);
    const repoRoot = resolve(dirname(ownPath), '../..');
    for (const ref of [...data.sourceDocuments, ...data.tasks.flatMap((task) => [...task.deliverables, ...task.evidence])]) {
      if (ref.path && safePath(ref.path) && !existsSync(resolve(repoRoot, ref.path))) errors.push(`document does not exist: ${ref.path}`);
    }
    if (errors.length) { console.error(errors.join('\n')); process.exitCode = 1; }
    else console.log(`Valid task report: ${data.tasks.length} tasks, ${data.milestones.length} milestones`);
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
