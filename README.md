# 🔪 terminal-kniferoll

Multipurpose terminal environment configurator: **security-focused Zsh** and **animated terminal projector**. One entrypoint, idempotent installs.

## Quick start

```bash
git clone https://github.com/YOUR_ORG/terminal-kniferoll.git
cd terminal-kniferoll
./install.sh
```

- **Shell only:** `./install.sh --shell`
- **Projector only:** `./install.sh --projector`
- **Both (default):** `./install.sh`

| Platform | Command |
|----------|---------|
| macOS    | `./install.sh` or `./install_mac.sh` |
| Linux    | `./install.sh` or `./install_linux.sh` |
| Windows  | `powershell -ExecutionPolicy Bypass -File install_windows.ps1` (projector; full stack via WSL) |

## How it works

1. **Entrypoint** — `./install.sh` detects OS and delegates to the right platform script.
2. **Shell path** — Installs Zsh, Oh My Zsh, plugins; deploys `shell/zshrc.zsh`, `aliases.zsh`, `plugins.zsh` into your profile.
3. **Projector path** — Installs Rust/Python, weathr, btop, fastfetch, cbonsai, cmatrix; runs `projector.py`; creates `~/.config/projector/config.json` on first run.
4. **Idempotent** — Already-installed tools are skipped; safe to re-run.
5. **Optional automation** — Other stacks can set `TERMINAL_KNIFEROLL_DIR`, clone this repo, and run `install.sh --shell` (or full) for a consistent environment.

## Features

- **Security-first Zsh** — Oh My Zsh, fzf, zoxide, atuin, Zscaler proxy detection, `PRIVATE_*` env vars for API keys.
- **Modern CLI** — lsd, bat, ripgrep, btop, fastfetch, and more.
- **Terminal projector** — Animated scenes (weather, stats, bonsai, matrix) via `projector.py`.
- **Cross-platform** — Ubuntu/Debian, macOS, Windows (WSL or PowerShell for projector).

## Layout

```
terminal-kniferoll/
├── install.sh           # Universal entrypoint
├── install_mac.sh       # macOS
├── install_linux.sh     # Linux (merged from v2; canonical)
├── install_windows.ps1  # Windows (projector)
├── projector.py
├── shell/               # zshrc, aliases, plugins
├── projector/           # config.json.default
├── docs/
│   ├── ARCHITECTURE.md  # Design overview
│   └── FLAVOR.md        # Voice & tone guide
├── GEMINI.md
└── README.md
```

## Optional integration

Automation can clone this repo and run `install.sh --shell` or full install. Use `TERMINAL_KNIFEROLL_DIR` to point at the clone. No hostnames or org-specific logic; replace `YOUR_ORG` in the clone URL with your fork.

## License

MIT
