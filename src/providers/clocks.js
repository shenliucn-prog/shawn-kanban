import { getConfig } from '../config.js';

// Pure local computation — no network needed.
function timeIn(tz) {
  const now = new Date();
  const fmt = new Intl.DateTimeFormat('zh-CN', {
    timeZone: tz,
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false
  });
  const dateFmt = new Intl.DateTimeFormat('zh-CN', {
    timeZone: tz,
    month: '2-digit',
    day: '2-digit',
    weekday: 'short'
  });
  return { time: fmt.format(now), date: dateFmt.format(now) };
}

export function getClocks() {
  const items = getConfig().clocks.map((c) => ({
    city: c.city,
    tz: c.tz,
    ...timeIn(c.tz)
  }));
  return { ok: true, items };
}
