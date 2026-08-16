# kindle-assistant

把一台已越狱的 Kindle（e-ink 墨水屏）改造成**常驻小助手显示屏**的 PC 侧数据服务。

当前已落地：从 WorkBuddy 本机本地数据库读取 **当前模型 + token 用量**，通过轻量 HTTP 服务（`/api/status`）提供给 Kindle 端渲染。狼人杀模块为下一步（见任务 #8）。

## 架构

```
┌─────────────┐   HTTP (LAN / USB)   ┌──────────────────┐
│  Kindle     │ ───────────────────▶ │  PC 本服务        │
│ (e-ink 显示) │ ◀─────────────────── │  kindle-assistant │
│  点按交互    │   /api/status JSON   │  读 workbuddy.db  │
└─────────────┘                      └──────────────────┘
```

- **边界**：Kindle 只显示 + 自身点按，**不**反向控制电脑。
- **数据源**：纯本地只读 `C:\Users\Shen\.workbuddy\workbuddy.db`（SQLite，WAL）。无需联网/API。
  - `session_usage.used` / `session_usage.size` → token 已用/总额，`剩余 = size − used`
  - `sessions.model` → 当前模型；取 `last_activity_at` 最新的会话
- **e-ink 约束**：只服务慢变静态信息；页面黑白、大字号、无动画；刷新建议手动点刷或数分钟间隔。

## 快速开始（开发）

```bash
npm install          # 安装依赖（better-sqlite3 等）
npm test             # 单元测试（node:test，自动生成 fixture DB）
npm run lint         # ESLint
npm start            # 启动服务，默认 http://0.0.0.0:8787
```

环境变量：

| 变量 | 默认 | 说明 |
|------|------|------|
| `WORKBUDDY_DB_PATH` | `~/.workbuddy/workbuddy.db` | 本地数据库路径 |
| `HOST` | `0.0.0.0` | 绑定地址（0.0.0.0 = 局域网可达） |
| `PORT` | `8787` | 监听端口 |
| `WORKBUDDY_CWD` | 空 | 限定到某工作区 cwd；空=最新会话 |

## API

`GET /api/status` →

```json
{
  "ok": true,
  "data": {
    "model": "hy3",
    "title": "开始进行规划",
    "status": "planning",
    "token": { "used": 43833, "size": 192000, "remaining": 148167, "percent": 22.8 },
    "credit": null,
    "lastActivityAt": 1786819701164,
    "updatedAt": 1786819746414,
    "source": "session"
  },
  "serverTime": 1786819800000
}
```

`GET /` → e-ink 友好的简易状态页。

## 项目结构

```
src/
  config.js        # 运行时配置（环境变量覆盖）
  status.js        # 纯函数：计算/格式化状态（无 I/O，易测）
  db.js            # 只读打开 SQLite + 读取状态逻辑
  server.js        # HTTP 服务（/api/status、/）
  index.js         # 入口：打开 DB、监听、优雅退出
test/
  status.test.js   # 纯逻辑单测
  db.test.js       # DB 读取单测（fixture）
  server.test.js   # 服务单测（端点）
  fixtures/        # 自动生成的测试 SQLite（build.mjs, *.db）
.github/workflows/ # CI：lint + test（Node 22）
kindle-jailbreak/  # 越狱物料（见其内 MANIFEST.md / README.md）
```

## CI/CD

GitHub Actions（`.github/workflows/ci.yml`）：`checkout → setup-node 22 → npm ci → npm run lint → npm test`。连接 GitHub 仓库后 push/PR 即自动跑。

## Kindle 接入（下一步 #4/#6/#7）

1. Kindle 越狱并装好 MRPI + KUAL + KOReader（物料见 `kindle-jailbreak/`）。
2. PC 放通防火墙入站规则（端口 8787）。
3. Kindle 通过 KOReader 内置浏览器或 USBNetwork(USB SSH) 访问 `http://<PC局域网IP>:8787/`。
4. 看板/狼人杀入口整合进 KUAL 启动器（任务 #9）。

## 越狱物料

见 [`kindle-jailbreak/`](./kindle-jailbreak/) 目录：`MANIFEST.md` 含 6 项物料（KindleBreak / Hotfix / MRPI / KUAL / USBNetwork / KOReader）的下载源、大小、MD5 与解压自检结果。**操作 Kindle 前务必保持飞行模式、冻版本（5.13.3）、用 USB 数据线拷文件。**
