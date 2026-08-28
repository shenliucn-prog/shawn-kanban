#!/usr/bin/env node
// 本机 AI 额度上报器
// 读取本机的 WorkBuddy / Claude Code / Codex 额度，写入 data/quotas.json，
// 并（可选）通过 GitHub API 推到仓库，供 GitHub Actions 在云端渲染看板。
//
// 环境变量：
//   GITHUB_TOKEN   必填（要能写仓库，勾 repo 或 contents:write）
//   GITHUB_REPO   owner/repo，例如 shen/shawn-kanban
//   GITHUB_BRANCH 默认 main
//   REPORT_PATH   仓库内路径，默认 data/quotas.json
//   REPORT_EVERY  最小上报间隔（毫秒），默认 5 分钟
//   REPORT_DRY    设为 1 时只写本地文件，不推远端
//
// 用法：
//   node tools/report_quota.js             # 上报一次
//   node tools/report_quota.js --loop      # 常驻，按 REPORT_EVERY 循环
//   node tools/report_quota.js --dry       # 只写本地，不推远端

import { writeFileSync, readFileSync, existsSync, mkdirSync } from 'node:fs';
import { format } from 'node:util';
import { dirname, join } from 'node:path';
import { openDb, closeDb } from '../src/db.js';
import { config } from '../src/config.js';
import { getWorkbuddy } from '../src/providers/workbuddy.js';
import { getClaudeCodeUsage } from '../src/providers/claudecode.js';
import { getCodexUsage } from '../src/providers/codex.js';

const LOCAL_OUT = join(process.cwd(), 'data', 'quotas.json');
const REMOTE_PATH = process.env.REPORT_PATH || 'data/quotas.json';
const REPO = process.env.GITHUB_REPO || '';
const BRANCH = process.env.GITHUB_BRANCH || 'main';
const EVERY = Number(process.env.REPORT_EVERY || 5 * 60 * 1000);
const DRY = process.env.REPORT_DRY === '1';

// 注意：console.log 只对第一个参数做 %s 替换，所以这里先 format 再拼时间戳
function log(...a) {
  const ts = new Date().toLocaleTimeString('zh-CN', { hour12: false });
  console.log('[' + ts + ']', format(...a));
}

function collect() {
  let db = null;
  try {
    db = openDb(config.dbPath);
  } catch (e) {
    log('DB unavailable:', e.message);
  }
  try {
    return {
      ts: Date.now(),
      host: process.env.COMPUTERNAME || '',
      quotas: {
        workbuddy: getWorkbuddy(db),
        claudecode: getClaudeCodeUsage(),
        codex: getCodexUsage()
      }
    };
  } finally {
    if (db) closeDb(db);
  }
}

// 没有实质变化就不打扰 GitHub（省 API 额度、减少无意义 commit）
function significant(prev, next) {
  if (!prev || !prev.quotas) return true;
  const num = (v) => (typeof v === 'number' ? v : null);
  for (const k of ['workbuddy', 'claudecode', 'codex']) {
    const a = prev.quotas[k] || {};
    const b = (next.quotas && next.quotas[k]) || {};
    if (!!a.ok !== !!b.ok) return true;
    const ra = num(a.remaining);
    const rb = num(b.remaining);
    if (ra == null || rb == null) {
      if (ra !== rb) return true;
      continue;
    }
    if (Math.abs(ra - rb) > Math.max(1, Math.abs(ra) * 0.005)) return true;
  }
  return false;
}

async function pushToGithub(content) {
  const token = process.env.GITHUB_TOKEN;
  if (!token || !REPO) {
    log('skip push: need GITHUB_TOKEN and GITHUB_REPO');
    return false;
  }
  const api = 'https://api.github.com/repos/' + REPO + '/contents/' + REMOTE_PATH;
  const headers = {
    Authorization: 'Bearer ' + token,
    Accept: 'application/vnd.github+json',
    'User-Agent': 'shawn-kanban-reporter',
    'X-GitHub-Api-Version': '2022-11-28'
  };

  let sha = null;
  const getRes = await fetch(api + '?ref=' + BRANCH, { headers });
  if (getRes.ok) {
    const j = await getRes.json();
    sha = j.sha;
  } else if (getRes.status !== 404) {
    log('gh get failed', getRes.status, (await getRes.text()).slice(0, 120));
    return false;
  }

  const body = {
    message: 'chore(quotas): update ' + new Date().toISOString().slice(0, 16).replace('T', ' '),
    content: Buffer.from(content, 'utf-8').toString('base64'),
    branch: BRANCH
  };
  if (sha) body.sha = sha;

  const res = await fetch(api, {
    method: 'PUT',
    headers: { ...headers, 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  if (!res.ok) {
    log('gh put failed', res.status, (await res.text()).slice(0, 200));
    return false;
  }
  log('pushed to github', REPO, REMOTE_PATH);
  return true;
}

async function once(opts = {}) {
  const data = collect();
  const text = JSON.stringify(data, null, 2);

  let prev = null;
  try {
    if (existsSync(LOCAL_OUT)) prev = JSON.parse(readFileSync(LOCAL_OUT, 'utf-8'));
  } catch {
    /* ignore */
  }

  const changed = significant(prev, data) || opts.force;
  try {
    mkdirSync(dirname(LOCAL_OUT), { recursive: true });
    writeFileSync(LOCAL_OUT, text);
  } catch (e) {
    log('write local failed:', e.message);
  }

  if (changed) {
    const q = data.quotas;
    log(
      'changed  wb=%s/%s  claude=%s/%s  codex=%s',
      q.workbuddy && q.workbuddy.remaining,
      q.workbuddy && q.workbuddy.cap,
      q.claudecode && q.claudecode.remaining,
      q.claudecode && q.claudecode.cap,
      q.codex && q.codex.ok ? q.codex.remaining + '/' + q.codex.cap : 'n/a'
    );
    if (!DRY) await pushToGithub(text);
  } else {
    log('no significant change');
  }
}

const args = process.argv.slice(2);
await once({ force: args.includes('--force') });

if (args.includes('--loop')) {
  log('loop mode, every', Math.round(EVERY / 1000), 's');
  setInterval(() => {
    once().catch((e) => log('loop error:', e.message));
  }, EVERY);
}
