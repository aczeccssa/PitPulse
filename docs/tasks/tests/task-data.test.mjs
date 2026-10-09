import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { validateTasks } from '../validate.mjs';
const data = JSON.parse(readFileSync(new URL('../tasks.json', import.meta.url), 'utf8'));
const copy = () => structuredClone(data);

test('all planned tasks have valid status data', () => {
  assert.deepEqual(validateTasks(data), []);
  const plan = readFileSync(new URL('../../../implementation-sequence.md', import.meta.url), 'utf8');
  const ids = [...plan.matchAll(/^### (T\d+) — /gm)].map((match) => match[1]);
  assert.deepEqual(data.tasks.map((task) => task.id), ids);
});
test('duplicate IDs and unknown states are rejected', () => {
  const value = copy(); value.tasks[1].id = value.tasks[0].id; value.tasks[0].status = 'almostDone';
  const errors = validateTasks(value);
  assert.ok(errors.some((error) => error.includes('duplicate task')));
  assert.ok(errors.some((error) => error.includes('invalid status')));
});
test('completion requires checked criteria and evidence', () => {
  const value = copy();
  const task = value.tasks.find((item) => item.status !== 'done');
  task.status = 'done'; task.history.at(-1).status = 'done';
  task.acceptanceCriteria.forEach((item) => { item.done = false; });
  task.evidence = [];
  const errors = validateTasks(value);
  assert.ok(errors.some((error) => error.includes('done requires all')));
  assert.ok(errors.some((error) => error.includes('done requires evidence')));
});
test('blocked state must explain the blocker', () => {
  const value = copy();
  const task = value.tasks.find((item) => item.status !== 'done');
  task.status = 'blocked'; task.history.at(-1).status = 'blocked'; task.blockers = [];
  assert.ok(validateTasks(value).some((error) => error.includes('blocked requires')));
});
test('UTC timestamps and history state consistency are required', () => {
  const value = copy(); value.updatedAt = '2026-10-08';
  const task = value.tasks.find((item) => item.status !== 'done');
  task.history.at(-1).status = 'done';
  const errors = validateTasks(value);
  assert.ok(errors.some((error) => error.includes('RFC 3339')));
  assert.ok(errors.some((error) => error.includes('disagrees')));
});
test('unknown and cyclic dependencies are rejected', () => {
  const value = copy(); value.tasks[0].dependencies = ['T02']; value.tasks[2].relatedTasks = ['T99'];
  const errors = validateTasks(value);
  assert.ok(errors.some((error) => error.includes('dependency cycle')));
  assert.ok(errors.some((error) => error.includes('unknown / self dependency')));
});
test('all document references must stay inside the repository', () => {
  const value = copy(); value.sourceDocuments[0].path = '../secrets.env';
  assert.ok(validateTasks(value).some((error) => error.includes('unsafe document path')));
});
test('milestone membership must match task assignments', () => {
  const value = copy(); value.milestones[0].taskIds.push('T15');
  assert.ok(validateTasks(value).some((error) => error.includes('invalid task T15')));
});
