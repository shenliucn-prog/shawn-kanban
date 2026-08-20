import http from 'node:http';
import { buildDashboard } from './aggregator.js';
import { readStatus } from './db.js';
import { config } from './config.js';

function sendJson(res, obj) {
  res.writeHead(200, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': '*'
  });
  res.end(JSON.stringify(obj, null, 2));
}

function renderHtml(d) {
  const q = d.quotas || {};
  const w = d.weather || {};
  const fx = d.fx || {};
  const row = (k, v) => `<div class="row"><b>${k}</b>: ${v ?? 'n/a'}</div>`;
  const stocks = (d.stocks?.items || [])
    .map((s) => {
      const pct = s.changePct == null ? '' : ` (${s.changePct > 0 ? '+' : ''}${s.changePct}%)`;
      const cls = s.changePct == null ? '' : s.changePct >= 0 ? 'up' : 'down';
      return `<div class="row">${s.mkt} ${s.label} [${s.sym}]: <span class="${cls}">${s.price ?? 'n/a'}${pct}</span></div>`;
    })
    .join('');
  const clocks = (d.clocks?.items || [])
    .map((c) => `<div class="row">${c.city}: ${c.time}</div>`)
    .join('');

  return `<!doctype html><html lang="zh"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Kindle Dash</title><style>
body{background:#fff;color:#000;font-family:sans-serif;margin:2rem;}
h1{font-size:1.8rem;} h2{font-size:1.4rem;border-bottom:2px solid #000;margin-top:1.5rem;}
.row{font-size:1.2rem;margin:.4rem 0;} .up{color:#000;font-weight:bold;} .down{color:#555;}
hr{border:none;border-top:2px solid #000;}
</style></head><body>
<h1>Kindle Dash</h1>
<h2>限额</h2>
${row('WorkBuddy', q.workbuddy?.model + ' / 剩余 ' + (q.workbuddy?.token?.remaining ?? 'n/a'))}
${row('Claude Code', (q.claudecode?.used7d ?? 'n/a') + ' / ' + (q.claudecode?.cap ?? ''))}
${row('Codex', (q.codex?.used7d ?? 'n/a') + ' / ' + (q.codex?.cap ?? ''))}
<h2>天气</h2>
${row(w.city, (w.text ?? '') + ' ' + (w.temp ?? '') + '°C  高' + (w.high ?? '') + '/低' + (w.low ?? '') + '  湿' + (w.humidity ?? '') + '%')}
<h2>股市</h2>${stocks}
<h2>汇率 (1 ${fx.base})</h2>
${row('人民币 CNY', fx.cny)} ${row('卢比 INR', fx.inr)}
<h2>世界时钟</h2>${clocks}
<hr><div class="row"><a href="/api/dashboard">JSON /api/dashboard</a></div>
</body></html>`;
}

export function createServer({ db = null, cfg = config } = {}) {
  return http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');

    if (url.pathname === '/api/dashboard') {
      try {
        const d = await buildDashboard(db);
        sendJson(res, d);
      } catch (e) {
        sendJson(res, { ok: false, error: e.message });
      }
      return;
    }

    if (url.pathname === '/api/status') {
      const status = db ? readStatus(db, { cwdFilter: cfg.cwdFilter }) : null;
      sendJson(res, { ok: true, data: status, serverTime: Date.now() });
      return;
    }

    if (url.pathname === '/' || url.pathname === '/index.html') {
      try {
        const d = await buildDashboard(db);
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(renderHtml(d));
      } catch (e) {
        res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end('error: ' + e.message);
      }
      return;
    }

    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Not Found');
  });
}
