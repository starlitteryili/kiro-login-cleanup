# kiro-login-cleanup

[![lint](https://github.com/starlitteryili/kiro-login-cleanup/actions/workflows/lint.yml/badge.svg)](https://github.com/starlitteryili/kiro-login-cleanup/actions/workflows/lint.yml)
[![license](https://img.shields.io/github/license/starlitteryili/kiro-login-cleanup)](LICENSE)
[![release](https://img.shields.io/github/v/release/starlitteryili/kiro-login-cleanup)](https://github.com/starlitteryili/kiro-login-cleanup/releases)
[![platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20WSL%20%7C%20windows-informational)](#支持的系统)
[![English](https://img.shields.io/badge/README-English-blue)](README.en.md)

> 一键彻底清理本机所有 **Kiro IDE 登录痕迹** + **轮换设备机器码**，
> 同时**完整保留聊天记录、用户设置、项目级 `.kiro/` 配置**。
> 适合换 Pro 账号 / 排障 / 防止账号关联封禁场景。

## 支持的系统

| OS | 脚本 | 状态 |
|---|---|---|
| **Linux**（Ubuntu / Debian / Fedora …） | `clean-kiro-login.sh` | ✅ 已实测（Ubuntu 24.04 + Kiro 0.12.x） |
| **macOS** | `clean-kiro-login.sh` | ✅ 路径自动检测，CI 通过 `bash -n` |
| **WSL2 (Windows 下的 Linux 子系统)** | `clean-kiro-login.sh` | ✅ 自动识别 |
| **Git Bash / MSYS / Cygwin (Windows)** | `clean-kiro-login.sh` | ✅ 自动识别 `%APPDATA%` |
| **原生 Windows PowerShell** | `clean-kiro-login.ps1` | ✅ 与 Bash 版功能完全一致 |

---

## 目录

- [它会做什么 / 不会做什么](#它会做什么--不会做什么)
- [依赖](#依赖)
- [安装](#安装)
- [快速使用](#快速使用)
- [命令行选项](#命令行选项)
- [清理范围一览](#清理范围一览)
- [机器码轮换（核心特性）](#机器码轮换核心特性)
- [事后验证](#事后验证)
- [回滚](#回滚)
- [常见问题](#常见问题)
- [路径对照表（其他平台参考）](#路径对照表其他平台参考)
- [免责声明](#免责声明)

---

## 它会做什么 / 不会做什么

### ✅ 会做（清理）
- 删除 `~/.aws/sso/cache/` 下所有 JSON（Kiro accessToken / refreshToken / SSO clientId+clientSecret）
- 删除 Kiro 内嵌 Chromium 的全部存储：`Cookies` / `Local Storage` / `Session Storage` / `WebStorage` / `Service Worker` / `Network Persistent State` / `TransportSecurity` / `Trust Tokens` / `DIPS` / `Preferences` / 各种 `*Cache*`
- **主动写入**全新随机的设备指纹：
  - `~/.config/Kiro/machineid`
  - `storage.json` 中的 `telemetry.devDeviceId` / `telemetry.machineId` / `telemetry.macMachineId` / `telemetry.sqmId`
  - `state.vscdb` 中的 `storage.serviceMachineId`
- 删除 `state.vscdb` 中的 `kiro.kiroAgent`（含旧账号配额/使用量）、`telemetry.*`、onboarding 标记
- 删除 `kiro.kiroagent/` 下与账号绑定的数据：`profile.json` / `dev_data/` / `default/` / 所有 32 位 hex 历史账号 bucket
- 清理系统 Chrome（`~/.config/google-chrome/Default/Cookies`）中的 `.kiro.dev` / `aws.amazon.com` / `signin.aws` / `awsapps.com` / `builderid.aws.com` 等域 cookie

### ✅ 会做（保留）
- `~/.config/Kiro/User/globalStorage/kiro.kiroagent/sessions/` — 聊天会话 JSON
- `~/.config/Kiro/User/globalStorage/kiro.kiroagent/workspace-sessions/` — 各工作区聊天
- `~/.config/Kiro/User/globalStorage/kiro.kiroagent/.diffs/` 与 `config.json`
- `~/.config/Kiro/User/History/` — 文件编辑历史
- `~/.config/Kiro/User/workspaceStorage/` — 工作区状态
- `~/.config/Kiro/User/settings.json` 与 `snippets/`
- `~/.config/Kiro/Backups/` 与 `extensions/`
- `~/.kiro/` 项目级目录（settings / skills / steering / extensions / powers）
- `state.vscdb` 中的 `chat.ChatSessionStore.index` 等聊天索引

### ❌ 不会做
- 不修改 / 注入 / patch Kiro 程序文件本身（不动 `/opt/Kiro` 下任何二进制）
- 不卸载 Kiro
- 不改你 Chrome 里非 Kiro/AWS 域的任何 cookie
- 不删除聊天记录、文件历史、项目设置
- 不联网、不上传任何数据

---

## 依赖

### Linux / macOS / WSL / Git Bash

| 工具 | 用途 |
|---|---|
| `bash` ≥ 3.2（macOS 自带 3.2 也能跑） | 主脚本 |
| `sqlite3` | 改 `state.vscdb` / Chrome `Cookies` |
| `jq` | 改 `storage.json` |
| `python3` | 生成随机 UUID / hex |

```bash
sudo apt install -y sqlite3 jq python3        # Ubuntu/Debian/WSL
sudo dnf install -y sqlite jq python3         # Fedora/RHEL
brew install sqlite jq python3                # macOS
pacman -S sqlite jq python                    # MSYS2
```

### Windows（PowerShell 原生）

| 工具 | 用途 |
|---|---|
| PowerShell ≥ 5.1（Win 10/11 自带） | 主脚本 |
| `sqlite3.exe` 在 PATH 上 | SQLite 操作 |

随便一个安装方式：
```powershell
winget install SQLite.SQLite       # Windows 10/11 推荐
scoop install sqlite               # 装了 scoop 的话
choco install sqlite               # 装了 chocolatey 的话
```
> Windows 上 `[guid]::NewGuid()` 和 `RandomNumberGenerator` 直接生成机器码，**无需** `python` / `jq`。

---

## 安装

### Linux / macOS / WSL / Git Bash

```bash
# 方式 1：clone 整个仓库
git clone https://github.com/starlitteryili/kiro-login-cleanup.git ~/kiro-login-cleanup
chmod +x ~/kiro-login-cleanup/clean-kiro-login.sh

# 方式 2：只下单脚本
curl -fsSL https://raw.githubusercontent.com/starlitteryili/kiro-login-cleanup/main/clean-kiro-login.sh \
  -o ~/clean-kiro-login.sh && chmod +x ~/clean-kiro-login.sh

# 方式 3：用 gh
gh repo clone starlitteryili/kiro-login-cleanup ~/kiro-login-cleanup
```

### Windows（PowerShell）

```powershell
# 方式 1：clone 整个仓库
git clone https://github.com/starlitteryili/kiro-login-cleanup.git $env:USERPROFILE\kiro-login-cleanup
cd $env:USERPROFILE\kiro-login-cleanup

# 方式 2：只下 PS1
iwr https://raw.githubusercontent.com/starlitteryili/kiro-login-cleanup/main/clean-kiro-login.ps1 `
    -OutFile $env:USERPROFILE\clean-kiro-login.ps1
```

如果首次运行报 *"无法加载文件，因为在此系统上禁止运行脚本"*：
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
# 或单次执行：
powershell -ExecutionPolicy Bypass -File .\clean-kiro-login.ps1 -DryRun
```

---

## 快速使用

**关键前置**：先**完全退出 Kiro**，并**关闭所有 Chrome 窗口**（如果你想顺便清浏览器 cookie）。

### Linux / macOS / WSL / Git Bash

```bash
# 1) 干跑预览（什么都不会改，强烈建议第一次用先跑这个）
./clean-kiro-login.sh --dry-run

# 2) 实际执行（每步交互确认）
./clean-kiro-login.sh

# 3) 一把过（不交互，自动确认所有步骤）
./clean-kiro-login.sh --yes

# 4) 不想关 Chrome：跳过浏览器清理
./clean-kiro-login.sh --yes --skip-browser

# 5) 只清登录、不轮换机器码
./clean-kiro-login.sh --yes --no-rotate
```

### Windows PowerShell

```powershell
# 1) 干跑预览
.\clean-kiro-login.ps1 -DryRun

# 2) 一把过
.\clean-kiro-login.ps1 -Yes

# 3) 跳过浏览器
.\clean-kiro-login.ps1 -Yes -SkipBrowser

# 4) 只清登录、不轮换机器码
.\clean-kiro-login.ps1 -Yes -NoRotate
```

每次实际运行都会在 `~/kiro-cleanup-backup-<时间戳>/`（Windows 是 `%USERPROFILE%\kiro-cleanup-backup-<TS>\`）
留**完整备份**（聊天记录 + state.vscdb + storage.json + Chrome Cookies + 新机器码列表）。

---

## 命令行选项

| Bash | PowerShell | 含义 |
|---|---|---|
| `-y`, `--yes` | `-Yes` | 跳过所有确认提示，自动 yes |
| `-n`, `--dry-run` | `-DryRun` | 只打印将要做什么，不实际改任何文件 |
| `--skip-browser` | `-SkipBrowser` | 跳过系统 Chrome 的 cookie 清理（Chrome 不关时用） |
| `--no-rotate` | `-NoRotate` | 不主动写入新机器码，仅删除——下次启动 Kiro 时由它自己生成 |
| `-h`, `--help` | `Get-Help .\clean-kiro-login.ps1` | 显示帮助 |

退出码：`0` 成功 / `1` 前置检查失败（Kiro 在跑、缺依赖等）/ `2` 用户取消。

---

## 清理范围一览

```
~/.aws/sso/cache/                                    全部 JSON 删除
~/.config/Kiro/
├── machineid                                        重写为新 UUID
├── Cookies, Cookies-journal                         删除
├── Local Storage/, Session Storage/, WebStorage/    删除
├── Service Worker/, Shared Dictionary/              删除
├── SharedStorage, Network Persistent State          删除
├── TransportSecurity, Trust Tokens, DIPS            删除
├── Preferences                                      删除
├── Cache/, Code Cache/, GPUCache/                   删除
├── DawnGraphiteCache/, DawnWebGPUCache/             删除
├── blob_storage/, Crashpad/                         删除
└── User/
    ├── settings.json                                ✅ 保留
    ├── snippets/                                    ✅ 保留
    ├── History/                                     ✅ 保留
    ├── workspaceStorage/                            ✅ 保留
    └── globalStorage/
        ├── storage.json                             telemetry.* 改为新随机值
        ├── state.vscdb                              删登录 key、写入新 serviceMachineId
        ├── state.vscdb.backup                       删除（避免回滚）
        └── kiro.kiroagent/
            ├── config.json                          ✅ 保留
            ├── sessions/                            ✅ 保留（聊天记录）
            ├── workspace-sessions/                  ✅ 保留（工作区聊天）
            ├── .diffs/                              ✅ 保留
            ├── profile.json                         删除（含 BuilderId ARN）
            ├── dev_data/                            删除（token 使用日志）
            ├── default/                             删除（默认 profile bucket）
            └── <32位 hex>/                          删除（每个旧账号一个）

~/.config/google-chrome/Default/Cookies              删除 Kiro/AWS 相关 cookie
```

---

## 机器码轮换（核心特性）

每次带 `--rotate`（默认开启）跑脚本，都会用 `python3 secrets / uuid` 生成全套**密码学随机**的新身份：

| 字段 | 格式 | 写入位置 |
|---|---|---|
| `telemetry.devDeviceId` | UUID v4 | `storage.json` + `~/.config/Kiro/machineid` |
| `telemetry.machineId` | 64 字符 hex（256 bit） | `storage.json` |
| `telemetry.macMachineId` | 128 字符 hex（512 bit） | `storage.json` |
| `telemetry.sqmId` | `{UUID 大写带花括号}` | `storage.json` |
| `storage.serviceMachineId` | UUID v4 | `state.vscdb` ItemTable |

新值的明文记录会被写到 `~/kiro-cleanup-backup-<时间戳>/new-machine-ids.txt`，便于排障。

如果你只想清登录、不想换机器码（比如想保留同一台设备身份再登回原账号），加 `--no-rotate`。

---

## 事后验证

下面这一行直接核验关键状态，全部正常应输出 5 个新随机 ID 且无残留 token：

```bash
echo "== AWS SSO ==" && ls ~/.aws/sso/cache/ ; \
echo "== Kiro Cookies ==" && ls ~/.config/Kiro/Cookies 2>&1 ; \
echo "== machineid ==" && cat ~/.config/Kiro/machineid ; echo ; \
echo "== telemetry.* ==" && jq '{dev:."telemetry.devDeviceId",mid:."telemetry.machineId",mac:."telemetry.macMachineId",sqm:."telemetry.sqmId"}' \
  ~/.config/Kiro/User/globalStorage/storage.json ; \
echo "== serviceMachineId ==" && \
sqlite3 ~/.config/Kiro/User/globalStorage/state.vscdb \
  "SELECT value FROM ItemTable WHERE key='storage.serviceMachineId';" ; \
echo "== 残留登录 key (应空) ==" && \
sqlite3 ~/.config/Kiro/User/globalStorage/state.vscdb \
  "SELECT key FROM ItemTable WHERE key IN ('kiro.kiroAgent','telemetry.firstSessionDate');"
```

预期：AWS SSO 目录为空、Cookies 不存在、machineid 是个新 UUID、`残留登录 key` 一行都没有。

---

## 回滚

每次运行都会备份到 `~/kiro-cleanup-backup-<TS>/`：

```bash
# 找到最近一次备份
B=$(ls -dt ~/kiro-cleanup-backup-* | head -1)

# 恢复 Kiro 用户数据（聊天记录 + 设置 + state.vscdb + storage.json）
cp -a "$B/.config/Kiro/User/"* ~/.config/Kiro/User/

# 恢复 Chrome Cookies（注意：必须先关 Chrome）
cp -a "$B/Default-Cookies.bak" ~/.config/google-chrome/Default/Cookies
```

> 注意：脚本**不**会备份 `~/.aws/sso/cache/`，因为那只是 token，删了重新登录即可。

---

## 常见问题

**Q1: 跑完启动 Kiro，弹窗仍显示旧账号的邮箱？**
未发生过。如果遇到：再确认 `state.vscdb` 中 `kiro.kiroAgent` 已删（事后验证脚本最后一行）；并 `rm -rf ~/.config/Kiro/User/globalStorage/kiro.kiroagent/profile.json` 后重启。

**Q2: 跑完启动 Kiro，聊天侧栏里看不到历史会话？**
可能 Kiro 把 sessions 锁定到旧 profile。检查 `~/.config/Kiro/User/globalStorage/kiro.kiroagent/sessions/` 下文件是否还在；如果还在但 UI 看不到，新登录后稍等几秒索引会重建；仍不行则把对应 session JSON 拷贝到新创建的 `<新hash>/` 目录下（新 hash 在登录后会自动生成）。

**Q3: 提示 `sqlite3: database is locked`？**
说明 Kiro 或 Chrome 还没完全退出。`pkill -f kiro ; pkill -f chrome` 后重试。

**Q4: 我同时安装了 `kiro-cli`（CLI 版本），脚本会清吗？**
当前脚本**不**清 CLI 版本的状态。CLI 版的 token 在 `~/.local/share/kiro-cli/data.sqlite3` 的 `auth_kv` 表。如需一并清理，参考下面手动命令：
```bash
rm -rf ~/.local/share/kiro-cli/data.sqlite3       # 简单粗暴
# 或保留 chat 历史、只删 token：
sqlite3 ~/.local/share/kiro-cli/data.sqlite3 \
  "DELETE FROM auth_kv WHERE key LIKE 'kirocli:odic:%' OR key LIKE 'codewhisperer:odic:%';"
```

**Q5: `kiro-account-manager` 第三方账号管理器要清吗？**
- 它是 Tauri 桌面应用，本地状态在 `~/.config/com.kiroaccountmanager.app/` 或类似目录。
- 如果你装了它，**直接卸载**或 `rm -rf` 上面那个目录即可——它本身没有"登录态"，只是把多账号 token 表存在那。
- 注意它可能会在你"切号"操作时**自动写回** `~/.aws/sso/cache/kiro-auth-token.json`，所以清理前要**先退出/卸载它**。

**Q6: 这能 100% 防关联封禁吗？**
不能。除了本地指纹，Kiro / AWS 后端还可能根据：
- 你的公网 IP / 出口
- 浏览器指纹（如果用了网页登录走 OAuth）
- 邮箱、支付方式、注册时间等
做关联。要更彻底，配合：换 IP（IPv6 可能不够，建议干净的代理出口）、换浏览器/隐身模式登录、换邮箱、换支付方式。

---

## 路径对照表（脚本内部映射，自动检测 OS）

| 项 | Linux / WSL | macOS | Windows |
|---|---|---|---|
| Kiro 用户目录 | `~/.config/Kiro` | `~/Library/Application Support/Kiro` | `%APPDATA%\Kiro` |
| machineid 文件名 | `machineid`（小写） | `machineId`（大写 I） | `machineId` |
| storage.json | `<UserDir>/User/globalStorage/storage.json` | 同 | 同 |
| state.vscdb | `<UserDir>/User/globalStorage/state.vscdb` | 同 | 同 |
| AWS SSO cache | `~/.aws/sso/cache/` | 同 | `%USERPROFILE%\.aws\sso\cache\` |
| Chrome Cookies | `~/.config/google-chrome/Default/Cookies` | `~/Library/Application Support/Google/Chrome/Default/Cookies` | `%LOCALAPPDATA%\Google\Chrome\User Data\Default\Network\Cookies` ⚠️ 注意 `Network\` 子目录 |

> 脚本里 `detect_os()` 函数自动选择上面对应一行的路径，无需手动修改。
> 进程检测、`pgrep`/`Get-Process`、`sqlite3` 调用方式也都会切换到对应平台的实现。

---

## 免责声明

- 本工具用于**自有账号**的本地数据维护（账号切换、设备身份重置、隐私清理）。
- 不要用于规避平台条款、伪造身份、欺诈等用途。后果自负。
- 工具不修改 Kiro 程序本体、不绕过订阅校验、不破解任何收费功能。
- 任何操作前请先 `--dry-run` 预览。备份目录请保留至少一周再删。
