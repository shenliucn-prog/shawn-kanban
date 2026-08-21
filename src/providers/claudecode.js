import { join } from 'node:path';
import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { paths, getConfig } from '../config.js';

const WEEK = 7 * 24 * 60 * 60 * 1000;

// Count assistant/user messages in ~/.claude/projects/*.jsonl over the last 7 days.
// This is an approximation of Claude Code usage derived from local history.
export function getClaudeCodeUsage() {
  const cap = getConfig().claudeCap;
  const dir = paths.claude;
  if (!existsSync(dir)) {
    return { ok: false, error: 'no ~/.claude/projects', cap };
  }
  const cutoff = Date.now() - WEEK;
  let used = 0;
  try {
    const walk = (d) => {
      for (const name of readdirSync(d)) {
        const p = join(d, name);
        let st;
        try {
          st = statSync(p);
        } catch {
          continue;
        }
        if (st.isDirectory()) walk(p);
        else if (name.endsWith('.jsonl')) {
          used += countRecentMessages(p, cutoff);
        }
      }
    };
    walk(dir);
  } catch (e) {
    return { ok: false, error: e.message, cap };
  }
  return {
    ok: true,
    used7d: used,
    cap,
    source: 'local ~/.claude/projects (approx)'
  };
}

function countRecentMessages(file, cutoff) {
  let n = 0;
  try {
    const lines = readFileSync(file, 'utf-8').split('\n');
    for (const line of lines) {
      if (!line.trim()) continue;
      let o;
      try {
        o = JSON.parse(line);
      } catch {
        continue;
      }
      const ts = parseTs(o);
      if (ts == null || ts < cutoff) continue;
      const role = o.role || (o.message && o.message.role);
      if (role === 'user' || role === 'assistant') n++;
    }
  } catch {
    /* unreadable file: ignore */
  }
  return n;
}

function parseTs(o) {
  const raw = o.timestamp || (o.message && o.message.timestamp) || o.created_at;
  if (!raw) return null;
  const t = Date.parse(raw);
  return Number.isFinite(t) ? t : null;
}
