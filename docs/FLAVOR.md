# Terminal-Kniferoll Voice & Flavor

Single source for the project's **tone**: knife/chef/kitchen, sharp and a little playful. No cringe; nerds should smirk, not groan.

## Palette (ANSI)

- **Success / done:** Green + herb accent. "Blade sharp." / "Pantry stocked."
- **Info / progress:** Cyan. "[⚙] Installing…"
- **Warning:** Orange/amber (heat). "Simmer, don't burn."
- **Error:** Red. One line + optional hint.
- **Quips:** Dim. Short, optional second line under a step.
- **Banners:** Steel + bright highlight for section titles.

## Voice rules

1. **One-liners over paragraphs.** Success: one punchy line. Skip: one line. Failure: one line + "Try: …" if useful.
2. **Kitchen/blade metaphor.** Sharp, precise, heat, pantry, forge, brigade. No "galley" or "line" are fine.
3. **No corporate speak.** No "Operation completed successfully." No "Error code 1."
4. **Witty, not try-hard.** If a joke feels forced, use a straight line instead.
5. **Verbose where it helps.** For long steps (rustup, big apt), one quip is enough. For skip/success, one line.

## Example lines (expand in install scripts / projector)

| Context   | Example |
|----------|--------|
| Already installed | "Already aboard — skipping." / "Pantry already stocked." |
| Installing       | "Slicing through dependencies…" / "Beaming aboard: …" → "Loading the line: …" |
| Success          | "Blade sharp." / "Kitchen closed clean." |
| Skip section     | "Nothing to install in this section. Pantry already stocked." |
| Failure          | "Could not install X — even the best chefs order takeout sometimes." |
| Sudo             | "Sharp knives require a steady hand. Authenticate to continue." / "Credentials verified — you're cleared for the kitchen." |
| Rust/cargo      | "Slow simmer — worth the wait." / "Forge hot." |
| Banner start     | "Kitchen Brigade — Field Deployment Script" / "Sharp tools. Clean cuts. No leftovers." |
| Banner end       | "Deployment complete. Knives sharp. Out." |

## Where to use

- **install-v2.sh** (Linux): banner, ok/warn/err, quips. Source this doc for consistency.
- **install_mac.sh / install_linux.sh** (main): same voice when adding or refactoring copy.
- **install_windows.ps1**: same tone in PowerShell; avoid emoji unless it renders everywhere.
- **projector.py**: optional one-line status between scene transitions (tasteful).
