import { readFileSync, existsSync } from 'node:fs';
import { getConfig } from './config.js';

// 本机上报上来的 AI 额度快照（cloud 模式下由 GitHub Actions 读取）。
// 上报器（tools/report_quota.js）把 workbuddy / claudecode / codex 的额度
// 写成 data/quotas.json，云端没有本地 DB，只能靠它。
// 超过 reportStaleMs 没更新 → stale=true，看板会标成"电脑离线"。

let _cache = { at: 0, value: null };
const CACHE_TTL = 30 * 1000; // 文件读取很便宜，但避免每次请求都读盘

export function getReported(force = false) {
  const now = Date.now();
  if (!force && _cache.at && now - _cache.at < CACHE_TTL) return _cache.value;

  const cfg = getConfig();
  if (!existsSync(cfg.quotasFile)) {
    const v = { ok: false, error: 'no report file', ts: null, ageMs: null, stale: true, quotas: null };
    _cache = { at: now, value: v };
    return v;
  }
  try {
    const d = JSON.parse(readFileSync(cfg.quotasFile, 'utf-8'));
    const ageMs = now - (Number(d.ts) || 0);
    const v = {
      ok: true,
      ts: Number(d.ts) || null,
      ageMs,
      stale: ageMs > cfg.reportStaleMs,
      quotas: d.quotas || {}
    };
    _cache = { at: now, value: v };
    return v;
  } catch (e) {
    const v = { ok: false, error: e.message, ts: null, ageMs: null, stale: true, quotas: null };
    _cache = { at: now, value: v };
    return v;
  }
}
