# 🔪 terminal-kniferoll

Multipurpose terminal environment configurator: **security-focused Zsh** and **animated terminal projector** in one repo. One entrypoint, idempotent installs, optional automation integration.

## Quick start

```bash
git clone https://github.com/YOUR_ORG/terminal-kniferoll.git
cd terminal-kniferoll
./install.sh
```

- **Shell only:** `./install.sh --shell`
- **Projector only:** `./install.sh --projector`
- **Both (default):** `./install.sh`

| Platform   | Command |
|-----------|---------|
| macOS     | `./install.sh` or `./install_mac.sh` |
| Linux     | `./install.sh` or `./install_linux.sh` |
| Windows   | `powershell -ExecutionPolicy Bypass -File install_windows.ps1` (projector; full stack via WSL + Linux installer) |

## How it works (step-by-step)

1. **Entrypoint** — You run `./install.sh` (optionally with `--shell` or `--projector`). Script detects OS via `uname -s` (and WSL if present).
2. **Optional awareness** — If an “awareness” script is found (e.g. via `LCARS_CORE_DIR` or a sibling `lcars-core` repo), it is sourced and reports OS/arch; otherwise the installer runs in standalone mode.
3. **Mode** — If the run is interactive (TTY), you may be asked: **[1] Interactive** (conversational tool choice) or **[2] Passive** (auto sync + config). Non-interactive runs default to Passive.
4. **Delegation** — `install.sh` invokes the platform script: `install_linux.sh` or `install_mac.sh` (or Windows instructions).
5. **Shell path** — Platform installer ensures Zsh, Oh My Zsh, and plugins (autosuggestions, fast-syntax-highlighting), then deploys `shell/zshrc.zsh`, `aliases.zsh`, and `plugins.zsh` into your profile (e.g. concatenated into `~/.zshrc` or copied to `~/.shell/` and sourced).
6. **Projector path** — Installs Rust/Python, weathr, btop, fastfetch, cbonsai, cmatrix, etc.; makes `projector.py` executable; creates `~/.config/projector/config.json` from default on first run.
7. **Config** — Shell: Zscaler PEM paths (Linux vs macOS) and `PRIVATE_*` API keys. Projector: scene list and durations in the config file.
8. **Idempotency** — Already-installed packages are skipped; config is deployed on each run unless guarded.
9. **Optional integration** — Automation can set `TERMINAL_KNIFEROLL_DIR`, clone this repo, and run `install.sh --shell` (or full). Set `LCARS_CORE_DIR` if you use that stack and want shell aliases/awareness.

For a full walkthrough and design notes, see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Features

- **Security-first Zsh** — Oh My Zsh, fzf, zoxide, atuin, Zscaler proxy detection, `PRIVATE_*` env vars for API keys.
- **Modern CLI** — lsd, bat, ripgrep, btop, fastfetch, and more.
- **Terminal projector** — `projector.py` cycles through scenes (weather, system stats, bonsai, matrix, etc.).
- **Cross-platform** — Ubuntu/Debian, macOS (Apple Silicon + Intel), Windows (projector via PowerShell; full stack via WSL).

## Repository layout

```
terminal-kniferoll/
├── install.sh           # Universal entrypoint
├── install_mac.sh       # macOS installer
├── install_linux.sh     # Linux installer
├── install_windows.ps1  # Windows (projector)
├── projector.py        # Scene orchestrator
├── shell/
│   ├── zshrc.zsh       # Core Zsh config
│   ├── aliases.zsh     # Aliases
│   └── plugins.zsh     # Plugins & evals
├── projector/
│   └── config.json.default
├── docs/
│   └── SESSION_LOG.md  # Log, plan, walkthrough, agent prompts
├── GEMINI.md           # Agent directives
└── README.md
```

## Optional automation integration

This repo works **standalone out of the box** and can also be invoked from an external automation or bootstrap stack:

- **Contract:** Caller sets `TERMINAL_KNIFEROLL_DIR` (default: clone path, e.g. `$HOME/Projects/terminal-kniferoll`). Run `install.sh --shell` for shell-only, or `install.sh` for full install. All runs are idempotent.
- **Optional:** If you use a companion orchestration stack that provides an awareness script, set `LCARS_CORE_DIR` to its path before sourcing your shell so the injected aliases work.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for integration details and the full architecture overview.

## License

MIT
