# Architecture & How It Works

Detailed walkthrough and design notes for terminal-kniferoll.

---

## Step-by-Step Functionality Walkthrough

1. **Entrypoint:** User runs `./install.sh` (or `install.sh --shell` / `--projector`).
2. **OS detection:** Script uses `uname -s` (and WSL detection if present) to choose Linux vs Darwin vs Windows.
3. **Mode (interactive TTY only):** If a TTY is attached you will be prompted for **[1] Interactive** (conversational tool selection) or **[2] Passive** (auto git pull + sync). Non-interactive runs default to Passive.
4. **Optional awareness:** If `LCARS_CORE_DIR` is set and an awareness script is found there, it is sourced and reports OS/arch/node. Otherwise the installer runs in **standalone mode** with no external dependency.
5. **Delegation:** `install.sh` invokes `install_linux.sh` or `install_mac.sh` (or the Windows path) with the appropriate mode flag.
6. **Platform installer:**
   - **Shell path** — Ensures Zsh, Oh My Zsh, and plugins (autosuggestions, fast-syntax-highlighting), then deploys `shell/zshrc.zsh`, `aliases.zsh`, and `plugins.zsh` into `~/.zshrc` / `~/.shell/`.
   - **Projector path** — Installs Rust/Python, weathr, btop, fastfetch, cbonsai, cmatrix, etc.; makes `projector.py` executable; creates `~/.config/projector/config.json` from the default template on first run.
7. **Shell config:** Single source in `shell/*.zsh`. Corporate proxy (Zscaler) paths are detected automatically; API keys use `PRIVATE_*` env vars only — never committed.
8. **Projector:** `projector.py` reads config, loops over scenes (command + duration), runs each in a subprocess, clears screen between scenes.
9. **Idempotency:** All installers skip already-installed packages and only overwrite config when intended.
10. **Optional integration:** When invoked from an external automation stack, callers set `TERMINAL_KNIFEROLL_DIR`, clone this repo if missing, and run `install.sh --shell` (or full). No hostname or org-specific logic lives inside this repo.

---

## SecDevOps Architecture

Phases used in the platform installers:

| Phase | What happens |
|-------|-------------|
| **Detect** | OS, architecture, sudo availability, optional external awareness script |
| **Validate** | Minimal deps (git, curl), package manager presence |
| **Install** | Idempotent package and tool installation per platform; no secrets in repo |
| **Configure** | Deploy shell config (single source), projector config (default + user override) |
| **Verify** *(optional)* | Smoke checks, e.g. `zsh -c 'source ~/.zshrc; type ls'` |

**Single entrypoint:** `install.sh` is the only script users run. Flags: `--shell`, `--projector`. Interactive/passive mode is detected automatically (TTY) or selected at the prompt.

**Security:** No secrets; `PRIVATE_*` vars only; Zscaler paths generic; all third-party fetches use HTTPS.

---

## terminal-kniferoll vs Optional Orchestration Stack

terminal-kniferoll is **fully standalone**. It can also be called by an external automation stack that manages multiple nodes.

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
- Caller may optionally set `LCARS_CORE_DIR` if using a companion orchestration stack that provides `lcars_awareness.sh`.
- All calls are idempotent; safe to re-run.
