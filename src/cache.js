// Tiny TTL cache + resilient JSON fetch helper (no external deps).

const store = new Map(); // key -> { value, expires }

/**
 * Run `producer()` and cache its result for `ttlMs`.
 * Concurrent calls for the same key share one in-flight promise.
 */
const inflight = new Map();
export async function cached(key, ttlMs, producer) {
  const hit = store.get(key);
  const now = Date.now();
  if (hit && hit.expires > now) return hit.value;

  if (inflight.has(key)) return inflight.get(key);

  const p = (async () => {
    try {
      const value = await producer();
      store.set(key, { value, expires: Date.now() + ttlMs });
      return value;
    } finally {
      inflight.delete(key);
    }
  })();
  inflight.set(key, p);
  return p;
}

/**
 * Fetch JSON with a timeout and a browser-like UA (some endpoints 403 without it).
 * @returns {Promise<{ok:boolean, status?:number, data?:any, error?:string}>}
 */
export async function fetchJson(url, { timeoutMs = 8000, headers = {} } = {}) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      signal: ctrl.signal,
      headers: { 'User-Agent': 'kindle-dash/1.0', Accept: 'application/json', ...headers }
    });
    const text = await res.text();
    let data = null;
    try {
      data = JSON.parse(text);
    } catch {
      return { ok: false, status: res.status, error: `bad json (${text.slice(0, 80)})` };
    }
    if (!res.ok) return { ok: false, status: res.status, error: `http ${res.status}` };
    return { ok: true, status: res.status, data };
  } catch (e) {
    return { ok: false, error: e.name === 'AbortError' ? 'timeout' : e.message };
  } finally {
    clearTimeout(t);
  }
}
