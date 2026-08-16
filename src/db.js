import Database from 'better-sqlite3';
import { computeStatus } from './status.js';

/**
 * Open WorkBuddy's local SQLite database in read-only mode.
 * Read-only avoids locking the live DB and prevents accidental writes.
 * @param {string} path
 * @returns {import('better-sqlite3').Database}
 */
export function openDb(path) {
  return new Database(path, { readonly: true, fileMustExist: true });
}

/**
 * Close a previously opened database handle (safe to call repeatedly).
 * @param {import('better-sqlite3').Database} db
 */
export function closeDb(db) {
  try {
    db.close();
  } catch {
    /* already closed */
  }
}

/**
 * Read the normalized status for the user's most recent WorkBuddy session.
 *
 * Logic:
 *  - pick the session with the newest `last_activity_at` (optionally scoped by cwd)
 *  - read its token usage from `session_usage` via `session_id`
 *  - if that session has no usage row, fall back to the globally newest usage row
 *
 * @param {import('better-sqlite3').Database} db
 * @param {{ cwdFilter?: string }} [opts]
 */
export function readStatus(db, { cwdFilter = '' } = {}) {
  const latestParams = cwdFilter ? [cwdFilter] : [];
  const latestSession = db
    .prepare(
      `
      SELECT id, model, title, status, last_activity_at
      FROM sessions
      WHERE deleted_at IS NULL
      ${cwdFilter ? 'AND cwd = ?' : ''}
      ORDER BY last_activity_at DESC
      LIMIT 1
    `
    )
    .get(...latestParams);

  if (!latestSession) {
    return computeStatus({ source: 'empty' });
  }

  let usage = db
    .prepare(
      `
      SELECT used, size, updated_at, credit_json
      FROM session_usage
      WHERE session_id = ?
      LIMIT 1
    `
    )
    .get(latestSession.id);

  let source = 'session';
  if (!usage) {
    usage = db
      .prepare(
        `
        SELECT used, size, updated_at, credit_json
        FROM session_usage
        ORDER BY updated_at DESC
        LIMIT 1
      `
      )
      .get();
    source = 'fallback';
  }

  return computeStatus({
    model: latestSession.model,
    title: latestSession.title,
    status: latestSession.status,
    used: usage ? usage.used : null,
    size: usage ? usage.size : null,
    credit_json: usage ? usage.credit_json : null,
    lastActivityAt: latestSession.last_activity_at,
    updatedAt: usage ? usage.updated_at : null,
    source
  });
}
