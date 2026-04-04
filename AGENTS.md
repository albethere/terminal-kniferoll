# AGENTS.md — Terminal-Kniferoll Universal Directive

> **For all AI agents (Claude, ChatGPT/Codex, Gemini, Copilot, Cursor, etc.)**
> This is the canonical entry point. Agent-specific files (`GEMINI.md`, `CLAUDE.md`, `.github/copilot-instructions.md`) reference this document for shared context.

You are accessing the `terminal-kniferoll` repository — a production-ready, security-hardened Zsh environment and animated terminal projector. It operates standalone or as a dependency of the `lcars-core` AIDSOCL ecosystem.

---

## 🎯 Core Objectives

1. **Utility** — Deploy a security-hardened Zsh environment on any OS (Linux, macOS, WSL).
2. **Dashboard** — Provide a rich animated terminal experience (Projector mode) for system monitoring.
3. **Identity** — Spiritual successor to minimal dotfile setups; usable standalone or orchestrated.

---

## 🏗 Architecture Mandates

- **Idempotency** — All scripts must be safe to re-run without data loss.
- **OS-Agnostic** — Detect and handle Debian/Ubuntu, macOS (Homebrew), and WSL.
- **Modular Configs** — `shell/zshrc.zsh` sources `~/.shell/aliases.zsh` and `~/.shell/plugins.zsh`.
- **Zero Secrets** — Never commit API keys. Use the `PRIVATE_*` environment variable pattern.
- **Proxy Aware** — Retain Zscaler certificate detection for corporate environments.
- **Permission Safety** — Use `sudo -E` for terminal operations to preserve user environment.

---

## 📡 Usage Modes

The `install.sh` script is the universal entrypoint:

| Flag | Action |
|------|--------|
| `./install.sh` | Full install (shell + projector) |
| `./install.sh --shell` | Zsh config, plugins, and aliases only |
| `./install.sh --projector` | Animation suite and `projector.py` only |

On interactive TTY, the installer prompts:
- **[1] Interactive** — Conversational, guided tool selection
- **[2] Passive** — Full autonomous AIDSOCL sync (no prompts, psychic alignment)

---

## 🔗 Integration with lcars-core

- Set `LCARS_CORE_DIR` if using alongside the orchestration stack — enables shell aliases and awareness sourcing.
- Set `TERMINAL_KNIFEROLL_DIR` when invoked from automation (e.g., central bootstrap scripts).
- Run `install.sh --shell` for shell-only deploys in automated pipelines.

---

## 📍 Key Files for Agents

| File | Purpose |
|------|---------|
| `install.sh` | Universal entrypoint — start here |
| `install_linux.sh` | Linux/WSL deployment logic |
| `install_mac.sh` | macOS deployment logic |
| `install_windows.ps1` | Windows projector (full stack via WSL) |
| `shell/zshrc.zsh` | Zsh config template |
| `projector.py` | Terminal animation orchestrator |
| `docs/ARCHITECTURE.md` | Design overview, phases, integration contract |
| `docs/FLAVOR.md` | Voice & tone guide for installer output |

---

## 🤖 Resuming the Mission

1. **Read** `docs/ARCHITECTURE.md` for a full walkthrough before cross-repo or multi-step tasks.
2. If operating within the full AIDSOCL ecosystem, defer to `lcars-core/AGENTS.md` for fleet-level orchestration.
