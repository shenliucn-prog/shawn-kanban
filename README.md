# Kindle Dash — 越狱 Kindle 常驻小助手数据服务

跨平台（Windows / macOS）Node.js 服务，把越狱 Kindle 的墨水屏变成一张常驻看板：
**WorkBuddy / Claude Code / Codex 限额、天气、美股 + A股、世界时钟、汇率**，
通过局域网喂给 KOReader 的 **KindleDash** 插件，插件每 30 分钟自动刷新。

## 运行（Windows 或 macOS 通用）

```bash
npm install
npm start
# 浏览器打开 http://127.0.0.1:8787/       看网页版看板
#           http://127.0.0.1:8787/api/dashboard  拿 JSON
```

在 **MacBook** 上工作时，同样地 `npm install && npm start`，让 Kindle 连同一个 WiFi，
把 KindleDash 插件的服务器地址改成 MacBook 的局域网 IP（插件菜单 → Set server address）。

### 让服务开机自启 / 崩溃自拉起（可选）
- Windows：`npm install -g pm2` 后 `pm2 start src/index.js --name kindle-dash`
- macOS：`brew install pm2 && pm2 start src/index.js --name kindle-dash`，再 `pm2 save && pm2 startup`

## 配置（config.json 或环境变量，环境变量优先）

| 项目 | config.json | 环境变量 |
|------|-------------|----------|
| 绑定地址/端口 | `host` / `port` | `HOST` / `PORT` |
| 城市与坐标 | `weather.city/lat/lon` | `DASH_CITY` / `DASH_LAT` / `DASH_LON` |
| 股票列表 | `stocks` | `DASH_STOCKS`(JSON) |
| 世界时钟 | `clocks` | `DASH_CLOCKS`(JSON) |
| 限额上限 | `claudeCap` / `codexCap` | `DASH_CLAUDE_CAP` / `DASH_CODEX_CAP` |
| WorkBuddy 库路径 | — | `WORKBUDDY_DB_PATH` |

天气=Open-Meteo、汇率=open.er-api.com、股票=Yahoo Finance，**均免 API key**。
限额中的 Claude Code / Codex 取自本机历史目录近 7 天的统计，为近似值（标注 `approx`）。

## Kindle 端（一次性部署）
把 `KindleDash.koplugin/` 整个文件夹拷到 Kindle 的 `koreader/plugins/` 下，
重启 KOReader → 工具 → Kindle Dash → Refresh。防火墙需放行 `TCP 8787` 入站。
