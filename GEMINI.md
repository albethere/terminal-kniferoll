> **Universal directives live in `AGENTS.md`** — read that first. This file contains Gemini-specific context and supplements `AGENTS.md`.

# GEMINI.md: Terminal-Kniferoll Protocol

> **Directive**: Standardized Environment Configuration & Projector Hub
> **Role**: This repository combines the security-focused Zsh environment (zsh-kniferoll) with the animated terminal projector (terminal-projector).

## 🚀 Core Objectives
1. **Utility**: Deploy a production-ready, security-hardened Zsh environment on any OS (Linux, macOS, WSL).
2. **Dashboard**: Provide a rich, animated terminal experience (Projector mode) for system monitoring and aesthetics.
3. **Identity**: Standalone terminal configurator; can be used with any automation stack or none.

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
- Automation can invoke this repo via `TERMINAL_KNIFEROLL_DIR` and `install.sh --shell` or full install. No hardcoded org or hostnames.
