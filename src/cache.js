// Tiny TTL cache + resilient JSON fetch helper (no external deps).

const store = new Map(); // key -> { value, expires, fetchedAt }
// 上一次"成功"的数据。失败时用它降级，让看板能显示"上一次缓存"而不是冷冰冰的"不可用"。
const lastOk = new Map(); // key -> { value, at }

// 各 provider 统一用 ok:false 标识失败；没带 ok 字段的对象视为成功。
const isOk = (v) => !!(v && v.ok !== false);

// 给返回体打上数据获取时间，渲染端据此显示刷新时间。
function stamp(value, at) {
  if (value && typeof value === 'object' && !Array.isArray(value)) value.fetchedAt = at;
  return value;
}

/**
 * Run `producer()` and cache its result for `ttlMs`.
 * Concurrent calls for the same key share one in-flight promise.
 *
 * 失败语义（stale-while-error）：本次拉取失败时，若历史上成功过，
 * 就返回那次成功的数据并打上 stale:true，fetchedAt 保持为上次成功的时间。
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
      const at = Date.now();

      if (isOk(value)) {
        lastOk.set(key, { value, at });
        store.set(key, { value, expires: at + ttlMs, fetchedAt: at });
        return stamp(value, at);
      }

      // 拉取失败：有上次成功数据就降级，否则原样返回失败体
      const prev = lastOk.get(key);
      if (prev) {
        const stale = stamp({ ...prev.value, stale: true }, prev.at);
        store.set(key, { value: stale, expires: at + ttlMs, fetchedAt: prev.at });
        return stale;
      }
      store.set(key, { value, expires: at + ttlMs, fetchedAt: at });
      return stamp(value, at);
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
