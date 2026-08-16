// Pure, framework-free status computation.
// This module has no I/O and is fully unit-testable without a database.

/**
 * Normalize a raw reading into the status object served to the Kindle.
 * @param {object} raw
 * @param {string} [raw.model]
 * @param {string} [raw.title]
 * @param {string} [raw.status]
 * @param {number} [raw.used]
 * @param {number} [raw.size]
 * @param {string} [raw.credit_json]
 * @param {number} [raw.lastActivityAt]
 * @param {number} [raw.updatedAt]
 * @param {string} [raw.source]
 */
export function computeStatus(raw = {}) {
  const model = raw.model || 'unknown';
  const title = raw.title || null;
  const status = raw.status || null;

  const used = Number.isFinite(raw.used) ? raw.used : null;
  const size = Number.isFinite(raw.size) ? raw.size : null;

  let remaining = null;
  let percent = null;
  if (used != null && size != null && size > 0) {
    remaining = Math.max(0, size - used);
    percent = Math.min(100, Math.max(0, Math.round((used / size) * 1000) / 10));
  }

  let credit = null;
  if (raw.credit_json) {
    try {
      credit = JSON.parse(raw.credit_json);
    } catch {
      credit = null;
    }
  }

  return {
    model,
    title,
    status,
    token: { used, size, remaining, percent },
    credit,
    lastActivityAt: raw.lastActivityAt ?? null,
    updatedAt: raw.updatedAt ?? null,
    source: raw.source || 'unknown'
  };
}

/**
 * Render a compact, human-readable one-liner (used by logs / e-ink fallback).
 */
export function formatStatus(s) {
  const t = s.token || {};
  const pct = t.percent == null ? 'n/a' : `${t.percent}%`;
  const rem = t.remaining == null ? 'n/a' : `${t.remaining} / ${t.size}`;
  const titlePart = s.title ? ` title=${s.title}` : '';
  return `model=${s.model} token=${rem} (${pct})${titlePart}`;
}
