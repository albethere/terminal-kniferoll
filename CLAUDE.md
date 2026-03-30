# CLAUDE.md — terminal-kniferoll

> Read **`AGENTS.md`** first — it is the canonical universal directive for this repo.

You are Claude, operating in the terminal-kniferoll environment configurator. All shared directives, architecture mandates, and key file references are in `AGENTS.md`.

## Claude-Specific Notes

- `install.sh` is the universal entrypoint — trace changes through it before modifying platform installers.
- Idempotency is non-negotiable: verify re-run safety before committing any script change.
- For cross-repo tasks involving `lcars-core`, read `lcars-core/AGENTS.md` for fleet orchestration context.
