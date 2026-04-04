# 🔪 terminal-kniferoll

Multipurpose terminal environment configurator: **security-focused Zsh** and **animated terminal projector**. One entrypoint, idempotent installs. Runs standalone or as a callable module from `lcars-init.sh`.

## Quick start

```bash
git clone https://github.com/YOUR_ORG/terminal-kniferoll.git
cd terminal-kniferoll
./install.sh
```

On a TTY, the installer presents a 4-choice interactive menu:

```
  [1] Full install     — Shell environment + Terminal projector (recommended)
  [2] Shell only       — Zsh, Oh My Zsh, plugins, aliases
  [3] Projector only   — Terminal animation suite (weather, bonsai, fastfetch)
  [4] Custom           — Choose individual tool groups
```

## Flags

| Flag | Action |
|------|--------|
| `./install.sh` | Full install (shell + projector) in non-interactive mode |
| `./install.sh --shell` | Shell environment only |
| `./install.sh --projector` | Projector stack only |
| `./install.sh --interactive` | Force the 4-choice menu |
| `./install.sh --full` | Full install, no menu |
| `./install.sh --help` | Usage summary |

## Platform support

| Platform | Script | Package manager | Notes |
|----------|--------|-----------------|-------|
| macOS    | `install_mac.sh` | Homebrew | Same 4-choice menu |
| Linux (Debian/Ubuntu) | `install_linux.sh` | apt + cargo | Canonical script |
| Windows  | `install_windows.ps1` | winget → Scoop → Chocolatey | PowerShell 7+; cbonsai/atuin via WSL only |

Direct invocation: `./install.sh` delegates to the correct platform script automatically.

## What gets installed

### Shell mode (`--shell`)

- **Zsh** + **Oh My Zsh** + shell configs (`zshrc.zsh`, `aliases.zsh`, `plugins.zsh`)
- **fzf**, **zoxide**, **ripgrep**, **micro**
- **lsd**, **bat** (GitHub release .deb on Linux; Homebrew on macOS)
- **atuin** (shell history sync), **mise** (runtime manager)
- **starship** prompt, **nushell**, **yazi** file manager
- **lolcat**, **cmatrix**, **cbonsai**, **fastfetch**
- Security tooling: **nmap**, **1Password CLI**, **jq**, **btop**, **tmux**
- Build tools: **Rust/cargo** (via rustup), **uv/pipx**, **Go**

### Projector mode (`--projector`)

- **Rust toolchain** (rustup)
- **weathr** (weather CLI), **trippy** (network pulse)
- **JetBrainsMono Nerd Font** v3.4.0 (pinned)
- `projector.py` config deployed to `~/.config/projector/config.json`

## Zsh plugins

Plugins are managed by Oh My Zsh and sourced via `~/.shell/plugins.zsh`. Load order matters — `fast-syntax-highlighting` **must be last**:

| Plugin | Source | Notes |
|--------|--------|-------|
| `git` | Oh My Zsh built-in | Git aliases |
| `z` | Oh My Zsh built-in | Directory jumping |
| `fzf` | Oh My Zsh built-in | Fuzzy finder integration |
| `zsh-autosuggestions` | zsh-users/zsh-autosuggestions | Fish-style suggestions |
| `fast-syntax-highlighting` | zdharma-continuum/fast-syntax-highlighting | **Must load last** |

Plugins are cloned with `git clone --depth=1` into `$ZSH_CUSTOM/plugins/` during install.

## Logging

Every install run writes a timestamped log to:

```
~/.terminal-kniferoll/logs/install_YYYYMMDD_HHMMSS.log
```

Log levels: `OK`, `INFO`, `WARN`, `SKIP`, `ERROR`. All failed tools are collected and printed in a summary at the end of the run.

## Windows

`install_windows.ps1` (624 lines, PowerShell 7+) provides a full Windows-native stack:

- **Package pipeline**: winget → Scoop → Chocolatey (fallback chain)
- **Oh My Posh** prompt, **PSReadLine**, **posh-git**, **Terminal-Icons**
- Full PowerShell profile with aliases mirroring the Zsh/lsd strategy
- 4-choice interactive menu (same UX as Linux/macOS)
- Timestamped logging to `~\AppData\Local\terminal-kniferoll\logs\`

**Windows gaps** (tracked in tk-tracker):
- `cbonsai` — WSL only; no native Windows build
- `atuin` — WSL only on Windows
- `weathr` / `lolcat` — no winget/scoop entry; install via cargo or omit

## Supply chain

All `curl` calls use `--proto '=https' --tlsv1.2`. JetBrainsMono NF is pinned to v3.4.0. Six P2/P3 supply chain hardening tasks are deferred and tracked.

See [`docs/SUPPLY_CHAIN_RISK.md`](docs/SUPPLY_CHAIN_RISK.md) for the full risk register, mitigations applied, and deferred items.

## lcars-core integration

`terminal-kniferoll` is callable from `lcars-init.sh` as a module:

```bash
export TERMINAL_KNIFEROLL_DIR=/path/to/terminal-kniferoll
"$TERMINAL_KNIFEROLL_DIR/install.sh" --shell   # or --full
```

Set `LCARS_CORE_DIR` if using alongside the full lcars-core orchestration stack.

## Layout

```
terminal-kniferoll/
├── install.sh             # Universal entrypoint (OS-detect + delegate)
├── install_linux.sh       # Linux/WSL canonical installer
├── install_mac.sh         # macOS installer
├── install_windows.ps1    # Windows PowerShell installer (624 lines)
├── projector.py           # Terminal animation orchestrator
├── shell/
│   ├── zshrc.zsh          # Zsh config template
│   ├── aliases.zsh        # Standardised aliases (lsd strategy)
│   └── plugins.zsh        # Plugin loader (FSH last)
├── projector/
│   └── config.json.default
├── docs/
│   ├── ARCHITECTURE.md    # Design overview
│   ├── FLAVOR.md          # Voice & tone guide
│   └── SUPPLY_CHAIN_RISK.md
├── AGENTS.md
├── GEMINI.md
├── CLAUDE.md
└── .github/copilot-instructions.md
```

## License

MIT
