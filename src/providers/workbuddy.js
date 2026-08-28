import { readStatus } from '../db.js';
import { getConfig } from '../config.js';

// WorkBuddy token quota, read live from its local SQLite DB (read-only).
// 统一度量衡：与 claudecode / codex 共用 used / cap / remaining / percent / unit 字段，
// 便于 UI 三行同构渲染（unit 区分单位：tokens vs messages）。
export function getWorkbuddy(db) {
  if (!db) {
    return {
      ok: false, error: 'db unavailable', model: 'unknown', token: null,
      used: null, cap: null, remaining: null, percent: 0, unit: 'tokens'
    };
  }
  try {
    const s = readStatus(db, { cwdFilter: getConfig().cwdFilter });
    const t = s.token || {};
    return {
      ok: true,
      model: s.model,
      title: s.title,
      token: {
        used: t.used,
        size: t.size,
        remaining: t.remaining,
        percent: t.percent
      },
      used: t.used,
      cap: t.size,
      remaining: t.remaining,
      percent: t.percent,
      unit: 'tokens',
      lastActivityAt: s.lastActivityAt,
      source: s.source
    };
  } catch (e) {
    return {
      ok: false, error: e.message, model: 'unknown', token: null,
      used: null, cap: null, remaining: null, percent: 0, unit: 'tokens'
    };
  }
}
