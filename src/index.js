import { createServer } from './server.js';
import { openDb, closeDb } from './db.js';
import { config } from './config.js';

let db = null;
try {
  db = openDb(config.dbPath);
  console.log('[shawn-kanban] opened DB:', config.dbPath);
} catch (e) {
  console.warn('[shawn-kanban] WARN: could not open DB at', config.dbPath, '-', e.message);
  console.warn('[shawn-kanban] service still runs; WorkBuddy quota will show unavailable.');
}

const server = createServer({ db, cfg: config });

server.listen(config.port, config.host, () => {
  console.log(`[shawn-kanban] listening on http://${config.host}:${config.port}`);
  console.log(`[shawn-kanban] Kindle/MacBook open http://<this-machine-ip>:${config.port}/api/dashboard`);
});

function shutdown() {
  console.log('[shawn-kanban] shutting down...');
  try {
    server.close();
  } catch {
    /* ignore */
  }
  if (db) closeDb(db);
  process.exit(0);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
