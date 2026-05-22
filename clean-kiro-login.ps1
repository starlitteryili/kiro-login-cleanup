<#
.SYNOPSIS
  彻底清理 Kiro IDE 登录痕迹 + 轮换设备机器码（Windows 原生 PowerShell 版）

.DESCRIPTION
  Bash 版 clean-kiro-login.sh 的 PowerShell 等价实现。功能完全一致：
    - 删除 AWS SSO 缓存（Kiro accessToken / refreshToken / clientId / clientSecret）
    - 清理 Kiro 内嵌 Chromium 的全部 storage / cookies / cache
    - 主动写入随机的新设备机器码（machineId / devDeviceId / macMachineId / sqmId / serviceMachineId）
    - 删除历史账号绑定数据（profile.json / per-account hash bucket / dev_data）
    - 清理系统 Chrome 中的 Kiro / AWS 域 cookie
    - 完整保留聊天记录（sessions / workspace-sessions）和用户设置

.PARAMETER Yes
  跳过所有交互确认。

.PARAMETER DryRun
  只打印将要做什么，不实际改动文件。

.PARAMETER SkipBrowser
  跳过系统 Chrome cookie 清理。

.PARAMETER NoRotate
  不主动写入新机器码，仅删除（让 Kiro 启动时自动生成）。

.EXAMPLE
  PS> .\clean-kiro-login.ps1 -DryRun
  PS> .\clean-kiro-login.ps1 -Yes
  PS> .\clean-kiro-login.ps1 -Yes -SkipBrowser

.NOTES
  依赖: PowerShell 5+（Windows 10/11 自带）；sqlite3.exe 在 PATH 上
        （安装：`winget install SQLite.SQLite` 或 `scoop install sqlite`）
  执行策略：如遇 "无法加载文件" 错误，先执行：
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
#>

[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$DryRun,
    [switch]$SkipBrowser,
    [switch]$NoRotate
)

$ErrorActionPreference = 'Stop'

# ---------- 辅助函数 ----------
function Write-Cyan   ($m) { Write-Host $m -ForegroundColor Cyan }
function Write-Green  ($m) { Write-Host $m -ForegroundColor Green }
function Write-Yellow ($m) { Write-Host $m -ForegroundColor Yellow }
function Write-Red    ($m) { Write-Host $m -ForegroundColor Red }

function Confirm-Step($prompt) {
    if ($Yes) { return $true }
    $a = Read-Host "$prompt [y/N]"
    return ($a -match '^[Yy]$')
}

function Invoke-Or-Dry($description, [scriptblock]$action) {
    Write-Host "  $description"
    if ($DryRun) {
        Write-Host "    DRY: 跳过实际执行" -ForegroundColor DarkGray
    } else {
        & $action
    }
}

function New-Hex([int]$bytes) {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $buf = New-Object byte[] $bytes
    $rng.GetBytes($buf)
    ($buf | ForEach-Object { $_.ToString('x2') }) -join ''
}

# ---------- 平台检测 / 路径解析 ----------
if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
    Write-Red "本脚本仅适用于 Windows。Linux/macOS/WSL 请使用 clean-kiro-login.sh"
    exit 1
}

$KiroDir       = Join-Path $env:APPDATA 'Kiro'
$KAgentDir     = Join-Path $KiroDir 'User\globalStorage\kiro.kiroagent'
$StorageJson   = Join-Path $KiroDir 'User\globalStorage\storage.json'
$StateDb       = Join-Path $KiroDir 'User\globalStorage\state.vscdb'
$AwsSsoCache   = Join-Path $env:USERPROFILE '.aws\sso\cache'
$ChromeDir     = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
$ChromeCookiesRel = 'Network\Cookies'
$Ts            = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir     = Join-Path $env:USERPROFILE "kiro-cleanup-backup-$Ts"

# ---------- 启动横幅 ----------
Write-Host "================================================="
Write-Cyan  " Kiro 登录痕迹清理脚本（Windows）"
Write-Host "================================================="
Write-Host "Kiro 目录: $KiroDir"
$mode = if ($DryRun) { 'DRY-RUN' } else { '实际执行' }
if ($Yes) { $mode += ' / 自动确认' }
Write-Host "模式: $mode"
Write-Host "备份目录: $BackupDir"
Write-Host ""

# ---------- [0/6] 前置检查 ----------
Write-Cyan "[0/6] 前置检查"

$kiroProcs = Get-Process -Name 'Kiro' -ErrorAction SilentlyContinue
if ($kiroProcs) {
    Write-Red "✘ 检测到 Kiro 正在运行，请先完全退出 Kiro:"
    $kiroProcs | Format-Table Id, ProcessName | Out-String | Write-Host
    exit 1
}
Write-Green "✔ Kiro 未运行"

$chromeRunning = $null -ne (Get-Process -Name 'chrome' -ErrorAction SilentlyContinue)
if (-not $SkipBrowser -and $chromeRunning) {
    Write-Yellow "⚠ Chrome 正在运行——清理 Chrome 中 Kiro/AWS cookie 需要先关闭 Chrome。"
    if (-not (Confirm-Step "继续执行（将自动跳过 Chrome cookie 清理）?")) {
        exit 2
    }
    $SkipBrowser = $true
}

$sqlite = (Get-Command sqlite3 -ErrorAction SilentlyContinue).Source
if (-not $sqlite) {
    Write-Red "需要 sqlite3.exe 在 PATH 中。建议安装："
    Write-Host  "  winget install SQLite.SQLite"
    Write-Host  "  scoop install sqlite     # 或 scoop"
    exit 1
}

Write-Host ""

# ---------- [1/6] 备份要保留的数据 ----------
Write-Cyan "[1/6] 备份要保留的数据（聊天记录 + 用户设置）"
if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
}

$backupPaths = @(
    "$KAgentDir\sessions",
    "$KAgentDir\workspace-sessions",
    "$KAgentDir\config.json",
    "$KiroDir\User\History",
    "$KiroDir\User\workspaceStorage",
    "$KiroDir\User\settings.json",
    "$KiroDir\User\snippets",
    "$KiroDir\User\globalStorage\storage.json",
    $StateDb
)
foreach ($p in $backupPaths) {
    if (Test-Path $p) {
        $rel = $p.Substring($env:USERPROFILE.Length).TrimStart('\')
        $dst = Join-Path $BackupDir $rel
        Invoke-Or-Dry "backup: $p" {
            New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
            Copy-Item -Recurse -Force $p $dst
        }
    }
}
Write-Green "✔ 备份完成: $BackupDir"
Write-Host ""

# ---------- [2/6] 删除 AWS SSO 缓存 ----------
Write-Cyan "[2/6] 删除 AWS SSO 缓存（Kiro token + SSO clientId/Secret）"
if (Test-Path $AwsSsoCache) {
    Get-ChildItem -Path $AwsSsoCache -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object {
        Invoke-Or-Dry "rm $($_.FullName)" { Remove-Item -Force $_.FullName }
    }
    Write-Green "✔ AWS SSO 缓存已清空"
} else {
    Write-Host "  (无 $AwsSsoCache，跳过)"
}
Write-Host ""

# ---------- [3/6] 清理 Kiro 内嵌 Chromium 存储 ----------
Write-Cyan "[3/6] 清理 Kiro 内嵌浏览器存储（cookie/localStorage/缓存）"
$chromiumTargets = @(
    'Cookies', 'Cookies-journal',
    'Local Storage', 'Session Storage', 'WebStorage',
    'Service Worker', 'Shared Dictionary', 'SharedStorage', 'SharedStorage-wal',
    'Network Persistent State', 'TransportSecurity',
    'Trust Tokens', 'Trust Tokens-journal',
    'DIPS', 'DIPS-journal',
    'Preferences',
    'Cache', 'Code Cache', 'GPUCache',
    'DawnGraphiteCache', 'DawnWebGPUCache',
    'blob_storage', 'Crashpad'
)
foreach ($name in $chromiumTargets) {
    $path = Join-Path $KiroDir $name
    if (Test-Path $path) {
        Invoke-Or-Dry "rm  $path" { Remove-Item -Recurse -Force $path }
    }
}
Write-Green "✔ Kiro Chromium 存储已清"
Write-Host ""

# ---------- [4/6] 重置设备指纹 ----------
if (-not $NoRotate) {
    Write-Cyan "[4/6] 主动写入随机新机器码"
} else {
    Write-Cyan "[4/6] 删除设备指纹（让 Kiro 启动时自动生成）"
}

# 4a. 生成新随机 ID
$NewDevDeviceId       = [guid]::NewGuid().ToString()
$NewMachineId         = New-Hex 32
$NewMacMachineId      = New-Hex 64
$NewSqmId             = '{' + ([guid]::NewGuid().ToString().ToUpper()) + '}'
$NewServiceMachineId  = [guid]::NewGuid().ToString()

if (-not $NoRotate) {
    Write-Host "  生成新设备身份:"
    Write-Host "    devDeviceId      = $NewDevDeviceId"
    Write-Host "    machineId        = $($NewMachineId.Substring(0,16))…(64hex)"
    Write-Host "    macMachineId     = $($NewMacMachineId.Substring(0,16))…(128hex)"
    Write-Host "    sqmId            = $NewSqmId"
    Write-Host "    serviceMachineId = $NewServiceMachineId"
}

# 4b. machineId 文件
$MidFilePath = Join-Path $KiroDir 'machineId'
if (-not $NoRotate) {
    Invoke-Or-Dry "write $MidFilePath <- $NewDevDeviceId" {
        New-Item -ItemType Directory -Force -Path $KiroDir | Out-Null
        [System.IO.File]::WriteAllText($MidFilePath, $NewDevDeviceId, [System.Text.UTF8Encoding]::new($false))
    }
} else {
    if (Test-Path $MidFilePath) {
        Invoke-Or-Dry "rm $MidFilePath" { Remove-Item -Force $MidFilePath }
    }
}

# 4c. storage.json
if (Test-Path $StorageJson) {
    Invoke-Or-Dry "patch $StorageJson" {
        $j = Get-Content -Raw $StorageJson | ConvertFrom-Json
        if (-not $NoRotate) {
            $j | Add-Member -NotePropertyName 'telemetry.devDeviceId'  -NotePropertyValue $NewDevDeviceId  -Force
            $j | Add-Member -NotePropertyName 'telemetry.machineId'    -NotePropertyValue $NewMachineId    -Force
            $j | Add-Member -NotePropertyName 'telemetry.macMachineId' -NotePropertyValue $NewMacMachineId -Force
            $j | Add-Member -NotePropertyName 'telemetry.sqmId'        -NotePropertyValue $NewSqmId        -Force
        } else {
            $j.PSObject.Properties.Remove('telemetry.devDeviceId')  | Out-Null
            $j.PSObject.Properties.Remove('telemetry.machineId')    | Out-Null
            $j.PSObject.Properties.Remove('telemetry.macMachineId') | Out-Null
            $j.PSObject.Properties.Remove('telemetry.sqmId')        | Out-Null
        }
        ($j | ConvertTo-Json -Depth 64) | Set-Content -Path $StorageJson -Encoding UTF8
    }
}

# 4d. state.vscdb 改 SQLite
if (Test-Path $StateDb) {
    if (-not $NoRotate) {
        $sql = @"
DELETE FROM ItemTable WHERE key IN (
  'kiro.kiroAgent',
  'telemetry.currentSessionDate',
  'telemetry.firstSessionDate',
  'telemetry.lastSessionDate',
  'kiroAgent.onboarding.onboardingCompleted'
);
INSERT INTO ItemTable(key,value) VALUES('storage.serviceMachineId','$NewServiceMachineId')
  ON CONFLICT(key) DO UPDATE SET value='$NewServiceMachineId';
VACUUM;
"@
    } else {
        $sql = @"
DELETE FROM ItemTable WHERE key IN (
  'storage.serviceMachineId',
  'kiro.kiroAgent',
  'telemetry.currentSessionDate',
  'telemetry.firstSessionDate',
  'telemetry.lastSessionDate',
  'kiroAgent.onboarding.onboardingCompleted'
);
VACUUM;
"@
    }
    Invoke-Or-Dry "sqlite3 patch $StateDb" {
        $sql | & $sqlite $StateDb | Out-Null
    }
}

# 4e. 删除 state.vscdb.backup
$dbBackup = "$StateDb.backup"
if (Test-Path $dbBackup) {
    Invoke-Or-Dry "rm $dbBackup" { Remove-Item -Force $dbBackup }
}

# 4f. 写日志
if (-not $NoRotate -and -not $DryRun) {
    @"
# 由 clean-kiro-login.ps1 在 $Ts 写入 Kiro 的新机器身份
telemetry.devDeviceId      = $NewDevDeviceId
telemetry.machineId        = $NewMachineId
telemetry.macMachineId     = $NewMacMachineId
telemetry.sqmId            = $NewSqmId
storage.serviceMachineId   = $NewServiceMachineId
$MidFilePath
  = $NewDevDeviceId
"@ | Set-Content -Path (Join-Path $BackupDir 'new-machine-ids.txt') -Encoding UTF8
}

if (-not $NoRotate) {
    Write-Green "✔ 新机器身份已写入（备份目录中有 new-machine-ids.txt）"
} else {
    Write-Green "✔ 设备指纹已删除（下次启动 Kiro 会自动生成新的）"
}
Write-Host ""

# ---------- [5/6] 清理账号绑定数据 ----------
Write-Cyan "[5/6] 清理 kiro.kiroagent 中与账号绑定的数据"
if (Test-Path $KAgentDir) {
    $profileJson = Join-Path $KAgentDir 'profile.json'
    if (Test-Path $profileJson) {
        Invoke-Or-Dry "rm $profileJson" { Remove-Item -Force $profileJson }
    }
    Get-ChildItem -Path $KAgentDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $n = $_.Name
        switch -Regex ($n) {
            '^(sessions|workspace-sessions|\.diffs)$' {
                Write-Host "  keep   $n/"
            }
            '^(default|dev_data)$' {
                Invoke-Or-Dry "rm $($_.FullName)  ($n)" { Remove-Item -Recurse -Force $_.FullName }
            }
            '^[0-9a-f]{32}$' {
                Invoke-Or-Dry "rm $($_.FullName)  (per-account bucket)" { Remove-Item -Recurse -Force $_.FullName }
            }
            default {
                Write-Host "  keep   $n/  (未知，保守保留)"
            }
        }
    }
}
Write-Green "✔ 账号绑定数据已清，sessions/ 与 workspace-sessions/ 完整保留"
Write-Host ""

# ---------- [6/6] 清理 Chrome 中的 Kiro/AWS cookie ----------
Write-Cyan "[6/6] 清理 Chrome 中 Kiro/AWS 相关 cookie"
if ($SkipBrowser) {
    Write-Yellow "  跳过(-SkipBrowser 或 Chrome 仍在运行)"
} elseif (-not (Test-Path $ChromeDir)) {
    Write-Host "  (未发现 Chrome 配置)"
} else {
    $profiles = @(Join-Path $ChromeDir 'Default')
    $profiles += Get-ChildItem -Path $ChromeDir -Directory -Filter 'Profile*' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
    foreach ($p in $profiles) {
        $cdb = Join-Path $p $ChromeCookiesRel
        if (-not (Test-Path $cdb)) { continue }
        Write-Host "  profile: $p"
        if (-not $DryRun) {
            Copy-Item $cdb (Join-Path $BackupDir "$(Split-Path $p -Leaf)-Cookies.bak") -Force
        }
        $sql = @"
DELETE FROM cookies WHERE
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
OR (host_key LIKE '%amazon.com' AND name LIKE '%aws%');
"@
        Invoke-Or-Dry "sqlite DELETE Kiro/AWS cookies" {
            $sql | & $sqlite $cdb | Out-Null
        }
    }
    Write-Green "✔ Chrome cookie 已清理"
}
Write-Host ""

# ---------- 总结 ----------
Write-Host "================================================="
Write-Green " 清理完成"
Write-Host "================================================="
@"
平台: Windows

保留:
  - 聊天历史:  $KAgentDir\sessions\
  - 工作区聊天:$KAgentDir\workspace-sessions\
  - 用户设置:  $KiroDir\User\settings.json, snippets\, History\, workspaceStorage\
  - state.vscdb 中 chat.ChatSessionStore.index 等聊天相关 key

已清:
  - Kiro accessToken / refreshToken ($AwsSsoCache\)
  - AWS SSO clientId/clientSecret  ($AwsSsoCache\)
  - Kiro 内嵌 Chromium 全部 storage / cookies / cache
  - Kiro 设备指纹: machineId + storage.json + state.vscdb 的 telemetry/serviceMachineId
  - 历史账号 bucket: kiro.kiroagent\<hash>\, default\, profile.json, dev_data\
  - Chrome 中 .kiro.dev / aws / awsapps / signin.aws 等 cookie ($ChromeCookiesRel)

备份: $BackupDir

下一步:
  1. 启动 Kiro，会进入未登录状态
  2. 用新的 Pro 账号登录
  3. 聊天记录依然可见
"@
