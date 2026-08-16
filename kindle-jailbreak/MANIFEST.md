# Kindle 越狱物料清单 / MANIFEST

- **目标设备**：Kindle Paperwhite 3（PW3，第 7 代），固件 **5.13.3**
- **越狱方法**：KindleBreak（适用 5.10.3–5.13.3，利用实验浏览器 JPEG XR 漏洞 / KindleDrip）
- **准备工作目录**：`kindle-jailbreak/`（本文件所在目录）
- **生成日期**：2026-08-16
- **完整性总判定**：✅ **全部 6 项物料齐备，且全部通过解压/校验。**

> ⚠️ 格式说明：NiLuJe 官方快照（kindlemodding / MobileRead）对 MRPI、KUAL、USBNetwork
> 均以 `.tar.xz` 形式分发，`.bin` 安装包内嵌在压缩包内（见各文件“关键子文件”列）。
> 因此本清单实际下载到的就是官方权威版本，与任务描述里 `*.zip` / `Update_*.bin` 的命名
> 是“同一来源的不同封装”，安装时按 README.md 解包即可。

---

## 一、下载源基础地址（OVH 公共镜像）

```
BASE = https://storage.gra.cloud.ovh.net/v1/AUTH_2ac4bfee353948ec8ea7fd1710574097/mr-public/
```

KOReader 来自 GitHub Releases。

---

## 二、逐项自检结果

### 1. jb-kindlebreak.zip —— KindleBreak 越狱包
- **用途**：越狱主程序。解压到 Kindle 根目录后，用实验浏览器打开 `file:///mnt/us/kindlebreak.html` 触发漏洞完成越狱。
- **下载 URL**：`BASE/Touch/jb-kindlebreak.zip`
- **文件大小**：84,287 bytes
- **MD5**：`0215C36CC1E3AD8136A67DAEBE369452`
- **下载成功**：是
- **校验结果**：✅ **MD5 与已知值完全匹配**
- **解压测试**：OK
- **关键子文件**：`jb` / `jb.sh` / `kindlebreak.html` / `kindlebreak.jxr` —— 全部存在

### 2. JailBreak-1.16.N-FW-5.x-hotfix.zip —— JailBreak Hotfix（固化补丁）
- **用途**：越狱后立即安装，防止固件升级/重置导致越狱失效。
- **下载 URL**：`BASE/Touch/JailBreak-1.16.N-FW-5.x-hotfix.zip`
- **文件大小**：155,956 bytes
- **MD5**：`B609F2DC1FFFEDB67371689FE3E17049`
- **下载成功**：是
- **校验结果**：无公开 MD5，仅核对文件存在与可解压（已通过）
- **解压测试**：OK
- **关键子文件**：`Update_jailbreak_hotfix_1.16.N_install.bin`（安装包，拷到根目录后“更新您的 Kindle”或经 MRPI 安装）

### 3. kual-mrinstaller-1.7.N-r19303.tar.xz —— MRPI 安装器
- **用途**：MobileRead Package Installer，KUAL 扩展；提供 `;log mrpi` 触发的一键安装能力，后续插件（含 Hotfix、USBNetwork）都靠它装。
- **下载 URL**：`BASE/KUAL/kual-mrinstaller-1.7.N-r19303.tar.xz`
- **文件大小**：1,778,608 bytes
- **MD5**：`03BB04584331E2DEC4F7E09C36E05239`
- **下载成功**：是
- **校验结果**：无公开 MD5，仅核对文件存在与可解压（已通过）
- **解压测试**：OK
- **关键子文件**：`extensions/MRInstaller/`（KUAL 菜单项）、`mrpackages/`（放待安装 .bin 的目录）—— 均存在

### 4. KUAL-v2.7.37-gfcb45b5-20250419.tar.xz —— KUAL 启动器
- **用途**：Kindle Unified Application Launcher，第三方应用的统一入口/启动器。
- **下载 URL**：`BASE/KUAL/KUAL-v2.7.37-gfcb45b5-20250419.tar.xz`
- **文件大小**：224,876 bytes
- **MD5**：`2CEDB9B8C9797D07CA8891ECDF9042D5`
- **下载成功**：是
- **校验结果**：无公开 MD5，仅核对文件存在与可解压（已通过）
- **解压测试**：OK
- **关键子文件**：`Update_KUALBooklet_v2.7.37_install.bin`（安装包）、`Update_KUALBooklet_hotfix_v2.7.37_install.bin`、`Update_KUALBooklet_v2.7.37_uninstall.bin` —— 均存在

### 5. kindle-usbnet-0.22.N-r19297.tar.xz —— USBNetwork（USB SSH）
- **用途**：开启 USB 网络，通过 USB 数据线以 SSH（root）连接 Kindle。
- **下载 URL**：`BASE/Touch/kindle-usbnet-0.22.N-r19297.tar.xz`
- **文件大小**：46,154,104 bytes（约 44 MB，含自带工具链，体积正常）
- **MD5**：`F5490B89A372D8469C1F696A2FB0CB9C`
- **下载成功**：是（首次因 2 分钟命令超时中断，已断点续传补全）
- **校验结果**：无公开 MD5，仅核对文件存在与可解压（已通过）
- **解压测试**：OK（共 1876 个条目）
- **关键子文件**：`USBNetwork/Update_usbnet_0.22.N_install_pw2_and_up.bin`（适用于 PW2 及更新机型，**含 PW3**）、`Update_usbnet_0.22.N_install_touch_pw.bin`、`Update_usbnet_0.22.N_uninstall.bin` —— 均存在

### 6. koreader-kindlepw2-v2026.07.1.zip —— KOReader（e-ink 阅读器）
- **用途**：开源 e-ink 阅读器/文件浏览器，支持 EPUB/PDF/MOBI 等，经 KUAL 启动。
- **下载 URL**：`https://github.com/koreader/koreader/releases/download/v2026.07.1/koreader-kindlepw2-v2026.07.1.zip`
- **文件大小**：40,715,224 bytes（约 38.8 MB）
- **MD5**：`649F6879CC4CF50C0C08EB3F4BA43334`
- **下载成功**：是
- **校验结果**：无公开 MD5，仅核对文件存在与可解压（已通过）
- **解压测试**：OK
- **关键子文件**：`koreader/`（主程序）、`extensions/koreader/`（KUAL 集成，含 `bin/koreader-ext.sh`、`menu.json`）—— 均存在
- **机型说明**：PW3 属于 PW2 及更新机型系列，必须选 **kindlepw2** 构建（不可选 kindle / kindle-legacy / kindlehf）。

---

## 三、完整性总判定

| 物料 | 状态 | 校验 |
|------|------|------|
| jb-kindlebreak.zip | ✅ 齐备 | MD5 与已知值 **完全匹配** |
| JailBreak Hotfix | ✅ 齐备 | 可解压，含 install .bin |
| MRPI 安装器 | ✅ 齐备 | 可解压，含 extensions/ + mrpackages/ |
| KUAL | ✅ 齐备 | 可解压，含 Update_KUALBooklet_*_install.bin |
| USBNetwork | ✅ 齐备 | 可解压，含 pw2_and_up 安装包 |
| KOReader (kindlepw2) | ✅ 齐备 | 可解压，含 koreader/ + extensions/ |

**结论：6/6 全部齐备，均可解压，关键子文件齐全。无缺失项。**
唯一带公开校验值的 `jb-kindlebreak.zip` MD5 命中；其余 5 项按“无公开校验值，仅核对文件存在与可解压”处理，全部通过。

---

## 四、重要提醒（操作 Kindle 前必读）

1. **切勿升级固件**：5.13.4 起已封堵本漏洞。越狱与装插件全程保持**飞行模式**。
2. 拷贝文件请使用 **USB 数据线**（USBMS 大容量存储模式），不要走 WiFi/邮件。
3. Hotfix 版本请以安装时 Kindle 实际提示为准；若提示“无效更新(007)”，说明该 Hotfix 版本暂未覆盖 5.13.3，需等待更新或改用 MRPI 方式安装。
4. 本清单仅做**本机文件准备**，未对 Kindle 硬件做任何操作。
