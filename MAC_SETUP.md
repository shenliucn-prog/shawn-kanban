# Kindle Dash —— 在 MacBook 上接上 Kindle（重点：越过防火墙）

本指南面向**工作电脑是 MacBook** 的场景。目标：Mac 上跑数据服务，越狱 Kindle（KOReader + KindleDash 插件）通过 WiFi 拉数据，墨水屏显示限额/天气/股市/汇率/世界时钟。

> 项目根目录下的 `KindleDash.koplugin/` 就是 Kindle 插件，部署方法见第五节。

---

## 0. 前置
- macOS（Intel / Apple Silicon 均可），能连 WiFi。
- 装好 Node.js ≥ 20：`brew install node` 或 https://nodejs.org 下载。
- Xcode 命令行工具（编译 better-sqlite3 原生模块需要）：
  ```bash
  xcode-select --install
  ```
  若 `npm install` 报 node-gyp / Python 错误，先装命令行工具再重试。

---

## 1. 启动数据服务
```bash
cd kindle-dash          # 解压后的项目目录
npm install             # 首次会编译 better-sqlite3（几十秒~几分钟）
npm start               # 监听 0.0.0.0:8787
```
看到 `listening on http://0.0.0.0:8787` 即成功。
本机验证：浏览器开 `http://127.0.0.1:8787/` 应看到看板页。

> 想改监听 IP / 端口 / 城市 / 股票，编辑 `config.json`（详见 README）。

---

## 2. ⚠️ 核心：越过 macOS 防火墙（Kindle 拉不到数据 90% 是这里卡住）

macOS 防火墙默认会**拦截 node 的入站连接**，而 Kindle 是通过 WiFi 主动访问 Mac 的 8787 端口的，所以必须放行。

### 2.1 首次运行放行（最简单）
`npm start` 第一次起来时，macOS 会弹窗：
> “node” 想要接受传入的网络连接。
**一定点「允许」**。点成「拒绝」或没弹窗，就会被挡。

### 2.2 没弹窗 / 之前点了拒绝 → 手动放行
- 系统设置 → 隐私与安全性 → **防火墙** → 点「选项…」
- 在允许列表中找到 `node`（或 `/usr/local/bin/node`、`~/.nvm/.../node`），确保其状态是**允许传入连接**。
- 若列表里没有 node：先停掉 `npm start`，在终端允许后重开。

### 2.3 命令行强开（最稳，推荐）
```bash
# 找到你的 node 真实路径
which node          # 例如 /usr/local/bin/node 或 /opt/homebrew/bin/node

# 用系统防火墙工具放行（需管理员密码）
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$(which node)"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblock "$(which node)"

# 确认防火墙是开的
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
```
> 注意：`npm start` 实际运行的就是上面的 node 二进制，放行这个路径即可，无需给 npm 本身放行。

### 2.4 关掉「隐身模式」干扰
系统设置 → 隐私与安全性 → 防火墙 → 选项… 里，把 **“拦截所有传入连接”** 关掉（它优先级高于上面的允许规则）。

---

## 3. ⚠️ 第二道墙：路由器 / AP 隔离（Kindle 与 Mac 同 WiFi 却 ping 不通）

即使 Mac 防火墙放开了，很多**路由器默认开启「AP 隔离 / 客户端隔离」**（尤其访客网络、公司/校园网、部分运营商光猫），会让同一 WiFi 下的设备之间无法互访。表现：Mac 能上外网、Kindle 也能上外网，但 Kindle 死活连不上 Mac 的 8787。

排查与解法（任选其一）：
1. **换到非访客 SSID**：把 Mac 和 Kindle 都连到同一个普通家庭 WiFi（不是 Guest/访客）。
2. **关掉 AP 隔离**：登录路由器管理页（通常 192.168.1.1 / 192.168.0.1），找「无线高级 / AP Isolation / 客户端隔离」关掉。
3. **让 Mac 自己开热点当网关（最省事、必通）**：
   - 系统设置 → 通用 → **共享** → 互联网共享
   - “共享以下来源的连接”选你已联网的网卡（如 Wi-Fi 或以太网），“用以下端口共享给”选 **Wi-Fi**
   - 设置热点名称/密码，打开互联网共享
   - **让 Kindle 连这个 Mac 热点**（而不是原来的路由器 WiFi）
   - 此时 Kindle 的服务器地址填 Mac 热点网卡的 IP，通常是 **`192.168.2.1:8787`**

---

## 4. 拿到 Mac 的局域网 IP，填进 Kindle
```bash
# Wi-Fi 网卡通常是 en0（Apple Silicon 某些机型是 en1）
ipconfig getifaddr en0
# 输出类似 192.168.1.23 或 192.168.2.1（开热点时）
```
- 如果在普通 WiFi 下：Kindle 插件「设置服务器地址」填 `<MacIP>:8787`，例如 `192.168.1.23:8787`。
- 如果连的是 Mac 热点：填 `192.168.2.1:8787`。

> 在 Kindle 插件里：工具 → Kindle Dash → 设置服务器地址，输入后保存（会持久化，下次不用再设）。

---

## 5. 部署 KindleDash 插件到 Kindle（USB 大容量模式）
1. Kindle 用 USB 连 Mac，**退出 KOReader**（让它回到原生界面，USB 才会变成大容量存储）。
2. Mac 上把项目里的 `KindleDash.koplugin/` 整个文件夹，拷到 Kindle 的：
   ```
   koreader/plugins/KindleDash.koplugin/
   ```
   （即 `KindleDash.koplugin/main.lua` 落在这个目录里）
3. 安全弹出 Kindle，断开 USB，重新打开 KOReader。
4. KOReader 里：菜单 → **工具** → **Kindle Dash** → 刷新，应看到看板。
   - 子菜单还有：刷新看板 / 设置服务器地址 / 切换自动刷新（30 分钟）/ 关于。

---

## 6. 数据说明
- **WorkBuddy 限额**：读 `~/.workbuddy/workbuddy.db`。Mac 上若没装 WorkBuddy，会显示 unavailable（不影响其它板块）。
- **Claude Code / Codex 限额**：Mac 上有真实使用历史（`~/.claude/projects`、`~/.codex`），会自动统计近 7 天用量并填充；Windows 开发机上无这些目录才显示 unavailable。
- **天气 / 股市 / 汇率 / 时钟**：走公网免费接口（Open-Meteo、腾讯财经、er-api、Intl 时区），与哪台电脑无关。
  - 股市用腾讯源，国内网络可用（Yahoo Finance 在国内被拦截，故未采用）。

---

## 7. ⚠️ OTA 红线（务必牢记）
Kindle 联网期间，若屏幕弹出「有软件更新」提示，**绝对不要点安装**！
- LanguageBreak 专属热修复已挡自动升级；但手动点「安装更新」会升级固件、丢失越狱。
- 可选加固：Kindle 根目录放空文件 `DISABLE_OTA_UPDATES`（越狱 Hotfix 已挡，非必须）。

---

## 8. 常见问题速查
| 现象 | 原因 / 解法 |
|---|---|
| Kindle 刷新失败 timeout | Mac 防火墙没放行 node（§2）；或 AP 隔离（§3）；或服务器地址填错（§4） |
| Mac 本机能看，Kindle 不行 | 防火墙 / AP 隔离，几乎都不是代码问题 |
| 股市空白 | 腾讯接口临时限流，等 1 分钟自动重试（60s 缓存） |
| Codex/ClaudeCode 显示 unavailable | Mac 上没对应历史目录，属正常；有使用记录后会自动出数 |
| npm install 报错 node-gyp | `xcode-select --install` 后重试 |
| 插件菜单找不到 | 在 KOReader「工具」分组，不在 ☰ 顶层 |
