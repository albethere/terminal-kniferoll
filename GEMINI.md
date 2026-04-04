> **Universal directives live in `AGENTS.md`** — read that first. This file contains Gemini-specific context and supplements `AGENTS.md`.

# GEMINI.md: Terminal-Kniferoll Protocol

## Work Tracker

This repo uses the **telex-kitchen tk-tracker**. DB: `/home/ctrl/telex-kitchen/tracker.db`

```bash
export TK_SCHEMA_DIR=/home/ctrl/telex-kitchen/tracker/schema
tk task create -t "<task>" -d "<detail>" -p P2 --created-by gemini-agent
tk task claim <task-id> --actor gemini-agent
tk task update <task-id> --status done --actor gemini-agent
tk task list
```

## Core Objectives

1. **Utility**: Deploy a production-ready, security-hardened Zsh environment on Linux, macOS, and Windows.
2. **Dashboard**: Provide a rich, animated terminal experience (Projector mode) for system monitoring.
3. **Identity**: Standalone terminal configurator; callable from `lcars-init.sh` or any automation stack.

## Usage Modes

The `install.sh` script is the universal entrypoint. On a TTY it shows a **4-choice menu**:

- **[1] Full install** — Shell + Projector
- **[2] Shell only** — Zsh, Oh My Zsh, plugins, aliases
- **[3] Projector only** — Animation suite (weathr, cbonsai, fastfetch)
- **[4] Custom** — Choose individual tool groups

Flags bypass the menu: `--shell`, `--projector`, `--interactive`, `--full`, `--help`.

## Architecture

- **Idempotency**: All scripts must be safe to re-run. Test `--shell` and `--projector` independently.
- **OS-Agnostic**: Detect Debian/Ubuntu vs macOS (Homebrew) vs Windows (winget/Scoop/Chocolatey).
- **Modular Configs**: `shell/zshrc.zsh` sources `~/.shell/aliases.zsh` and `~/.shell/plugins.zsh`.
- **FSH Last**: `fast-syntax-highlighting` must always be the last plugin loaded.
- **TLS Hardened**: All `curl` calls use `--proto '=https' --tlsv1.2`.

## Security Mandates

- **Zero Secrets**: Never commit API keys. Use the `PRIVATE_*` environment variable pattern.
- **Proxy Aware**: Retain Zscaler certificate detection.
- **Supply Chain**: Review `docs/SUPPLY_CHAIN_RISK.md` before adding any download-then-run patterns.

## New in this overhaul

- `install_windows.ps1` fully rewritten (624 lines) — winget→Scoop→Choco pipeline, Oh My Posh, PSReadLine, posh-git, Terminal-Icons
- `zsh-autosuggestions` + `fast-syntax-highlighting` added to all platform scripts (FSH must be last)
- Verbose timestamped logging to `~/.terminal-kniferoll/logs/`
- `install-v2.sh` deleted — merged into `install_linux.sh`
- 9 deferred tasks logged to tk-tracker (6 supply chain + 3 Windows gaps)

## Integration

- Set `TERMINAL_KNIFEROLL_DIR` when invoking from automation. No hardcoded org or hostnames.
- Set `LCARS_CORE_DIR` if using alongside the full AIDSOCL ecosystem.
