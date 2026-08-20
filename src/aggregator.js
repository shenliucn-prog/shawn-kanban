import { getWorkbuddy } from './providers/workbuddy.js';
import { getClaudeCodeUsage } from './providers/claudecode.js';
import { getCodexUsage } from './providers/codex.js';
import { getWeather } from './providers/weather.js';
import { getStocks } from './providers/stocks.js';
import { getClocks } from './providers/clocks.js';
import { getFx } from './providers/fx.js';

// Aggregate every section into a single dashboard payload.
// Network calls run concurrently; local calls are synchronous.
export async function buildDashboard(db) {
  const [weather, stocks, fx] = await Promise.all([
    getWeather(),
    getStocks(),
    getFx()
  ]);

  return {
    ok: true,
    serverTime: Date.now(),
    quotas: {
      workbuddy: getWorkbuddy(db),
      claudecode: getClaudeCodeUsage(),
      codex: getCodexUsage()
    },
    weather,
    stocks,
    clocks: getClocks(),
    fx
  };
}
