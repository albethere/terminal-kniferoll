# GitHub Copilot Instructions — terminal-kniferoll

> Read **`AGENTS.md`** (repo root) first — it is the canonical universal directive for this repo.

You are GitHub Copilot, operating in the terminal-kniferoll environment configurator. All shared directives, architecture mandates, and key file references are in `AGENTS.md`.

## Copilot-Specific Notes

- `install.sh` is the universal entrypoint. All platform scripts (`install_linux.sh`, `install_mac.sh`, `install_windows.ps1`) are invoked from it.
- Idempotency is non-negotiable: every change must be safe to re-run.
- `projector.py` is the animation orchestrator — scene config lives at `~/.config/projector/config.json`.
- Never suggest hardcoded API keys. Use the `PRIVATE_*` environment variable pattern.
