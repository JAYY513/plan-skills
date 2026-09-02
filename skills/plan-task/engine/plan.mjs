#!/usr/bin/env node
/**
 * plan.mjs — plan-skills 单一引擎。
 * 所有 hook 逻辑与任务机械动作（start / finish / status / doctor）都在这里实现，
 * hooks/ 目录下的 sh / ps1 脚本只是调用本文件的薄壳，保证双平台行为永远一致。
 *
 * 约定：
 * - hook 子命令只读状态文件并输出注入文本；唯一写入是节流缓存 .planning/.hook-cache.json。
 *   状态文件（TASKS.md 等）只由 start / finish 子命令写入。
 * - PLANNING_HOOKS_DISABLED=1 → hook 子命令静默 exit 0（doctor / start / finish 不受影响）。
 * - PLANNING_ROOT 显式指定项目根；否则从 CWD 向上探测 ROADMAP.md / TASKS.md / .planning。
 * - PLANNING_HOOKS_NO_THROTTLE=1 → 关闭注入节流（调试 / 测试用）。
 *
 * 退出码：hook 注入类 0；stop-gate 命中阻止 2；命令类错误 1。
 * 需要 Node.js >= 18，零第三方依赖。
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const ENGINE_DIR = path.dirname(fileURLToPath(import.meta.url));
const SKILL_DIR = path.resolve(ENGINE_DIR, '..');

// ── 基础工具 ──────────────────────────────────────────────────

const isDir = (p) => { try { return fs.statSync(p).isDirectory(); } catch { return false; } };
const isFile = (p) => { try { return fs.statSync(p).isFile(); } catch { return false; } };
const read = (p) => { try { return fs.readFileSync(p, 'utf8'); } catch { return null; } };
const sha1 = (s) => crypto.createHash('sha1').update(s, 'utf8').digest('hex');

const out = (...lines) => { for (const l of lines) process.stdout.write(l + '\n'); };

function localDate(offsetDays = 0) {
  const d = new Date(Date.now() + offsetDays * 86400000);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

/** 项目根：PLANNING_ROOT 优先；否则从 CWD 向上找状态标记；找不到返回 null。 */
function findRoot() {
  if (process.env.PLANNING_ROOT) return path.resolve(process.env.PLANNING_ROOT);
  let dir = process.cwd();
  for (;;) {
    if (isFile(path.join(dir, 'ROADMAP.md')) || isFile(path.join(dir, 'TASKS.md')) || isDir(path.join(dir, '.planning'))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

// ── 状态文件解析 ──────────────────────────────────────────────

function loadTasksDoc(root) {
  const file = path.join(root, 'TASKS.md');
  const text = read(file);
  if (text === null) return null;
  return { file, lines: text.split('\n') };
}

function saveTasksDoc(doc) {
  fs.writeFileSync(doc.file, doc.lines.join('\n'));
}

/** TASKS.md 的 `## ` 级分段（name 不含 ## 前缀）。 */
function docSections(doc) {
  const res = [];
  let cur = null;
  doc.lines.forEach((ln, i) => {
    if (/^## /.test(ln)) {
      if (cur) cur.end = i;
      cur = { name: ln.replace(/^## +/, '').trim(), headingIdx: i, start: i + 1, end: doc.lines.length };
      res.push(cur);
    }
  });
  return res;
}

function findSection(doc, namePrefix) {
  return docSections(doc).find((s) => s.name.startsWith(namePrefix)) || null;
}

/** 某分段内的任务块（`### ` 到下一个 ###/## 或段尾）。title 保留 ✅ 等后缀。 */
function tasksInSection(doc, sectionPrefix) {
  const sec = findSection(doc, sectionPrefix);
  if (!sec) return { sec: null, tasks: [] };
  const tasks = [];
  let cur = null;
  for (let i = sec.start; i < sec.end; i++) {
    if (/^### /.test(doc.lines[i])) {
      if (cur) cur.end = i;
      cur = { title: doc.lines[i].replace(/^### */, '').trim(), titleIdx: i, start: i, end: sec.end, section: sec };
      tasks.push(cur);
    }
  }
  return { sec, tasks };
}

/** 任务标题归一化（去 ✅、去空白），用于精确匹配。 */
const normTitle = (t) => t.replace(/✅/g, '').trim();

/** 任务块内取字段行值：`- 开始：2026-01-01` → `2026-01-01`。 */
function taskField(doc, task, fieldRe) {
  for (let i = task.start + 1; i < task.end; i++) {
    const m = doc.lines[i].match(fieldRe);
    // 取最后一个捕获组：字段正则里组 1 可能是可选后缀（如「开始(日期)?」），值永远在末组
    if (m) return m[m.length - 1].trim();
  }
  return null;
}
const RE_START_DATE = /^-\s*\**开始(日期)?\**\s*[:：]\s*(.+)$/;
const RE_DONE_DATE = /^-\s*\**完成(日期)?\**\s*[:：]\s*(.+)$/;
const RE_WORKSPACE = /^-\s*\**工作区\**\s*[:：]\s*(.+)$/;

/** 任务块尾部插入位置：最后一个非空行之后。 */
function findBlockTail(doc, task) {
  let end = task.end;
  while (end > task.start + 1 && doc.lines[end - 1].trim() === '') end--;
  return end;
}

/** 摘出任务块行（去掉尾部空行）。 */
function blockLines(doc, task) {
  const block = doc.lines.slice(task.start, task.end);
  while (block.length && block[block.length - 1].trim() === '') block.pop();
  return block;
}

/** 删除任务块（顺带吞掉紧随的一个分隔空行，避免留双空行）。 */
function removeBlock(doc, task) {
  const block = blockLines(doc, task);
  let delEnd = task.start + block.length;
  if (delEnd < doc.lines.length && doc.lines[delEnd].trim() === '') delEnd++;
  doc.lines.splice(task.start, delEnd - task.start);
  return block;
}

/** 把任务块插入某分段末尾，自动补空行分隔。 */
function insertBlock(doc, sectionPrefix, block) {
  const sec = findSection(doc, sectionPrefix);
  if (!sec) throw new Error(`TASKS.md 缺少「${sectionPrefix}」段`);
  let idx = sec.end;
  while (idx > sec.headingIdx + 1 && doc.lines[idx - 1].trim() === '') idx--;
  const ins = [...block];
  if (doc.lines[idx - 1] !== undefined && doc.lines[idx - 1].trim() !== '') ins.unshift('');
  if (idx < doc.lines.length && doc.lines[idx].trim() !== '') ins.push('');
  doc.lines.splice(idx, 0, ...ins);
}

/** ROADMAP.md 当前里程碑（首个 `## ▶` 行，去掉 # 前缀），无则 null。 */
function currentMilestone(root) {
  const text = read(path.join(root, 'ROADMAP.md'));
  if (text === null) return null;
  const ln = text.split('\n').find((l) => /^## *▶/.test(l));
  return ln ? ln.replace(/^#* */, '') : null;
}

/**
 * SPEC.md 红线解析：「不做什么（边界）」的条目 + 「技术选型」表的「决策 = 选择」。
 * 供 session-start 作执行期护栏注入，防隐式漂移（做着做着违背边界 / 选型）；只读不改 SPEC。
 * 跳过 HTML 注释（模板占位说明）与未填充的模板示例行，避免刚建好的空模板产生噪音。
 * 返回 { boundary: string[], tech: string[] }，无 SPEC 或无内容则对应数组为空。
 */
function specRedlines(root) {
  const res = { boundary: [], tech: [] };
  const text = read(path.join(root, 'SPEC.md'));
  if (text === null) return res;
  let section = null;
  for (const ln of text.split('\n')) {
    if (/^##\s/.test(ln)) {
      if (/不做什么|边界/.test(ln)) section = 'boundary';
      else if (/技术选型/.test(ln)) section = 'tech';
      else section = null;
      continue;
    }
    if (!section || /^\s*<!--/.test(ln)) continue;
    if (section === 'boundary') {
      const m = ln.match(/^\s*[-*]\s+(.+?)\s*$/);
      if (m) res.boundary.push(m[1]);
    } else {
      if (!/^\s*\|/.test(ln)) continue;
      const cells = ln.split('|').map((c) => c.trim()).filter((c) => c !== '');
      if (cells.length < 2) continue;
      if (cells.every((c) => /^:?-+:?$/.test(c))) continue; // 表格分隔行
      if (cells[0] === '决策' || cells[0].startsWith('示例')) continue; // 表头 / 模板示例行
      if (cells.some((c) => /YYYY-MM-DD|^xxx$|^<.*>$/.test(c))) continue; // 未填充占位符
      res.tech.push(`${cells[0]} = ${cells[1]}`);
    }
  }
  return res;
}

/** .planning/ 下活跃工作区目录名（排除 done/，字母序，与 shell glob 一致）。 */
function activeWorkspaces(root) {
  const dir = path.join(root, '.planning');
  if (!isDir(dir)) return [];
  return fs.readdirSync(dir).filter((n) => n !== 'done' && isDir(path.join(dir, n))).sort();
}

/** INBOX.md「待裁决」段内 `- [ ]` 条数。 */
function inboxPendingCount(root) {
  const text = read(path.join(root, 'INBOX.md'));
  if (text === null) return 0;
  let f = false; let n = 0;
  for (const ln of text.split('\n')) {
    if (/^## /.test(ln)) { if (f) break; f = /^## *待裁决/.test(ln); continue; }
    if (f && /^- \[ \]/.test(ln)) n++;
  }
  return n;
}

/** TASKS.md「进行中」段原文行（含 `## 进行中` 标题行，去尾部空行），无则 null。 */
function inProgressRawSection(root) {
  const text = read(path.join(root, 'TASKS.md'));
  if (text === null) return null;
  let f = false; const section = [];
  for (const ln of text.split('\n')) {
    if (/^## /.test(ln)) {
      if (f) break;
      f = /^## *进行中/.test(ln);
      if (f) section.push(ln);
      continue;
    }
    if (f) section.push(ln);
  }
  while (section.length && section[section.length - 1].trim() === '') section.pop();
  return section.length ? section : null;
}

/** 工作区 plan.md 的「当前位置」摘要行（前 3 条 `- ` 行）。 */
function workspacePosition(root, name) {
  const text = read(path.join(root, '.planning', name, 'plan.md'));
  if (text === null) return [];
  let f = false; const res = [];
  for (const ln of text.split('\n')) {
    if (/^## 当前位置/.test(ln)) { f = true; continue; }
    if (f && /^- /.test(ln)) { res.push(ln); if (res.length >= 3) break; }
  }
  return res;
}

/** 工作区 plan.md 的「关联 TASKS 条目」字段值（仍是占位符则视为无），无则 null。 */
function workspaceLinkedTask(root, name) {
  const text = read(path.join(root, '.planning', name, 'plan.md'));
  if (text === null) return null;
  for (const ln of text.split('\n')) {
    const m = ln.match(/^-\s*\**关联\s*TASKS\s*条目\**\s*[:：]\s*(.+)$/);
    if (m) {
      const v = m[1].trim();
      return v && !v.includes('<') ? v : null;
    }
  }
  return null;
}

/** progress.md 的 postmortem 是否已固化（声明句在且 <F? 编号> 占位符已替换）。 */
function postmortemFilled(wsDir) {
  const text = read(path.join(wsDir, 'progress.md'));
  if (text === null) return false;
  return text.includes('本文档为过程记录') && !text.includes('<F? 编号>');
}

// ── 节流缓存 ──────────────────────────────────────────────────

function cachePath(root) { return path.join(root, '.planning', '.hook-cache.json'); }
function loadCache(root) {
  try { return JSON.parse(fs.readFileSync(cachePath(root), 'utf8')); } catch { return {}; }
}
function saveCache(root, cache) {
  try {
    fs.mkdirSync(path.join(root, '.planning'), { recursive: true });
    fs.writeFileSync(cachePath(root), JSON.stringify(cache));
  } catch { /* 缓存写失败不影响注入 */ }
}
const throttleOff = () => process.env.PLANNING_HOOKS_NO_THROTTLE === '1';

// ── hook 子命令（输出文本与旧版 sh 脚本逐字一致） ─────────────

function hookSessionStart(root) {
  if (!isFile(path.join(root, 'ROADMAP.md')) && !isFile(path.join(root, 'TASKS.md'))
    && !isFile(path.join(root, 'INBOX.md')) && !isDir(path.join(root, '.planning'))) return 0;

  // SPEC 红线：执行期护栏，防「隐式漂移」（做着做着违背边界 / 技术选型）。每会话注入一次，带行数上限防膨胀刷屏。
  const spec = specRedlines(root);
  const redlines = [...spec.boundary.map((b) => `- 边界：${b}`), ...spec.tech.map((t) => `- 选型：${t}`)];
  if (redlines.length) {
    out('[plan] SPEC 红线（执行期护栏，与其他文档冲突以 SPEC.md 为准）：');
    const LIMIT = 12;
    for (const l of redlines.slice(0, LIMIT)) out(l);
    if (redlines.length > LIMIT) out('- （SPEC 红线过长已截断，完整边界见 SPEC.md）');
  }

  const milestone = currentMilestone(root);
  if (milestone) out(`[plan] 当前里程碑：${milestone}`);

  const doc = loadTasksDoc(root);
  let taskCount = 0;
  if (doc) {
    const { tasks } = tasksInSection(doc, '进行中');
    taskCount = tasks.length;
    if (tasks.length) {
      out('[plan] 进行中任务：');
      for (const t of tasks) out(`- ${normTitle(t.title)}`);
    }
  }

  for (const name of activeWorkspaces(root)) {
    out(`[plan] 活跃工作区：.planning/${name}（开工前先读 plan.md 的「当前位置」）`);
  }

  out(`[plan] 提示：进行中任务 ${taskCount} 个，INBOX 待裁决 ${inboxPendingCount(root)} 条`);
  return 0;
}

function hookUserPromptSubmit(root) {
  if (!isFile(path.join(root, 'ROADMAP.md')) && !isFile(path.join(root, 'TASKS.md'))
    && !isDir(path.join(root, '.planning'))) return 0;

  const milestone = currentMilestone(root);
  const section = inProgressRawSection(root);
  const wsNames = activeWorkspaces(root);

  // 节流：注入内容没变 → 只发一行摘要
  const payload = `${milestone || ''}\n${section ? section.join('\n') : ''}\n${wsNames.join(' ')}`;
  const hash = sha1(payload);
  const cache = loadCache(root);
  if (!throttleOff() && cache.ups && cache.ups.hash === hash) {
    const n = section ? section.filter((l) => /^### /.test(l)).length : 0;
    out(`[plan] 计划状态无变化（进行中任务 ${n} 个）`);
    return 0;
  }

  if (milestone) out(`[plan] 当前里程碑：${milestone}`);
  if (section && section.some((l) => /^### /.test(l))) {
    out('[plan] 进行中任务（TASKS.md 原文）：');
    if (section.length > 60) {
      for (const l of section.slice(0, 60)) out(l);
      out('[plan] 进行中段过长已截断，详见 TASKS.md');
    } else {
      for (const l of section) out(l);
    }
  }
  if (wsNames.length) out(`[plan] 活跃工作区： ${wsNames.join(' ')}（开工前先读 plan.md 的「当前位置」）`);

  cache.ups = { hash };
  saveCache(root, cache);
  return 0;
}

function hookPreToolUse(root) {
  const lines = [];
  const doc = loadTasksDoc(root);
  if (doc) {
    const { tasks } = tasksInSection(doc, '进行中');
    if (tasks.length) {
      lines.push('[plan] 进行中任务：');
      for (const t of tasks) lines.push(`- ${normTitle(t.title)}`);
    }
  }
  for (const name of activeWorkspaces(root)) {
    const pos = workspacePosition(root, name);
    if (pos.length) {
      lines.push(`[plan] 工作区 .planning/${name} 当前位置：`);
      lines.push(...pos);
    }
  }
  if (!lines.length) return 0;

  // 节流：内容没变且距上次输出 < 10 分钟 → 静默
  const cache = loadCache(root);
  const hash = sha1(lines.join('\n'));
  const now = Date.now();
  if (!throttleOff() && cache.pre && cache.pre.hash === hash && now - (cache.pre.ts || 0) < 600000) return 0;
  out(...lines);
  cache.pre = { hash, ts: now };
  saveCache(root, cache);
  return 0;
}

function hookPostToolUse(root) {
  if (!isDir(path.join(root, '.planning'))) return 0;
  const active = activeWorkspaces(root);
  if (!active.length) return 0;

  const cache = loadCache(root);
  const hash = sha1(active.join(' '));
  const now = Date.now();
  if (!throttleOff() && cache.post && cache.post.hash === hash && now - (cache.post.ts || 0) < 600000) return 0;
  out(
    `[plan] 存在活跃工作区： ${active.join(' ')}`,
    '[plan] 若本次修改属于其中任务，请按 2-Action 规则把进展 / 决策 / 错误落 progress.md，并更新 plan.md 的勾选与「当前位置」。',
  );
  cache.post = { hash, ts: now };
  saveCache(root, cache);
  return 0;
}

function hookPreCompact(root) {
  const active = activeWorkspaces(root);
  if (!active.length) return 0;
  for (const name of active) {
    out(`[plan] 上下文即将压缩：请先把当前进展、决策、「当前位置」更新进 .planning/${name}/progress.md 和 plan.md，再继续`);
  }
  const doc = loadTasksDoc(root);
  if (doc) {
    const { tasks } = tasksInSection(doc, '进行中');
    if (tasks.length) out(`[plan] 另：TASKS.md 有 ${tasks.length} 个进行中任务，请确认 TASKS 状态已最新。`);
  }
  return 0;
}

function hookPermissionRequest(root) {
  const doc = loadTasksDoc(root);
  if (!doc) return 0;
  const { tasks } = tasksInSection(doc, '进行中');
  if (tasks.length) {
    out(`[plan] 当前进行中任务：${normTitle(tasks[0].title)}（权限请求与计划纪律相关时请对照 TASKS.md / plan.md）`);
  }
  return 0;
}

function hookStopGate(root) {
  if (!isDir(path.join(root, '.planning')) && !isFile(path.join(root, 'TASKS.md'))) return 0;
  const doc = loadTasksDoc(root);
  const active = activeWorkspaces(root);

  // ── 门一：活跃工作区未归档 ──
  const warn = [];
  for (const name of active) {
    const wsDir = path.join(root, '.planning', name);
    let marked = false;
    // 精确匹配：plan.md「关联 TASKS 条目」→ TASKS.md 中该任务是否已完成（在已完成段 / 标题带 ✅ / 有完成日期）
    const linked = workspaceLinkedTask(root, name);
    if (linked && doc) {
      for (const prefix of ['已完成', '进行中', '已拆好', '调研']) {
        const { tasks } = tasksInSection(doc, prefix);
        const hit = tasks.find((t) => normTitle(t.title) === normTitle(linked));
        if (hit) {
          marked = prefix.startsWith('已完成') || hit.title.includes('✅') || !!taskField(doc, hit, RE_DONE_DATE);
          break;
        }
      }
    }
    // 兜底：postmortem 已固化视为完成动作已做
    if (!marked && postmortemFilled(wsDir)) marked = true;
    if (!marked) warn.push(name);
  }
  if (warn.length) {
    out(`[plan] 阻止收尾：以下活跃工作区的任务未标 ✅： ${warn.join(' ')}`);
    out('[plan] 若任务已完成，请先执行三合一动作（结论回填 FINDINGS.md + progress.md 顶部固化 postmortem + 工作区移入 .planning/done/），再走 plan-task 标 ✅；若任务未完成，请在 progress.md 记录当前进展供下次恢复。');
    return 2;
  }

  // ── 门二：进行中任务无完成痕迹（当天开工的豁免） ──
  if (doc && active.length === 0) {
    const { tasks } = tasksInSection(doc, '进行中');
    const today = localDate();
    const blocked = tasks.filter((t) => taskField(doc, t, RE_START_DATE) !== today);
    if (blocked.length) {
      out(`[plan] 阻止收尾：TASKS.md「进行中」仍有 ${blocked.length} 个未完成任务：`);
      for (const t of blocked) out(`[plan] - ${normTitle(t.title)}`);
      out('[plan] 下一步：若任务已完成，标 ✅ 前先走完成三合一动作（结论回填 FINDINGS.md + progress.md 顶部固化 postmortem + 工作区移入 .planning/done/）；若确认暂停，请把任务移回「已拆好（待做）」并记录当前进展供下次恢复。');
      out('[plan] 说明：当天开工（开始日期 = 今天）的任务豁免本门；开始日期早于今天或未写开始日期的才会被阻止。');
      return 2;
    }
  }
  return 0;
}

const HOOKS = {
  'session-start': hookSessionStart,
  'user-prompt-submit': hookUserPromptSubmit,
  'pre-tool-use': hookPreToolUse,
  'post-tool-use': hookPostToolUse,
  'pre-compact': hookPreCompact,
  'permission-request': hookPermissionRequest,
  'stop-gate': hookStopGate,
};

// ── status 子命令 ─────────────────────────────────────────────

function cmdStatus(root, asJson) {
  const doc = loadTasksDoc(root);
  const state = {
    root,
    milestone: currentMilestone(root),
    inProgress: [],
    readyCount: 0,
    researchCount: 0,
    donePendingCount: 0,
    workspaces: activeWorkspaces(root),
    inboxPending: inboxPendingCount(root),
  };
  if (doc) {
    const grab = (prefix) => tasksInSection(doc, prefix).tasks;
    for (const t of grab('进行中')) {
      const dodLine = doc.lines.slice(t.start, t.end).find((l) => /^-\s*DoD\s*[:：]/.test(l)) || '';
      state.inProgress.push({
        title: normTitle(t.title),
        dod: dodLine.replace(/^-\s*DoD\s*[:：]\s*/, ''),
        start: taskField(doc, t, RE_START_DATE),
        workspace: taskField(doc, t, RE_WORKSPACE),
      });
    }
    state.readyCount = grab('已拆好').length;
    state.researchCount = grab('调研').length;
    state.donePendingCount = grab('已完成').length;
  }
  if (asJson) { out(JSON.stringify(state, null, 2)); return 0; }
  if (state.milestone) out(`当前里程碑：${state.milestone}`);
  out(`进行中 ${state.inProgress.length} ｜ 已拆好 ${state.readyCount} ｜ 调研 ${state.researchCount} ｜ 已完成待归档 ${state.donePendingCount} ｜ INBOX 待裁决 ${state.inboxPending}`);
  for (const t of state.inProgress) {
    out(`- ${t.title}${t.start ? `（开始：${t.start}）` : ''}${t.workspace ? `［${t.workspace}］` : ''}`);
    if (t.dod) out(`  DoD：${t.dod}`);
  }
  for (const name of state.workspaces) {
    const pos = workspacePosition(root, name);
    out(`工作区 .planning/${name}${pos.length ? `：${pos[0].replace(/^- /, '')}` : ''}`);
  }
  return 0;
}

// ── start 子命令 ──────────────────────────────────────────────

function slugify(name) {
  return name.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '-').replace(/^-+|-+$/g, '');
}

function fillTemplate(text, name, date) {
  return text
    .replaceAll('<任务名>', name)
    .replaceAll('<TASKS.md 中的任务标题>', name)
    .replaceAll('<YYYY-MM-DD>', date);
}

function cmdStart(root, name, opts) {
  const doc = loadTasksDoc(root);
  if (!doc) { out('[plan] 未找到 TASKS.md，请先运行 plan-init'); return 1; }
  const date = opts.date || localDate();

  let task = null; let fromSection = null;
  for (const prefix of ['已拆好', '进行中', '调研']) {
    const { tasks } = tasksInSection(doc, prefix);
    const hit = tasks.find((t) => normTitle(t.title) === normTitle(name));
    if (hit) { task = hit; fromSection = prefix; break; }
  }
  if (!task) {
    out(`[plan] 未找到任务：「${name}」`);
    const { tasks } = tasksInSection(doc, '已拆好');
    if (tasks.length) {
      out('[plan] 当前「已拆好（待做）」队列：');
      for (const t of tasks) out(`- ${normTitle(t.title)}`);
    } else {
      out('[plan] 「已拆好（待做）」队列为空——先走 plan-task 录入流程添加任务');
    }
    return 1;
  }

  if (fromSection === '进行中') {
    // 幂等：只补缺失的开始日期
    if (!taskField(doc, task, RE_START_DATE)) {
      doc.lines.splice(findBlockTail(doc, task), 0, `- 开始：${date}`);
      saveTasksDoc(doc);
      out(`[plan] 任务已在「进行中」，补记开始日期：${date}`);
    } else {
      out(`[plan] 任务已在「进行中」（开始：${taskField(doc, task, RE_START_DATE)}），无需重复认领`);
    }
  } else {
    const block = removeBlock(doc, task);
    if (!block.some((l) => RE_START_DATE.test(l))) block.push(`- 开始：${date}`);
    insertBlock(doc, '进行中', block);
    saveTasksDoc(doc);
    out(`[plan] 已认领：「${normTitle(task.title)}」→「进行中」（开始：${date}）`);
  }

  // 工作区处理：移动后重新定位任务块
  const moved = tasksInSection(doc, '进行中').tasks.find((t) => normTitle(t.title) === normTitle(name));
  const wsRel = moved ? taskField(doc, moved, RE_WORKSPACE) : null;

  if (opts.workspace || wsRel) {
    let slugDir;
    let rebuilt = false;
    if (wsRel) {
      slugDir = wsRel.replace(/\/$/, '');
      rebuilt = !isDir(path.join(root, slugDir));
    } else {
      slugDir = `.planning/${date}-${slugify(name)}`;
    }
    const wsAbs = path.join(root, slugDir);
    if (isFile(path.join(wsAbs, 'plan.md'))) {
      out(`[plan] 工作区已存在，直接复用：${slugDir}/`);
    } else {
      const tplDir = path.join(SKILL_DIR, 'assets', 'templates');
      const planTpl = read(path.join(tplDir, 'plan.md'));
      const progTpl = read(path.join(tplDir, 'progress.md'));
      if (planTpl === null || progTpl === null) { out('[plan] 工作区模板缺失（assets/templates/），请检查技能安装完整性'); return 1; }
      fs.mkdirSync(wsAbs, { recursive: true });
      let planText = fillTemplate(planTpl, name, date);
      if (rebuilt) planText = `⚠️ 工作区曾于 ${localDate()} 丢失，此为重建，历史进度未恢复\n\n${planText}`;
      fs.writeFileSync(path.join(wsAbs, 'plan.md'), planText);
      fs.writeFileSync(path.join(wsAbs, 'progress.md'), fillTemplate(progTpl, name, date));
      out(rebuilt
        ? `[plan] 工作区曾丢失，已按原 slug 重建：${slugDir}/（历史进度未恢复）`
        : `[plan] 已建工作区：${slugDir}/（plan.md + progress.md）`);
    }
    // 任务行下补工作区关联行（唯一关联据）
    if (moved && !taskField(doc, moved, RE_WORKSPACE)) {
      doc.lines.splice(findBlockTail(doc, moved), 0, `- 工作区：${slugDir}/`);
      saveTasksDoc(doc);
      out(`[plan] TASKS.md 已补关联行：工作区：${slugDir}/`);
    }
  }
  out('[plan] 开工前先读 plan.md / TASKS.md 对应条目；执行中遵守 2-Action 落盘纪律。');
  return 0;
}

// ── finish 子命令 ─────────────────────────────────────────

function cmdFinish(root, name, opts) {
  const doc = loadTasksDoc(root);
  if (!doc) { out('[plan] 未找到 TASKS.md，请先运行 plan-init'); return 1; }
  const date = opts.date || localDate();

  const { tasks } = tasksInSection(doc, '进行中');
  const task = tasks.find((t) => normTitle(t.title) === normTitle(name));
  if (!task) {
    out(`[plan] 「进行中」未找到任务：「${name}」`);
    if (tasks.length) {
      out('[plan] 当前进行中：');
      for (const t of tasks) out(`- ${normTitle(t.title)}`);
    }
    return 1;
  }

  const wsRel = (taskField(doc, task, RE_WORKSPACE) || '').replace(/\/$/, '');
  if (wsRel) {
    const wsAbs = path.join(root, wsRel);
    const slugName = path.basename(wsRel);
    const missing = [];
    // 三合一证据一：结论已回填 FINDINGS（含指向工作区的过程追溯行）
    const findings = [read(path.join(root, 'FINDINGS.md')), read(path.join(root, 'FINDINGS.archive.md'))]
      .filter((t) => t !== null).join('\n');
    const hasTrace = findings.split('\n').some((l) => l.includes('过程追溯') && (l.includes(slugName) || l.includes(wsRel)));
    if (!hasTrace) missing.push(`FINDINGS.md 缺「过程追溯：.planning/done/${slugName}/progress.md」引用行（结论须先回填）`);
    // 三合一证据二：postmortem 已固化
    if (!postmortemFilled(wsAbs)) missing.push('progress.md 顶部 postmortem 未固化（填写结论 → FINDINGS 编号，替换 <F? 编号> 占位符）');
    if (missing.length) {
      out('[plan] 不能标 ✅，三合一动作缺失：');
      for (const m of missing) out(`- ${m}`);
      out('[plan] 请先补齐上述内容（结论由 agent 撰写，引擎不代写），再重新执行 finish。');
      return 1;
    }
  }

  // 机械动作：移入已完成段 + ✅ + 完成日期
  const block = removeBlock(doc, task);
  block[0] = block[0].includes('✅') ? block[0] : `${block[0]} ✅`;
  if (!block.some((l) => RE_DONE_DATE.test(l))) block.push(`- 完成：${date}`);
  insertBlock(doc, '已完成', block);
  saveTasksDoc(doc);
  out(`[plan] 已完成：✅ ${normTitle(task.title)}（完成：${date}）→「已完成（待归档）」`);

  // 机械动作：工作区移入 done/（归档后只读）
  if (wsRel) {
    const wsAbs = path.join(root, wsRel);
    const slugName = path.basename(wsRel);
    const doneAbs = path.join(root, '.planning', 'done', slugName);
    if (isDir(wsAbs)) {
      if (isDir(doneAbs)) { out(`[plan] 归档冲突：.planning/done/${slugName}/ 已存在，请人工处理`); return 1; }
      fs.mkdirSync(path.join(root, '.planning', 'done'), { recursive: true });
      fs.renameSync(wsAbs, doneAbs);
      out(`[plan] 工作区已归档：${wsRel}/ → .planning/done/${slugName}/（只读，永不修改）`);
    } else {
      out(`[plan] 提示：工作区目录 ${wsRel}/ 不存在，跳过移动`);
    }
  }
  out('[plan] 提醒：归档到 ROADMAP 里程碑由 plan-review 负责；本任务不许删除。');
  return 0;
}

// ── doctor 子命令（1:1 移植 plan-doctor.sh 输出行 + 新增 node 检查） ──

function cmdDoctor(globalOnly) {
  let PASS = 0; let WARN = 0; let FAIL = 0;
  const pass = (m) => { PASS++; out(`[PASS] ${m}`); };
  const warn = (m) => { WARN++; out(`[WARN] ${m}`); };
  const fail = (m) => { FAIL++; out(`[FAIL] ${m}`); };

  const HOME = process.env.HOME || process.env.USERPROFILE || os.homedir();
  const cwd = process.cwd();
  const SCRIPTS = ['session-start', 'user-prompt-submit', 'pre-tool-use', 'post-tool-use', 'pre-compact', 'stop-gate', 'permission-request'];
  const CC_EVENTS = ['SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PreCompact', 'Stop'];
  const resolveRel = (d) => (d.startsWith('./') ? path.join(cwd, d) : d);

  // 1. 技能安装
  const candidates = [];
  if (!globalOnly) candidates.push('./.agents/skills/plan-task', './.claude/skills/plan-task');
  candidates.push(
    path.join(HOME, '.claude', 'skills', 'plan-task'),
    path.join(HOME, '.codex', 'skills', 'plan-task'),
    path.join(HOME, '.config', 'opencode', 'skills', 'plan-task'),
  );
  const foundDirs = candidates.filter((d) => isFile(path.join(resolveRel(d), 'SKILL.md')));
  if (foundDirs.length) {
    pass(`技能安装: 发现 plan-task 于:${foundDirs.map((d) => ` ${d}`).join('')}`);
  } else {
    fail('技能安装: 未发现 plan-task（运行 npx skills add JAYY513/plan-skills --skill plan-task）');
  }

  // 2. hook 脚本齐全
  for (const d of foundDirs) {
    const base = resolveRel(d);
    const missing = [];
    for (const s of SCRIPTS) {
      if (!isFile(path.join(base, 'hooks', `${s}.sh`))) missing.push(` ${s}.sh`);
      if (!isFile(path.join(base, 'hooks', `${s}.ps1`))) missing.push(` ${s}.ps1`);
    }
    if (!missing.length) pass(`hook 脚本齐全: ${d}（7 对 sh/ps1）`);
    else fail(`hook 脚本齐全: ${d} 缺失:${missing.join('')}（运行 npx skills update 更新技能）`);
  }

  // 3. Claude Code hooks 注册（frontmatter）
  for (const d of foundDirs) {
    if (!d.includes('/.claude/') && !d.includes('\\.claude\\')) continue;
    const text = read(path.join(resolveRel(d), 'SKILL.md'));
    if (text === null) continue;
    const all = text.split('\n').slice(0, 100);
    let endIdx = all.length;
    for (let i = 1; i < all.length; i++) if (all[i] === '---') { endIdx = i + 1; break; }
    const fm = all.slice(0, endIdx);
    if (!fm.some((l) => /^hooks:/.test(l))) {
      fail(`Claude Code hooks 注册: ${d} 的 SKILL.md frontmatter 缺少 hooks: 键（旧版本？运行 npx skills update）`);
      continue;
    }
    const missingEv = CC_EVENTS.filter((ev) => !fm.some((l) => l.startsWith(`  ${ev}:`)));
    if (!missingEv.length) pass(`Claude Code hooks 注册: ${d} frontmatter 6 个事件齐全`);
    else fail(`Claude Code hooks 注册: ${d} 缺少事件:${missingEv.map((e) => ` ${e}`).join('')}`);
  }

  // 4. Codex hooks 注册
  const hjCandidates = [];
  if (!globalOnly) hjCandidates.push('./.codex/hooks.json');
  hjCandidates.push(path.join(HOME, '.codex', 'hooks.json'));
  const hjFound = hjCandidates.filter((f) => isFile(resolveRel(f)));
  if (hjFound.length) {
    const ptFiles = [];
    for (const f of hjFound) {
      const text = read(resolveRel(f)) ?? '';
      if (!text.includes('plan-task')) continue;
      ptFiles.push(f);
      try {
        JSON.parse(text);
        pass(`Codex hooks 注册: ${f} 存在、含 plan-task、JSON 合法`);
      } catch {
        fail(`Codex hooks 注册: ${f} 不是合法 JSON`);
      }
    }
    if (ptFiles.length >= 2) warn('Codex hooks 注册: 项目级与全局 hooks.json 都注册了 plan-task，hook 会重复触发，请只保留一处');
    if (ptFiles.length) {
      for (const f of hjFound) {
        if (!ptFiles.includes(f)) pass(`Codex hooks 注册: ${f} 未注册 plan-task（全局未安装 Codex hooks，可选）`);
      }
      const cfg = path.join(HOME, '.codex', 'config.toml');
      const cfgText = read(cfg);
      if (cfgText && /hooks *= *true/.test(cfgText)) pass(`Codex hooks 特性: ${cfg} 含 hooks = true`);
      else warn(`Codex hooks 特性: 未在 ${cfg} 找到 hooks = true（请在 [features] 节配置，或用 codex features list 验证）`);
    } else {
      fail('Codex hooks 注册: 项目级与全局 hooks.json 均不含 plan-task 路径（参考 hooks/codex/README.md 安装）');
    }
  } else {
    warn('Codex hooks 注册: 未发现 hooks.json（使用 Codex 时参考 hooks/codex/README.md 安装；不用 Codex 可忽略）');
  }

  // 5. sh 可用性 / Windows powershell
  const shProbe = spawnSync('sh', ['-c', 'command -v sh'], { encoding: 'utf8' });
  if (shProbe.status === 0 && shProbe.stdout && shProbe.stdout.trim()) {
    pass(`sh 可用: ${shProbe.stdout.trim()}`);
  } else {
    // Windows 上 sh 常不在 PATH 但随 Git Bash 安装，探测常见位置避免误报
    const gitSh = [
      'C:/Program Files/Git/usr/bin/sh.exe',
      'C:/Program Files (x86)/Git/usr/bin/sh.exe',
      `${process.env.LOCALAPPDATA || ''}/Programs/Git/usr/bin/sh.exe`,
    ].find((p) => p && isFile(p));
    if (gitSh) pass(`sh 可用: ${gitSh}（Git Bash，不在 PATH）`);
    else fail('sh 可用: 未找到 sh（hooks 的 sh 入口全部无法运行）');
  }

  const isWindows = process.platform === 'win32' || !!process.env.MSYSTEM;
  if (isWindows) {
    const pwshProbe = spawnSync('pwsh', ['-NoProfile', '-Command', '$PSVersionTable.PSVersion.Major'], { encoding: 'utf8' });
    if (pwshProbe.status === 0 && pwshProbe.stdout && pwshProbe.stdout.trim()) {
      pass(`powershell 可用: pwsh ${pwshProbe.stdout.trim()}`);
    } else {
      const whereProbe = spawnSync('where', ['powershell'], { encoding: 'utf8' });
      const sysPs = 'C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe';
      if (whereProbe.status === 0 && whereProbe.stdout && whereProbe.stdout.trim()) pass(`powershell 可用: ${whereProbe.stdout.trim().split(/\r?\n/)[0]}`);
      else if (isFile(sysPs)) pass('powershell 可用: Windows PowerShell 5.x（不在 PATH，但系统路径存在）');
      else warn('powershell 可用: 未找到 powershell（Windows 下 ps1 hook 不可用，sh 入口仍可用时可忽略）');
    }
  }

  // 6. 状态文件（当前目录是否已 plan-init）
  if (!globalOnly) {
    const missingSf = ['SPEC.md', 'ROADMAP.md', 'TASKS.md', 'INBOX.md', 'FINDINGS.md'].filter((f) => !isFile(path.join(cwd, f)));
    if (!missingSf.length) pass('状态文件: 当前目录已初始化计划体系（5 文件齐全）');
    else warn(`状态文件: 当前目录缺少:${missingSf.map((f) => ` ${f}`).join('')}（尚未运行 plan-init；hooks 会静默跳过，属预期）`);
  }

  // 7. node 运行时（新增：引擎与所有 hook 薄壳依赖 node）
  pass(`node 运行时: ${process.version}（${process.execPath}）`);

  out('-----');
  out(`合计 ${PASS + WARN + FAIL} 项：PASS ${PASS}，WARN ${WARN}，FAIL ${FAIL}`);
  return FAIL > 0 ? 1 : 0;
}

// ── 入口 ──────────────────────────────────────────────────

function parseArgs(args) {
  const opts = { positional: [] };
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--workspace') opts.workspace = true;
    else if (a === '--json') opts.json = true;
    else if (a === '--global') opts.global = true;
    else if (a === '--date') opts.date = args[++i];
    else if (a.startsWith('--date=')) opts.date = a.slice(7);
    else opts.positional.push(a);
  }
  return opts;
}

function usage() {
  out(
    '用法：plan.mjs <命令> [参数]',
    '',
    '  hook <name>                 运行 hook 逻辑（session-start / user-prompt-submit / pre-tool-use /',
    '                              post-tool-use / pre-compact / permission-request / stop-gate）',
    '  status [--json]             输出当前计划状态摘要',
    '  start "<任务名>" [--workspace] [--date YYYY-MM-DD]   认领任务（移入进行中 + 补开始日期，可建工作区）',
    '  finish "<任务名>" [--date YYYY-MM-DD]                完成任务（校验三合一 → ✅ + 移入已完成 + 归档工作区）',
    '  doctor [--global]           安装自检（PASS / WARN / FAIL）',
    '',
    '环境变量：PLANNING_ROOT（项目根）、PLANNING_HOOKS_DISABLED=1（hook 静默）、PLANNING_HOOKS_NO_THROTTLE=1（关节流）',
  );
}

function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  const opts = parseArgs(rest);

  if (cmd === 'doctor') return cmdDoctor(!!opts.global);
  if (cmd === 'hook') {
    if (process.env.PLANNING_HOOKS_DISABLED === '1') return 0;
    const name = opts.positional[0];
    const fn = HOOKS[name];
    if (!fn) { process.stderr.write(`[plan] 未知 hook：${name}\n`); return 1; }
    const root = findRoot();
    if (!root) return 0; // 无计划体系 → 静默
    return fn(root) || 0;
  }
  if (cmd === 'status') {
    const root = findRoot();
    if (!root) { out('[plan] 未找到计划体系（ROADMAP.md / TASKS.md / .planning 均不存在），请先运行 plan-init'); return 1; }
    return cmdStatus(root, !!opts.json);
  }
  if (cmd === 'start' || cmd === 'finish') {
    const name = opts.positional[0];
    if (!name) { out(`[plan] 缺少任务名：plan.mjs ${cmd} "<任务名>"`); return 1; }
    const root = findRoot();
    if (!root) { out('[plan] 未找到计划体系（ROADMAP.md / TASKS.md / .planning 均不存在），请先运行 plan-init'); return 1; }
    return cmd === 'start' ? cmdStart(root, name, opts) : cmdFinish(root, name, opts);
  }
  usage();
  return cmd ? 1 : 0;
}

try {
  process.exitCode = main();
} catch (err) {
  if (process.argv[2] === 'hook') {
    if (process.env.PLANNING_DEBUG === '1' && err && err.stack) process.stderr.write(`[plan] hook 错误（已静默吞掉）：${err.stack}\n`);
    process.exitCode = 0; // hook 出错绝不阻断会话：静默退出
  } else {
    const detail = process.env.PLANNING_DEBUG === '1' && err && err.stack ? err.stack : (err && err.message ? err.message : err);
    process.stderr.write(`[plan] 引擎错误：${detail}\n`);
    process.exitCode = 1;
  }
}
