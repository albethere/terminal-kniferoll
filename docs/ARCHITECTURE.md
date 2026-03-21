# Architecture & How It Works

Detailed walkthrough and design notes for terminal-kniferoll.

---

## Step-by-Step Functionality Walkthrough

1. **Entrypoint:** User runs `./install.sh` (or `install.sh --shell` / `--projector`).
2. **OS detection:** Script uses `uname -s` (and WSL detection if present) to choose Linux vs Darwin vs Windows.
3. **Delegation:** `install.sh` invokes `install_linux.sh` or `install_mac.sh` (or the Windows path) and forwards any flags.
4. **Platform installer:**
   - **Shell path** — Ensures Zsh, Oh My Zsh, and plugins (autosuggestions, fast-syntax-highlighting), then deploys `shell/zshrc.zsh`, `aliases.zsh`, and `plugins.zsh` into `~/.zshrc` / `~/.shell/`.
   - **Projector path** — Installs Rust/Python, weathr, btop, fastfetch, cbonsai, cmatrix, etc.; makes `projector.py` executable; creates `~/.config/projector/config.json` from the default template on first run.
5. **Shell config:** Single source in `shell/*.zsh`. Corporate proxy (Zscaler) paths are detected automatically; API keys use `PRIVATE_*` env vars only — never committed.
6. **Projector:** `projector.py` reads config, loops over scenes (command + duration), runs each in a subprocess, clears screen between scenes. Interactive: `SPACE` skips, `+/-` adjusts speed, `Q` quits.
7. **Idempotency:** All installers skip already-installed packages and only overwrite config when intended.
8. **Optional integration:** When invoked from an external automation stack, callers set `TERMINAL_KNIFEROLL_DIR`, clone this repo if missing, and run `install.sh --shell` (or full). No hostname or org-specific logic lives inside this repo.

---

## SecDevOps Architecture

Phases used in the platform installers:

| Phase | What happens |
|-------|-------------|
| **Detect** | OS, architecture, sudo availability |
| **Validate** | Minimal deps (git, curl), package manager presence |
| **Install** | Idempotent package and tool installation per platform; no secrets in repo |
| **Configure** | Deploy shell config (single source), projector config (default + user override) |
| **Verify** *(optional)* | Smoke checks, e.g. `zsh -c 'source ~/.zshrc; type ls'` |

**Single entrypoint:** `install.sh` is the only script users run. Flags: `--shell`, `--projector`.

**v2 Linux installer:** `install-v2.sh` is a full redesign with batch apt installs, per-step failure tracking, architecture detection, sudo keepalive, and knife/chef flavored output. See `docs/FLAVOR.md` for the voice and tone guide.

**Security:** No secrets; `PRIVATE_*` vars only; Zscaler paths generic; all third-party fetches use HTTPS.

---

## terminal-kniferoll vs Optional Orchestration Stack

terminal-kniferoll is **fully standalone**. It can also be called by an external automation stack.

| Aspect | terminal-kniferoll | Optional orchestration stack |
|--------|--------------------|------------------------------|
| **Purpose** | Bootstrap **one machine's** shell and terminal projector (animated dashboard) | Orchestrate a fleet: IaC, agents, GitOps, consoles, mesh networking |
| **Scope** | Single-node, user-facing environment (Zsh, CLI tools, projector) | Multi-node, AI-persona workflows, hybrid cloud |
| **Invocation** | User runs `./install.sh` on a new machine; or automation calls it | Automation sets `TERMINAL_KNIFEROLL_DIR` and calls `install.sh --shell` |
| **Dependency** | **Standalone. No requirement for any orchestration stack.** | May optionally depend on terminal-kniferoll to standardise the shell on each node |
| **Independent use** | ✅ Run install.sh; done | ✅ Orchestration stack works with any shell baseline |

**Integration contract (optional):**
- Caller sets `TERMINAL_KNIFEROLL_DIR` (default clone path: `$HOME/Projects/terminal-kniferoll`).
- Caller runs `install.sh --shell` for shell-only, or `install.sh` for full install.
- All calls are idempotent; safe to re-run.
