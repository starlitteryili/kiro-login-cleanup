#!/usr/bin/env bash
# clean-kiro-login.sh
#
# 彻底清理 Kiro 登录痕迹（token / cookie / 设备指纹 / AWS SSO 缓存 /
# 浏览器 Kiro+AWS cookie），保留聊天记录和项目设置。
#
# 支持平台: Linux / macOS / WSL / Git Bash on Windows
#
# 用法:
#   ./clean-kiro-login.sh            # 交互式（每步确认）
#   ./clean-kiro-login.sh --yes      # 全部自动确认
#   ./clean-kiro-login.sh --dry-run  # 只打印将做什么，不实际删除
#   ./clean-kiro-login.sh --skip-browser  # 跳过 Chrome cookie 清理
#   ./clean-kiro-login.sh --no-rotate     # 不写入新机器码，仅删除
#
# 退出码:
#   0 成功 / 1 前置检查失败 / 2 用户取消

set -euo pipefail

YES=0
DRY=0
SKIP_BROWSER=0
ROTATE_IDS=1   # 主动写入随机机器码；--no-rotate 改为只删除让 Kiro 自己生成
for arg in "$@"; do
  case "$arg" in
    --yes|-y)        YES=1 ;;
    --dry-run|-n)    DRY=1 ;;
    --skip-browser)  SKIP_BROWSER=1 ;;
    --no-rotate)     ROTATE_IDS=0 ;;
    -h|--help)
      sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "未知参数: $arg" >&2; exit 1 ;;
  esac
done

# 生成器
gen_uuid()    { python3 -c 'import uuid; print(uuid.uuid4())'; }
gen_hex64()   { python3 -c 'import secrets; print(secrets.token_hex(32))'; }
gen_hex128()  { python3 -c 'import secrets; print(secrets.token_hex(64))'; }
gen_sqmid()   { python3 -c 'import uuid; print("{"+str(uuid.uuid4()).upper()+"}")'; }

cyan()  { printf "\033[36m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }
red()   { printf "\033[31m%s\033[0m\n" "$*"; }

confirm() {
  local prompt="$1"
  if [[ $YES -eq 1 ]]; then return 0; fi
  read -r -p "$prompt [y/N] " a
  [[ "$a" =~ ^[Yy]$ ]]
}

run() {
  if [[ $DRY -eq 1 ]]; then
    echo "  DRY: $*"
  else
    eval "$@"
  fi
}

# ----- 平台检测 + 路径解析 -----
detect_os() {
  local u; u="$(uname -s 2>/dev/null || echo unknown)"
  case "$u" in
    Linux*)
      if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then echo wsl; else echo linux; fi ;;
    Darwin*)              echo macos ;;
    MINGW*|MSYS*|CYGWIN*) echo windows-bash ;;
    *)                    echo unknown ;;
  esac
}
OS_KIND="$(detect_os)"

case "$OS_KIND" in
  linux|wsl)
    KIRO_DIR="$HOME/.config/Kiro"
    MACHINEID_FILE="machineid"
    AWS_SSO_CACHE="$HOME/.aws/sso/cache"
    CHROME_DIR="$HOME/.config/google-chrome"
    CHROME_COOKIES_REL="Cookies"
    KIRO_PROC_REGEX='([Kk]iro|/opt/Kiro)'
    CHROME_PROC_REGEX='/opt/google/chrome/chrome|/usr/bin/google-chrome|chromium|/snap/chromium'
    ;;
  macos)
    KIRO_DIR="$HOME/Library/Application Support/Kiro"
    MACHINEID_FILE="machineId"
    AWS_SSO_CACHE="$HOME/.aws/sso/cache"
    CHROME_DIR="$HOME/Library/Application Support/Google/Chrome"
    CHROME_COOKIES_REL="Cookies"
    KIRO_PROC_REGEX='[Kk]iro\.app|[Kk]iro Helper'
    CHROME_PROC_REGEX='Google Chrome|/Applications/Google Chrome'
    ;;
  windows-bash)
    # Git Bash / MSYS：把 Windows 环境变量翻译成 POSIX 路径
    : "${APPDATA:=$HOME/AppData/Roaming}"
    : "${LOCALAPPDATA:=$HOME/AppData/Local}"
    : "${USERPROFILE:=$HOME}"
    KIRO_DIR="$APPDATA/Kiro"
    MACHINEID_FILE="machineId"
    AWS_SSO_CACHE="$USERPROFILE/.aws/sso/cache"
    CHROME_DIR="$LOCALAPPDATA/Google/Chrome/User Data"
    CHROME_COOKIES_REL="Network/Cookies"
    KIRO_PROC_REGEX='[Kk]iro\.exe'
    CHROME_PROC_REGEX='chrome\.exe'
    ;;
  *)
    echo "✘ 不支持的操作系统: $(uname -s)" >&2
    echo "  本脚本支持: Linux / macOS / WSL / Git Bash on Windows" >&2
    echo "  原生 Windows PowerShell 用户请使用 clean-kiro-login.ps1" >&2
    exit 1
    ;;
esac

KAGENT_DIR="$KIRO_DIR/User/globalStorage/kiro.kiroagent"
STORAGE_JSON="$KIRO_DIR/User/globalStorage/storage.json"
STATE_DB="$KIRO_DIR/User/globalStorage/state.vscdb"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/kiro-cleanup-backup-$TS"

# 跨平台进程查找：优先 pgrep -fl（Linux/macOS BSD 都支持），fallback ps + grep
ps_match() {
  local re="$1"
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -fl "$re" 2>/dev/null || true
  else
    ps -A -o pid=,command= 2>/dev/null | grep -E "$re" | grep -v grep || true
  fi
}

echo "================================================="
cyan  " Kiro 登录痕迹清理脚本"
echo "================================================="
echo "平台: $OS_KIND"
echo "Kiro 目录: $KIRO_DIR"
echo "模式: $([[ $DRY -eq 1 ]] && echo DRY-RUN || echo 实际执行)$([[ $YES -eq 1 ]] && echo ' / 自动确认')"
echo "备份目录(若发生): $BACKUP_DIR"
echo

# ----- 0. 前置检查 -----
cyan "[0/6] 前置检查"

kiro_procs="$(ps_match "$KIRO_PROC_REGEX" | grep -viE 'clean-kiro-login|kiroaccountmanager|kiro-cleanup|kiro_account|Kiro Account Manager' || true)"
if [[ -n "$kiro_procs" ]]; then
  red "✘ 检测到 Kiro 进程正在运行，请先完全退出 Kiro:"
  printf '%s\n' "$kiro_procs"
  exit 1
fi
green "✔ Kiro 未运行"

CHROME_RUNNING=0
if [[ -n "$(ps_match "$CHROME_PROC_REGEX")" ]]; then
  CHROME_RUNNING=1
fi
if [[ $SKIP_BROWSER -eq 0 && $CHROME_RUNNING -eq 1 ]]; then
  yellow "⚠ Chrome 正在运行——清理 Chrome 中 Kiro/AWS cookie 需要先关闭 Chrome。"
  echo "  你可以选择: 1) 现在退出脚本去关闭 Chrome 后重跑;"
  echo "             2) 用 --skip-browser 跳过浏览器清理(只清 Kiro 本体)。"
  if ! confirm "继续执行(将自动跳过 Chrome cookie 清理)?"; then
    exit 2
  fi
  SKIP_BROWSER=1
fi

if ! command -v sqlite3 >/dev/null; then red "需要 sqlite3"; exit 1; fi
if ! command -v jq      >/dev/null; then red "需要 jq";      exit 1; fi

echo

# ----- 1. 备份聊天记录 + 关键配置（保险） -----
cyan "[1/6] 备份要保留的数据（聊天记录 + 用户设置）"
if [[ $DRY -eq 0 ]]; then
  mkdir -p "$BACKUP_DIR"
fi

backup_paths=(
  "$KAGENT_DIR/sessions"
  "$KAGENT_DIR/workspace-sessions"
  "$KAGENT_DIR/config.json"
  "$KIRO_DIR/User/History"
  "$KIRO_DIR/User/workspaceStorage"
  "$KIRO_DIR/User/settings.json"
  "$KIRO_DIR/User/snippets"
  "$KIRO_DIR/User/globalStorage/storage.json"
  "$STATE_DB"
)
for p in "${backup_paths[@]}"; do
  if [[ -e "$p" ]]; then
    rel="${p#$HOME/}"
    dst="$BACKUP_DIR/$rel"
    echo "  backup: $p"
    run "mkdir -p \"\$(dirname '$dst')\""
    run "cp -a '$p' '$dst'"
  fi
done
green "✔ 备份完成: $BACKUP_DIR"
echo

# ----- 2. 删除 AWS SSO 缓存（Kiro token + clientRegistration） -----
cyan "[2/6] 删除 AWS SSO 缓存（Kiro token + SSO clientId/Secret）"
if [[ -d "$AWS_SSO_CACHE" ]]; then
  for f in "$AWS_SSO_CACHE"/*.json; do
    [[ -e "$f" ]] || continue
    echo "  rm $f"
    run "rm -f '$f'"
  done
  green "✔ AWS SSO 缓存已清空"
else
  echo "  (无 ~/.aws/sso/cache，跳过)"
fi
echo

# ----- 3. 清理 Kiro 内嵌 Chromium 存储（cookie/localStorage/...） -----
cyan "[3/6] 清理 Kiro 内嵌浏览器存储（cookie/localStorage/缓存）"
chromium_targets=(
  "Cookies" "Cookies-journal"
  "Local Storage" "Session Storage" "WebStorage"
  "Service Worker" "Shared Dictionary" "SharedStorage" "SharedStorage-wal"
  "Network Persistent State" "TransportSecurity"
  "Trust Tokens" "Trust Tokens-journal"
  "DIPS" "DIPS-journal"
  "Preferences"
  "Cache" "Code Cache" "GPUCache"
  "DawnGraphiteCache" "DawnWebGPUCache"
  "blob_storage" "Crashpad"
  ".org.chromium.Chromium."*
)
for name in "${chromium_targets[@]}"; do
  for path in "$KIRO_DIR/$name"; do
    [[ -e "$path" ]] || continue
    echo "  rm -rf  $path"
    run "rm -rf '$path'"
  done
done
green "✔ Kiro Chromium 存储已清"
echo

# ----- 4. 重置设备指纹（machineid + storage.json + state.vscdb） -----
if [[ $ROTATE_IDS -eq 1 ]]; then
  cyan "[4/6] 主动写入随机新机器码"
else
  cyan "[4/6] 删除设备指纹（让 Kiro 启动时自动生成）"
fi

# 4a. 生成新随机 ID（即便不写入也先生成，dry-run 时展示）
NEW_DEV_DEVICE_ID="$(gen_uuid)"
NEW_MACHINE_ID="$(gen_hex64)"
NEW_MAC_MACHINE_ID="$(gen_hex128)"
NEW_SQM_ID="$(gen_sqmid)"
NEW_SERVICE_MACHINE_ID="$(gen_uuid)"

if [[ $ROTATE_IDS -eq 1 ]]; then
  echo "  生成新设备身份:"
  echo "    devDeviceId       = $NEW_DEV_DEVICE_ID"
  echo "    machineId         = ${NEW_MACHINE_ID:0:16}…(64hex)"
  echo "    macMachineId      = ${NEW_MAC_MACHINE_ID:0:16}…(128hex)"
  echo "    sqmId             = $NEW_SQM_ID"
  echo "    serviceMachineId  = $NEW_SERVICE_MACHINE_ID"
fi

# 4b. machineid 文件 — 总是和 devDeviceId 保持一致（Kiro 的约定）
# Linux 用 'machineid'，macOS/Windows 用 'machineId'；为保险起见两个都处理
MID_FILE_PATH="$KIRO_DIR/$MACHINEID_FILE"
if [[ $ROTATE_IDS -eq 1 ]]; then
  echo "  write $MID_FILE_PATH <- $NEW_DEV_DEVICE_ID"
  if [[ $DRY -eq 0 ]]; then
    mkdir -p "$KIRO_DIR"
    printf '%s' "$NEW_DEV_DEVICE_ID" > "$MID_FILE_PATH"
  fi
  # 顺手清理另一种大小写的旧文件（防止跨平台拷贝过来的残留）
  for alt in machineid machineId machineID; do
    [[ "$alt" != "$MACHINEID_FILE" && -f "$KIRO_DIR/$alt" ]] && { echo "  rm  $KIRO_DIR/$alt  (旧大小写残留)"; run "rm -f '$KIRO_DIR/$alt'"; }
  done
else
  for alt in machineid machineId machineID; do
    [[ -f "$KIRO_DIR/$alt" ]] && { echo "  rm $KIRO_DIR/$alt"; run "rm -f '$KIRO_DIR/$alt'"; }
  done
fi

# 4c. storage.json: 写入或删除 telemetry.* 字段
if [[ -f "$STORAGE_JSON" ]]; then
  if [[ $ROTATE_IDS -eq 1 ]]; then
    echo "  patch $STORAGE_JSON  (set telemetry.{devDeviceId,machineId,macMachineId,sqmId})"
    if [[ $DRY -eq 0 ]]; then
      tmp="$(mktemp)"
      jq --arg dev "$NEW_DEV_DEVICE_ID" \
         --arg mid "$NEW_MACHINE_ID" \
         --arg mac "$NEW_MAC_MACHINE_ID" \
         --arg sqm "$NEW_SQM_ID" \
         '."telemetry.devDeviceId"=$dev
        | ."telemetry.machineId"=$mid
        | ."telemetry.macMachineId"=$mac
        | ."telemetry.sqmId"=$sqm' \
         "$STORAGE_JSON" > "$tmp" && mv "$tmp" "$STORAGE_JSON"
    fi
  else
    echo "  patch $STORAGE_JSON  (drop telemetry.* keys)"
    if [[ $DRY -eq 0 ]]; then
      tmp="$(mktemp)"
      jq 'del(."telemetry.machineId", ."telemetry.devDeviceId", ."telemetry.sqmId", ."telemetry.macMachineId")' \
         "$STORAGE_JSON" > "$tmp" && mv "$tmp" "$STORAGE_JSON"
    fi
  fi
fi

# 4d. state.vscdb: 写入新 serviceMachineId, 同时删登录/账号/旧遥测
if [[ -f "$STATE_DB" ]]; then
  if [[ $ROTATE_IDS -eq 1 ]]; then
    echo "  sqlite UPDATE storage.serviceMachineId  &  DELETE kiro.kiroAgent / telemetry.*"
    if [[ $DRY -eq 0 ]]; then
      sqlite3 "$STATE_DB" <<SQL
DELETE FROM ItemTable WHERE key IN (
  'kiro.kiroAgent',
  'telemetry.currentSessionDate',
  'telemetry.firstSessionDate',
  'telemetry.lastSessionDate',
  'kiroAgent.onboarding.onboardingCompleted'
);
INSERT INTO ItemTable(key,value) VALUES('storage.serviceMachineId','$NEW_SERVICE_MACHINE_ID')
  ON CONFLICT(key) DO UPDATE SET value='$NEW_SERVICE_MACHINE_ID';
VACUUM;
SQL
    fi
  else
    echo "  sqlite DELETE storage.serviceMachineId / kiro.kiroAgent / telemetry.*"
    if [[ $DRY -eq 0 ]]; then
      sqlite3 "$STATE_DB" <<'SQL'
DELETE FROM ItemTable WHERE key IN (
  'storage.serviceMachineId',
  'kiro.kiroAgent',
  'telemetry.currentSessionDate',
  'telemetry.firstSessionDate',
  'telemetry.lastSessionDate',
  'kiroAgent.onboarding.onboardingCompleted'
);
VACUUM;
SQL
    fi
  fi
fi

# 4e. backup 文件同步删（避免回滚旧机器码）
[[ -f "${STATE_DB}.backup" ]] && { echo "  rm ${STATE_DB}.backup"; run "rm -f '${STATE_DB}.backup'"; }

# 4f. 记录到清理日志，便于追溯
if [[ $ROTATE_IDS -eq 1 && $DRY -eq 0 ]]; then
  cat > "$BACKUP_DIR/new-machine-ids.txt" <<EOF
# 由 clean-kiro-login.sh 在 $TS 写入 Kiro 的新机器身份
telemetry.devDeviceId      = $NEW_DEV_DEVICE_ID
telemetry.machineId        = $NEW_MACHINE_ID
telemetry.macMachineId     = $NEW_MAC_MACHINE_ID
telemetry.sqmId            = $NEW_SQM_ID
storage.serviceMachineId   = $NEW_SERVICE_MACHINE_ID
$MID_FILE_PATH
  = $NEW_DEV_DEVICE_ID
EOF
fi

if [[ $ROTATE_IDS -eq 1 ]]; then
  green "✔ 新机器身份已写入（备份目录中有 new-machine-ids.txt）"
else
  green "✔ 设备指纹已删除（下次启动 Kiro 会自动生成新的）"
fi
echo

# ----- 5. 清理 Kiro Agent 账号绑定数据（保留 sessions / workspace-sessions） -----
cyan "[5/6] 清理 kiro.kiroagent 中与账号绑定的数据"
if [[ -d "$KAGENT_DIR" ]]; then
  # 5a. profile.json (BuilderId ARN)
  if [[ -f "$KAGENT_DIR/profile.json" ]]; then
    echo "  rm $KAGENT_DIR/profile.json"
    run "rm -f '$KAGENT_DIR/profile.json'"
  fi
  # 5b. 每个账号的 hash 子目录 + default + dev_data
  shopt -s nullglob
  for d in "$KAGENT_DIR"/*/; do
    name="$(basename "$d")"
    case "$name" in
      sessions|workspace-sessions|.diffs)
        echo "  keep   $name/"
        ;;
      default)
        echo "  rm -rf $d  (default profile bucket)"
        run "rm -rf '$d'"
        ;;
      dev_data)
        echo "  rm -rf $d  (token 使用记录)"
        run "rm -rf '$d'"
        ;;
      *)
        # 32 位 hex hash 目录 = 历史账号 bucket
        if [[ "$name" =~ ^[0-9a-f]{32}$ ]]; then
          echo "  rm -rf $d  (per-account bucket)"
          run "rm -rf '$d'"
        else
          echo "  keep   $name/  (未知，保守保留)"
        fi
        ;;
    esac
  done
  shopt -u nullglob
fi
green "✔ 账号绑定数据已清，sessions/ 与 workspace-sessions/ 完整保留"
echo

# ----- 6. 清理系统 Chrome 中的 kiro/aws cookie -----
cyan "[6/6] 清理 Chrome 中 Kiro/AWS 相关 cookie"
if [[ $SKIP_BROWSER -eq 1 ]]; then
  yellow "  跳过(--skip-browser 或 Chrome 仍在运行)"
elif [[ ! -d "$CHROME_DIR" ]]; then
  echo "  (未发现 Chrome 配置)"
else
  # 找出所有 Profile（Default + Profile *）
  profiles=()
  for p in "$CHROME_DIR/Default" "$CHROME_DIR"/Profile*; do
    [[ -d "$p" ]] && profiles+=("$p")
  done
  for p in "${profiles[@]}"; do
    cdb="$p/$CHROME_COOKIES_REL"
    [[ -f "$cdb" ]] || continue
    echo "  profile: $p"
    if [[ $DRY -eq 0 ]]; then
      cp -a "$cdb" "$BACKUP_DIR/$(basename "$p")-Cookies.bak"
    fi
    # 匹配 Kiro / AWS / AWS SSO / AWS Builder ID 相关域
    sql="DELETE FROM cookies WHERE
       host_key LIKE '%kiro.dev'
    OR host_key LIKE '%.kiro.dev'
    OR host_key LIKE '%amazonaws.com'
    OR host_key LIKE '%.amazonaws.com'
    OR host_key LIKE '%aws.amazon.com'
    OR host_key LIKE '%signin.aws'
    OR host_key LIKE '%.signin.aws'
    OR host_key LIKE '%awsapps.com'
    OR host_key LIKE '%.awsapps.com'
    OR host_key LIKE '%builderid.aws.com'
    OR host_key LIKE '%.builderid.aws.com'
    OR host_key LIKE '%amazon.com' AND name LIKE '%aws%';"
    echo "    sqlite DELETE Kiro/AWS cookies"
    run "sqlite3 '$cdb' \"$sql\""
  done
  green "✔ Chrome cookie 已清理"
fi
echo

# ----- 总结 -----
echo "================================================="
green " 清理完成"
echo "================================================="
cat <<EOF
平台: $OS_KIND

保留:
  - 聊天历史:  $KAGENT_DIR/sessions/
  - 工作区聊天:$KAGENT_DIR/workspace-sessions/
  - 用户设置:  $KIRO_DIR/User/settings.json, snippets/, History/, workspaceStorage/
  - 项目级 :   ~/.kiro/   (settings/skills/steering/extensions/powers)
  - state.vscdb 中 chat.ChatSessionStore.index 等聊天相关 key

已清:
  - Kiro accessToken / refreshToken ($AWS_SSO_CACHE/)
  - AWS SSO clientId/clientSecret  ($AWS_SSO_CACHE/)
  - Kiro 内嵌 Chromium 全部 storage / cookies / cache
  - Kiro 设备指纹: $MACHINEID_FILE + storage.json + state.vscdb 的 telemetry/serviceMachineId
  - 历史账号 bucket: kiro.kiroagent/<hash>/, default/, profile.json, dev_data/
  - Chrome 中 .kiro.dev / aws / awsapps / signin.aws 等 cookie ($CHROME_COOKIES_REL)

备份: $BACKUP_DIR

下一步:
  1. 启动 Kiro，会进入未登录状态
  2. 用新的 Pro 账号登录
  3. 聊天记录依然可见
EOF
