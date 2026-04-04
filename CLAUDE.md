# CLAUDE.md — terminal-kniferoll

> Read **`AGENTS.md`** first — it is the canonical universal directive for this repo.

You are Claude, operating in the terminal-kniferoll environment configurator.

## Work Tracker

This repo uses the **telex-kitchen tk-tracker**. DB: `/home/ctrl/telex-kitchen/tracker.db`

```bash
export TK_SCHEMA_DIR=/home/ctrl/telex-kitchen/tracker/schema
tk task create -t "<task>" -d "<detail>" -p P2 --created-by claude-agent
tk task claim <task-id> --actor claude-agent
tk task update <task-id> --status done --actor claude-agent
tk task list
```

## Claude-Specific Notes

- `install.sh` is the universal entrypoint — trace changes through it before modifying platform installers.
- Idempotency is non-negotiable: verify re-run safety before committing any script change.
- Test `--shell` and `--projector` flags independently after any script changes.
- `fast-syntax-highlighting` must always be the **last** plugin in the load order.
- `install-v2.sh` is gone — do not recreate it; `install_linux.sh` is the canonical Linux script.
- All `curl` calls must use `--proto '=https' --tlsv1.2` — see `docs/SUPPLY_CHAIN_RISK.md`.
- For cross-repo tasks involving `lcars-core`, read `lcars-core/AGENTS.md` for fleet orchestration context.
