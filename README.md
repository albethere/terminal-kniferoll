# 🔪 terminal-kniferoll

Multipurpose terminal environment configurator: security-focused Zsh + animated terminal projector.

`terminal-kniferoll` is the successor to `zsh-kniferoll` and `terminal-projector`, providing a unified, idempotent bootstrap for modern terminal workflows.

## 🚀 Quick Start

```bash
# Full installation (Shell + Projector)
./install.sh

# Shell-only (Zsh, plugins, aliases)
./install.sh --shell

# Projector-only (btop, fastfetch, cbonsai, animation suite)
./install.sh --projector
```

## 🛠 Features

- **Security-First Zsh**: Standardized `.zshrc` with Oh My Zsh, modern plugins (fzf, zoxide, atuin), and Zscaler proxy detection.
- **Modern CLI Payload**: Automatically installs `lsd`, `bat`, `sd`, `ripgrep`, `btop`, `fastfetch`, and more.
- **Terminal Projector**: A Python-based orchestrator (`projector.py`) that cycles through animated terminal scenes (bonsai, matrix, weather, etc.).
- **Cross-Platform**: Native support for Ubuntu/Debian, macOS (Apple Silicon + Intel), and Windows WSL.

## 📁 Repository Structure

```
terminal-kniferoll/
├── install.sh              # Universal entrypoint (OS detect → delegates)
├── install_mac.sh          # macOS full installer
├── install_linux.sh        # Linux full installer
├── install_windows.ps1     # Windows PowerShell installer
├── projector.py            # Terminal animation orchestrator
├── shell/
│   ├── zshrc.zsh           # Standardized .zshrc template
│   ├── aliases.zsh         # Alias definitions
│   └── plugins.zsh         # Plugin declarations
├── projector/
│   └── config.json.default # Default scene rotation config
├── GEMINI.md               # AI Agent directives
└── README.md               # You are here
```

## 🔗 LCARS Core Integration

This repository is designed to be the primary bootstrap for the `lcars-core` ecosystem. It is automatically called by `lcars-init.sh` to ensure every node in the fleet has a consistent, powerful, and secure terminal environment.

## ⚖️ License

MIT
