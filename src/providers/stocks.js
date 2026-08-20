import { cached } from '../cache.js';
import { config } from '../config.js';

// Tencent finance (gtimg) is reliable from mainland China for both US and
// A-share quotes. Response is GBK-encoded, but the numeric fields we need are
// pure ASCII, so we split the raw text on '~' without decoding the Chinese name
// (we use the config label instead).
//
// Field layout (US and A-share share it for our purposes):
//   [1]  name            [3]  current price
//   [4]  previous close  [30] change amount   [31] change percent
const GTIMG = 'https://qt.gtimg.cn/q=';

function toGtimgCode(s) {
  if (s.mkt === 'US') return 'us' + String(s.sym).toUpperCase();
  // A-share: "600519.SS" / "399001.SZ" -> sh600519 / sz399001
  const raw = String(s.sym).toUpperCase();
  const [code, ex] = raw.split('.');
  const pfx = ex === 'SS' ? 'sh' : ex === 'SZ' ? 'sz' : ex === 'SH' ? 'sh' : ex === 'SZ' ? 'sz' : 'sh';
  return pfx + code;
}

function currencyFor(mkt) {
  return mkt === 'US' ? 'USD' : 'CNY';
}

async function fetchBatch(codes) {
  const url = GTIMG + codes.join(',');
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 9000);
  try {
    const res = await fetch(url, {
      signal: ctrl.signal,
      headers: { 'User-Agent': 'Mozilla/5.0', Referer: 'https://gu.qq.com/' }
    });
    const text = await res.text();
    return text;
  } finally {
    clearTimeout(t);
  }
}

export async function getStocks() {
  const list = config.stocks || [];
  if (!list.length) return { ok: false, error: 'no stocks configured', items: [] };

  const codes = list.map(toGtimgCode);
  let text = '';
  try {
    text = await cached('stocks:all', 60 * 1000, () => fetchBatch(codes));
  } catch (e) {
    return { ok: false, error: e.message, items: [] };
  }

  // Build a lookup: gtimg code (lowercased) -> raw field string.
  const byCode = new Map();
  for (const line of text.split('\n')) {
    const m = line.match(/^v_([^=]+)="(.*)";?\s*$/);
    if (!m) continue;
    byCode.set(m[1].toLowerCase(), m[2]);
  }

  const items = list.map((s, i) => {
    const code = codes[i].toLowerCase();
    const raw = byCode.get(code);
    const label = s.name || s.sym;
    if (!raw) {
      return { sym: s.sym, ok: false, error: 'no data', label, mkt: s.mkt };
    }
    const p = raw.split('~');
    const price = Number(p[3]);
    const prev = Number(p[4]);
    if (!Number.isFinite(price)) {
      return { sym: s.sym, ok: false, error: 'bad data', label, mkt: s.mkt };
    }
    // Compute change from price & previous close rather than relying on a
    // fixed field index — the gtimg field layout differs between individual
    // stocks and indices, so the raw change/percent columns are unreliable.
    let change = null;
    let changePct = null;
    if (Number.isFinite(prev) && prev !== 0) {
      change = Math.round((price - prev) * 100) / 100;
      changePct = Math.round(((price - prev) / prev) * 10000) / 100;
    }
    return {
      sym: s.sym,
      ok: true,
      name: label,
      price,
      prev: Number.isFinite(prev) ? prev : null,
      change,
      changePct,
      currency: currencyFor(s.mkt),
      label,
      mkt: s.mkt
    };
  });

  return { ok: true, items };
}
