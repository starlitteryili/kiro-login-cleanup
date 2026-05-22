# kiro-login-cleanup

[![lint](https://github.com/starlitteryili/kiro-login-cleanup/actions/workflows/lint.yml/badge.svg)](https://github.com/starlitteryili/kiro-login-cleanup/actions/workflows/lint.yml)
[![license](https://img.shields.io/github/license/starlitteryili/kiro-login-cleanup)](LICENSE)
[![release](https://img.shields.io/github/v/release/starlitteryili/kiro-login-cleanup)](https://github.com/starlitteryili/kiro-login-cleanup/releases)
[![platform](https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20WSL%20%7C%20windows-informational)](#supported-systems)
[![中文](https://img.shields.io/badge/README-中文-red)](README.md)

> One-shot wipe of every **Kiro IDE login trace** on the box, plus active
> **device-fingerprint rotation**, while **chat history, user settings,
> and project-level `.kiro/` config are kept intact**.
> Useful for switching Pro accounts, troubleshooting, or avoiding
> account-association bans.

## Supported systems

| OS | Script | Status |
|---|---|---|
| **Linux** (Ubuntu / Debian / Fedora …) | `clean-kiro-login.sh` | ✅ Tested on Ubuntu 24.04 + Kiro 0.12.x |
| **macOS** | `clean-kiro-login.sh` | ✅ Auto path detection, CI verifies `bash -n` |
| **WSL2** | `clean-kiro-login.sh` | ✅ Auto-detected |
| **Git Bash / MSYS / Cygwin** | `clean-kiro-login.sh` | ✅ Auto-resolves `%APPDATA%` |
| **Native Windows PowerShell** | `clean-kiro-login.ps1` | ✅ Feature-parity with the Bash script |

---

## What it does / does not do

### ✅ Does (cleans)
- Deletes every JSON under `~/.aws/sso/cache/` (Kiro accessToken / refreshToken / SSO clientId+clientSecret)
- Wipes Kiro's embedded Chromium storage: `Cookies` / `Local Storage` / `Session Storage` / `WebStorage` / `Service Worker` / `Network Persistent State` / `TransportSecurity` / `Trust Tokens` / `DIPS` / `Preferences` / all `*Cache*`
- **Actively writes** brand-new random device identifiers:
  - `<KiroDir>/machineid` (or `machineId` on macOS/Windows)
  - `storage.json` keys: `telemetry.devDeviceId` / `telemetry.machineId` / `telemetry.macMachineId` / `telemetry.sqmId`
  - `state.vscdb` key `storage.serviceMachineId`
- Removes `state.vscdb` keys: `kiro.kiroAgent` (old account quotas/usage), `telemetry.*`, onboarding markers
- Removes account-bound data under `kiro.kiroagent/`: `profile.json`, `dev_data/`, `default/`, all 32-hex per-account buckets
- Cleans system Chrome cookies (`Default/Cookies` or `Default/Network/Cookies` on Windows) for `.kiro.dev` / `aws.amazon.com` / `signin.aws` / `awsapps.com` / `builderid.aws.com`

### ✅ Keeps
- `<KiroDir>/User/globalStorage/kiro.kiroagent/sessions/` — chat sessions JSON
- `<KiroDir>/User/globalStorage/kiro.kiroagent/workspace-sessions/` — per-workspace chats
- `<KiroDir>/User/History/`, `workspaceStorage/`, `settings.json`, `snippets/`
- `<KiroDir>/Backups/`, `extensions/`
- `~/.kiro/` (project-level: settings / skills / steering / extensions / powers)
- `state.vscdb` chat indexes (`chat.ChatSessionStore.index`)

### ❌ Does NOT
- Does not modify / patch / inject anything into the Kiro program binaries
- Does not uninstall Kiro
- Does not touch any non-Kiro/AWS cookie in your browser
- Does not delete chat history, file edit history, or project settings
- Does not phone home or upload anything

---

## Dependencies

### Linux / macOS / WSL / Git Bash

| Tool | Used for |
|---|---|
| `bash` ≥ 3.2 (macOS-default 3.2 is fine) | Main script |
| `sqlite3` | Edit `state.vscdb` and Chrome `Cookies` |
| `jq` | Edit `storage.json` |
| `python3` | Generate cryptographically random UUID / hex |

```bash
sudo apt install -y sqlite3 jq python3        # Ubuntu / Debian / WSL
sudo dnf install -y sqlite jq python3         # Fedora / RHEL
brew install sqlite jq python3                # macOS
pacman -S sqlite jq python                    # MSYS2
```

### Windows (native PowerShell)

| Tool | Used for |
|---|---|
| PowerShell ≥ 5.1 (built-in on Windows 10/11) | Main script |
| `sqlite3.exe` on `PATH` | SQLite operations |

```powershell
winget install SQLite.SQLite
# or:
scoop install sqlite
choco install sqlite
```
> No `python` / `jq` is needed on Windows — `[guid]::NewGuid()` and `RandomNumberGenerator` cover ID generation natively.

---

## Install

### Linux / macOS / WSL / Git Bash

```bash
git clone https://github.com/starlitteryili/kiro-login-cleanup.git ~/kiro-login-cleanup
chmod +x ~/kiro-login-cleanup/clean-kiro-login.sh

# or single-file:
curl -fsSL https://raw.githubusercontent.com/starlitteryili/kiro-login-cleanup/main/clean-kiro-login.sh \
  -o ~/clean-kiro-login.sh && chmod +x ~/clean-kiro-login.sh
```

### Windows (PowerShell)

```powershell
git clone https://github.com/starlitteryili/kiro-login-cleanup.git $env:USERPROFILE\kiro-login-cleanup
cd $env:USERPROFILE\kiro-login-cleanup

# or single-file:
iwr https://raw.githubusercontent.com/starlitteryili/kiro-login-cleanup/main/clean-kiro-login.ps1 `
    -OutFile $env:USERPROFILE\clean-kiro-login.ps1
```

If you hit *"running scripts is disabled on this system"*:
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
# or one-shot:
powershell -ExecutionPolicy Bypass -File .\clean-kiro-login.ps1 -DryRun
```

---

## Usage

**Always quit Kiro completely first.** Close all Chrome windows too if you want
the browser cookies wiped.

### Linux / macOS / WSL / Git Bash

```bash
./clean-kiro-login.sh --dry-run        # preview, no changes
./clean-kiro-login.sh                  # interactive
./clean-kiro-login.sh --yes            # non-interactive
./clean-kiro-login.sh --yes --skip-browser
./clean-kiro-login.sh --yes --no-rotate
```

### Windows PowerShell

```powershell
.\clean-kiro-login.ps1 -DryRun
.\clean-kiro-login.ps1 -Yes
.\clean-kiro-login.ps1 -Yes -SkipBrowser
.\clean-kiro-login.ps1 -Yes -NoRotate
```

Every real run drops a complete backup at `~/kiro-cleanup-backup-<TS>/`
(`%USERPROFILE%\kiro-cleanup-backup-<TS>\` on Windows): chat sessions,
state.vscdb, storage.json, Chrome Cookies, plus a `new-machine-ids.txt`.

---

## CLI flags

| Bash | PowerShell | Meaning |
|---|---|---|
| `-y`, `--yes` | `-Yes` | Auto-confirm every prompt |
| `-n`, `--dry-run` | `-DryRun` | Print intended actions only; touch nothing |
| `--skip-browser` | `-SkipBrowser` | Skip system Chrome cookie cleanup |
| `--no-rotate` | `-NoRotate` | Don't write new IDs — only delete (Kiro will regenerate) |
| `-h`, `--help` | `Get-Help .\clean-kiro-login.ps1` | Show help |

Exit codes: `0` success, `1` precondition failed (Kiro running, missing dep…), `2` user cancel.

---

## Machine-code rotation (the headline feature)

Each invocation (with rotation, default) generates a fresh **cryptographically
random** identity via `python3 secrets`/`uuid` (or `[guid]::NewGuid()` on
Windows) and writes:

| Field | Format | Written to |
|---|---|---|
| `telemetry.devDeviceId` | UUID v4 | `storage.json` + `<KiroDir>/machineid` |
| `telemetry.machineId` | 64-hex (256 bit) | `storage.json` |
| `telemetry.macMachineId` | 128-hex (512 bit) | `storage.json` |
| `telemetry.sqmId` | `{UUID UPPER}` | `storage.json` |
| `storage.serviceMachineId` | UUID v4 | `state.vscdb` ItemTable |

Plain-text record of the new IDs is dropped at
`~/kiro-cleanup-backup-<TS>/new-machine-ids.txt` for audit.

Pass `--no-rotate` / `-NoRotate` if you want only token wipe, no identity rotation.

---

## Verify after running

```bash
echo "== AWS SSO ==" && ls ~/.aws/sso/cache/ ; \
echo "== machineid ==" && cat "$KIRO_DIR/machineid" 2>/dev/null || cat "$KIRO_DIR/machineId" ; echo ; \
echo "== telemetry.* ==" && jq '{dev:."telemetry.devDeviceId",mid:."telemetry.machineId",mac:."telemetry.macMachineId",sqm:."telemetry.sqmId"}' \
  "$KIRO_DIR/User/globalStorage/storage.json" ; \
echo "== serviceMachineId ==" && \
sqlite3 "$KIRO_DIR/User/globalStorage/state.vscdb" \
  "SELECT value FROM ItemTable WHERE key='storage.serviceMachineId';" ; \
echo "== leftover login keys (should be empty) ==" && \
sqlite3 "$KIRO_DIR/User/globalStorage/state.vscdb" \
  "SELECT key FROM ItemTable WHERE key IN ('kiro.kiroAgent','telemetry.firstSessionDate');"
```

(Set `KIRO_DIR=~/.config/Kiro` on Linux,
`~/Library/Application\ Support/Kiro` on macOS,
or `$env:APPDATA\Kiro` on Windows.)

Expected: `~/.aws/sso/cache/` empty, machineid is a fresh UUID, the four
telemetry fields are new randoms, leftover-keys query returns nothing.

---

## Rollback

```bash
B=$(ls -dt ~/kiro-cleanup-backup-* | head -1)
cp -a "$B/.config/Kiro/User/"* ~/.config/Kiro/User/        # Linux paths shown
# Restore Chrome Cookies (close Chrome first):
cp -a "$B/Default-Cookies.bak" ~/.config/google-chrome/Default/Cookies
```

> Tokens at `~/.aws/sso/cache/` are **not** backed up — just log into Kiro again.

---

## FAQ

**Q1: After running, Kiro still shows the old account email on the login screen?**
Should not happen. If it does: confirm `kiro.kiroAgent` is gone from `state.vscdb`
(see Verify above), then `rm -rf ~/.config/Kiro/User/globalStorage/kiro.kiroagent/profile.json`
and restart Kiro.

**Q2: After running, my chat history sidebar is empty?**
The session JSON files in `kiro.kiroagent/sessions/` and `workspace-sessions/`
should still be intact (verify with `ls`). After the new account logs in, Kiro
will rebuild the index — usually a few seconds. If it doesn't pick them up,
copy the session JSON files into the freshly-generated `<new-account-hash>/`
directory under `kiro.kiroagent/`.

**Q3: `sqlite3: database is locked`?**
Kiro or Chrome hasn't fully exited. `pkill -f kiro ; pkill -f chrome` (or the
PS equivalent) and retry.

**Q4: I also use `kiro-cli`. Will this clean it?**
Not yet. CLI tokens live in `~/.local/share/kiro-cli/data.sqlite3` `auth_kv` table.
Manual one-liner:
```bash
rm -rf ~/.local/share/kiro-cli/data.sqlite3
# or only purge auth, keep chat:
sqlite3 ~/.local/share/kiro-cli/data.sqlite3 \
  "DELETE FROM auth_kv WHERE key LIKE 'kirocli:odic:%' OR key LIKE 'codewhisperer:odic:%';"
```

**Q5: I have `kiro-account-manager` installed (3rd-party). Should I clean it?**
It's a Tauri app; data lives in `~/.config/com.kiroaccountmanager.app/` (or
similar, platform-specific). It can auto-rewrite `~/.aws/sso/cache/kiro-auth-token.json`
on account-switch. Quit / uninstall it **before** running this script.

**Q6: Will this 100% prevent association bans?**
No. Beyond local fingerprints, the backend can correlate by:
- Public IP / egress
- Browser fingerprint (when the OAuth flow uses a real browser)
- Email, payment method, signup timing
For full mitigation, combine: clean egress IP, separate browser/incognito
profile for login, fresh email, fresh payment method.

---

## Path map (auto-detected by the script)

| Field | Linux / WSL | macOS | Windows |
|---|---|---|---|
| Kiro user dir | `~/.config/Kiro` | `~/Library/Application Support/Kiro` | `%APPDATA%\Kiro` |
| machineid filename | `machineid` (lowercase) | `machineId` (capital I) | `machineId` |
| storage.json | `<UserDir>/User/globalStorage/storage.json` | same | same |
| state.vscdb | `<UserDir>/User/globalStorage/state.vscdb` | same | same |
| AWS SSO cache | `~/.aws/sso/cache/` | same | `%USERPROFILE%\.aws\sso\cache\` |
| Chrome Cookies | `~/.config/google-chrome/Default/Cookies` | `~/Library/Application Support/Google/Chrome/Default/Cookies` | `%LOCALAPPDATA%\Google\Chrome\User Data\Default\Network\Cookies` (note the `Network\` subdir) |

The Bash script's `detect_os()` and the PowerShell script's environment-variable
lookups select the right row automatically. No manual edits needed.

---

## Disclaimer

- For local maintenance of accounts you legitimately own (account switching,
  device identity reset, privacy hygiene).
- Don't use this to circumvent platform terms, impersonate, or commit fraud.
  All consequences are yours.
- Does not patch the Kiro binaries, doesn't bypass subscription checks, and
  doesn't crack any paid feature.
- Always preview with `--dry-run` first. Keep the backup directory for at
  least a week before deleting it.
