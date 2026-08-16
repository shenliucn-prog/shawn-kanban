import http from 'node:http';
import { readStatus } from './db.js';
import { config } from './config.js';

/**
 * Build the e-ink-friendly HTML page (B/W, large text, no animation).
 * @param {object|null} status
 */
function renderPage(status) {
  const t = status?.token || {};
  const pct = t.percent == null ? 'n/a' : `${t.percent}%`;
  const rem = t.remaining == null ? 'n/a' : `${t.remaining} / ${t.size}`;
  const model = status?.model || 'unknown';
  return `<!doctype html>
<html lang="zh">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Kindle Assistant</title>
<style>
  body { background:#fff; color:#000; font-family: sans-serif; margin:2rem; }
  h1 { font-size:2rem; }
  .row { font-size:1.6rem; margin:.6rem 0; }
  .big { font-size:2.4rem; font-weight:bold; }
  hr { border:none; border-top:2px solid #000; }
</style>
</head>
<body>
  <h1>Kindle Assistant</h1>
  <hr>
  <div class="row">Model: <span class="big">${model}</span></div>
  <div class="row">Token: <span class="big">${rem}</span> (${pct})</div>
  <hr>
  <div class="row"><a href="/api/status">JSON /api/status</a></div>
</body>
</html>`;
}

/**
 * Create the HTTP server.
 * @param {{ db?: import('better-sqlite3').Database, cfg?: object }} [opts]
 * @returns {import('node:http').Server}
 */
export function createServer({ db = null, cfg = config } = {}) {
  return http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    const status = db ? readStatus(db, { cwdFilter: cfg.cwdFilter }) : null;

    if (url.pathname === '/api/status') {
      res.writeHead(200, {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store'
      });
      res.end(
        JSON.stringify({ ok: true, data: status, serverTime: Date.now() }, null, 2)
      );
      return;
    }

    if (url.pathname === '/' || url.pathname === '/index.html') {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(renderPage(status));
      return;
    }

    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Not Found');
  });
}
