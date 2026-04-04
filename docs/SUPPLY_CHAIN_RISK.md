# Supply Chain Risk Analysis — terminal-kniferoll
Generated: 2026-04-04

## Summary

The installer suite (install_linux.sh, install_mac.sh, install-v2.sh, install_windows.ps1) pulls from
a mix of official package managers, GitHub releases, and custom-domain install scripts. The overall
posture is **MEDIUM** risk. No high-risk unverified custom-domain scripts are executed without TLS
enforcement; however several download-then-run patterns lack checksum verification, and multiple
install scripts track floating `HEAD`/`master`/`latest` rather than pinned versions.

**Key findings:**
- Two custom-domain install scripts (mise, atuin) use `curl | bash`-equivalent patterns with no checksums — mitigated by enforcing TLS 1.2+, deferred for checksum addition
- Oh My Zsh and Homebrew install scripts are fetched from GitHub `master`/`HEAD` — no commit pinning
- `sd` was removed from aliases but still installed on Linux/macOS — removed in this sweep
- JetBrainsMono Nerd Font was downloaded from `releases/latest` — pinned to v3.4.0 in this sweep
- GitHub release .deb downloads (lsd, bat) lack SHA256 verification
- cargo installs (weathr, trippy, etc.) rely on crates.io registry integrity with no version pinning

---

## Risk Register

| Tool | Source | Version Pinned | Verification | Fetch Method | Risk | Notes |
|---|---|---|---|---|---|---|
| Oh My Zsh | raw.githubusercontent.com/ohmyzsh/ohmyzsh/master | NO (master) | None | download-then-run | MEDIUM | Trusted project; TLS enforced; no commit pin |
| Homebrew | raw.githubusercontent.com/Homebrew/install/HEAD | NO (HEAD) | None | download-then-run | MEDIUM | Trusted project; TLS enforced; no commit pin |
| rustup | sh.rustup.rs | NO (latest) | None | download-then-run | MEDIUM | Official Rust installer; TLS 1.2+ enforced in all scripts |
| mise | mise.jdx.dev/install.sh | NO | None | download-then-run | HIGH | Custom domain; TLS 1.2+ enforced; no checksum |
| atuin | setup.atuin.sh | NO | None | download-then-run | HIGH | Custom domain; TLS 1.2+ enforced; no checksum |
| uv | astral.sh/uv/install.sh | NO | None | download-then-run | HIGH | Custom domain; TLS 1.2+ already enforced in install-v2.sh |
| 1Password CLI | downloads.1password.com (apt repo) | stable channel | GPG signed apt repo | package manager | LOW | Official signed repo; GPG key verified |
| lsd | GitHub releases (lsd-rs/lsd) latest | NO (latest API) | None | download .deb | MEDIUM | GitHub origin; no SHA256 check |
| bat | GitHub releases (sharkdp/bat) latest | NO (latest API) | None | download .deb | MEDIUM | GitHub origin; no SHA256 check |
| JetBrainsMono NF | GitHub releases (ryanoasis/nerd-fonts) | YES v3.4.0 (pinned this sweep) | None | download zip | MEDIUM | Pinned version; SHA256 deferred |
| zsh-autosuggestions | github.com/zsh-users (git clone) | NO (default branch) | None | git clone --depth=1 | MEDIUM | Well-known plugin; no commit pin |
| zsh-fast-syntax-highlighting | github.com/zdharma-continuum (git clone) | NO (default branch) | None | git clone --depth=1 | MEDIUM | Well-known plugin; no commit pin |
| weathr | crates.io | NO (latest) | crates.io checksums | cargo install | MEDIUM | crates.io provides hash verification; version unspecified |
| trippy | crates.io | NO (latest) | crates.io checksums | cargo install | MEDIUM | crates.io provides hash verification |
| yazi | crates.io | NO (latest) | crates.io checksums | cargo install | MEDIUM | crates.io provides hash verification |
| atuin (cargo, Windows) | crates.io | NO (latest) | crates.io checksums | cargo install | MEDIUM | crates.io provides hash verification |
| cbonsai | apt / AUR | distro-managed | Package manager signatures | package manager | LOW/MEDIUM | LOW on apt/brew; MEDIUM on AUR (user scripts) |
| cmatrix | apt / brew / scoop | distro-managed | Package manager signatures | package manager | LOW | Available in standard repos |
| lolcat | RubyGems (gem install) | NO | None | gem install | MEDIUM | No checksum; gem registry trust |
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

1. **TLS hardening** — added `--proto '=https' --tlsv1.2` to all `curl` invocations in:
   - `install_linux.sh`: `download_to_tmp()`, `install_github_deb()`, font download
   - `install_mac.sh`: `download_to_tmp()`, font download
   - `install-v2.sh`: `github_deb_install()` (both GitHub API calls and .deb download)

2. **Font version pinning** — JetBrainsMono Nerd Font URL changed from `releases/latest` to `releases/download/v3.4.0/` in install_linux.sh and install_mac.sh.

3. **`sd` removed** — the `sd` (sed alternative) tool was already removed from aliases but was still being installed via `cargo install sd` (install_linux.sh) and in BREW_PACKAGES (install_mac.sh). Removed from both.

4. **Security comments** — added inline comments to all high-risk fetch points (mise, atuin, rustup, Oh My Zsh, Homebrew) explaining the risk and applied mitigations.

---

## Deferred Mitigations

These items were identified but not implemented to avoid breaking install flow. Each has a corresponding tracker task.

| Item | Reason Deferred | Recommended Action |
|---|---|---|
| SHA256 verification for lsd/bat .deb | GitHub releases provide SHA files; requires multi-step download + verify | Parse GitHub release API for SHA256 assets; verify before `dpkg -i` |
| SHA256 verification for JetBrainsMono font | Releases include sha256 checksums; requires download + compare | Download `.sha256` file alongside zip; verify with `sha256sum -c` |
| Pin Oh My Zsh to a git tag/SHA | Install script doesn't accept a version arg | Clone from a pinned tag instead of running the install script |
| Pin Homebrew install script | No version parameter available | Consider using a specific commit hash in the raw.githubusercontent.com URL |
| Pin atuin via cargo instead of setup.atuin.sh | Pacman has atuin natively; apt does not | Use `cargo install atuin` as fallback for apt systems; pin crate version |
| Pin mise via cargo or package manager | Pacman has mise natively; apt relies on custom script | Use `cargo install mise` as fallback for apt systems |
| Version-pin cargo installs (weathr, trippy, yazi, etc.) | Requires updating version strings when upgrading | Add `--version X.Y.Z` to all `cargo install` calls |
| Pin zsh-autosuggestions/zsh-fast-syntax-highlighting to a tag | `git clone` tracks default branch | Add `--branch <tag>` to git clone commands |
| Verify uv install script via astral.sh hash | astral.sh publishes SHA256 for uv installers | Pin version in URL: `https://astral.sh/uv/0.6.x/install.sh` |
| SLSA provenance for GitHub release binaries | lsd/bat do not yet publish SLSA provenance | Monitor for SLSA support; add provenance verification when available |

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

### lolcat — KEEP
- **Risk**: MEDIUM — `gem install lolcat` from RubyGems. Ruby gem registry is community-maintained.
- **Value**: Low (aesthetic output colorizing for fastfetch alias)
- **Recommendation**: KEEP on macOS (brew provides it). On Linux, consider replacing `gem install lolcat` with the apt package where available, or remove the alias if not installed.

### sd — **REMOVED**
- **Risk**: MEDIUM (was cargo install from crates.io)
- **Value**: None — already removed from all aliases
- **Action**: Removed from install_linux.sh and install_mac.sh in this sweep. Not present in current install_windows.ps1.
