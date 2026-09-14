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
 * 退出码：hook 注入类 0；stop-gate 命中阻止 2；无计划体系 1；具名实体缺失/歧义 2；用法/未知 flag 3。
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
const RE_TIMEBOX = /^-\s*\**时间盒\**\s*[:：]/;
const RE_PRE = /^-\s*\**前置\**\s*[:：]\s*(.+)$/;
const RE_TAG = /^-\s*\**标签\**\s*[:：]\s*(.+)$/;
const RE_BASIS = /^-\s*\**依据\**\s*[:：]\s*(.+)$/;
const RE_FROM = /^-\s*\**来自\**\s*[:：]\s*(.+)$/;
const RE_CONC = /^-\s*\**结论\**\s*[:：]\s*(.+)$/;

/** 任务块是否带「时间盒」（调研探针的持久标记，移入进行中后仍在）。 */
function taskHasTimebox(doc, task) {
  if (!doc || !task) return false;
  for (let i = task.start + 1; i < task.end; i++) {
    if (RE_TIMEBOX.test(doc.lines[i])) return true;
  }
  return false;
}

/** 工作区是否已有 notes/（有才催材料落盘，避免逼出空目录）。 */
function workspaceHasNotes(root, name) {
  return isDir(path.join(root, '.planning', name, 'notes'));
}

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

/** 标题相似（finish 软警告 / inbox 疑似共用）：包含或 token/bigram ≥60%。 */
function normalizeTitle(s) {
  return String(s)
    .toLowerCase()
    .replace(/[`"'「」《》【】]/g, '')
    .replace(/^\s*\d{4}-\d{2}-\d{2}\s*/, '')
    .replace(/[🔴⚪]/g, '')
    .replace(/^-\s*(?:\[\s*\]\s*)?/, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function similarTitles(a, b) {
  const na = normalizeTitle(a);
  const nb = normalizeTitle(b);
  const shorter = na.length <= nb.length ? na : nb;
  const longer = na.length <= nb.length ? nb : na;
  if (shorter.length < 4) return false;
  if (longer.includes(shorter)) return true;
  const ta = na.split(' ').filter(Boolean);
  const tb = nb.split(' ').filter(Boolean);
  if (ta.length >= 2 && tb.length >= 2) {
    const setA = new Set(ta);
    let inter = 0;
    for (const t of tb) if (setA.has(t)) inter++;
    return inter / Math.min(ta.length, tb.length) >= 0.6;
  }
  if (!/\s/.test(na) && !/\s/.test(nb)) {
    const bigrams = (s) => {
      const set = new Set();
      for (let i = 0; i < s.length - 1; i++) set.add(s.slice(i, i + 2));
      return set;
    };
    const ba = bigrams(na);
    const bb = bigrams(nb);
    if (!ba.size || !bb.size) return false;
    let inter = 0;
    for (const x of ba) if (bb.has(x)) inter++;
    return inter / Math.min(ba.size, bb.size) >= 0.6;
  }
  return false;
}

function parseFindings(root) {
  const text = read(path.join(root, 'FINDINGS.md'));
  if (text === null) return [];
  const entries = [];
  let cur = null;
  const flush = () => { if (cur) entries.push(cur); cur = null; };
  for (const ln of text.split('\n')) {
    const m = ln.match(/^###\s+(F\d+)\s*[：:]\s*(.+)$/);
    if (m) {
      flush();
      cur = { id: m[1], theme: m[2].trim(), date: '', tags: [], source: '', impact: '', status: '', material: '', trace: '', raw: [ln] };
      continue;
    }
    if (!cur) continue;
    if (/^#{2,3}\s/.test(ln)) { flush(); continue; }
    cur.raw.push(ln);
    const f = ln.match(/^-\s*([^：:]+)[：:]\s*(.*)$/);
    if (!f) continue;
    const key = f[1].replace(/\*/g, '').trim();
    const val = f[2].trim();
    if (key === '日期') cur.date = val;
    else if (key === '标签') cur.tags = val.split(/[,，]/).map((s) => s.trim()).filter(Boolean);
    else if (key === '来源') cur.source = val;
    else if (key === '影响') cur.impact = val;
    else if (key === '状态') cur.status = val;
    else if (key === '材料') cur.material = val;
    else if (key === '过程追溯') cur.trace = val;
  }
  flush();
  return entries;
}

function findingsMatch(e, opts) {
  if (opts.tag != null) {
    if (opts.tag === '未分类') { if (e.tags.length) return false; }
    else if (!e.tags.includes(opts.tag)) return false;
  }
  if (opts.source != null && !e.source.includes(opts.source)) return false;
  if (opts.status != null) {
    if (opts.status === '有效') { if (e.status !== '有效') return false; }
    else if (opts.status === '推翻') { if (!e.status.includes('推翻')) return false; }
    else if (e.status !== opts.status) return false;
  }
  if (opts.impact != null) {
    if (opts.impact === 'none') { if (e.impact !== '无') return false; }
    else if (opts.impact === 'spec') { if (!/SPEC/i.test(e.impact)) return false; }
    else if (!e.impact.includes(opts.impact)) return false;
  }
  return true;
}

function inboxItemTitle(ln) {
  let s = ln.replace(/^-\s*(?:\[\s*\]\s*)?/, '');
  s = s.replace(/^\d{4}-\d{2}-\d{2}\s*/, '');
  s = s.replace(/[🔴⚪]\s*/, '');
  s = s.replace(/\s+[—–]\s+.*$/, '');
  s = s.replace(/\s+→\s+.*$/, '');
  return s.trim();
}

function parseInbox(root) {
  const text = read(path.join(root, 'INBOX.md'));
  if (text === null) return [];
  const items = [];
  let section = null;
  let cur = null;
  const flush = () => { if (cur) items.push(cur); cur = null; };
  for (const ln of text.split('\n')) {
    if (/^##\s/.test(ln)) {
      flush();
      if (/待裁决/.test(ln)) section = 'pending';
      else if (/已裁决/.test(ln)) section = 'resolved';
      else section = null;
      continue;
    }
    if (!section) continue;
    const solved = ln.match(/^-\s*已解决[：:]\s*(.+)$/);
    if (solved && cur) {
      cur.resolvedLine = solved[1].trim();
      cur.resolved = true;
      continue;
    }
    if (/^-\s/.test(ln)) {
      flush();
      cur = {
        line: ln.trim(),
        title: inboxItemTitle(ln),
        section,
        resolved: section === 'resolved',
        resolvedLine: section === 'resolved' ? ln.trim() : '',
      };
    }
  }
  flush();
  return items;
}

/** INBOX 未决条数：待裁决且无 `- 已解决`（旧「已裁决」区不算未决）。 */
function inboxPendingCount(root) {
  return parseInbox(root).filter((i) => i.section === 'pending' && !i.resolved).length;
}

function dodOf(doc, task) {
  if (!doc || !task) return '';
  const line = doc.lines.slice(task.start, task.end).find((l) => /^-\s*DoD\s*[:：]/.test(l)) || '';
  return line.replace(/^-\s*DoD\s*[:：]\s*/, '').trim();
}

function completedTaskTitles(root) {
  const doc = loadTasksDoc(root);
  if (!doc) return [];
  return tasksInSection(doc, '已完成').tasks.map((t) => normTitle(t.title));
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
  return positionFromDir(path.join(root, '.planning', name));
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

function loadPlanView(root) {
  const doc = loadTasksDoc(root);
  const spec = specRedlines(root);
  const view = {
    root,
    milestone: currentMilestone(root),
    inProgress: [],
    nextTitle: '',
    nextDod: '',
    readyCount: 0,
    researchCount: 0,
    donePendingCount: 0,
    workspaces: activeWorkspaces(root),
    inboxPending: inboxPendingCount(root),
    redlines: [...spec.boundary.map((b) => `- 边界：${b}`), ...spec.tech.map((t) => `- 选型：${t}`)],
  };
  if (doc) {
    const grab = (prefix) => tasksInSection(doc, prefix).tasks;
    for (const t of grab('进行中')) {
      view.inProgress.push({
        title: normTitle(t.title),
        dod: dodOf(doc, t),
        start: taskField(doc, t, RE_START_DATE),
        workspace: taskField(doc, t, RE_WORKSPACE),
      });
    }
    const ready = grab('已拆好');
    view.readyCount = ready.length;
    if (ready[0]) {
      view.nextTitle = normTitle(ready[0].title);
      view.nextDod = dodOf(doc, ready[0]);
    }
    view.researchCount = grab('调研').length;
    view.donePendingCount = grab('已完成').length;
  }
  return view;
}

function comparisonPayload(v) {
  return `${v.inProgress.map((t) => t.title).join('\n')}\n${v.nextTitle}\n${v.inboxPending}`;
}

function emitStatusBody(v, withRedlines) {
  if (withRedlines && v.redlines.length) {
    out('[plan] SPEC 红线（执行期护栏，与其他文档冲突以 SPEC.md 为准）：');
    const LIMIT = 3;
    for (const l of v.redlines.slice(0, LIMIT)) out(l);
    if (v.redlines.length > LIMIT) out('- （其余红线见 SPEC.md）');
  }
  if (v.milestone) out(`[plan] 当前里程碑：${v.milestone}`);
  const ip = v.inProgress.map((t) => t.title).join('、') || '无';
  out(`[plan] 进行中：${ip} ｜ 下一张：${v.nextTitle || '无'}`);
  out(`[plan] 提示：进行中 ${v.inProgress.length} 个，INBOX 待裁决 ${v.inboxPending} 条`);
}

function emitHeartbeat(v) {
  if (v.inProgress.length) {
    const first = v.inProgress[0].title;
    out(`[plan] 进行中：${first}（${v.inProgress.length}）｜详情 plan.mjs task "${first}"`);
    return;
  }
  if (v.nextTitle) {
    out(`[plan] 下一张：${v.nextTitle}｜详情 plan.mjs next`);
    return;
  }
  out('[plan] 进行中：无｜详情 plan.mjs status');
}

function emitChangeCard(v) {
  emitStatusBody(v, false);
  if (v.nextTitle) {
    out(`下一张：${v.nextTitle}`);
    out(`DoD：${v.nextDod || '（无）'}`);
  }
  emitHeartbeat(v);
}


function hookSessionStart(root) {
  if (!isFile(path.join(root, 'ROADMAP.md')) && !isFile(path.join(root, 'TASKS.md'))
    && !isFile(path.join(root, 'INBOX.md')) && !isDir(path.join(root, '.planning'))) return 0;
  emitStatusBody(loadPlanView(root), true);
  return 0;
}


function hookUserPromptSubmit(root) {
  if (!isFile(path.join(root, 'ROADMAP.md')) && !isFile(path.join(root, 'TASKS.md'))
    && !isDir(path.join(root, '.planning'))) return 0;
  const v = loadPlanView(root);
  const hash = sha1(comparisonPayload(v));
  const cache = loadCache(root);
  const unchanged = cache.ups && cache.ups.hash === hash;
  if (throttleOff() || !cache.ups || unchanged) emitHeartbeat(v);
  else emitChangeCard(v);
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

  const withNotes = active.filter((n) => workspaceHasNotes(root, n));
  const cache = loadCache(root);
  const hash = sha1(active.join(' ') + '|notes:' + withNotes.join(' '));
  const now = Date.now();
  if (!throttleOff() && cache.post && cache.post.hash === hash && now - (cache.post.ts || 0) < 600000) return 0;
  const lines = [
    `[plan] 存在活跃工作区： ${active.join(' ')}`,
    '[plan] 若本次修改属于其中任务，请按 2-Action 规则把进展 / 决策 / 错误落 progress.md，并更新 plan.md 的勾选与「当前位置」。',
  ];
  if (withNotes.length) {
    lines.push(`[plan] 若本次产出了调研材料，写入 ${withNotes.map((n) => `.planning/${n}/notes/`).join(' ')}（先 index.md），不要写进 progress.md。`);
  }
  out(...lines);
  cache.post = { hash, ts: now };
  saveCache(root, cache);
  return 0;
}

function hookPreCompact(root) {
  const active = activeWorkspaces(root);
  if (!active.length) return 0;
  for (const name of active) {
    out(`[plan] 上下文即将压缩：请先把当前进展、决策、「当前位置」更新进 .planning/${name}/progress.md 和 plan.md，再继续`);
    if (workspaceHasNotes(root, name)) {
      out(`[plan] 工作区 .planning/${name}/notes/ 已有材料：压缩前把章节 / 对比表 / 摘录写入 notes/（先更新 index.md），不要只留在对话里`);
    }
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
  const v = loadPlanView(root);
  if (asJson) {
    out(JSON.stringify({
      root: v.root,
      milestone: v.milestone,
      inProgress: v.inProgress,
      readyCount: v.readyCount,
      researchCount: v.researchCount,
      donePendingCount: v.donePendingCount,
      workspaces: v.workspaces,
      inboxPending: v.inboxPending,
    }, null, 2));
    return 0;
  }
  emitStatusBody(v, true);
  return 0;
}


function cmdNext(root) {
  const doc = loadTasksDoc(root);
  const ready = doc ? tasksInSection(doc, '已拆好').tasks : [];
  if (!ready.length) { out('（无匹配）'); return 0; }
  const t = ready[0];
  out(`下一张：${normTitle(t.title)}`);
  out(`DoD：${dodOf(doc, t) || '（无）'}`);
  return 0;
}

function findingIndexLine(e) {
  const tag = e.tags.length ? e.tags.join(',') : '未分类';
  const theme = e.theme.length > 40 ? e.theme.slice(0, 40) : e.theme;
  return `${e.id} | ${e.date || '—'} | ${tag} | ${e.status || '—'} | ${theme}`;
}

function cmdFindings(root, opts) {
  if (opts.full && !opts.fullId) {
    out('[plan] 缺少编号：plan.mjs findings --full F3');
    return 3;
  }
  const entries = parseFindings(root);
  if (opts.full) {
    const want = String(opts.fullId).replace(/^F/i, '');
    const hit = entries.find((e) => e.id.replace(/^F/i, '') === want || e.id === opts.fullId);
    if (!hit) { out(`[plan] 未找到 ${/^\d+$/.test(String(opts.fullId)) ? 'F' + opts.fullId : opts.fullId}`); return 2; }
    out(...hit.raw);
    return 0;
  }
  const filtered = entries.filter((e) => findingsMatch(e, opts));
  if (!filtered.length) { out('（无匹配）'); return 0; }
  for (const e of filtered) out(findingIndexLine(e));
  return 0;
}


function cmdInbox(root, opts) {
  const items = parseInbox(root);
  const pending = items.filter((i) => i.section === 'pending' && !i.resolved);
  const resolved = items.filter((i) => i.resolved);
  const doneTitles = completedTaskTitles(root);

  const printPending = () => {
    if (!pending.length) { out('（无匹配）'); return; }
    const doc = loadTasksDoc(root);
    const open = allTasks(doc).filter((t) => t.zone !== '已完成' && !/✅/.test(t.title));
    for (const i of pending) {
      let claim = '';
      for (const t of open) {
        const q = inboxQuery(taskField(doc, t, RE_FROM));
        if (q && (i.title === q || similarTitles(i.title, q))) { claim = normTitle(t.title); break; }
      }
      out(claim ? `${i.line}  认领中：${claim}` : i.line);
    }
  };

  const printResolved = () => {
    if (!resolved.length) out('（无匹配）');
    else {
      for (const i of resolved) {
        if (i.section === 'pending') out(`${i.line} → ${i.resolvedLine}`);
        else out(i.line);
      }
    }
  };
  const printSuspect = () => {
    const hits = [];
    for (const i of pending) {
      for (const t of doneTitles) {
        if (similarTitles(i.title, t)) { hits.push({ i, t }); break; }
      }
    }
    if (!hits.length) return;
    out('⚠️ 疑似已实现：');
    for (const h of hits) out(`- ${h.i.title} ≈ 已完成「${h.t}」`);
  };

  if (opts.all) {
    out('## 未决');
    printPending();
    out('## 已解决');
    printResolved();
    return 0;
  }
  if (opts.resolved) {
    printResolved();
    return 0;
  }
  printPending();
  printSuspect();
  return 0;
}

function unknownFlag(opts) {
  if (!opts.unknownFlag) return 0;
  out(`[plan] 未知参数：${opts.unknownFlag}`);
  return 3;
}

function allTasks(doc) {
  if (!doc) return [];
  const acc = [];
  for (const prefix of ['进行中', '已拆好', '调研', '已完成']) {
    for (const t of tasksInSection(doc, prefix).tasks) acc.push({ ...t, zone: prefix });
  }
  return acc;
}

function parseFids(s) {
  return [...String(s || '').matchAll(/F\d+/gi)].map((m) => m[0].replace(/^f/i, 'F'));
}

function inboxQuery(s) {
  return String(s || '').replace(/^INBOX\s+/i, '').trim();
}

function repoPathOk(root, p) {
  if (!p) return true;
  const rel = p.replace(/^[`"'<\s]+|[`"'>\s]+$/g, '').split(/\s/)[0];
  if (!rel || rel.startsWith('<')) return true;
  const abs = path.isAbsolute(rel) ? rel : path.join(root, rel);
  return isFile(abs) || isDir(abs);
}

function resolveWsDir(root, slug) {
  if (!slug) return null;
  const n = slug.replace(/\\/g, '/').replace(/\/$/, '');
  const cands = [
    path.join(root, n),
    path.join(root, '.planning', n),
    path.join(root, '.planning', 'done', n),
    path.join(root, '.planning', path.basename(n)),
    path.join(root, '.planning', 'done', path.basename(n)),
  ];
  for (const d of cands) {
    if (isFile(path.join(d, 'plan.md')) || isDir(d)) return d;
  }
  return null;
}

function positionFromDir(wsAbs) {
  const text = read(path.join(wsAbs, 'plan.md'));
  if (text === null) return [];
  let f = false; const res = [];
  for (const ln of text.split('\n')) {
    if (/^## 当前位置/.test(ln)) { f = true; continue; }
    if (f && /^- /.test(ln)) { res.push(ln); if (res.length >= 3) break; }
  }
  return res;
}

function findingsForWorkspace(root, slugName, wsRel) {
  return parseFindings(root).filter((e) => {
    const blob = `${e.trace}\n${e.raw.join('\n')}`;
    if (!blob.includes('过程追溯')) return false;
    if (slugName && blob.includes(slugName)) return true;
    if (wsRel && blob.includes(wsRel.replace(/\\/g, '/'))) return true;
    return false;
  });
}

function lookupTasks(doc, name) {
  return allTasks(doc).filter((t) => normTitle(t.title) === normTitle(name));
}

function cmdTask(root, name, opts) {
  const doc = loadTasksDoc(root);
  const hits = lookupTasks(doc, name);
  if (!hits.length) { out(`[plan] 未找到任务：${name}`); return 2; }
  if (hits.length > 1) {
    out(`[plan] 任务名歧义：${name}`);
    for (const t of hits) out(`- ${t.zone} ｜ ${normTitle(t.title)}`);
    return 2;
  }
  const t = hits[0];
  const fields = [
    ['DoD', dodOf(doc, t)],
    ['前置', taskField(doc, t, RE_PRE)],
    ['工作区', taskField(doc, t, RE_WORKSPACE)],
    ['标签', taskField(doc, t, RE_TAG)],
    ['依据', taskField(doc, t, RE_BASIS)],
    ['来自', taskField(doc, t, RE_FROM)],
    ['结论', taskField(doc, t, RE_CONC)],
  ];
  out(`### ${normTitle(t.title)}`);
  for (const [k, v] of fields) {
    if (v) out(`- ${k}：${v}`);
  }
  const fids = [...parseFids(taskField(doc, t, RE_BASIS)), ...parseFids(taskField(doc, t, RE_CONC))];
  const findings = parseFindings(root).filter((e) => fids.includes(e.id));
  const fromQ = inboxQuery(taskField(doc, t, RE_FROM));
  const inboxHits = parseInbox(root).filter((i) => {
    if (fromQ && (i.title === fromQ || similarTitles(i.title, fromQ))) return true;
    if (i.resolved && i.resolvedLine && i.resolvedLine.includes(normTitle(t.title))) return true;
    return false;
  });
  out('关联：');
  if (findings.length) for (const e of findings) out(`- ${findingIndexLine(e)}`);
  else out('- 结论：无');
  if (inboxHits.length) for (const i of inboxHits) out(`- INBOX ${i.title}${i.resolved ? ` → ${i.resolvedLine || '已解决'}` : ''}`);
  else out('- INBOX：无');
  if (opts.full) {
    for (const e of findings) {
      out(`--- ${e.id} ---`);
      out(...e.raw);
    }
    for (const i of inboxHits) {
      out('--- INBOX ---');
      out(i.line);
      if (i.resolvedLine) out(`- 已解决：${i.resolvedLine}`);
    }
  }
  return 0;
}

function cmdWs(root, slug, opts) {
  if (opts.full && !slug) {
    out('[plan] 缺少工作区：plan.mjs ws <slug> --full');
    return 3;
  }
  if (!slug) {
    const names = activeWorkspaces(root);
    if (!names.length) { out('（无匹配）'); return 0; }
    for (const name of names) {
      const pos = workspacePosition(root, name);
      out(`.planning/${name}${pos[0] ? ` ｜ ${pos[0].replace(/^- /, '')}` : ''}`);
    }
    return 0;
  }
  const wsAbs = resolveWsDir(root, slug);
  if (!wsAbs) { out(`[plan] 未找到工作区：${slug}`); return 2; }
  const rel = path.relative(root, wsAbs).replace(/\\/g, '/');
  if (opts.full) {
    const text = read(path.join(wsAbs, 'progress.md'));
    if (text === null) { out(`[plan] 未找到 ${rel}/progress.md`); return 2; }
    out(text.replace(/\n$/, ''));
    return 0;
  }
  const pos = positionFromDir(wsAbs);
  if (pos.length) out(...pos);
  else out('（无当前位置）');
  const slugName = path.basename(wsAbs);
  const produced = findingsForWorkspace(root, slugName, rel);
  if (produced.length) for (const e of produced) out(findingIndexLine(e));
  return 0;
}

function cmdLinks(root, opts) {
  const doc = loadTasksDoc(root);
  const tasks = allTasks(doc);
  const findings = parseFindings(root);
  const inbox = parseInbox(root);
  const fidSet = new Set(findings.map((e) => e.id));
  const titleSet = new Set(tasks.map((t) => normTitle(t.title)));
  const doneSet = new Set(tasks.filter((t) => t.zone === '已完成' || /✅/.test(t.title)).map((t) => normTitle(t.title)));

  const edges = [];
  const orphans = [];
  const linked = new Set();

  for (const t of tasks) {
    const title = normTitle(t.title);
    const conc = taskField(doc, t, RE_CONC);
    const basis = taskField(doc, t, RE_BASIS);
    const from = taskField(doc, t, RE_FROM);
    const pre = taskField(doc, t, RE_PRE);
    const ws = taskField(doc, t, RE_WORKSPACE);
    const fOut = parseFids(conc);
    const fIn = parseFids(basis);
    if (fOut.length || fIn.length || from || pre) linked.add(title);
    if (fOut.length) edges.push(`T ${title} → ${fOut.join(',')}`);
    if (from) {
      const q = inboxQuery(from);
      const solved = inbox.filter((i) => i.resolved && (i.title === q || similarTitles(i.title, q)));
      if (solved.length) edges.push(`T ${title} ｜ 解决 INBOX ${q}`);
      else if (t.zone !== '已完成') edges.push(`INBOX ${q} → 认领中 ${title}`);
      linked.add(title);
    }
    if (pre) edges.push(`T ${title} → 前置 ${pre}`);

    const done = t.zone === '已完成' || /✅/.test(t.title);
    if (done && ws && !conc) orphans.push(`⚠️ 有工作区的已完成任务缺「结论」行：${title}`);
    for (const id of [...fOut, ...fIn]) {
      if (!fidSet.has(id)) orphans.push(`⚠️ 引用不存在的 ${id}（任务 ${title}）`);
    }
    if (from) {
      const q = inboxQuery(from);
      if (!inbox.some((i) => i.title === q || similarTitles(i.title, q) || i.line.includes(q))) {
        orphans.push(`⚠️ 来自 INBOX 不存在：${q}（任务 ${title}）`);
      }
    }
  }

  for (const e of findings) {
    const spawned = tasks.filter((t) => parseFids(taskField(doc, t, RE_BASIS)).includes(e.id));
    if (spawned.length) edges.push(`F ${e.id} → 催生任务 ${spawned.map((t) => normTitle(t.title)).join(',')}`);
    for (const p of [e.material, e.trace]) {
      if (p && !repoPathOk(root, p)) orphans.push(`⚠️ 路径打不开：${p}（${e.id}）`);
    }
    if (/调研探针|开发中发现/.test(e.source)) {
      const claimed = tasks.some((t) => parseFids(`${taskField(doc, t, RE_CONC) || ''} ${taskField(doc, t, RE_BASIS) || ''}`).includes(e.id));
      const hasWs = /[.]planning/.test(`${e.material} ${e.trace}`);
      if (!claimed && !hasWs) orphans.push(`⚠️ ${e.id} 来源=${e.source} 且无工作区/任务关联`);
    }
  }

  for (const i of inbox) {
    if (!i.resolved || i.section !== 'pending') continue;
    const m = String(i.resolvedLine).match(/^([^✅（(]+)/);
    const tn = m ? m[1].trim() : '';
    if (tn && !doneSet.has(normTitle(tn)) && !titleSet.has(normTitle(tn))) {
      orphans.push(`⚠️ 已解决指向不存在的任务：${tn}`);
    } else if (tn && !doneSet.has(normTitle(tn))) {
      orphans.push(`⚠️ 已解决指向未完成任务：${tn}`);
    } else if (tn) linked.add(normTitle(tn));
  }

  if (opts.orphan) {
    if (!orphans.length) out('（无匹配）');
    else out(...orphans);
    return 0;
  }
  if (opts.unlinked) {
    const u = tasks.map((t) => normTitle(t.title)).filter((n) => !linked.has(n));
    if (!u.length) out('（无匹配）');
    else for (const n of u) out(`T ${n}`);
    return 0;
  }
  if (!edges.length) out('（无匹配）');
  else out(...edges);
  out(`统计：边 ${edges.length} ｜ 任务 ${tasks.length} ｜ 结论 ${findings.length} ｜ INBOX ${inbox.length} ｜ ⚠️ ${orphans.length}`);
  return 0;
}

function upsertDocField(doc, task, key, value) {
  const re = new RegExp(`^-\\s*\\**${key}\\**\\s*[:：]`);
  const line = `- ${key}：${value}`;
  for (let i = task.start + 1; i < task.end; i++) {
    if (re.test(doc.lines[i])) { doc.lines[i] = line; return; }
  }
  const tail = findBlockTail(doc, task);
  doc.lines.splice(tail, 0, line);
  task.end++;
}

function writeInboxResolved(root, items, taskName, date) {
  const file = path.join(root, 'INBOX.md');
  const text = read(file);
  if (text === null || !items.length) return;
  const want = new Set(items.map((i) => i.line));
  const done = `- 已解决：${taskName} ✅（${date}）`;
  const lines = text.split('\n');
  const next = [];
  for (let i = 0; i < lines.length; i++) {
    next.push(lines[i]);
    if (want.has(lines[i].trim()) && !/^-\s*已解决/.test(lines[i + 1] || '')) next.push(done);
  }
  fs.writeFileSync(file, next.join('\n'));
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
  const research = fromSection === '调研' || taskHasTimebox(doc, moved);

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
      let notesTpl = null;
      if (research) {
        notesTpl = read(path.join(tplDir, 'notes-index.md'));
        if (notesTpl === null) { out('[plan] 工作区模板缺失（assets/templates/notes-index.md），请检查技能安装完整性'); return 1; }
      }
      fs.mkdirSync(wsAbs, { recursive: true });
      let planText = fillTemplate(planTpl, name, date);
      if (rebuilt) planText = `⚠️ 工作区曾于 ${localDate()} 丢失，此为重建，历史进度未恢复\n\n${planText}`;
      fs.writeFileSync(path.join(wsAbs, 'plan.md'), planText);
      fs.writeFileSync(path.join(wsAbs, 'progress.md'), fillTemplate(progTpl, name, date));
      let notesCreated = false;
      if (notesTpl !== null) {
        const notesDir = path.join(wsAbs, 'notes');
        fs.mkdirSync(notesDir, { recursive: true });
        fs.writeFileSync(path.join(notesDir, 'index.md'), fillTemplate(notesTpl, name, date));
        notesCreated = true;
      }
      out(rebuilt
        ? `[plan] 工作区曾丢失，已按原 slug 重建：${slugDir}/（历史进度未恢复）`
        : `[plan] 已建工作区：${slugDir}/（plan.md + progress.md${notesCreated ? ' + notes/' : ''}）`);
    }
    // 任务行下补工作区关联行（唯一关联据）
    if (moved && !taskField(doc, moved, RE_WORKSPACE)) {
      doc.lines.splice(findBlockTail(doc, moved), 0, `- 工作区：${slugDir}/`);
      saveTasksDoc(doc);
      out(`[plan] TASKS.md 已补关联行：工作区：${slugDir}/`);
    }
  }
  // 存量提醒：认领新任务时「进行中」还有其他任务 → 提示先收尾或显式暂停（提醒非阻断）
  const others = tasksInSection(doc, '进行中').tasks.filter((t) => normTitle(t.title) !== normTitle(name));
  if (others.length) {
    out(`[plan] 提醒：「进行中」还有 ${others.length} 个任务未收尾：`);
    for (const t of others) out(`[plan] - ${normTitle(t.title)}（已做完请先走完成流程并 finish；暂停请移回「已拆好（待做）」）`);
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

  const slugName = wsRel ? path.basename(wsRel) : '';
  const concIds = findingsForWorkspace(root, slugName, wsRel).map((e) => e.id);
  if (concIds.length) upsertDocField(doc, task, '结论', concIds.join(','));

  const pending = parseInbox(root).filter((i) => i.section === 'pending' && !i.resolved);
  const resolveTargets = [];
  const warnLines = [];
  const addResolve = (q) => {
    if (!q) return;
    const qn = inboxQuery(q);
    const hit = pending.find((i) => i.title === qn || similarTitles(i.title, qn) || i.line.includes(qn));
    if (hit) resolveTargets.push(hit);
    else warnLines.push(`[plan] 警告：未匹配未决 INBOX「${qn}」`);
  };
  const fromVal = taskField(doc, task, RE_FROM);
  if (fromVal) addResolve(fromVal);
  if (opts.resolve) addResolve(opts.resolve);
  if (!fromVal && !opts.resolve) {
    for (const i of pending) {
      if (similarTitles(i.title, name)) {
        warnLines.push(`[plan] 警告：未决 INBOX「${i.title}」与本任务标题相似，未写已解决（补 --resolve 或任务块 - 来自：）`);
      }
    }
  }

  // 机械动作：移入已完成段 + ✅ + 完成日期
  const block = removeBlock(doc, task);
  block[0] = block[0].includes('✅') ? block[0] : `${block[0]} ✅`;
  if (!block.some((l) => RE_DONE_DATE.test(l))) block.push(`- 完成：${date}`);
  insertBlock(doc, '已完成', block);
  saveTasksDoc(doc);
  out(`[plan] 已完成：✅ ${normTitle(task.title)}（完成：${date}）→「已完成（待归档）」`);
  if (concIds.length) out(`[plan] 已回写结论：${concIds.join(',')}`);
  if (resolveTargets.length) {
    writeInboxResolved(root, resolveTargets, normTitle(task.title), date);
    out(`[plan] 已写 INBOX 已解决：${resolveTargets.map((i) => i.title).join('、')}`);
  }
  for (const w of warnLines) out(w);

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
  cmdReindex(root, true);
  out('[plan] 已再生 FINDINGS 索引');
  return 0;
}

const INDEX_BEGIN = '<!-- plan-index:begin | 引擎维护：finish / reindex / finding-add 时从正文重新生成，手改会被覆盖 -->';
const INDEX_END = '<!-- plan-index:end -->';

function cmdReindex(root, quiet) {
  const file = path.join(root, 'FINDINGS.md');
  const text = read(file);
  if (text === null) {
    if (!quiet) out('[plan] 未找到 FINDINGS.md');
    return quiet ? 0 : 1;
  }
  const entries = parseFindings(root);
  const block = [INDEX_BEGIN, ...entries.map((e) => `- ${findingIndexLine(e)}`), INDEX_END].join('\n');
  const re = /<!--\s*plan-index:begin[\s\S]*?<!--\s*plan-index:end\s*-->/;
  let next;
  if (re.test(text)) next = text.replace(re, block);
  else if (/^##\s*索引/m.test(text)) {
    next = text.replace(/^(##\s*索引[^\n]*\n)/m, `$1\n${block}\n`);
  } else {
    next = `${text.replace(/\s*$/, '')}\n\n## 索引\n\n${block}\n`;
  }
  fs.writeFileSync(file, next);
  if (!quiet) out(`[plan] 已再生 FINDINGS 索引（${entries.length} 条）`);
  return 0;
}


// ── doctor 子命令（1:1 移植 plan-doctor.sh 输出行 + 新增 node 检查） ──

// ── 追加写入族（task-add / finding-add / inbox-add / progress-log）──
// 定位：只做「追加一条」的搬砖。判断（标题 / DoD / 结论）仍由 agent 想好、经参数交给引擎。
// 纪律：查重与引用校验全部在落盘前做完，任何一项不过 → 不落盘。
// 依据 docs/context-query-write-path.md（§4 命令契约）。

const LIMIT_DOD = 200;          // --dod 上限（Windows argv 与「一句 DoD」双重理由）
const LIMIT_TITLE = 40;         // FINDINGS 主题上限
const LIMIT_CONCLUSION = 500;   // 结论一段话上限
const LIMIT_TEXT = 200;         // progress 单行日志上限
const FINDING_SOURCES = ['调研探针', '开发中发现', '失败尝试', '外部输入'];
const PROGRESS_KINDS = ['进展', '决策', '错误'];

/** FINDINGS.md + FINDINGS.archive.md 里已用过的 F 编号。 */
function existingFids(root) {
  const text = [read(path.join(root, 'FINDINGS.md')), read(path.join(root, 'FINDINGS.archive.md'))]
    .filter((t) => t !== null).join('\n');
  return new Set([...text.matchAll(/^###\s*(F\d+)/gm)].map((m) => m[1].replace(/^f/i, 'F')));
}

/** 下一个 F 编号：热区 + 归档已用最大 + 1；永不复用。 */
function nextFid(root) {
  const nums = [...existingFids(root)].map((s) => Number(s.slice(1)));
  return `F${(nums.length ? Math.max(...nums) : 0) + 1}`;
}

/** 本命令不该出现的 flag（含 parseArgs 兜底抓到的未知 flag）→ 退出 3。 */
function rejectFlags(opts, allowed) {
  const bad = [];
  if (opts.unknownFlag) bad.push(opts.unknownFlag);
  for (const k of Object.keys(opts)) {
    if (k === 'positional' || k === 'unknownFlag' || allowed.includes(k)) continue;
    bad.push(`--${k}`);
  }
  return bad;
}

/** 插入段首（紧急插队）：段内第一个任务块之前；段内无块时等同追加。 */
function insertBlockHead(doc, sectionPrefix, block) {
  const sec = findSection(doc, sectionPrefix);
  if (!sec) throw new Error(`TASKS.md 缺少「${sectionPrefix}」段`);
  let idx = sec.end;
  for (let i = sec.start; i < sec.end; i++) if (/^### /.test(doc.lines[i])) { idx = i; break; }
  const ins = [...block];
  if (doc.lines[idx - 1] !== undefined && doc.lines[idx - 1].trim() !== '') ins.unshift('');
  if (doc.lines[idx] !== undefined && doc.lines[idx].trim() !== '') ins.push('');
  doc.lines.splice(idx, 0, ...ins);
}

/** FINDINGS.md 中某 F 条目的行范围（不含尾部空行），找不到返回 null。 */
function entryRange(lines, id) {
  const start = lines.findIndex((l) => new RegExp(`^###\\s+${id}\\s*[：:]`).test(l));
  if (start < 0) return null;
  let end = start + 1;
  while (end < lines.length && !/^###\s+F\d+\s*[：:]/.test(lines[end]) && !/^##\s/.test(lines[end])) end++;
  while (end > start + 1 && lines[end - 1].trim() === '') end--;
  return { start, end };
}

/** 在「热条目」段末尾追加条目块；无该段则追加到文件末尾。 */
function appendFindingBlock(root, block) {
  const file = path.join(root, 'FINDINGS.md');
  const lines = read(file).split('\n');
  const start = lines.findIndex((l) => /^##\s*热条目/.test(l));
  const from = start < 0 ? 0 : start + 1;
  let end = lines.length;
  if (start >= 0) for (let i = from; i < lines.length; i++) if (/^##\s/.test(lines[i])) { end = i; break; }
  let idx = end;
  while (idx > from && lines[idx - 1].trim() === '') idx--;
  const ins = [...block];
  if (lines[idx - 1] !== undefined && lines[idx - 1].trim() !== '') ins.unshift('');
  lines.splice(idx, 0, ...ins);
  fs.writeFileSync(file, lines.join('\n'));
}

/** 在某 F 条目块内追加一行（互写 `- 参见：F?` 用）。 */
function appendEntryLine(root, id, line) {
  const file = path.join(root, 'FINDINGS.md');
  const lines = read(file).split('\n');
  const range = entryRange(lines, id);
  if (!range) return false;
  lines.splice(range.end, 0, line);
  fs.writeFileSync(file, lines.join('\n'));
  return true;
}

/** 结论纪律：不许问句、不许「待确认 / 待决」。 */
function isOpenEnded(conclusion) {
  return /[?？]\s*$/.test(conclusion) || /待确认|待决/.test(conclusion);
}

/** 标题命中：精确相等优先，再走相似（相似对 <4 字的短标题恒为 false，故必须先看精确）。 */
const titleHit = (a, b) => normTitle(a) === normTitle(b) || similarTitles(a, b);

/** `- 已解决：X ✅（日期）` 里的任务名 X；旧「已裁决」区没有任务名，返回 ''。 */
function resolvedTaskName(item) {
  if (item.section === 'resolved') return '';
  const m = String(item.resolvedLine || '').match(/^([^✅（(]+)/);
  const tn = m ? m[1].trim() : '';
  return tn && !/[→—]/.test(tn) && !tn.startsWith('-') ? tn : '';
}

/** INBOX 已解决命中：既比停车项标题，也比「解决它的那个任务」的名字。 */
function solvedHit(items, name) {
  return items.filter((i) => i.resolved).find((i) => {
    if (titleHit(i.title, name)) return true;
    const tn = resolvedTaskName(i);
    return tn ? titleHit(tn, name) : false;
  });
}

/** INBOX 已解决命中时的统一回话（无任务名可回时不瞎编）。 */
function solvedNotice(item) {
  const tn = resolvedTaskName(item);
  return tn ? `[plan] 已由 ${tn} ✅ 实现` : `[plan] 已裁决：${item.title}`;
}

// ── task-add ────────────────────────────────────────────────

function cmdTaskAdd(root, name, opts) {
  const bad = rejectFlags(opts, ['dod', 'section', 'tag', 'basis', 'from', 'pre', 'head']);
  if (bad.length) { out(`[plan] 未知参数：${bad.join(' ')}`); return 3; }
  if (!name) { out('[plan] 缺少任务名：plan.mjs task-add "<任务名>" --dod "<一句>"'); return 3; }

  const dod = String(opts.dod || '').trim();
  if (!dod) { out('[plan] 缺少 --dod：一句可验证的完成标准（判断活，引擎不代写）'); return 3; }
  if (dod.length > LIMIT_DOD) { out(`[plan] --dod 超 ${LIMIT_DOD} 字（当前 ${dod.length}）：请压缩成一句`); return 3; }

  const section = opts.section || '已拆好';
  if (/^调研/.test(section)) {
    out('[plan] 本期不支持 --section 调研：调研任务必须带「时间盒」与「产出」，且时间盒须先问用户——命令化会绕过这条纪律');
    return 3;
  }
  if (!/^(已拆好|进行中)/.test(section)) { out(`[plan] 未知 --section：${section}（可选 已拆好 / 进行中）`); return 3; }
  if (opts.head && !/^已拆好/.test(section)) { out('[plan] --head 只对「已拆好」有效'); return 3; }

  const doc = loadTasksDoc(root);
  if (!doc) { out('[plan] 未找到 TASKS.md，请先运行 plan-init'); return 1; }
  if (!findSection(doc, section)) { out(`[plan] TASKS.md 缺「${section}」段`); return 1; }

  // 查重 1：TASKS 任意区标题重叠（含已完成）→ 退 2，不新建
  const dups = allTasks(doc).filter((t) => titleHit(t.title, name));
  if (dups.length) {
    out(`[plan] 任务重名，未新建：「${name}」已存在`);
    for (const t of dups) out(`- ${t.zone} ｜ ${normTitle(t.title)}`);
    return 2;
  }

  // 查重 2：INBOX 已解决 → 退 0（没新建，看 stdout 才知道）；未决相似 → 软警告仍新建
  const inbox = parseInbox(root);
  const solved = solvedHit(inbox, name);
  if (solved) { out(solvedNotice(solved)); return 0; }
  const pendingLike = inbox.filter((i) => i.section === 'pending' && !i.resolved).find((i) => titleHit(i.title, name));

  // 引用校验：任一项不存在 → 退 2，不落盘
  if (opts.basis) {
    const fids = parseFids(opts.basis);
    const have = existingFids(root);
    const missing = fids.filter((f) => !have.has(f));
    if (!fids.length || missing.length) { out(`[plan] 依据不存在的结论：${missing.join(',') || opts.basis}`); return 2; }
  }
  let fromLine = '';
  if (opts.from) {
    const q = inboxQuery(opts.from);
    if (!inbox.some((i) => i.title === q || similarTitles(i.title, q) || i.line.includes(q))) {
      out(`[plan] 未找到 INBOX 条目：${q}`);
      return 2;
    }
    fromLine = `INBOX ${q}`;
  }
  let preName = '';
  if (opts.pre) {
    const hit = allTasks(doc).find((t) => titleHit(t.title, opts.pre));
    if (!hit) { out(`[plan] 未找到前置任务：${opts.pre}`); return 2; }
    preName = normTitle(hit.title);
  }

  const block = [`### ${name}`, `- DoD：${dod}`];
  if (opts.tag) block.push(`- 标签：${opts.tag}`);
  if (opts.basis) block.push(`- 依据：${opts.basis}`);
  if (fromLine) block.push(`- 来自：${fromLine}`);
  if (preName) block.push(`- 前置：${preName}`);

  if (opts.head) insertBlockHead(doc, section, block);
  else insertBlock(doc, section, block);
  saveTasksDoc(doc);

  const zone = findSection(doc, section).name;
  const links = [];
  if (opts.basis) links.push(`依据：${opts.basis}`);
  if (fromLine) links.push(`来自：${fromLine}`);
  if (preName) links.push(`前置：${preName}`);
  out(`[plan] 已录入「${zone}」${opts.head ? '队首' : '队尾'}：${name}${opts.tag ? ` ｜ 标签：${opts.tag}` : ''}`);
  out(`- DoD：${dod}`);
  if (links.length) out(`- 关联：${links.join(' ｜ ')}`);
  if (pendingLike) out(`[plan] 提示：未决 INBOX「${pendingLike.title}」与本任务相似（未写已解决）`);
  return 0;
}

// ── finding-add ─────────────────────────────────────────────

function cmdFindingAdd(root, opts) {
  const bad = rejectFlags(opts, ['title', 'source', 'conclusion', 'tag', 'impact', 'material', 'trace', 'amend', 'force']);
  if (bad.length) { out(`[plan] 未知参数：${bad.join(' ')}`); return 3; }
  const file = path.join(root, 'FINDINGS.md');
  if (!isFile(file)) { out('[plan] 未找到 FINDINGS.md，请先运行 plan-init'); return 1; }

  // 规范化 --amend 的编号：F3 / f3 / 3 都收
  let amendId = null;
  if (opts.amend) {
    const raw = String(opts.amend).trim().replace(/^f/i, '');
    if (!/^\d+$/.test(raw)) { out(`[plan] --amend 需要 F 编号（如 --amend F3），收到：${opts.amend}`); return 3; }
    amendId = `F${raw}`;
  }

  const conclusion = String(opts.conclusion || '').trim();
  if (amendId) {
    if (opts.title || opts.source || opts.force) {
      out('[plan] --amend 不能与 --title / --source / --force 同用（补充不新开条目）');
      return 3;
    }
    // 条目级字段不能进「补」：parseFindings 按条目合并同名键，补里的 `- 标签：` 会覆盖原条目字段。
    // 明确拒绝而不是静默丢弃——静默丢弃会让 agent 以为记下了材料指针。
    const entryLevel = ['tag', 'impact', 'material', 'trace'].filter((k) => opts[k]);
    if (entryLevel.length) {
      out(`[plan] --amend 不支持 ${entryLevel.map((k) => `--${k}`).join(' / ')}：补小节只追加一段结论；这些是条目级字段，写进补里会覆盖原条目`);
      return 3;
    }
    if (!conclusion) { out('[plan] 缺少 --conclusion：要补充的一段话'); return 3; }
    if (conclusion.length > LIMIT_CONCLUSION) { out(`[plan] --conclusion 超 ${LIMIT_CONCLUSION} 字：改 notes + --material`); return 3; }
    if (isOpenEnded(conclusion)) { out('[plan] 结论不是陈述句（问句 / 待确认 / 待决）：不进热区'); return 3; }

    const lines = read(file).split('\n');
    const range = entryRange(lines, amendId);
    if (!range) { out(`[plan] 未找到 ${amendId}`); return 2; }
    // 用 #### 而非 ###：### 会被 parseFindings 当作新条目边界，把 F3 的块切断
    lines.splice(range.end, 0, '', `#### 补（${localDate()}）`, '', conclusion);
    fs.writeFileSync(file, lines.join('\n'));
    const rc = cmdReindex(root, true);
    out(`[plan] 已补充 ${amendId}：#### 补（${localDate()}）`);
    out(rc === 0 ? '[plan] 已再生索引' : '[plan] 索引再生失败，请手动运行 plan.mjs reindex');
    return 0;
  }

  const title = String(opts.title || '').trim();
  const source = String(opts.source || '').trim();
  if (!title) { out('[plan] 缺少 --title：条目的主题一句话（写进 ### F<n>：<主题>，索引与查重都靠它）'); return 3; }
  if (title.length > LIMIT_TITLE) { out(`[plan] --title 超 ${LIMIT_TITLE} 字（当前 ${title.length}）`); return 3; }
  if (!source) { out(`[plan] 缺少 --source：${FINDING_SOURCES.join(' / ')}`); return 3; }
  if (!FINDING_SOURCES.includes(source)) { out(`[plan] 未知 --source：${source}（${FINDING_SOURCES.join(' / ')}）`); return 3; }
  if (!conclusion) { out('[plan] 缺少 --conclusion：一段话结论（判断活，引擎不代写）'); return 3; }
  if (conclusion.length > LIMIT_CONCLUSION) { out(`[plan] --conclusion 超 ${LIMIT_CONCLUSION} 字：改 notes + --material`); return 3; }
  if (isOpenEnded(conclusion)) { out('[plan] 结论不是陈述句（问句 / 待确认 / 待决）：不进热区'); return 3; }
  if (opts.material && !repoPathOk(root, opts.material)) { out(`[plan] 材料路径打不开：${opts.material}`); return 2; }

  // 同主题查重：已有有效条目 → 逼 --amend；确有第二条独立结论才 --force
  const hit = parseFindings(root)
    .filter((e) => !/推翻/.test(e.status))
    .find((e) => titleHit(e.theme, title) || similarTitles(e.theme, conclusion));
  if (hit && !opts.force) {
    out(`[plan] 同主题已有 ${hit.id}：${hit.theme}`);
    out(`[plan] 改用 --amend ${hit.id} 补充；确属另一条独立结论则加 --force`);
    return 2;
  }

  const id = nextFid(root);
  const block = [
    `### ${id}：${title}`,
    `- 日期：${localDate()}`,
    `- 来源：${source}`,
  ];
  if (opts.tag) block.push(`- 标签：${opts.tag}`);
  block.push(`- 结论：${conclusion}`);
  if (opts.material) block.push(`- 材料：${opts.material}`);
  if (opts.trace) block.push(`- 过程追溯：${opts.trace}`);
  block.push(`- 影响：${opts.impact || '无'}`);
  block.push('- 状态：有效');
  if (hit && opts.force) block.push(`- 参见：${hit.id}`);

  appendFindingBlock(root, block);
  if (hit && opts.force) appendEntryLine(root, hit.id, `- 参见：${id}`);

  const rc = cmdReindex(root, true);
  const made = parseFindings(root).find((e) => e.id === id);
  out(made ? findingIndexLine(made) : `${id} | ${localDate()} | ${opts.tag || '未分类'} | 有效 | ${title}`);
  out(rc === 0 ? '[plan] 已再生索引' : '[plan] 索引再生失败，请手动运行 plan.mjs reindex');
  return 0;
}

// ── inbox-add ───────────────────────────────────────────────

function cmdInboxAdd(root, name, opts) {
  const bad = rejectFlags(opts, ['flag', 'origin', 'finding', 'date']);
  if (bad.length) { out(`[plan] 未知参数：${bad.join(' ')}`); return 3; }
  if (!name) { out('[plan] 缺少标题：plan.mjs inbox-add "<想法一句话>"'); return 3; }

  let mark = '⚪';
  if (opts.flag) {
    if (opts.flag === '红') mark = '🔴';
    else if (opts.flag !== '白') { out(`[plan] 未知 --flag：${opts.flag}（红 / 白）`); return 3; }
  }

  let fid = '';
  if (opts.finding) {
    const fids = parseFids(opts.finding);
    const have = existingFids(root);
    const missing = fids.filter((f) => !have.has(f));
    if (!fids.length || missing.length) { out(`[plan] 引用不存在的结论：${missing.join(',') || opts.finding}`); return 2; }
    fid = fids.join(',');
  }

  const file = path.join(root, 'INBOX.md');
  if (!isFile(file)) { out('[plan] 未找到 INBOX.md，请先运行 plan-init'); return 1; }

  const items = parseInbox(root);
  const solved = solvedHit(items, name);
  if (solved) { out(solvedNotice(solved)); return 0; }
  const pendingLike = items.filter((i) => i.section === 'pending' && !i.resolved).find((i) => titleHit(i.title, name));

  const tail = [];
  if (opts.origin) tail.push(`来源：${opts.origin}`);
  if (fid) tail.push(fid);
  const line = `- [ ] ${opts.date || localDate()} ${mark} ${name}${tail.length ? ` — ${tail.join(' ｜ ')}` : ''}`;

  const lines = read(file).split('\n');
  const start = lines.findIndex((l) => /^##\s*待裁决/.test(l));
  if (start < 0) { out('[plan] INBOX.md 缺「待裁决」段'); return 2; }
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) if (/^##\s/.test(lines[i])) { end = i; break; }
  let idx = end;
  while (idx > start + 1 && lines[idx - 1].trim() === '') idx--;
  const ins = [line];
  if (lines[idx - 1] !== undefined && lines[idx - 1].trim() !== '') ins.unshift('');
  lines.splice(idx, 0, ...ins);
  fs.writeFileSync(file, lines.join('\n'));

  out(`[plan] 已停 INBOX：${name}`);
  if (pendingLike) out(`[plan] 提示：未决 INBOX「${pendingLike.title}」相似，仍已写入（不自动合并）`);
  return 0;
}

// ── progress-log ────────────────────────────────────────────

function cmdProgressLog(root, slug, opts) {
  const bad = rejectFlags(opts, ['kind', 'text', 'position', 'next', 'date']);
  if (bad.length) { out(`[plan] 未知参数：${bad.join(' ')}`); return 3; }
  if (!slug) { out('[plan] 缺少工作区：plan.mjs progress-log <slug> --text "<一行>"'); return 3; }

  const text = String(opts.text || '').trim();
  if (text && text.length > LIMIT_TEXT) { out(`[plan] --text 超 ${LIMIT_TEXT} 字（当前 ${text.length}）：详情写 notes/`); return 3; }
  if (!text && !opts.position && !opts.next) {
    out('[plan] 缺少 --text / --position / --next：至少要给一样');
    return 3;
  }
  if (!text && opts.kind) { out('[plan] --kind 只在给了 --text 时有意义（没有日志行可归类）'); return 3; }
  const kind = opts.kind || '进展';
  if (text && !PROGRESS_KINDS.includes(kind)) { out(`[plan] 未知 --kind：${kind}（${PROGRESS_KINDS.join(' / ')}）`); return 3; }

  const wsAbs = resolveWsDir(root, slug);
  if (!wsAbs) { out(`[plan] 未找到工作区：${slug}`); return 2; }
  const rel = path.relative(root, wsAbs).replace(/\\/g, '/');
  if (/(^|\/)done\//.test(rel)) { out(`[plan] 工作区已归档、只读：${rel}`); return 2; }

  const acts = [];
  if (text) {
    const progFile = path.join(wsAbs, 'progress.md');
    if (!isFile(progFile)) { out(`[plan] 未找到 ${rel}/progress.md`); return 2; }
    const lines = read(progFile).split('\n');
    const date = opts.date || localDate();
    const secStart = lines.findIndex((l) => /^##\s*日志/.test(l));
    const from = secStart < 0 ? 0 : secStart + 1;
    let secEnd = lines.length;
    if (secStart >= 0) for (let i = from; i < lines.length; i++) if (/^##\s/.test(lines[i])) { secEnd = i; break; }

    const dayRe = new RegExp(`^###\\s*${date}\\s*$`);
    let day = -1;
    for (let i = from; i < secEnd; i++) if (dayRe.test(lines[i].trim())) { day = i; break; }

    if (day < 0) {
      let at = secEnd;
      while (at > from && lines[at - 1].trim() === '') at--;
      lines.splice(at, 0, '', `### ${date}`, '', `- ${kind}：${text}`);
    } else {
      let end = day + 1;
      while (end < secEnd && !/^###\s/.test(lines[end])) end++;
      while (end > day + 1 && lines[end - 1].trim() === '') end--;
      lines.splice(end, 0, `- ${kind}：${text}`);
    }
    fs.writeFileSync(progFile, lines.join('\n'));
    acts.push(`已记 progress（${kind}）`);
  }

  if (opts.position || opts.next) {
    const planFile = path.join(wsAbs, 'plan.md');
    if (!isFile(planFile)) { out(`[plan] 未找到 ${rel}/plan.md`); return 2; }
    const lines = read(planFile).split('\n');
    const start = lines.findIndex((l) => /^##\s*当前位置/.test(l));
    if (start < 0) { out('[plan] plan.md 缺「当前位置」段'); return 2; }
    let end = lines.length;
    for (let i = start + 1; i < lines.length; i++) if (/^##\s/.test(lines[i])) { end = i; break; }
    const idxs = [];
    for (let i = start + 1; i < end; i++) if (/^- /.test(lines[i])) idxs.push(i);

    // 保留模板里的标签（进行到哪一步 / 下一步要做什么），只换值
    const setLine = (nth, raw) => {
      const i = idxs[nth - 1];
      if (i === undefined) { out(`[plan] 「当前位置」第 ${nth} 条不存在`); return false; }
      const m = lines[i].match(/^-\s*([^：:]+)[：:]/);
      const label = m ? m[1].trim() : '';
      const val = String(raw).trim();
      const dup = label && (val === label || val.startsWith(`${label}：`) || val.startsWith(`${label}:`));
      lines[i] = label && !dup ? `- ${label}：${val}` : `- ${val}`;
      return true;
    };
    const changed = [];
    if (opts.position) { if (!setLine(1, opts.position)) return 2; changed.push(1); }
    if (opts.next) { if (!setLine(2, opts.next)) return 2; changed.push(2); }
    fs.writeFileSync(planFile, lines.join('\n'));
    acts.push(`已改当前位置（第 ${changed.join('、')} 条）`);
  }

  out(`[plan] ${acts.join(' ｜ ')}：${rel}`);
  return 0;
}

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
    const findingsPath = path.join(cwd, 'FINDINGS.md');
    if (isFile(findingsPath)) {
      const ft = read(findingsPath) || '';
      if (!/plan-index:begin/.test(ft) || !/<!--\s*plan-index:end/.test(ft)) {
        warn('FINDINGS 索引: 缺 plan-index 受管标记（跑 plan.mjs reindex；旧项目属预期）');
      } else pass('FINDINGS 索引: 受管标记存在');
      const badH = ft.split('\n').filter((l) => /^###\s+/.test(l) && !/^###\s+F\d+/.test(l) && !/^###\s+F</.test(l));
      if (badH.length) warn(`FINDINGS 解析: ${badH.length} 个无法按 F 编号解析的标题`);
    }
    const inboxPath = path.join(cwd, 'INBOX.md');
    if (isFile(inboxPath)) {
      let sec = null; let badI = 0;
      for (const ln of (read(inboxPath) || '').split('\n')) {
        if (/^##\s/.test(ln)) { sec = /待裁决/.test(ln) ? 'p' : null; continue; }
        if (sec === 'p' && /^-\s/.test(ln) && !/^-\s*\[/.test(ln) && !/^-\s*已解决/.test(ln) && !/^-\s*</.test(ln)) badI++;
      }
      if (badI) warn(`INBOX 解析: ${badI} 条待裁决行无法识别`);
    }
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
  const take = (i, a, key) => {
    const pfx = `--${key}=`;
    if (a.startsWith(pfx)) { opts[key] = a.slice(pfx.length); return i; }
    opts[key] = args[i + 1];
    return i + 1;
  };
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--workspace') opts.workspace = true;
    else if (a === '--json') opts.json = true;
    else if (a === '--global') opts.global = true;
    else if (a === '--resolved') opts.resolved = true;
    else if (a === '--all') opts.all = true;
    else if (a === '--unlinked') opts.unlinked = true;
    else if (a === '--orphan') opts.orphan = true;
    else if (a === '--full' || a.startsWith('--full=')) {
      opts.full = true;
      if (a.startsWith('--full=')) opts.fullId = a.slice(7);
      else if (args[i + 1] && !args[i + 1].startsWith('-')) opts.fullId = args[++i];
    }
    else if (a === '--date' || a.startsWith('--date=')) i = take(i, a, 'date');
    else if (a === '--resolve' || a.startsWith('--resolve=')) i = take(i, a, 'resolve');
    else if (a === '--tag' || a.startsWith('--tag=')) i = take(i, a, 'tag');
    else if (a === '--source' || a.startsWith('--source=')) i = take(i, a, 'source');
    else if (a === '--status' || a.startsWith('--status=')) i = take(i, a, 'status');
    else if (a === '--impact' || a.startsWith('--impact=')) i = take(i, a, 'impact');
    else if (a === '--head') opts.head = true;
    else if (a === '--force') opts.force = true;
    else if (a === '--amend' || a.startsWith('--amend=')) i = take(i, a, 'amend');
    else if (a === '--dod' || a.startsWith('--dod=')) i = take(i, a, 'dod');
    else if (a === '--section' || a.startsWith('--section=')) i = take(i, a, 'section');
    else if (a === '--basis' || a.startsWith('--basis=')) i = take(i, a, 'basis');
    else if (a === '--from' || a.startsWith('--from=')) i = take(i, a, 'from');
    else if (a === '--pre' || a.startsWith('--pre=')) i = take(i, a, 'pre');
    else if (a === '--title' || a.startsWith('--title=')) i = take(i, a, 'title');
    else if (a === '--conclusion' || a.startsWith('--conclusion=')) i = take(i, a, 'conclusion');
    else if (a === '--material' || a.startsWith('--material=')) i = take(i, a, 'material');
    else if (a === '--trace' || a.startsWith('--trace=')) i = take(i, a, 'trace');
    else if (a === '--origin' || a.startsWith('--origin=')) i = take(i, a, 'origin');
    else if (a === '--flag' || a.startsWith('--flag=')) i = take(i, a, 'flag');
    else if (a === '--finding' || a.startsWith('--finding=')) i = take(i, a, 'finding');
    else if (a === '--kind' || a.startsWith('--kind=')) i = take(i, a, 'kind');
    else if (a === '--text' || a.startsWith('--text=')) i = take(i, a, 'text');
    else if (a === '--position' || a.startsWith('--position=')) i = take(i, a, 'position');
    else if (a === '--next' || a.startsWith('--next=')) i = take(i, a, 'next');
    else if (a.startsWith('--')) opts.unknownFlag = a;
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
    '  status [--json]             底线：红线 + 里程碑 + 进行中一行 + 下一张 + INBOX 计数',
    '  next                        队首待做：标题 + DoD',
    '  task "<名>" [--full]        任务卡片 + 关联区',
    '  findings [--tag|--source|--status|--impact] [--full F3]  结论索引或单条全文',
    '  inbox [--resolved|--all]    未决索引 + 疑似已实现',
    '  ws [slug] [--full]          当前位置三行 / progress 全文',
    '  links [--unlinked|--orphan] 关联边 / 数据毛病',
    '  start "<任务名>" [--workspace] [--date YYYY-MM-DD]   认领任务',
    '  finish "<任务名>" [--resolve "<INBOX>"] [--date YYYY-MM-DD]  完成任务',
    '  reindex                     再生 FINDINGS 受管索引区',
    '  task-add "<标题>" --dod "<一句>" [--section 已拆好|进行中] [--tag X] [--basis F2]',
    '                              [--from "INBOX x"] [--pre "<任务名>"] [--head]   追加任务（落盘前查重）',
    '  finding-add --title "<主题>" --source <来源> --conclusion "<一段话>"',
    '                              [--tag X] [--impact 无] [--material <路径>] [--trace <路径>] [--force]',
    '  finding-add --amend F3 --conclusion "<补充>"        在 F3 下追加补，不新开号',
    '  inbox-add "<标题>" [--flag 红|白] [--origin "<来源>"] [--finding F3] [--date YYYY-MM-DD]',
    '  progress-log <slug> [--text "<一行>"] [--kind 进展|决策|错误] [--position "<一行>"] [--next "<一行>"]',
    '  doctor [--global]           安装自检（PASS / WARN / FAIL）',
    '',
    '环境变量：PLANNING_ROOT（项目根）、PLANNING_HOOKS_DISABLED=1（hook 静默）、PLANNING_HOOKS_NO_THROTTLE=1（关节流）',
  );
}

function noRoot() {
  out('[plan] 未找到计划体系（ROADMAP.md / TASKS.md / .planning 均不存在），请先运行 plan-init');
  return 1;
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
    if (!root) return 0;
    return fn(root) || 0;
  }

  const queries = new Set(['status', 'next', 'findings', 'inbox', 'task', 'ws', 'links']);
  if (queries.has(cmd)) {
    const bad = unknownFlag(opts);
    if (bad) return bad;
    const root = findRoot();
    if (!root) return noRoot();
    if (cmd === 'status') return cmdStatus(root, !!opts.json);
    if (cmd === 'next') return cmdNext(root);
    if (cmd === 'findings') return cmdFindings(root, opts);
    if (cmd === 'inbox') return cmdInbox(root, opts);
    if (cmd === 'task') {
      const name = opts.positional[0];
      if (!name) { out('[plan] 缺少任务名：plan.mjs task "<任务名>"'); return 3; }
      return cmdTask(root, name, opts);
    }
    if (cmd === 'ws') return cmdWs(root, opts.positional[0], opts);
    if (opts.unlinked && opts.orphan) { out('[plan] 未知参数：--unlinked 与 --orphan 不能同时用'); return 3; }
    return cmdLinks(root, opts);
  }


  const appends = new Set(['task-add', 'finding-add', 'inbox-add', 'progress-log']);
  if (appends.has(cmd)) {
    const root = findRoot();
    if (!root) return noRoot();
    if (cmd === 'task-add') return cmdTaskAdd(root, opts.positional[0], opts);
    if (cmd === 'finding-add') return cmdFindingAdd(root, opts);
    if (cmd === 'inbox-add') return cmdInboxAdd(root, opts.positional[0], opts);
    return cmdProgressLog(root, opts.positional[0], opts);
  }

  if (cmd === 'start' || cmd === 'finish') {
    const name = opts.positional[0];
    if (!name) { out(`[plan] 缺少任务名：plan.mjs ${cmd} "<任务名>"`); return 1; }
    const root = findRoot();
    if (!root) return noRoot();
    return cmd === 'start' ? cmdStart(root, name, opts) : cmdFinish(root, name, opts);
  }

  if (cmd === 'reindex') {
    const root = findRoot();
    if (!root) return noRoot();
    return cmdReindex(root, false);
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
