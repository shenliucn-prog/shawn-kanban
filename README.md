# Shawn Kanban — 越狱 Kindle 常驻看板（原 Kindle Dash）

跨平台（Windows / macOS）Node.js 服务，把越狱 Kindle 的墨水屏变成一张常驻看板：
**WorkBuddy / Claude Code / Codex 限额、天气、美股 + A股（带 30 日走势图）、世界时钟、汇率**，
由电脑或云端生成整屏图片，KOReader 的 **Shawn Kanban** 插件负责下载和显示。看板打开时，每个整点/半点自动刷新（如 08:30、09:00）。

## 免费云端部署

采用 cron-job.org 外部定时触发 + GitHub Actions 生成 + GitHub Pages 发布：每小时第 **25、55 分钟**触发，供 Kindle 在整点、半点取图。GitHub 自带定时任务作为备用；触发和发布可能延迟，不保证准点。

- 源码在 `main`，额度输入在独立 `runtime-data` 分支；仍属于同一仓库。
- 新生成图片通过 Pages 部署产物发布，不提交到源码分支。生成失败时尽量保留上次成功图片。
- [网页版看板](https://shenliucn-prog.github.io/shawn-kanban/)显示更新状态；[status.json](https://shenliucn-prog.github.io/shawn-kanban/status.json)记录生成时间和工作流结果。超过45分钟未更新时，网页标记过期。
- 电脑关闭时仍可生成公共数据；本机额度数据取决于上报程序，可能保持最后一次的值。

配置与状态检查见 [云端部署](docs/CLOUD_DEPLOY.md)。外部触发所用令牌到期前需更新；不要把令牌写入仓库。

## 运行（Windows 或 macOS 通用）

```bash
npm install
npm start
# 浏览器打开 http://127.0.0.1:8787/       看网页版看板（单页、30s 整点半点自动刷新、SVG 折线图）
#           http://127.0.0.1:8787/api/dashboard  拿 JSON
```

在 **MacBook** 上工作时，同样地 `npm install && npm start`，让 Kindle 连同一个 WiFi，
把插件（工具 → Shawn Kanban）里的服务器地址改成 MacBook 的局域网 IP（菜单 → 设置服务器地址）。

### 让服务开机自启 / 崩溃自拉起（可选）
- Windows：`npm install -g pm2` 后 `pm2 start src/index.js --name shawn-kanban`
- macOS：`brew install pm2 && pm2 start src/index.js --name shawn-kanban`，再 `pm2 save && pm2 startup`

## 配置（config.json 或环境变量，环境变量优先）

| 项目 | config.json | 环境变量 |
|------|-------------|----------|
| 绑定地址/端口 | `host` / `port` | `HOST` / `PORT` |
| 城市与坐标 | `weather.city/lat/lon` | `DASH_CITY` / `DASH_LAT` / `DASH_LON` |
| 股票列表 | `stocks` | `DASH_STOCKS`(JSON) |
| 世界时钟 | `clocks` | `DASH_CLOCKS`(JSON) |
| 限额上限 | `claudeCap` / `codexCap` | `DASH_CLAUDE_CAP` / `DASH_CODEX_CAP` |
| WorkBuddy 库路径 | — | `WORKBUDDY_DB_PATH` |

股票默认：苹果(AAPL)、美光(MU)、贵州茅台、长鑫科技(688825)，每只带 30 日收盘走势。
数据源：天气=Open-Meteo、汇率=open.er-api.com、股票=腾讯财经（gtimg），**均免 API key**。
限额中的 Claude Code / Codex 取自本机历史目录近 7 天的统计，为近似值（标注 `本地`）。

## Kindle 安装与升级

需要已越狱的 Kindle 和 KOReader。

1. 退出 KOReader，通过 USB 连接电脑。
2. 升级前备份设备中的 `koreader/plugins/KindleDash.koplugin/`，再用本仓库同名文件夹覆盖。
3. 安全弹出设备，重启 KOReader → 工具 → **Shawn Kanban** → **刷新看板**。
4. 在 **设置云端图地址** 中确认完整图片地址：`https://shenliucn-prog.github.io/shawn-kanban/screen.png`。新安装默认使用此地址；升级保留原配置，原先留空的地址需手动填写。
5. 如使用局域网服务，在 **设置局域网服务器** 中填写电脑的 `IP:8787`，电脑防火墙需放行 TCP 8787。仅用云端无需开放电脑端口。

取图顺序为 **局域网电脑 → 云端 → 本地缓存**。电脑不在线时会先等待局域网请求超时，再尝试云端。云端 HTTPS 下载校验证书，需要 KOReader 自带的有效 CA 证书文件。

### 显示、休眠与刷新

- 点击屏幕顶部10%区域，或从顶部25%区域向下滑动，可退出看板；有返回键的设备也可按返回键退出。
- 看板打开时暂停 KOReader 自动休眠，并每4分钟通过 KOReader 的 Kindle 电源接口重置系统空闲计时；兼容已有 KeepAlive 状态及充电状态。退出看板或卸载插件时取消计时并恢复原休眠设置。
- 电源键仍可手动休眠。唤醒后约5秒尝试刷新，失败时在约20秒、60秒重试，给 Wi-Fi 恢复留出时间。Wi-Fi 需要已开启并能够重新连接；插件不会强制打开 Wi-Fi。
- 自动刷新在整点、半点执行，仅看板显示期间取图；关闭自动刷新会取消该定时器，手动刷新和唤醒刷新仍可用。
- **当前不是深度休眠后的定时唤醒方案**：设备真正休眠时不能依靠界面定时器刷新。常驻看板通过保持运行实现刷新，会增加耗电。

本次修复已通过 Lua 语法和模拟行为测试；尚未完成真机睡眠、Wi-Fi 恢复和长期耗电验证。

### 真机检查与回退

关闭电脑上的本地服务后，确认 Kindle 仍能获取云端图片；看板保持打开至少35分钟，核对图中生成时间是否变化。再按电源键休眠、唤醒，确认恢复联网后刷新；退出看板后确认能正常自动休眠。

遇到问题可退出 KOReader，恢复备份的插件文件夹并重启。若显示旧图，先检查公开 `status.json`：云端生成时间已更新而 Kindle 没变，优先检查设备联网和插件；云端也未更新，则检查 Actions 和外部定时任务。

## 开发验证

```bash
npm ci
npm run lint
npm test
python -m pip install lupa
python tools/check_lua.py
python -m unittest discover -s test -p "*_test.py"
```

Lua 行为测试使用模拟的 KOReader 接口，覆盖 HTTPS 图片收集、网络失败、定时器取消、休眠与唤醒重试及清理，不替代真机验证。
