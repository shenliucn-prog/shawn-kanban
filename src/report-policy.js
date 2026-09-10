// Compare against the last successful upload, never the latest local collection.
export function shouldUpload(previous, next, now = Date.now(), force = false) {
  if (force || !previous?.quotas || now - previous.ts >= 5 * 60 * 1000) return true;
  for (const key of ['workbuddy', 'claudecode', 'codex']) {
    const a = previous.quotas[key] || {};
    const b = next.quotas[key] || {};
    if (!!a.ok !== !!b.ok) return true;
    const ra = typeof a.remaining === 'number' ? a.remaining : null;
    const rb = typeof b.remaining === 'number' ? b.remaining : null;
    if (ra === null || rb === null) {
      if (ra !== rb) return true;
    } else if (Math.abs(ra - rb) > Math.max(1, Math.abs(ra) * 0.005)) return true;
  }
  return false;
}
