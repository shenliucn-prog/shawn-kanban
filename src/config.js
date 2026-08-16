import { homedir } from 'node:os';
import { join } from 'node:path';

// Runtime configuration, overridable via environment variables.
// Defaults target the local WorkBuddy install on this PC.
export const config = {
  // Path to WorkBuddy's local SQLite database (opened read-only at runtime).
  dbPath:
    process.env.WORKBUDDY_DB_PATH ||
    join(homedir(), '.workbuddy', 'workbuddy.db'),

  // Host/port the HTTP service binds to.
  // 0.0.0.0 makes it reachable from the Kindle over the LAN.
  host: process.env.HOST || '0.0.0.0',
  port: Number(process.env.PORT || 8787),

  // Optional scoping to a specific workspace cwd. Empty = newest session overall.
  cwdFilter: process.env.WORKBUDDY_CWD || '',

  // A reading older than this (ms) is flagged stale in the response.
  staleMs: Number(process.env.STALE_MS || 10 * 60 * 1000)
};
