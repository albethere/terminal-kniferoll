# Architecture & How It Works

Detailed walkthrough and design notes for terminal-kniferoll.

---

## Step-by-Step Functionality Walkthrough

1. **Entrypoint:** User runs `./install.sh` (or passes `--shell` / `--projector` / `--interactive`).
2. **OS detection:** `install.sh` reads `uname -s` and delegates to the platform installer, forwarding all flags.
3. **Platform installers:**
   - `install_linux.sh` — Debian/Ubuntu (apt) and Arch/CachyOS (pacman). Canonical Linux script.
   - `install_mac.sh` — macOS via Homebrew.
   - `install_windows.ps1` — Windows via winget, PSGallery, scoop.
4. **Supply chain policy:** On interactive TTY, the user selects a risk tolerance (Strict / Balanced / Permissive / Manual) before any downloads begin. In CI/batch mode, Strict is the default. Controlled by `lib/supply_chain_guard.sh`.
5. **Housekeeping:** Before installing anything, `cleanup_removed_tools()` evicts tools that have been cut from the project (currently: atuin, mise). Safe on fresh machines — all checks are guarded.
6. **Install phases (Linux example):**
   - **Core prerequisites** — apt/pacman update, ca-certificates, curl, gnupg, unzip, fontconfig.
   - **Shell environment** — Zsh, Oh My Zsh, zsh-autosuggestions, fast-syntax-highlighting (always last), then deploy `shell/zshrc.zsh`, `aliases.zsh`, `plugins.zsh` to `~/.zshrc` / `~/.shell/`.
   - **Security & developer tools** — nmap, ripgrep, fzf, jq, btop, 1Password CLI (GPG-signed apt repo), lsd/bat (GitHub release .deb), wtfis (pipx), lolcat (gem), uv (pipx/pacman — safe path only), nushell, yazi, Homebrew + Gemini CLI.
   - **Projector stack** — Rust toolchain (rustup), weathr (cargo), trippy (cargo), JetBrainsMono Nerd Font v3.4.0 (pinned), `~/.config/projector/config.json` from default template.
7. **Logging:** Every installer writes a timestamped log to `~/.terminal-kniferoll/logs/install_YYYYMMDD_HHMMSS.log`. Failed tools accumulate in `FAILED_TOOLS[]` and are reported in the mission debrief.
8. **Idempotency:** All installers check `is_installed` / `dpkg -s` / `brew list` before acting. Config files are only overwritten when intended. Safe to re-run.
9. **Projector:** `projector.py` reads `~/.config/projector/config.json`, loops over scenes (command + duration), runs each in a subprocess with a clean screen between scenes. Interactive: `SPACE` skips, `+/-` adjusts speed, `Q` quits.
10. **Shell config:** Single source in `shell/*.zsh`. Corporate proxy (Zscaler) cert paths are detected automatically. API keys use `PRIVATE_*` env vars only — never committed.

---

## Install Flags

| Flag | Behavior |
|------|----------|
| `./install.sh` | Shows 4-choice menu on TTY; full install in batch/CI |
| `--shell` | Shell environment only (Zsh, Oh My Zsh, plugins, aliases) |
| `--projector` | Projector stack only (Rust, cargo tools, font, config) |
| `--interactive` | Force the 4-choice menu even in batch/CI |
| `--help` | Print usage and exit |

---

## Supply Chain Architecture

All risky third-party installs are gated by `lib/supply_chain_guard.sh`.

| Tool | Previous method | Current method | Risk |
|------|-----------------|----------------|------|
| uv | astral.sh/uv/install.sh (curl\|bash) | `pipx install uv` / pacman native | LOW |
| mise | mise.jdx.dev/install.sh (curl\|bash) | **Removed** | — |
| atuin | setup.atuin.sh (curl\|bash) | **Removed** | — |
| Oh My Zsh | raw.githubusercontent.com/master | `download_to_tmp` + TLS 1.2+ | MEDIUM |
| rustup | sh.rustup.rs | `download_to_tmp` + TLS 1.2+ | MEDIUM |
| lsd / bat | GitHub releases/latest | `install_github_deb()` + TLS 1.2+ | MEDIUM |
| JetBrainsMono | releases/latest (floating) | Pinned to v3.4.0 + TLS 1.2+ | LOW-MEDIUM |

See `docs/SUPPLY_CHAIN_RISK.md` for the full risk register, per-package decisions, and deferred mitigations.

### Risk policy env vars

```bash
SC_RISK_TOLERANCE=1   # Strict — pkg managers only (CI default when no TTY)
SC_RISK_TOLERANCE=2   # Balanced — prompt on HIGH; proceed on MEDIUM/LOW (interactive default)
SC_RISK_TOLERANCE=3   # Permissive — original install methods; TLS enforced
SC_RISK_TOLERANCE=4   # Manual — ask per package; includes inspect/OSINT option
SC_ALLOW_RISKY=1      # Shorthand for SC_RISK_TOLERANCE=3
```

---

## SecDevOps Install Phases

| Phase | What happens |
|-------|-------------|
| **Detect** | OS, architecture, sudo availability, TTY/batch mode |
| **Policy** | Supply chain risk tolerance prompt (interactive) or env default (CI) |
| **Evict** | Remove tools cut from the project (atuin, mise) |
| **Validate** | Minimal deps: git, curl, package manager presence |
| **Install** | Idempotent per-platform installs; no secrets in repo |
| **Configure** | Deploy shell configs; projector config (default + user override) |
| **Verify** *(optional)* | Smoke checks, e.g. `zsh -c 'source ~/.zshrc; type ls'` |

---

## Key Helpers (Linux)

| Function | Purpose |
|----------|---------|
| `download_to_tmp URL PATTERN` | Secure temp file download; `umask 077`, TLS 1.2+, `chmod 600` |
| `apt_install BIN PKG` | Single-package apt install; skip if binary present |
| `apt_batch SECTION PKG...` | Batch apt install with skip-if-present per entry |
| `cargo_install BIN CRATE` | Idempotent cargo install; skip if binary present |
| `install_github_deb BIN REPO PATTERN` | Arch-aware GitHub release .deb installer |
| `sc_install NAME RISK DESC SAFE RISKY GITHUB URL` | Supply chain gated install dispatch |
| `cleanup_removed_tools` | Evicts cut tools (atuin, mise); idempotent |
| `run_optional DESC CMD...` | Soft-fail wrapper; logs and continues on error |
| `append_if_missing FILE LINE` | Idempotent append to config files |

---

## terminal-kniferoll vs Optional Orchestration Stack

terminal-kniferoll is **fully standalone**. It can also be called by an external automation stack.

| Aspect | terminal-kniferoll | Optional orchestration stack |
|--------|--------------------|------------------------------|
| **Purpose** | Bootstrap one machine's shell and terminal projector | Orchestrate a fleet: IaC, agents, GitOps, mesh networking |
| **Scope** | Single-node, user-facing environment | Multi-node, AI-persona workflows, hybrid cloud |
| **Invocation** | User runs `./install.sh` on a new machine; or automation calls it | Automation sets `TERMINAL_KNIFEROLL_DIR` and calls `install.sh --shell` |
| **Dependency** | **Standalone. No requirement for any orchestration stack.** | May optionally depend on terminal-kniferoll to standardise the shell |
| **Independent use** | ✅ Run install.sh; done | ✅ Orchestration stack works with any shell baseline |

**Integration contract (optional):**
- Caller sets `TERMINAL_KNIFEROLL_DIR` (default clone path: `$HOME/Projects/terminal-kniferoll`).
- Caller runs `install.sh --shell` for shell-only, or `install.sh` for full install.
- Set `SC_RISK_TOLERANCE=1` or `SC_ALLOW_RISKY=1` to control supply chain policy in automation.
- All calls are idempotent; safe to re-run.
