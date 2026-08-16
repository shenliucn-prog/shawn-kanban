# Kindle Paperwhite 3（固件 5.13.3）越狱物料 README

> 本目录只做**本机文件准备**，不涉及对 Kindle 的任何写操作。下面说明每个文件在越狱流程中的
> 角色与安装顺序，供你上机时照做。

---

## ⚠️ 两条铁律（上机前必读）

1. **永远保持飞行模式**：5.13.4 起已封堵本漏洞，任何联网/OTA 都可能把固件升上去导致越狱失效。
   拷文件、装插件全程飞行模式；根目录若已有 ~200MB 的固件缓存（`update-*.bin` 隐藏文件），先删掉。
2. **用 USB 数据线拷文件**：Kindle 连接电脑选“大容量存储(USBMS)”模式，把文件放到**磁盘根目录**
   （即与 `documents/` 同级），不是放进 documents 里。

---

## 物料清单与用途

| 文件名 | 用途 | 安装方式 |
|--------|------|----------|
| `jb-kindlebreak.zip` | 越狱主程序（KindleBreak） | 解压 4 个文件到根目录，浏览器打开 HTML 触发 |
| `JailBreak-1.16.N-FW-5.x-hotfix.zip` | 固化补丁，防升级/重置掉越狱 | 解压出 `Update_jailbreak_hotfix_1.16.N_install.bin` 到根目录 |
| `kual-mrinstaller-1.7.N-r19303.tar.xz` | MRPI 包管理器（提供 `;log mrpi`） | 解压 `extensions/` + `mrpackages/` 到根目录 |
| `KUAL-v2.7.37-gfcb45b5-20250419.tar.xz` | KUAL 启动器（应用入口） | 解压出 `Update_KUALBooklet_v2.7.37_install.bin` 到根目录 |
| `kindle-usbnet-0.22.N-r19297.tar.xz` | USBNetwork（USB SSH） | 解压出 `Update_usbnet_0.22.N_install_pw2_and_up.bin` 到根目录 |
| `koreader-kindlepw2-v2026.07.1.zip` | KOReader 阅读器 | 解压 `koreader/` + `extensions/` 到根目录 |

> 注意：MRPI / KUAL / USBNetwork 的官方分发是 `.tar.xz`，里面的 `.bin` 才是真正安装包。
> 先解压 .tar.xz 到本地，再把里面的 `.bin`（及 extensions/、mrpackages/）拷到 Kindle 根目录。

---

## 推荐安装顺序

### ① KindleBreak 越狱
1. 飞行模式已开。从 `jb-kindlebreak.zip` 解出 `jb`、`jb.sh`、`kindlebreak.html`、`kindlebreak.jxr`。
2. 用 USB 数据线拷到 Kindle **根目录**，安全弹出、拔线。
3. 打开 Kindle「实验版网页浏览器」，地址栏输入（三个斜杠）：
   `file:///mnt/us/kindlebreak.html`
4. 浏览器会卡死/崩溃，数秒到数分钟后设备重启，并弹“Application Error / Collecting Debug Info”。
   → 重启后越狱完成。根目录会留下 `kindlebreak_log.txt`，装完 Hotfix 前别删。

### ② 安装 JailBreak Hotfix（固化）
1. 解压 `JailBreak-1.16.N-FW-5.x-hotfix.zip`，得到 `Update_jailbreak_hotfix_1.16.N_install.bin`。
2. USB 拷到根目录 → 弹出 → 菜单 → 设置 → 更新您的 Kindle。
3. 若提示“无效更新(007)”，说明该 Hotfix 暂未覆盖 5.13.3，等更新或改走 MRPI 安装。

### ③ 安装 MRPI + KUAL
1. 解压 `kual-mrinstaller-1.7.N-r19303.tar.xz` → 把 `extensions/` 和 `mrpackages/` 合并拷到根目录。
2. 解压 `KUAL-v2.7.37-gfcb45b5-20250419.tar.xz` → 把 `Update_KUALBooklet_v2.7.37_install.bin` 拷到根目录。
3. 弹出 → 设置 → 更新您的 Kindle。装好后书库里会出现 **KUAL** 这本书，打开即启动器。
4. 之后装插件都可把 `.bin` 丢进 `mrpackages/`，再在搜索栏输入 `;log mrpi` 回车一键安装。

### ④ 安装 KOReader
1. 解压 `koreader-kindlepw2-v2026.07.1.zip` → 把 `koreader/` 和 `extensions/` 合并拷到根目录。
2. 重启 Kindle，在 KUAL 菜单里找到 KOReader 启动即可。（PW3 务必用 **kindlepw2** 构建）

### ⑤ 安装 USBNetwork（可选）
1. 解压 `kindle-usbnet-0.22.N-r19297.tar.xz` → 把 `Update_usbnet_0.22.N_install_pw2_and_up.bin` 拷到根目录（或放进 `mrpackages/` 用 `;log mrpi` 装）。
2. 在 KUAL 里开启 USBNetwork；USB 连电脑后主机侧需手动配 `192.168.15.x` 网段，SSH 到 `192.168.15.244`（默认用户 `root`，密码空或 `mario`）。

---

## 校验
详见同目录 `MANIFEST.md`：6/6 物料齐备、均可解压、关键子文件齐全；
`jb-kindlebreak.zip` 的 MD5 与已知值 **完全匹配**。
