export const statuses = ['pending', 'inProgress', 'inReview', 'done', 'blocked'];
const timestampPattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/;
const nonempty = (value) => typeof value === 'string' && value.trim().length > 0;
const timestamp = (value) => timestampPattern.test(value) && Number.isFinite(Date.parse(value));
export const safePath = (value) => nonempty(value) && !value.startsWith('/') && !value.split('/').includes('..') && !/[\\:?#\x00-\x1f]/.test(value);

export function validateTasks(data) {
  const errors = [];
  const require = (condition, message) => { if (!condition) errors.push(message); };
  require(data?.schemaVersion === 1, 'schemaVersion must be 1');
  require(timestamp(data?.updatedAt), 'updatedAt must be an RFC 3339 UTC timestamp ending in Z');
  require(nonempty(data?.project?.name), 'project.name is required');
  require(nonempty(data?.project?.description), 'project.description is required');
  try { new Intl.DateTimeFormat('zh-CN', { timeZone: data?.project?.timezone }).format(); } catch { errors.push('project.timezone must be an IANA time zone'); }
  require(nonempty(data?.project?.timezone), 'project.timezone is required');
  require(Array.isArray(data?.sourceDocuments), 'sourceDocuments must be an array');
  require(Array.isArray(data?.milestones), 'milestones must be an array');
  require(Array.isArray(data?.tasks), 'tasks must be an array');
  if (!Array.isArray(data?.tasks) || !Array.isArray(data?.milestones)) return errors;
  const taskIds = new Set();
  const milestoneIds = new Set();
  for (const milestone of data.milestones) {
    require(nonempty(milestone.id), 'milestone.id is required');
    require(!milestoneIds.has(milestone.id), `duplicate milestone ${milestone.id}`);
    milestoneIds.add(milestone.id);
    require(nonempty(milestone.title) && nonempty(milestone.description), `${milestone.id}: title and description required`);
    require(Array.isArray(milestone.taskIds), `${milestone.id}: taskIds must be an array`);
  }
  for (const task of data.tasks) {
    require(/^T\d{2,}$/.test(task.id), 'task.id must use the T01 format');
    require(!taskIds.has(task.id), `duplicate task ${task.id}`);
    taskIds.add(task.id);
    for (const field of ['title', 'area', 'summary', 'scope', 'nextAction']) require(nonempty(task[field]), `${task.id}: ${field} required`);
    require(['P0', 'P1', 'P2'].includes(task.priority), `${task.id}: invalid priority`);
    require(statuses.includes(task.status), `${task.id}: invalid status`);
    require(milestoneIds.has(task.milestone), `${task.id}: unknown milestone`);
    require(timestamp(task.updatedAt), `${task.id}: invalid updatedAt`);
    require(Date.parse(task.updatedAt) <= Date.parse(data.updatedAt), `${task.id}: updatedAt is newer than report updatedAt`);
    for (const field of ['steps','dependencies','relatedTasks','acceptanceCriteria','deliverables','evidence','blockers','history']) require(Array.isArray(task[field]), `${task.id}: ${field} must be an array`);
    for (const field of ['steps', 'blockers']) if (Array.isArray(task[field])) require(task[field].every(nonempty), `${task.id}: ${field} must contain strings`);
    const criterionIds = new Set();
    for (const criterion of task.acceptanceCriteria || []) {
      require(nonempty(criterion.id) && !criterionIds.has(criterion.id), `${task.id}: duplicate / missing criterion ID`);
      criterionIds.add(criterion.id);
      require(nonempty(criterion.text) && typeof criterion.done === 'boolean', `${task.id}: invalid acceptance criterion`);
    }
    let previousTime = -Infinity;
    for (const entry of task.history || []) {
      require(timestamp(entry.at) && statuses.includes(entry.status) && nonempty(entry.note), `${task.id}: invalid history entry`);
      require(Date.parse(entry.at) >= previousTime && Date.parse(entry.at) <= Date.parse(task.updatedAt), `${task.id}: history must be chronological and not newer than updatedAt`);
      previousTime = Date.parse(entry.at);
    }
    require(task.history?.length > 0, `${task.id}: history is required`);
    const last = task.history?.at(-1);
    if (last) require(last.status === task.status, `${task.id}: latest history status disagrees with current status`);
    if (task.status === 'done') {
      require(task.acceptanceCriteria?.length > 0 && task.acceptanceCriteria.every((item) => item.done), `${task.id}: done requires all acceptance criteria checked`);
      require(task.evidence?.length > 0, `${task.id}: done requires evidence`);
      require(task.blockers?.length === 0, `${task.id}: done cannot have unresolved blockers`);
    }
    if (task.status === 'blocked') require(task.blockers?.length > 0, `${task.id}: blocked requires a blocker explanation`);
  }
  for (const task of data.tasks) {
    for (const ref of [...(task.dependencies || []), ...(task.relatedTasks || [])]) require(taskIds.has(ref) && ref !== task.id, `${task.id}: unknown / self dependency ${ref}`);
    const milestone = data.milestones.find((item) => item.id === task.milestone);
    if (milestone) require(milestone.taskIds?.includes(task.id), `${task.id}: missing from milestone taskIds`);
  }
  for (const milestone of data.milestones) {
    require(new Set(milestone.taskIds).size === milestone.taskIds?.length, `${milestone.id}: duplicate taskIds`);
    for (const id of milestone.taskIds || []) require(data.tasks.some((item) => item.id === id && item.milestone === milestone.id), `${milestone.id}: invalid task ${id}`);
  }
  const visited = new Set(); const active = new Set();
  function visit(id) {
    if (active.has(id)) { errors.push(`dependency cycle at ${id}`); return; }
    if (visited.has(id)) return;
    active.add(id);
    const task = data.tasks.find((item) => item.id === id);
    for (const dependency of task?.dependencies || []) if (taskIds.has(dependency)) visit(dependency);
    active.delete(id); visited.add(id);
  }
  data.tasks.forEach((task) => visit(task.id));
  const refs = [...(data.sourceDocuments || []), ...data.tasks.flatMap((task) => [...(task.deliverables || []), ...(task.evidence || [])])];
  for (const ref of refs) {
    require(nonempty(ref.label), 'document / evidence label required');
    if (ref.path !== undefined) require(safePath(ref.path), `unsafe document path: ${ref.path}`);
  }
  return errors;
}
