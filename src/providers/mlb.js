import { cached, fetchJson } from '../cache.js';

// MLB 赛况：只跟洛杉矶道奇与圣地亚哥教士。
// 数据源为 MLB 官方 StatsAPI（无需 key）。每队给出：
//   last —— 最近一场已结束比赛的对手与比分
//   next —— 下一场（或进行中）比赛的时间（北京时间）与对手
// 所有时间统一换算为北京时间 UTC+8。

const TEAMS = [
  { id: 119, abbr: 'LAD', cn: '道奇' },
  { id: 135, abbr: 'SD', cn: '教士' }
];

// MLB 30 队中文简称（按 StatsAPI 的 abbreviation）
const CN = {
  ARI: '响尾蛇', ATL: '勇士', BAL: '金莺', BOS: '红袜', CHC: '小熊', CWS: '白袜',
  CIN: '红人', CLE: '守护者', COL: '洛基', DET: '老虎', HOU: '太空人', KC: '皇家',
  LAA: '天使', LAD: '道奇', MIA: '马林鱼', MIL: '酿酒人', MIN: '双城', NYM: '大都会',
  NYY: '洋基', OAK: '运动家', PHI: '费城人', PIT: '海盗', SD: '教士', SF: '巨人',
  SEA: '水手', STL: '红雀', TB: '光芒', TEX: '游骑兵', TOR: '蓝鸟', WSH: '国民'
};

const DAY = 24 * 60 * 60 * 1000;
const pad = (n) => String(n).padStart(2, '0');

function cnName(team) {
  return CN[team?.abbreviation] || team?.clubName || team?.name || '?';
}

// UTC 毫秒 -> 北京时间 的 "MM-DD HH:mm"
function toBeijing(ms) {
  const d = new Date(ms + 8 * 3600 * 1000);
  return {
    date: `${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`,
    time: `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`
  };
}

function ymd(d) {
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
}

async function fetchSchedule(teamId, now) {
  const url =
    'https://statsapi.mlb.com/api/v1/schedule?sportId=1&teamId=' +
    teamId +
    '&startDate=' + ymd(new Date(now - 14 * DAY)) +
    '&endDate=' + ymd(new Date(now + 14 * DAY));
  // StatsAPI 偶发超时，失败重试一次
  let r = await fetchJson(url, { timeoutMs: 12000 });
  if (!r.ok) r = await fetchJson(url, { timeoutMs: 15000 });
  return r;
}

function buildTeam(team, data, now) {
  const games = [];
  for (const dt of data.dates || []) {
    for (const g of dt.games || []) games.push(g);
  }
  games.sort((a, b) => Date.parse(a.gameDate) - Date.parse(b.gameDate));

  // 上一场：最近一场已结束的比赛
  const finals = games.filter((g) => g.status && g.status.abstractGameState === 'Final');
  const lastRaw = finals[finals.length - 1];

  // 下一场：第一场还没结束的（含进行中）
  const nextRaw = games.find(
    (g) => g.status && g.status.abstractGameState !== 'Final' && Date.parse(g.gameDate) >= now - 6 * 3600 * 1000
  );

  let last = null;
  if (lastRaw) {
    const isHome = lastRaw.teams.home.team.id === team.id;
    const us = isHome ? lastRaw.teams.home : lastRaw.teams.away;
    const them = isHome ? lastRaw.teams.away : lastRaw.teams.home;
    const w = us.score ?? 0;
    const l = them.score ?? 0;
    last = {
      date: toBeijing(Date.parse(lastRaw.gameDate)).date,
      home: isHome,
      opp: cnName(them.team),
      us: w,
      them: l,
      win: w > l
    };
  }

  let next = null;
  if (nextRaw) {
    const isHome = nextRaw.teams.home.team.id === team.id;
    const them = isHome ? nextRaw.teams.away : nextRaw.teams.home;
    const bj = toBeijing(Date.parse(nextRaw.gameDate));
    const live = nextRaw.status && nextRaw.status.abstractGameState === 'Live';
    next = {
      date: bj.date,
      time: live ? '进行中' : bj.time,
      home: isHome,
      opp: cnName(them.team),
      live
    };
  }

  return { abbr: team.abbr, cn: team.cn, last, next };
}

export function getMlb() {
  // 比赛数据变化慢，缓存 30 分钟；失败也按此周期重试
  return cached('mlb', 30 * 60 * 1000, async () => {
    const now = Date.now();
    const items = [];
    const errors = [];

    for (const team of TEAMS) {
      const r = await fetchSchedule(team.id, now);
      if (r.ok && r.data) {
        items.push(buildTeam(team, r.data, now));
      } else {
        errors.push(team.cn + ': ' + (r.error || 'fail'));
      }
    }

    if (!items.length) {
      return { ok: false, error: errors.join('; ') || 'no mlb data', items: [] };
    }
    return { ok: true, items, source: 'statsapi.mlb.com' };
  });
}
