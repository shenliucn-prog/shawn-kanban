import { join } from 'node:path';
import { readdirSync, statSync, existsSync } from 'node:fs';
import { paths, getConfig } from '../config.js';

const WEEK = 7 * 24 * 60 * 60 * 1000;

// Approximate Codex usage by counting history/session files touched in the
// last 7 days under the Codex data directory. Structure varies by version,
// so this is best-effort and clearly labelled as an approximation.
export function getCodexUsage() {
  const cap = getConfig().codexCap;
  const dir = paths.codexCandidates.find((p) => existsSync(p));
  if (!dir) {
    return { ok: false, error: 'no codex data dir found', cap };
  }
  const cutoff = Date.now() - WEEK;
  let used = 0;
  try {
    const scan = (d, depth) => {
      if (depth > 4) return;
      let entries;
      try {
        entries = readdirSync(d);
      } catch {
        return;
      }
      for (const name of entries) {
        const p = join(d, name);
        let st;
        try {
          st = statSync(p);
        } catch {
          continue;
        }
        if (st.isDirectory()) {
          // session/conversation folders count as 1 unit if recently modified
          if (st.mtimeMs >= cutoff) used++;
          scan(p, depth + 1);
        } else if (/\.(jsonl|json|log)$/i.test(name) && st.mtimeMs >= cutoff) {
          used++;
        }
      }
    };
    scan(dir, 0);
  } catch (e) {
    return { ok: false, error: e.message, cap };
  }
  return {
    ok: true,
    used7d: used,
    cap,
    source: `local ${dir} (approx)`
  };
}
