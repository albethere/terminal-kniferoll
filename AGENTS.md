# AGENTS.md — Terminal-Kniferoll Universal Directive

> **For all AI agents (Claude, ChatGPT/Codex, Gemini, Copilot, Cursor, etc.)**
> This is the canonical entry point. Agent-specific files (`GEMINI.md`, `CLAUDE.md`, `.github/copilot-instructions.md`) reference this document for shared context.

You are accessing the `terminal-kniferoll` repository — a production-ready, security-hardened Zsh environment and animated terminal projector. It operates standalone or as a dependency of the `lcars-core` AIDSOCL ecosystem.

---

## 📋 Work Tracker

This repo uses the **telex-kitchen tk-tracker** for task coordination.

- **DB**: `/home/ctrl/telex-kitchen/tracker.db`
- **CLI**: `tk` — install with `pip install /home/ctrl/telex-kitchen/tracker`
- **Schema env**: `export TK_SCHEMA_DIR=/home/ctrl/telex-kitchen/tracker/schema`

```bash
# Before starting work
tk task create -t "<your task>" -d "<detail>" -p P2 --created-by <agent-name>
tk task claim <task-id> --actor <agent-name>

# After completing
tk task update <task-id> --status done --actor <agent-name>

# For anything deferred or blocked
tk task update <task-id> --status blocked --actor <agent-name> --detail "<reason>"
# OR create a new task for the follow-up work

# Check current backlog
tk task list
```

---

## 🎯 Core Objectives

1. **Utility** — Deploy a security-hardened Zsh environment on any OS (Linux, macOS, Windows).
2. **Dashboard** — Provide a rich animated terminal experience (Projector mode) for system monitoring.
3. **Identity** — Usable standalone or orchestrated via `lcars-core`.

---

## 🏗 Architecture Mandates

- **Idempotency** — All scripts must be safe to re-run without data loss. Test `--shell` and `--projector` flags independently.
- **OS-Agnostic** — Detect and handle Debian/Ubuntu, macOS (Homebrew), and Windows.
- **Modular Configs** — `shell/zshrc.zsh` sources `~/.shell/aliases.zsh` and `~/.shell/plugins.zsh`.
- **Zero Secrets** — Never commit API keys. Use the `PRIVATE_*` environment variable pattern.
- **Proxy Aware** — Retain Zscaler certificate detection for corporate environments.
- **Permission Safety** — Use `sudo -E` for terminal operations to preserve user environment.
- **FSH Last** — `fast-syntax-highlighting` must always be the **last** plugin in the plugin load order.
- **TLS Hardened** — All `curl` calls must use `--proto '=https' --tlsv1.2`.

---

## 📡 Usage Modes

The `install.sh` script is the universal entrypoint. On a TTY it shows a 4-choice menu:

| Choice | Action |
|--------|--------|
| `[1]` Full install | Shell environment + Terminal projector (default) |
| `[2]` Shell only | Zsh, Oh My Zsh, plugins, aliases |
| `[3]` Projector only | Animation suite (weather, bonsai, fastfetch) |
| `[4]` Custom | Choose individual tool groups |

Flags bypass the menu:

| Flag | Action |
|------|--------|
| `./install.sh --shell` | Zsh config, plugins, and aliases only |
| `./install.sh --projector` | Animation suite and `projector.py` only |
| `./install.sh --interactive` | Force the 4-choice menu |
| `./install.sh --full` | Full install, no menu |

---

## 🔗 Integration with lcars-core

- Set `LCARS_CORE_DIR` if using alongside the orchestration stack.
- Set `TERMINAL_KNIFEROLL_DIR` when invoked from automation.
- Run `install.sh --shell` for shell-only deploys in automated pipelines.

---

## 📍 Key Files for Agents

| File | Purpose |
|------|---------|
| `install.sh` | Universal entrypoint — OS-detect + delegate |
| `install_linux.sh` | Linux/WSL deployment logic (canonical) |
| `install_mac.sh` | macOS deployment logic |
| `install_windows.ps1` | Windows PowerShell installer (624 lines) |
| `shell/zshrc.zsh` | Zsh config template |
| `shell/aliases.zsh` | Standardised aliases (lsd strategy) |
| `shell/plugins.zsh` | Plugin loader (FSH must be last) |
| `projector.py` | Terminal animation orchestrator |
| `docs/ARCHITECTURE.md` | Design overview, phases, integration contract |
| `docs/FLAVOR.md` | Voice & tone guide for installer output |
| `docs/SUPPLY_CHAIN_RISK.md` | Supply chain risk register and deferred tasks |

---

## 🤖 Agent Instructions

1. **Read** `docs/ARCHITECTURE.md` for a full walkthrough before cross-repo or multi-step tasks.
2. **Log tasks** to the tk-tracker before starting work (see Work Tracker section above).
3. **Don't break idempotency** — always test re-run safety before committing script changes.
4. **Test flags** — verify `--shell` and `--projector` still work independently after any changes.
5. **Keep FSH last** — never reorder the plugin list; `fast-syntax-highlighting` must always load last.
6. **Supply chain** — any new `curl | bash` or download-then-run patterns must be reviewed against `docs/SUPPLY_CHAIN_RISK.md` and logged if deferred.
7. If operating within the full AIDSOCL ecosystem, defer to `lcars-core/AGENTS.md` for fleet-level orchestration.
