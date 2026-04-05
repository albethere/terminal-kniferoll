# Terminal-Kniferoll Voice & Flavor

Single source for the project's **tone**: knife/chef/kitchen, sharp and a little playful. No cringe; nerds should smirk, not groan.

---

## Palette (ANSI)

| Role | Color | Variable |
|------|-------|----------|
| Success / done | Green + herb accent | `$GREEN`, `$HERB` |
| Info / progress | Cyan | `$CYAN` |
| Warning | Orange/amber (heat) | `$ORANGE` |
| Error | Red, one line | `$RED` |
| Quips | Dim, optional second line | `$DIM` |
| Banners | Bold cyan section titles | `$BOLD$CYAN` |
| Security prompts | Bold cyan box-draw border | `$BOLD$CYAN` |
| Eviction / removal | Orange warn, ok on success | `$ORANGE` → `$GREEN` |

---

## Voice Rules

1. **One-liners over paragraphs.** Success: one punchy line. Skip: one line. Failure: one line + "Try: …" if useful.
2. **Kitchen/blade metaphor.** Sharp, precise, heat, pantry, forge, brigade. "Galley" and "line" are fine too.
3. **No corporate speak.** Never: "Operation completed successfully." Never: "Error code 1."
4. **Witty, not try-hard.** If a joke feels forced, use a straight line instead.
5. **Verbose where it helps.** For long steps (rustup, big apt), one quip is enough. For skip/success, one line.
6. **Security is tactical, not alarmist.** Supply chain decisions use box-draw borders and "DECISION" framing — serious but not panicked.

---

## Example Lines

### Install flow

| Context | Example |
|---------|---------|
| Already installed | `"Already aboard — skipping."` / `"Pantry already stocked."` |
| Installing | `"Slicing through dependencies…"` / `"Loading the line: …"` |
| Success | `"Blade sharp."` / `"Kitchen closed clean."` |
| Skip section | `"Nothing to install in this section. Pantry already stocked."` |
| Failure | `"Could not install X — even the best chefs order takeout sometimes."` |
| Sudo | `"Sharp knives require a steady hand. Authenticate to continue."` |
| Rust/cargo | `"Slow simmer — worth the wait."` / `"Forge hot."` |
| Banner start | `"Kitchen Brigade — Field Deployment Script"` |
| Banner end | `"mission complete. knives sharp. out."` |

### Supply chain guard (`lib/supply_chain_guard.sh`)

| Context | Example |
|---------|---------|
| Policy prompt header | `"⌁ SUPPLY CHAIN SECURITY POLICY"` (box-draw) |
| Risk: HIGH | Red + bold `"HIGH"` — terse one-liner description of the risk |
| Risk: MEDIUM | Yellow `"MEDIUM"` |
| Risk: LOW | Green `"LOW"` |
| Inspect/OSINT | `"⌁ INSPECT: mise"` (yellow box-draw) — factual, no drama |
| SHA256 result | Green hash on one line; dim note: "Record this. Changes = tampered." |
| Deferred | `"Deferred: atuin (will review before summary)"` — matter-of-fact |
| Skipped | `"Skipped: X — install manually: <url>"` |
| Deferred review | `"DEFERRED PACKAGE REVIEW"` banner — calm, final checkpoint |

### Housekeeping / eviction

| Context | Example |
|---------|---------|
| Tool found to evict | `"[~] atuin found — evicting (cut: supply chain risk)"` |
| Eviction success | `"[✓] atuin — evicted"` |
| Nothing to clean | `"[~] skip: No removed tools found — clean slate"` |

---

## Where to Use

- **`install_linux.sh`** — all banners, `ok/warn/err/skip/quip`, eviction messages, supply chain policy.
- **`install_mac.sh`** — same voice; macOS-specific quips OK (`"brew tap incoming"`, etc.).
- **`install_windows.ps1`** — same tone in PowerShell; emoji optional (test rendering first).
- **`lib/supply_chain_guard.sh`** — tactical/security register tone; box-draw borders for DECISION and INSPECT blocks; no jokes during security decisions.
- **`projector.py`** — optional one-line status between scene transitions (tasteful).

---

## Anti-patterns

- `"Successfully installed X"` → use `"[✓] X installed"` or `"[✓] X — ready"`
- `"Warning: this may take a while"` → use `"Slow simmer — worth the wait."`
- `"Please enter your password"` → use `"Sharp knives require a steady hand."`
- `"ERROR: package not found"` → use `"[✗] X — not found. Try: apt-get install X"`
- Nested bullet explanations in terminal output → one punchy line, maybe one quip
