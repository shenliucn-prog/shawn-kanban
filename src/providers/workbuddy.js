import { readStatus } from '../db.js';
import { config } from '../config.js';

// WorkBuddy token quota, read live from its local SQLite DB (read-only).
export function getWorkbuddy(db) {
  if (!db) {
    return { ok: false, error: 'db unavailable', model: 'unknown', token: null };
  }
  try {
    const s = readStatus(db, { cwdFilter: config.cwdFilter });
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
      lastActivityAt: s.lastActivityAt,
      source: s.source
    };
  } catch (e) {
    return { ok: false, error: e.message, model: 'unknown', token: null };
  }
}
