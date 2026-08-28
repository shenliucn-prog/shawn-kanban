// 公历固定节日倒计时（真实节日，不含自定义/自编条目）。
// 只用日期固定的公历节日，避免农历换算与手工维护成本。
const FESTIVALS = [
  { name: '元旦', md: '01-01' },
  { name: '情人节', md: '02-14' },
  { name: '妇女节', md: '03-08' },
  { name: '愚人节', md: '04-01' },
  { name: '劳动节', md: '05-01' },
  { name: '儿童节', md: '06-01' },
  { name: '建党节', md: '07-01' },
  { name: '建军节', md: '08-01' },
  { name: '教师节', md: '09-10' },
  { name: '国庆节', md: '10-01' },
  { name: '万圣节', md: '10-31' },
  { name: '平安夜', md: '12-24' },
  { name: '圣诞节', md: '12-25' }
];

export function getFestivals() {
  const now = new Date();
  const y = now.getFullYear();
  const out = [];
  // 覆盖今年与明年，保证跨年时不断档
  for (const year of [y, y + 1]) {
    for (const f of FESTIVALS) {
      const d = new Date(`${year}-${f.md}T00:00:00`);
      if (isNaN(d.getTime())) continue;
      const days = Math.ceil((d.getTime() - now.getTime()) / 86400000);
      if (days >= 0) out.push({ name: f.name, date: `${year}-${f.md}`, days });
    }
  }
  out.sort((a, b) => a.days - b.days);
  return { ok: true, items: out.slice(0, 3), source: 'built-in solar festivals' };
}
