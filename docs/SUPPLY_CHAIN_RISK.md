# Supply Chain Risk Analysis — terminal-kniferoll
Updated: 2026-05-02 (lolcat → lolcrab swap)

## Summary

The installer suite (install_linux.sh, install_mac.sh, install_windows.ps1) pulls from
a mix of official package managers, GitHub releases, and custom-domain install scripts. The overall
posture is **LOW-MEDIUM** risk following the addition of `lib/supply_chain_guard.sh` and the
removal of automatic execution of HIGH-risk custom-domain scripts without user consent.

**Key findings and current mitigations:**
- Three custom-domain curl|bash scripts (mise, atuin, uv) are now gated behind `sc_install()` —
  users choose their risk policy at install start or per-package in Manual mode
- `sd` fully removed from install_linux.sh and install_mac.sh BREW_PACKAGES (was orphaned)
- JetBrainsMono Nerd Font pinned to v3.4.0 in both Linux and macOS scripts; TLS flags added
- **NEW** GitHub release .deb downloads (lsd, bat) now verified via SHA256 before `dpkg -i`
- **NEW** Oh My Zsh cloned at pinned tag `24.9.0` instead of curl-piping master/install.sh
- **NEW** zsh-autosuggestions pinned to `v0.7.1`; fast-syntax-highlighting pinned to `v1.55`
- Homebrew install script is fetched from GitHub `HEAD` — no commit pinning (lower priority)
- cargo installs (weathr, trippy, etc.) rely on crates.io registry integrity with no version pinning

## Supply Chain Guard (`lib/supply_chain_guard.sh`)

Added in 2026-04-05 sweep. All HIGH-risk installs on Linux now flow through `sc_install()`.

### Risk Policy Options

Set via interactive prompt at install start, or pre-set via environment:

| Policy | `SC_RISK_TOLERANCE` | Behavior |
|--------|---------------------|----------|
| Strict | `1` | Only package managers (apt/brew/cargo). All curl\|bash scripts skipped. |
| Balanced | `2` | Safe methods for HIGH risk; original methods for MEDIUM/LOW. **(default in non-TTY/CI)** |
| Permissive | `3` | All original methods used. Equivalent to pre-guard behavior. (`SC_ALLOW_RISKY=1`) |
| Manual | `4` | Prompt individually for every risky package. |

Non-interactive (batch/CI) defaults to `SC_RISK_TOLERANCE=1` (Strict) unless overridden.

### Per-Package Options (Manual mode / [4])

For each HIGH-risk package, the user can choose:
1. **Safe install** — package manager or `cargo install` (no custom-domain scripts)
2. **Original method** — the upstream curl|bash script (TLS 1.2+ enforced)
3. **Skip** — bypass and install manually later
4. **Defer** — queue for review at end of install session
5. **Inspect / OSINT** — shows GitHub URL, source URL, live SHA256 hash of the script,
   TLS cert check command, and optionally opens the script in `less` for review

### Environment Variables

```bash
SC_RISK_TOLERANCE=1   # Strict (CI-safe default when no TTY)
SC_RISK_TOLERANCE=2   # Balanced
SC_RISK_TOLERANCE=3   # Permissive
SC_RISK_TOLERANCE=4   # Manual (prompt per package)
SC_ALLOW_RISKY=1      # Shorthand for SC_RISK_TOLERANCE=3
```

---

## Risk Register

| Tool | Source | Version Pinned | Verification | Fetch Method | Risk | Notes |
|---|---|---|---|---|---|---|
| Oh My Zsh | github.com/ohmyzsh/ohmyzsh | YES v24.9.0 (pinned tag) | None | git clone --depth 1 --branch | LOW | Cloned at pinned tag; no longer piping master/install.sh |
| Homebrew | raw.githubusercontent.com/Homebrew/install/HEAD | NO (HEAD) | None | download-then-run | MEDIUM | Trusted project; TLS enforced; no commit pin |
| rustup | sh.rustup.rs | NO (latest) | None | download-then-run | MEDIUM | Official Rust installer; TLS 1.2+ enforced in all scripts |
| mise | mise.jdx.dev/install.sh | NO | None | download-then-run | HIGH | Custom domain; TLS 1.2+ enforced; no checksum |
| atuin | setup.atuin.sh | NO | None | download-then-run | HIGH | Custom domain; TLS 1.2+ enforced; no checksum |
| uv | astral.sh/uv/install.sh | NO | None | download-then-run | HIGH | Custom domain; TLS 1.2+ already enforced in install-v2.sh |
| 1Password CLI | downloads.1password.com (apt repo) | stable channel | GPG signed apt repo | package manager | LOW | Official signed repo; GPG key verified |
| lsd | GitHub releases (lsd-rs/lsd) latest | NO (latest API) | SHA256 verified | download .deb | LOW | SHA256 from release assets verified before dpkg -i |
| bat | GitHub releases (sharkdp/bat) latest | NO (latest API) | SHA256 verified | download .deb | LOW | SHA256 from release assets verified before dpkg -i |
| JetBrainsMono NF | GitHub releases (ryanoasis/nerd-fonts) | YES v3.4.0 (pinned this sweep) | None | download zip | MEDIUM | Pinned version; SHA256 deferred |
| zsh-autosuggestions | github.com/zsh-users (git clone) | YES v0.7.1 (pinned tag) | None | git clone --depth=1 --branch | LOW | Pinned to release tag |
| zsh-fast-syntax-highlighting | github.com/zdharma-continuum (git clone) | YES v1.55 (pinned tag) | None | git clone --depth=1 --branch | LOW | Pinned to release tag; FSH still loaded last |
| weathr | crates.io | NO (latest) | crates.io checksums | cargo install | MEDIUM | crates.io provides hash verification; version unspecified |
| trippy | crates.io | NO (latest) | crates.io checksums | cargo install | MEDIUM | crates.io provides hash verification |
| yazi | crates.io | NO (latest) | crates.io checksums | cargo install | MEDIUM | crates.io provides hash verification |
| atuin (cargo, Windows) | crates.io | NO (latest) | crates.io checksums | cargo install | MEDIUM | crates.io provides hash verification |
| cbonsai | apt / AUR | distro-managed | Package manager signatures | package manager | LOW/MEDIUM | LOW on apt/brew; MEDIUM on AUR (user scripts) |
| cmatrix | apt / brew / scoop | distro-managed | Package manager signatures | package manager | LOW | Available in standard repos |
| lolcrab | crates.io / winget / scoop | NO (latest) | crates.io / winget hash verification | cargo install / winget / scoop / AUR | LOW | Replaced lolcat (RubyGems) 2026-05-02; cascade falls through cleanly. lolcat → lolcrab alias added by installer for backwards compat |
| wtfis | PyPI (pipx install) | NO | PyPI integrity | pipx install | LOW | PyPI provides hash verification |
| Gemini CLI | brew / npm @google/gemini-cli | NO | brew/npm registry | package manager | MEDIUM | npm global install; no pinned version |
| Oh My Posh (Windows) | winget (JanDeDobbeleer.OhMyPosh) | NO | winget hash verify | winget | LOW | winget verifies packages |
| PSReadLine / Terminal-Icons | PSGallery (Install-Module) | NO | PSGallery checksums | Install-Module | LOW | PSGallery verifies packages |
| sd | ~~crates.io~~ | — | — | removed | — | **Removed** — was orphaned (no alias) |

---

## High Risk Findings

### 1. mise — `https://mise.jdx.dev/install.sh`
- **Why HIGH**: Custom domain (jdx.dev), script is executed directly after download. Domain hijack or compromise delivers arbitrary code.
- **Mitigation applied**: TLS 1.2+ enforced via `download_to_tmp` / `--proto '=https' --tlsv1.2`, security comment added.
- **Deferred**: Checksum verification; consider using `cargo install mise` or package manager (pacman has mise natively).

### 2. atuin — `https://setup.atuin.sh`
- **Why HIGH**: Custom domain (atuin.sh), script is executed directly after download. No checksum.
- **Mitigation applied**: TLS 1.2+ enforced, security comment added.
- **Deferred**: Checksum verification; consider `cargo install atuin` or native package manager (pacman has atuin).

### 3. uv — `https://astral.sh/uv/install.sh`
- **Why HIGH**: Custom domain (astral.sh), script executed after download.
- **Mitigation applied**: Already had `--proto '=https' --tlsv1.2` in install-v2.sh. install_linux.sh uses `pipx install uv` (safer).
- **Deferred**: Consider `pip install uv` or pinned version URL `https://astral.sh/uv/{version}/install.sh`.

---

## Mitigations Implemented

### 2026-04-05 sweep #2 (supply chain hardening)

4. **SHA256 verification for lsd/bat .debs** — `install_github_deb()` in `install_linux.sh`
   now fetches the GitHub release JSON once, locates a checksum asset (per-file
   `<name>.sha256sum`/`.sha256` or combined `sha256sums`/`SHA256SUMS`), and verifies the
   download before `dpkg -i`. Hard-fails on mismatch; soft-warns if no checksum asset published.

5. **Oh My Zsh pinned to tag** — Both `install_linux.sh` and `install_mac.sh` now clone
   `ohmyzsh/ohmyzsh` at `git clone --depth 1 --branch 24.9.0` instead of piping
   `master/tools/install.sh`. Fallback to install.sh with a warning if the tag is not found.

6. **zsh plugins pinned to release tags** — Both installers clone zsh-autosuggestions at
   `v0.7.1` and fast-syntax-highlighting at `v1.55` via `--branch <tag>`. Version variables
   (`ZSH_AUTOSUG_TAG`, `ZSH_FSH_TAG`) are defined adjacent to each clone with links to upstream
   tags pages. FSH-last order unchanged.

7. **Homebrew PATH fixed for non-login shells (macOS)** — `install_mac.sh` now appends the
   `brew shellenv` eval line to both `~/.zprofile` (login shells) and `~/.zshrc` (non-login
   interactive shells opened by Terminal.app / GUI editors). Closes the missing-PATH bug for
   the silo user.

### 2026-04-05 sweep #1

1. **Supply chain guard** — `lib/supply_chain_guard.sh` added. All three HIGH-risk packages
   (mise, atuin, uv) on Linux are now routed through `sc_install()` with safe alternatives
   and interactive user controls. macOS gets the guard framework (mise/atuin/uv come from
   Homebrew there, which is already lower risk).

2. **`sd` fully removed** — `cargo_install "sd"` removed from `install_linux.sh`; `sd` removed
   from `BREW_PACKAGES` in `install_mac.sh`. (Was orphaned — no remaining aliases.)

3. **Font URL hardened** — `install_linux.sh` and `install_mac.sh` font download now uses
   pinned `v3.4.0` URL and adds `--proto '=https' --tlsv1.2` curl flags.

### 2026-04-04 sweep

4. **TLS hardening** — added `--proto '=https' --tlsv1.2` to all `curl` invocations in:
   - `install_linux.sh`: `download_to_tmp()`, `install_github_deb()`, font download
   - `install_mac.sh`: `download_to_tmp()`, font download

5. **Security comments** — added inline comments to all high-risk fetch points (mise, atuin,
   rustup, Oh My Zsh, Homebrew) explaining the risk and applied mitigations.

---

## Deferred Mitigations

These items were identified but not implemented to avoid breaking install flow. Each has a corresponding tracker task.

| Item | Status | Notes |
|---|---|---|
| ~~SHA256 verification for lsd/bat .deb~~ | **DONE** 2026-04-05 | `install_github_deb()` now verifies against release checksum assets |
| ~~Pin Oh My Zsh to a git tag/SHA~~ | **DONE** 2026-04-05 | Cloned at tag `24.9.0`; update `OMZ_TAG` variable to upgrade |
| ~~Pin zsh-autosuggestions/zsh-fast-syntax-highlighting to a tag~~ | **DONE** 2026-04-05 | `v0.7.1` / `v1.55`; update `ZSH_AUTOSUG_TAG` / `ZSH_FSH_TAG` to upgrade |
| SHA256 verification for JetBrainsMono font | Deferred | Releases include sha256 checksums; download `.sha256` file alongside zip; verify with `sha256sum -c` |
| Pin Homebrew install script | Deferred | No version parameter available; consider specific commit hash in raw.githubusercontent.com URL |
| Pin atuin via cargo instead of setup.atuin.sh | N/A | atuin removed 2026-04-05 |
| Pin mise via cargo or package manager | N/A | mise removed 2026-04-05 |
| Version-pin cargo installs (weathr, trippy, yazi, etc.) | Deferred | Add `--version X.Y.Z` to all `cargo install` calls |
| Verify uv install script via astral.sh hash | Deferred | Pin version in URL: `https://astral.sh/uv/0.6.x/install.sh` |
| SLSA provenance for GitHub release binaries | Deferred | Monitor for SLSA support from lsd/bat; add provenance verification when available |

---

## Tools Considered for Removal

### cbonsai — KEEP (conditional)
- **Risk**: LOW on apt/brew (standard repos), MEDIUM on AUR (user-maintained build script)
- **Value**: Low (visual terminal animation)
- **Recommendation**: KEEP for apt and brew. For Arch/AUR: acceptable given AUR standard practice, but document the AUR risk. If security posture tightens, mark OPTIONAL.

### cmatrix — KEEP
- **Risk**: LOW — available in apt, brew, and scoop from standard repos
- **Value**: Low (entertainment), but zero additional supply chain risk versus apt packages already installed
- **Recommendation**: KEEP

### weathr — KEEP
- **Risk**: MEDIUM — `cargo install weathr` from crates.io; crates.io provides SHA256 integrity checks. The crate is actively maintained.
- **Value**: Moderate — lightweight weather CLI tool used in the projector stack
- **Recommendation**: KEEP, but add `--version` pin as a deferred task

### lolcrab — KEEP (replaced lolcat 2026-05-02)
- **Risk**: LOW — Rust port of lolcat, single static binary. Distribution channels (crates.io, winget, scoop, AUR) all hash-verify packages. Ruby dependency eliminated across the fleet.
- **Value**: Low (aesthetic output colorizing for fastfetch alias / greeter)
- **Recommendation**: KEEP. Cross-OS cascade is winget/scoop/cargo on Windows, brew (when available) → cargo on macOS, cargo (apt path) / AUR (Arch path) on Linux. A `lolcat → lolcrab` backwards-compat alias is added by the installer's rainbow-block sweep so muscle-memory and any external scripts referencing `lolcat` continue to work.
- **History**: Replaced `gem install lolcat` (Ruby gem, no checksum, MEDIUM risk) — same hardening pattern as the 2026-04-05 mise/atuin/uv removals. See commit history for the swap.

### sd — **REMOVED**
- **Risk**: MEDIUM (was cargo install from crates.io)
- **Value**: None — already removed from all aliases
- **Action**: Removed from install_linux.sh and install_mac.sh in this sweep. Not present in current install_windows.ps1.
