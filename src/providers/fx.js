import { fetchJson, cached } from '../cache.js';
import { getConfig } from '../config.js';

// Free, keyless FX rates. Base is configurable (default USD).
export async function getFx() {
  const base = getConfig().fxBase;
  const url = `https://open.er-api.com/v6/latest/${base}`;
  return cached('fx', 5 * 60 * 1000, async () => {
    const r = await fetchJson(url);
    if (!r.ok || !r.data?.rates) return { ok: false, error: r.error, base };
    const rates = r.data.rates;
    return {
      ok: true,
      base,
      updated: r.data.time_last_update_utc,
      cny: rates.CNY ?? null, // 人民币 / 1 USD
      inr: rates.INR ?? null, // 卢比 / 1 USD
      source: 'open.er-api.com'
    };
  });
}
