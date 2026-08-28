# 云端部署（免费方案）：电脑关机也能刷新

完全免费，用的是 GitHub Actions + GitHub Pages。

## 架构

```
本机（开机时，每 5 分钟）
   └─ 上报器把 AI 额度推到仓库 data/quotas.json
                                   │
GitHub Actions（每 15 分钟）        │
   ├─ 读 data/quotas.json ─────────┘
   ├─ 拉公开 API：天气 / 股票 / 汇率 / 新闻 / MLB
   ├─ Python + Pillow 渲染 1072x1448 PNG
   └─ 发布到 gh-pages 分支
                   │
Kindle  <──────────┘
   https://<用户名>.github.io/<仓库>/screen.png
```

Kindle 取图顺序：**局域网 PC → 云端 Pages → 本地缓存**。电脑开着走局域网（数据最新），
电脑关了自动落到云端，网络全断才用缓存。

## 数据边界（重要）

| 数据 | 电脑关机后 | 说明 |
|---|---|---|
| 天气 / 股票 / 汇率 / 新闻 / MLB / 时钟 | ✅ 照常刷新 | 公开 API，云端能直接拉 |
| WorkBuddy / Claude Code / Codex 额度 | ⚠️ 最后已知值 | 只存在本机，物理上无法凭空更新；超过 15 分钟没上报，标题会标「电脑离线」 |

> GitHub Pages 免费版要求仓库**公开**。仓库里会有天气/股票/新闻等公开数据，
> 以及 AI 额度数字（不含任何密钥）。介意的话可以只上报百分比 —— 见文末「脱敏」。

---

## 步骤 1：建仓库并推送

```bash
cd C:/Users/Shen/WorkBuddy/2026-08-16-01-28-56
git remote add origin https://github.com/<用户名>/shawn-kanban.git
git push -u origin main
```

## 步骤 2：开启 GitHub Pages（用 gh-pages 分支）

仓库 **Settings → Pages → Build and deployment**：
- Source 选 `Deploy from a branch`
- Branch 选 `gh-pages`，目录 `/ (root)`
- 保存

第一次要等 Actions 跑完一次，`gh-pages` 分支才会出现。可以先手动触发：
**Actions → Render Kindle Screen → Run workflow**。

页面地址就是：`https://<用户名>.github.io/shawn-kanban/screen.png`

## 步骤 3：建 Personal Access Token

GitHub **Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token**
- 勾 `repo`（或最小权限 `public_repo` + `contents:write`）
- 生成后复制（只显示一次）

## 步骤 4：配置本机上报器

```bat
copy tools\report_secrets.example.bat tools\report_secrets.bat
```

编辑 `tools\report_secrets.bat`：

```bat
set "GITHUB_TOKEN=ghp_你刚才复制的token"
set "GITHUB_REPO=你的用户名/shawn-kanban"
set "GITHUB_BRANCH=main"
set "REPORT_EVERY=300000"
```

（`report_secrets.bat` 已在 .gitignore 里，不会泄露）

先手动跑一次验证：

```bat
cd C:\Users\Shen\WorkBuddy\2026-08-16-01-28-56
C:\Users\Shen\.workbuddy\binaries\node\versions\22.12.0\node.exe tools\report_quota.js --force
```

看到 `pushed to github <repo> data/quotas.json` 就成了。
> 必须用托管 Node 22.x：better-sqlite3 预编译为 ABI 127，系统 node v24 是 ABI 137 会加载失败。

## 步骤 5：上报器开机自启

按 `Win + R`，输入 `shell:startup` 回车，把 `tools\run_report_hidden.vbs` 的快捷方式放进去。

## 步骤 6：Kindle 上填云端地址

KOReader → 菜单 → **Shawn Kanban → 设置云端图地址**，填：

```
https://<用户名>.github.io/shawn-kanban/screen.png
```

---

## 验证

1. 电脑开着打开看板 → 应正常显示（走局域网）
2. **关掉电脑**，再打开看板 → 应显示云端图，并提示「来自云端（电脑未连上）」，
   AI 额度那里标题会变成「AI 额度 · 电脑离线」
3. 断网再打开 → 显示最后一次的图 + 「离线 · 最后 HH:MM」

## 排错

| 现象 | 检查 |
|---|---|
| Actions 失败：字体缺失 | 看 `Verify CJK font really renders` 那一步；它会明确报出哪个字体加载不了 |
| 云端图是空的/方块 | 同上，字体问题。`--check-fonts` 会以退出码 2 失败 |
| 一直是「电脑离线」 | 上报器没跑；看 `tools\report_quota.log`，确认 Token 有 `repo` 权限 |
| Kindle 取不到云端图 | 先在电脑浏览器打开那个 URL 确认能访问；Kindle 走 HTTPS 需要 KOReader 的 `data/ca-bundle.crt` |
| 很久没刷新 | GitHub 对 **60 天无活动**的仓库会暂停定时任务；去 Actions 页手动 Run 一次即可恢复 |

## 脱敏（可选）

不想把额度绝对值放公开仓库，改 `tools/report_quota.js` 的 `collect()`：
上报时只保留 `percent` / `ok`，把 `used` / `remaining` / `cap` 置空。
看板仍能显示进度条和百分比，只是没有具体数字。
