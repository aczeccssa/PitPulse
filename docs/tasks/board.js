import { validateTasks } from "./task-schema.mjs";

const STATUS = {
  pending: { label: "待开始", className: "status-pending" },
  inProgress: { label: "进行中", className: "status-inProgress" },
  inReview: { label: "待验收", className: "status-inReview" },
  done: { label: "完成", className: "status-done" },
  blocked: { label: "受阻", className: "status-blocked" },
};
const FILTERS = [
  { id: "all", label: "全部" },
  { id: "pending", label: "待开始" },
  { id: "inProgress", label: "进行中" },
  { id: "inReview", label: "待验收" },
  { id: "done", label: "完成" },
  { id: "blocked", label: "受阻" },
];
const state = { data: null, status: "all", milestone: "all", query: "" };
const $ = (id) => document.getElementById(id);

function node(tag, className, text) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (text !== undefined) element.textContent = text;
  return element;
}
function formatDate(value, options = {}) {
  if (!value) return "未记录时间";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "时间格式无效";
  return new Intl.DateTimeFormat("zh-CN", {
    timeZone: state.data?.project?.timezone || "Asia/Shanghai",
    year: "numeric", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", ...options,
  }).format(date);
}
function taskCounts(tasks) {
  const counts = Object.fromEntries(Object.keys(STATUS).map((id) => [id, 0]));
  tasks.forEach((task) => { if (Object.hasOwn(counts, task.status)) counts[task.status] += 1; });
  return counts;
}
function renderOverview() {
  const tasks = state.data.tasks;
  const counts = taskCounts(tasks);
  const complete = counts.done;
  const percent = tasks.length ? Math.round((complete / tasks.length) * 100) : 0;
  $("completion-value").textContent = `${percent}%`;
  $("completion-count").textContent = `${complete} / ${tasks.length} 完成`;
  $("completion-bar").style.width = `${percent}%`;
  $("total-count").textContent = tasks.length;
  $("active-count").textContent = counts.inProgress;
  $("pending-count").textContent = counts.pending;
  $("blocked-count").textContent = counts.blocked;
  $("status-tabs").replaceChildren(...FILTERS.map((filter) => {
    const button = node("button", "status-tab");
    button.type = "button";
    button.dataset.status = filter.id;
    button.setAttribute("aria-pressed", String(state.status === filter.id));
    button.append(document.createTextNode(filter.label));
    const count = filter.id === "all" ? tasks.length : counts[filter.id];
    button.append(node("small", "", String(count)));
    return button;
  }));
}
function renderMilestones() {
  const select = $("milestone-filter");
  const selected = state.milestone;
  select.replaceChildren(new Option("全部里程碑", "all"));
  state.data.milestones.forEach((milestone) => {
    select.add(new Option(`${milestone.id} · ${milestone.title}`, milestone.id));
  });
  select.value = selected;
  $("milestones").replaceChildren(...state.data.milestones.map((milestone) => {
    const tasks = state.data.tasks.filter((task) => task.milestone === milestone.id);
    const counts = taskCounts(tasks);
    const button = node("button", "milestone");
    button.type = "button";
    button.dataset.milestone = milestone.id;
    button.setAttribute("aria-pressed", String(selected === milestone.id));
    const kicker = node("span", "milestone-kicker");
    kicker.append(node("span", "", milestone.id), node("span", "", `${counts.done}/${tasks.length} 完成`));
    button.append(kicker, node("h3", "", milestone.title), node("p", "", milestone.description));
    return button;
  }));
}
function appendSection(parent, title, content) {
  if (!content || (Array.isArray(content) && content.length === 0)) return;
  parent.append(node("h4", "", title));
  if (Array.isArray(content)) {
    const list = node("ul");
    content.forEach((item) => {
      const text = typeof item === "string" ? item : item.label || item.text || item.note || JSON.stringify(item);
      list.append(node("li", "", text));
    });
    parent.append(list);
  } else {
    parent.append(node("p", "", content));
  }
}
function appendRefs(parent, title, refs) {
  if (!refs?.length) return;
  parent.append(node("h4", "", title));
  const container = node("div");
  refs.forEach((ref) => {
    const anchor = node("a", "task-ref", ref.label || ref.path);
    anchor.href = `../../${ref.path}`;
    container.append(anchor);
  });
  parent.append(container);
}
function renderDetails(task) {
  const details = node("div", "task-details");
  const body = node("div", "detail-body");
  details.append(body);
  appendSection(body, "任务说明", task.scope);
  appendSection(body, "执行步骤", task.steps);
  if (task.acceptanceCriteria?.length) {
    body.append(node("h4", "", "验收标准"));
    const list = node("ul", "criteria-list");
    task.acceptanceCriteria.forEach((criterion) => {
      const item = node("li");
      item.append(node("span", "check-mark", criterion.done ? "✓" : "○"), node("span", "", criterion.text));
      list.append(item);
    });
    body.append(list);
  }
  if (task.dependencies?.length) {
    body.append(node("h4", "", "前置任务"));
    body.append(node("p", "", task.dependencies.join(" · ")));
  }
  if (task.relatedTasks?.length) {
    body.append(node("h4", "", "关联任务"));
    body.append(node("p", "", task.relatedTasks.join(" · ")));
  }
  appendSection(body, "交付物", task.deliverables);
  appendSection(body, "验证证据", task.evidence);
  if (task.blockers?.length) {
    body.append(node("h4", "", "待处理 / 阻塞"));
    const list = node("ul");
    task.blockers.forEach((text) => list.append(node("li", "blocker-note", text)));
    body.append(list);
  }
  if (task.history?.length) {
    body.append(node("h4", "", "状态记录"));
    const list = node("ul", "history");
    task.history.slice().reverse().forEach((entry) => {
      const status = STATUS[entry.status]?.label || entry.status;
      const item = node("li");
      item.append(node("time", "", `${formatDate(entry.at)} · ${status} · `), document.createTextNode(entry.note || "状态已更新"));
      list.append(item);
    });
    body.append(list);
  }
  appendRefs(body, "任务相关文档", task.deliverables?.filter((item) => item.path));
  return details;
}
function createCard(task) {
  const article = node("article", "task-card");
  article.dataset.status = task.status;
  const main = node("div", "card-main");
  const top = node("div", "card-top");
  const identity = node("span", "task-id", task.id);
  identity.append(node("span", "priority", task.priority));
  const badge = node("span", `status-badge ${STATUS[task.status]?.className || ""}`, STATUS[task.status]?.label || task.status);
  top.append(identity, badge);
  const title = node("h3", "", task.title);
  const summary = node("p", "summary", task.summary);
  const meta = node("div", "card-meta");
  meta.append(node("span", "", task.milestone), node("span", "", task.area));
  const totalCriteria = task.acceptanceCriteria?.length || 0;
  const checkedCriteria = task.acceptanceCriteria?.filter((item) => item.done).length || 0;
  const checks = node("div", "card-checks", totalCriteria ? `验收项 ${checkedCriteria} / ${totalCriteria}` : "尚无验收记录");
  main.append(top, title, summary, meta, checks);
  const footer = node("div", "card-footer");
  footer.append(node("span", "", `下一步 · ${task.nextAction}`), node("time", "", formatDate(task.updatedAt, { hour: undefined, minute: undefined })));
  article.append(main, footer);
  article.tabIndex = 0;
  article.setAttribute("role", "button");
  article.setAttribute("aria-haspopup", "dialog");
  article.setAttribute("aria-label", `打开 ${task.id} ${task.title} 详情`);
  article.dataset.taskId = task.id;
  return article;
}
function filteredTasks() {
  const query = state.query.trim().toLocaleLowerCase("zh-CN");
  return state.data.tasks.filter((task) => {
    if (state.status !== "all" && task.status !== state.status) return false;
    if (state.milestone !== "all" && task.milestone !== state.milestone) return false;
    if (!query) return true;
    const haystack = [task.id, task.title, task.summary, task.area, task.milestone, task.scope, task.nextAction, ...(task.steps || []), ...(task.blockers || [])].join(" ").toLocaleLowerCase("zh-CN");
    return haystack.includes(query);
  });
}
function openModal(task) {
  const modal = $("task-modal");
  modal.hidden = false;
  document.body.classList.add("modal-open");
  $("modal-id").replaceChildren(node("span", "", task.id), node("span", "priority", task.priority));
  $("modal-title").textContent = task.title;
  const badge = $("modal-status");
  badge.textContent = STATUS[task.status]?.label || task.status;
  badge.className = `status-badge ${STATUS[task.status]?.className || ""}`;
  $("modal-body").replaceChildren(renderDetails(task));
  const meta = $("modal-meta");
  meta.replaceChildren();
  meta.append(node("span", "", `${task.milestone} · ${task.area} · 更新 ${formatDate(task.updatedAt)}`));
  modal.dataset.modalTaskId = task.id;
  $("modal-close").focus();
}
function closeModal() {
  const modal = $("task-modal");
  if (modal.hidden) return;
  modal.hidden = true;
  document.body.classList.remove("modal-open");
  const trigger = document.querySelector(`#task-list [data-task-id="${modal.dataset.modalTaskId}"]`);
  modal.removeAttribute("data-modal-task-id");
  trigger?.focus();
}
$("task-modal").addEventListener("click", (event) => {
  if (event.target === event.currentTarget || event.target.closest("#modal-close, #modal-dismiss")) closeModal();
});
document.addEventListener("keydown", (event) => {
  if ($("task-modal").hidden || event.key !== "Escape") return;
  closeModal();
});
function renderTasks() {
  const tasks = filteredTasks();
  $("visible-count").textContent = String(tasks.length);
  $("task-list").replaceChildren(...tasks.map(createCard));
  $("empty-state").hidden = tasks.length > 0;
  $("clear-filters").hidden = state.status === "all" && state.milestone === "all" && !state.query;
  $("status-tabs").querySelectorAll("button").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.status === state.status)));
  $("milestones").querySelectorAll("button").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.milestone === state.milestone)));
}
$("task-list").addEventListener("click", (event) => {
  const card = event.target.closest("[data-task-id]");
  if (!card) return;
  const task = state.data.tasks.find((item) => item.id === card.dataset.taskId);
  if (task) openModal(task);
});
$("task-list").addEventListener("keydown", (event) => {
  if (!["Enter", " "].includes(event.key)) return;
  const card = event.target.closest("[data-task-id]");
  if (!card) return;
  event.preventDefault();
  const task = state.data.tasks.find((item) => item.id === card.dataset.taskId);
  if (task) openModal(task);
});
function render() {
  const { project } = state.data;
  document.title = `${project.name} · 任务状态`;
  $("project-description").textContent = project.description;
  $("updated-at").textContent = `数据更新 · ${formatDate(state.data.updatedAt)}`;
  $("footer-date").textContent = new Intl.DateTimeFormat("zh-CN", { timeZone: project.timezone, year: "numeric", month: "long", day: "numeric" }).format(new Date());
  $("load-clock").textContent = `时区 ${project.timezone} · 任务状态仅由 JSON 驱动`;
  $("source-links").replaceChildren(...state.data.sourceDocuments.map((source) => {
    const link = node("a", "", source.label);
    link.href = `../../${source.path}`;
    return link;
  }));
  renderOverview();
  renderMilestones();
  renderTasks();
  $("workspace").hidden = false;
  $("load-error").hidden = true;
}
function validate(data) {
  const errors = validateTasks(data);
  if (errors.length) throw new Error(`任务 JSON 校验失败：${errors.slice(0, 3).join("；")}`);
  return data;
}
async function loadData() {
  const refresh = $("refresh");
  refresh.disabled = true;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10000);
  $("load-status").textContent = "正在重新读取任务 JSON";
  try {
    const response = await fetch(`tasks.json?reload=${Date.now()}`, { cache: "no-store", signal: controller.signal });
    if (!response.ok) throw new Error(`读取 tasks.json 失败（HTTP ${response.status}）。`);
    state.data = validate(await response.json());
    render();
    $("load-status").textContent = `已加载 ${state.data.tasks.length} 项任务`;
  } catch (error) {
    const panel = $("load-error");
    const message = error.name === "AbortError" ? "读取任务数据超时，请检查静态服务器后重试。" : error.message;
    const guidance = location.protocol === "file:"
      ? "请在仓库根目录执行 python3 -m http.server 8765 --bind 127.0.0.1，再通过 http://127.0.0.1:8765/docs/tasks/ 打开；file:// 页面无法可靠读取 JSON。"
      : "请检查同目录的 tasks.json 文件、JSON 格式和任务字段，再点击刷新数据。";
    panel.replaceChildren(node("strong", "", "无法加载任务数据"), node("p", "", message), node("p", "", guidance));
    if (state.data) panel.append(node("p", "", "下面保留的是上一次成功读取的数据，尚未反映本次更新。"));
    panel.hidden = false;
    $("load-status").textContent = error.message;
  } finally {
    clearTimeout(timeout);
    refresh.disabled = false;
  }
}
$("status-tabs").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-status]");
  if (!button) return;
  state.status = button.dataset.status;
  renderTasks();
});
$("milestones").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-milestone]");
  if (!button) return;
  state.milestone = state.milestone === button.dataset.milestone ? "all" : button.dataset.milestone;
  $("milestone-filter").value = state.milestone;
  renderMilestones();
  renderTasks();
});
$("search").addEventListener("input", (event) => { state.query = event.target.value; renderTasks(); });
$("milestone-filter").addEventListener("change", (event) => {
  state.milestone = event.target.value;
  renderMilestones();
  renderTasks();
});
function resetFilters() {
  state.status = "all"; state.milestone = "all"; state.query = "";
  $("search").value = ""; $("milestone-filter").value = "all";
  renderMilestones(); renderTasks();
}
$("clear-filters").addEventListener("click", resetFilters);
$("reset-empty").addEventListener("click", resetFilters);
/* ---------------------------------------------------------------------------
   主题：三态（auto / light / dark）
   - data-theme 由 index.html 的 head 内联脚本在首帧前写入，这里只负责后续切换。
   - 这里持久化的是「界面外观偏好」，不是任务数据副本；任务状态仍只来自 tasks.json。
   - 只有 auto 模式才跟随系统外观变化。
   --------------------------------------------------------------------------- */
const THEME_KEY = "pitpulse.board.theme";
const THEME_MODES = ["auto", "light", "dark"];
const darkScheme = window.matchMedia("(prefers-color-scheme: dark)");

function readThemeMode() {
  try {
    const saved = localStorage.getItem(THEME_KEY);
    return THEME_MODES.includes(saved) ? saved : "auto";
  } catch {
    return "auto";
  }
}
function applyTheme(mode, persist) {
  const root = document.documentElement;
  const dark = mode === "dark" || (mode === "auto" && darkScheme.matches);
  root.dataset.theme = dark ? "dark" : "light";
  root.dataset.themeMode = mode;
  $("theme-switch").querySelectorAll("button[data-theme-mode]").forEach((button) => {
    button.setAttribute("aria-pressed", String(button.dataset.themeMode === mode));
  });
  if (persist) {
    try { localStorage.setItem(THEME_KEY, mode); } catch { /* storage 不可用时仅本次生效 */ }
  }
}
function syncWithSystemTheme() {
  if (document.documentElement.dataset.themeMode === "auto") applyTheme("auto", false);
}
$("theme-switch").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-theme-mode]");
  if (button) applyTheme(button.dataset.themeMode, true);
});
if (darkScheme.addEventListener) darkScheme.addEventListener("change", syncWithSystemTheme);
else darkScheme.addListener(syncWithSystemTheme);
applyTheme(readThemeMode(), false);

$("refresh").addEventListener("click", loadData);
loadData();
