# GEMINI.md: Terminal-Kniferoll Protocol

> **Directive**: Standardized Environment Configuration & Projector Hub
> **Role**: This repository combines the security-focused Zsh environment (zsh-kniferoll) with the animated terminal projector (terminal-projector).

## 🚀 Core Objectives
1. **Utility**: Deploy a production-ready, security-hardened Zsh environment on any OS (Linux, macOS, WSL).
2. **Dashboard**: Provide a rich, animated terminal experience (Projector mode) for system monitoring and aesthetics.
3. **Identity**: Spiritual successor to minimal dotfile setups; can be used standalone or with an optional orchestration stack.

## 📡 Usage Modes
The `install.sh` script is the universal entrypoint. Use flags to scope execution:

- `./install.sh --shell`: Deploys only the Zsh configuration, plugins, and aliases.
- `./install.sh --projector`: Deploys only the animation suite (btop, fastfetch, cbonsai, etc.) and `projector.py`.
- `./install.sh`: Deploys both in sequence.

## 🛠 Architecture
- **Idempotency**: All scripts must be safe to re-run.
- **OS-Agnostic**: Logic must detect and handle Debian/Ubuntu vs. macOS (Homebrew) vs. WSL.
- **Modular Configs**: `shell/zshrc.zsh` sources `~/.shell/aliases.zsh` and `~/.shell/plugins.zsh`.

## 🛡 Security Mandates
- **Zero Secrets**: Never commit API keys. Use the `PRIVATE_*` environment variable pattern in `.zshrc`.
- **Proxy Aware**: Retain Zscaler certificate detection for corporate environments.
- **Permission Safety**: Use `sudo -E` for terminal operations to preserve user environment variables.

## 🔗 Integration
- This repo can be invoked by automation (e.g. a central bootstrap script). Use `TERMINAL_KNIFEROLL_DIR`; run `install.sh --shell` or full install.
- Optional: when used with an orchestration stack, that stack may clone this repo and run the installer for new nodes.

## 📍 Guiding context for delegated agents
- **Directive and role:** This file (GEMINI.md).
- **Implementation plan, scrub list, walkthrough, architecture, lcars vs kniferoll, and delegation prompts:** `docs/SESSION_LOG.md`. Read it before implementing cross-repo or multi-step tasks.
- **Future Protocol**: Refer to `TUNING_DIRECTIVE.md` for upcoming UX/Performance optimizations including parallel deployment and adaptive scene intelligence.
