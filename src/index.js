import { createServer } from './server.js';
import { openDb, closeDb } from './db.js';
import { config } from './config.js';

let db = null;
try {
  db = openDb(config.dbPath);
  console.log('[kindle-assistant] opened DB:', config.dbPath);
} catch (e) {
  console.warn(
    '[kindle-assistant] WARN: could not open DB at',
    config.dbPath,
    '-',
    e.message
  );
  console.warn(
    '[kindle-assistant] service will run, but /api/status returns null until the DB is available.'
  );
}

const server = createServer({ db, cfg: config });

server.listen(config.port, config.host, () => {
  console.log(
    `[kindle-assistant] listening on http://${config.host}:${config.port}`
  );
  console.log(
    `[kindle-assistant] Kindle can open http://<this-pc-ip>:${config.port}/`
  );
});

function shutdown() {
  console.log('[kindle-assistant] shutting down...');
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
