# Shawn Kanban — an always-on dashboard for jailbroken Kindle

[中文（默认）](README.md) | **English**

A Windows/macOS Node.js service and cloud renderer for an e-ink dashboard: WorkBuddy / Claude Code / Codex activity estimates, weather, US and A-share markets, world clocks, and exchange rates. The KOReader **Shawn Kanban** plugin downloads full-screen images and refreshes at :00 and :30 while the dashboard is open.

Chinese is the default documentation and application language. This repository provides English documentation; the Kindle menus, dashboard content, and runtime messages remain Chinese.

## Cloud deployment

cron-job.org triggers GitHub Actions at **:25 and :55** each hour. Actions generates an image and publishes it to GitHub Pages ahead of the Kindle's next refresh. GitHub's own schedule is a fallback. Queueing and deployment can delay updates; this is not a real-time guarantee.

- `main` contains source code; `runtime-data` stores quota input in a separate branch of the same repository.
- Generated images are published as Pages deployment artifacts, not source commits. On generation failure, the pipeline attempts to retain the last good image.
- The [dashboard](https://shenliucn-prog.github.io/shawn-kanban/) reports freshness; [status.json](https://shenliucn-prog.github.io/shawn-kanban/status.json) records generation time and workflow results. The web page marks images older than 45 minutes as stale.
- Public data can update while the computer is off. Local activity estimates depend on the reporter and may retain their last values.

See [cloud deployment](docs/CLOUD_DEPLOY.en.md). Renew the external trigger token before expiry; never commit it.

## Run locally on Windows or macOS

Requires Node.js 20 or later.

```bash
npm install
npm start
```

Open `http://127.0.0.1:8787/` for the dashboard or `/api/dashboard` for JSON. Connect the Kindle and computer to the same network and enter the computer's LAN address in the plugin's **设置局域网服务器** (LAN server) menu. See the [Mac setup guide](MAC_SETUP.en.md).

Optional startup management: install PM2, run `pm2 start src/index.js --name shawn-kanban`, and configure startup persistence for your operating system. On macOS, `pm2 save` and `pm2 startup` provide the setup instructions.

## Configuration

Environment variables override `config.json`.

| Setting | config.json | Environment variable |
|---|---|---|
| Bind address / port | `host` / `port` | `HOST` / `PORT` |
| Weather location | `weather.city/lat/lon` | `DASH_CITY` / `DASH_LAT` / `DASH_LON` |
| Stocks | `stocks` | `DASH_STOCKS` (JSON) |
| World clocks | `clocks` | `DASH_CLOCKS` (JSON) |
| Activity caps | `claudeCap` / `codexCap` | `DASH_CLAUDE_CAP` / `DASH_CODEX_CAP` |
| WorkBuddy database | — | `WORKBUDDY_DB_PATH` |

Market data uses Tencent Finance, weather uses Open-Meteo, and FX uses open.er-api.com. These integrations do not require an API key. See `config.json` for the configured instruments and locations. AI activity metrics are estimates, not authoritative account quotas; the cloud reporter's current labels and limitations are explained in the deployment guide.

## Kindle installation and upgrade

Requires a jailbroken Kindle with KOReader.

1. Exit KOReader and connect the Kindle by USB.
2. Back up `koreader/plugins/KindleDash.koplugin/` before upgrading, then replace it with this repository's `KindleDash.koplugin/` folder.
3. Safely eject the device, restart KOReader, and open Tools → **Shawn Kanban** → **刷新看板** (Refresh dashboard).
4. Under **设置云端图地址** (Cloud image URL), use `https://shenliucn-prog.github.io/shawn-kanban/screen.png`. New installations use this default. Existing settings are preserved; an existing empty URL must be filled in manually.
5. For local service access, set **设置局域网服务器** to your computer's `IP:8787` and allow inbound TCP 8787. Cloud-only use requires no inbound computer port.

Image fallback order: **LAN computer → cloud → local cache**. An offline computer can cause a timeout before the plugin tries the cloud. HTTPS validates certificates and requires KOReader's CA bundle.

### Display, sleep, and refresh

- Tap the top 10% of the screen, swipe down from the top 25%, or use a Back key if available to exit.
- While the dashboard is open, the plugin pauses KOReader autosuspend and resets the Kindle native idle timer every four minutes through KOReader's power API, respecting charging and KeepAlive state. Closing the dashboard or unloading the plugin cancels the timer and restores the previous autosuspend setting.
- The power button still permits manual sleep. After resume, refresh is attempted after approximately 5 seconds, with retries around 20 and 60 seconds if needed. Wi-Fi must already be enabled and able to reconnect; the plugin does not force Wi-Fi on.
- Scheduled refresh runs at :00 and :30 only while the dashboard is displayed. Turning off automatic refresh cancels that timer; manual and resume refresh remain available.
- **This does not implement scheduled wake from deep sleep.** UI timers cannot refresh a suspended device. Keeping the dashboard running increases battery consumption.

The fix passes Lua syntax and simulated behavior tests. Real-device sleep, Wi-Fi recovery, and long-term battery testing remain pending.

### Device checks and rollback

Stop the local computer service and confirm cloud images still load. Leave the dashboard open for at least 35 minutes and check the image's generation time. Manually sleep and wake the Kindle, confirm refresh after network recovery, then close the dashboard and confirm normal autosuspend.

To roll back, exit KOReader, restore the backed-up plugin folder, and restart. If an image is old, inspect public `status.json`: a fresh cloud timestamp points to device connectivity or the plugin; an old cloud timestamp points to Actions or the external scheduler.

## Development checks

```bash
npm ci
npm run lint
npm test
python -m pip install lupa
python tools/check_lua.py
python -m unittest discover -s test -p "*_test.py"
```

Lua tests use a simulated KOReader API to cover HTTPS body collection, failed requests, timer cancellation, suspend/resume retries, and cleanup. They do not replace device testing.

## Documentation languages

Keep Chinese and English document pairs in sync when changing behavior or setup instructions. Chinese files are the default entry points; `.en.md` files are their English counterparts. Code identifiers, URLs, and configuration keys stay unchanged.
