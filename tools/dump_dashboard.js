#!/usr/bin/env node
// 把 buildDashboard() 的结果直接打到 stdout，供 CI/离线渲染使用。
// 云端（SHAWN_MODE=cloud）不连本地 DB，只聚公开数据 + data/quotas.json。
//
//   node tools/dump_dashboard.js > dashboard.json
//   python tools/render_screen.py --data dashboard.json --out screen.png

import { buildDashboard } from '../src/aggregator.js';
import { openDb, closeDb } from '../src/db.js';
import { config } from '../src/config.js';

let db = null;
if (config.mode !== 'cloud') {
  try {
    db = openDb(config.dbPath);
  } catch (e) {
    console.error('[dump] DB unavailable, falling back to no-db mode:', e.message);
  }
}

try {
  const data = await buildDashboard(db);
  process.stdout.write(JSON.stringify(data, null, 2));
} catch (e) {
  console.error('[dump] failed:', e.message);
  process.exit(1);
} finally {
  if (db) closeDb(db);
}
