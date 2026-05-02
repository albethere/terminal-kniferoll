# terminal-kniferoll v2 — Design Plan

## Context

`terminal-kniferoll` is the standalone, multi-platform terminal-environment installer at `~/Projects/terminal-kniferoll` (GitHub: `albethere/terminal-kniferoll`). Today it ships three monolithic install scripts — `install_mac.sh` (1,473 lines), `install_linux.sh` (1,635 lines), `install_windows.ps1` (2,748 lines) — plus a shared `lib/`, a Go TUI selector, a Python projector, and a tightly maintained set of voice/architecture/risk docs. The current repo is ~5,900 lines of installer code wrapped around what is, conceptually, a relatively small set of choices.

The current version works. That is not the same as it being right. Three years of layered hotfixes — Zscaler hard-gating, dual sweep parsers, supply-chain guards that are half-implemented, fragile platform detection branches, no real dry-run on Unix, no rollback story, soft-warn fallbacks for fonts that have no published checksums — have produced a system whose behavior nobody can hold in their head all at once. The recent git log is dominated by commits like `fix(linux): add cmp -s guard in upsert_rc_zscaler_block` and `fix(mac): remove configure_tool_certs; install rustup via brew` — these are not features. They are the smell of a design that has accumulated more responsibilities than its skeleton can carry cleanly.

This document proposes a complete from-scratch rewrite. The rewrite splits the project on the two axes that actually matter — operating system (4) and security posture (managed/unmanaged, 2) — into eight standalone scripts, each one short enough to read in one sitting. It defines a naming family, a repo strategy that hard-segregates corporate assumptions out of the public surface, three governing principles in priority order (simplicity, security, beauty), a per-script skeleton, a competitive landscape positioning, an explicit list of decisions deferred to Chef, and a phasing plan that sequences by learning velocity rather than by platform.

The v1 scripts and their hard-won knowledge are not being thrown away. They are being read as a specification. Every bug they fixed is a constraint v2 must respect; every workaround they encode is a piece of evidence about the world. The redesign's job is to preserve every meaningful behavior while shedding the structural weight that made each new behavior cost more than it should.

---

## 1. Inventory of current behavior

This section is the source-of-truth for "what must the rewrite still do." It is grouped by category and cites the current code by path and approximate line range.

### 1.1 Entrypoint and dispatch

`install.sh:39-61` does OS detection via `uname -s` and execs the platform script. `MINGW*|MSYS*|CYGWIN*` is special-cased to invoke `powershell.exe` from Git Bash; native PowerShell users are expected to invoke `install_windows.ps1` directly. There is one universal entrypoint and three platform implementations.

### 1.2 Preflight and platform detection

- **macOS** (`install_mac.sh`, opening 60 lines + `preflight_zscaler_check` at lines ~297–359): strict mode, prepends Homebrew canonical paths to `PATH` before any detection so `brew` is findable from non-login shells, sudo, GUI launches, and CI; TTY-guarded color palette; MDM/restricted-device detection via `profiles status -type enrollment`; Zscaler TLS preflight is a **hard gate** — if it fails, the whole installer halts.
- **Linux** (`install_linux.sh:0-950`): distro detection via `apt-get` vs `pacman` (Debian/Ubuntu vs Arch/CachyOS); AUR helper detection (`yay`/`paru`); sudo validation with a background `sudo -v` keepalive loop.
- **Windows** (`install_windows.ps1:64-90`): minimum PowerShell 5.1, recommended 7+; auto-installs `curl` via winget if missing; auto-upgrades the host PowerShell to 7 via winget and re-launches.

### 1.3 Package-manager bootstrap

- macOS: Homebrew is fetched from `raw.githubusercontent.com/Homebrew/install/HEAD/install.sh` via `download_to_tmp` (TLS 1.2 enforced, `CURL_CA_BUNDLE`-aware); then `HOMEBREW_NO_AUTO_UPDATE=1` is set globally; `/opt/homebrew/share` is hardened with `chmod g-w,o-w` to silence oh-my-zsh's compaudit. (`install_mac.sh:1008-1050`)
- Linux: apt and pacman are assumed present. Linuxbrew is bootstrapped from the same upstream URL; `build-essential` installed first; brew shellenv eval'd; marker block written into rc files. (`install_linux.sh:708-752`)
- Windows: winget is a hard prerequisite; Scoop is bootstrapped via `iwr | iex`; Chocolatey is the tertiary fallback with a self-elevating UAC prompt. (`install_windows.ps1:1579-1630`)

### 1.4 CLI tools and toolchains

The full inventory across the three scripts (deduped, not exhaustive on every platform):

- **Core CLI / TUI**: bat, btop, cmatrix, cbonsai, exiftool, fastfetch, fzf, gh, hexyl, jq, lolcat, lsd, micro, ngrep, nmap, nushell, ripgrep, speedtest-cli, sqlite, starship, tealdeer, tmux, yazi, zoxide, zsh-autosuggestions, fast-syntax-highlighting.
- **Build / language tools**: gcc, build-essential, binutils, fontconfig, freetype, gnutls, lz4, m4, ncurses, harfbuzz, openssl@3, openjdk, lua, ruby (+ `lolcat` gem), node + npm + yarn, python@3.12 + pipx + uv, go, **rustup**.
- **Security**: ca-certificates, gnutls, nmap, ngrep, tcpdump, unbound, wireshark, yara, 1password-cli.
- **Cloud CLIs**: awscli, azure-cli (Win), gcloud (Win), rclone.
- **AI CLIs**: gemini-cli, Anthropic Claude (winget on Windows).
- **Cargo crates**: weathr, trippy (`trip`), yazi-fm, nu (Linuxbrew/cargo fallbacks).
- **PSGallery (Windows)**: Oh-MyPosh, PSReadLine, Terminal-Icons, PSFzf, posh-git.
- **Fonts** — all platforms, `ryanoasis/nerd-fonts` v3.4.0 zips downloaded directly: Iosevka, Hack, UbuntuMono, JetBrainsMono, 3270, FiraCode, CascadiaCode, VictorMono, Mononoki, SpaceMono, SourceCodePro, Meslo, GeistMono.

### 1.5 Rust / rustup — the most-scarred toolchain

- **macOS**: deliberately installed via `brew install rustup` (`install_mac.sh` ~line 1227+), explicitly avoiding the `sh.rustup.rs` curl-pipe-bash because `docs/SUPPLY_CHAIN_RISK.md` flags it as MEDIUM-risk.
- **Linux**: still pipes `sh.rustup.rs` through `download_to_tmp` because there is no Homebrew on most Linux installs and the team has accepted the trade-off. There is **no explicit aarch64 branch**; the script relies on rustup's own arch detection. The recurring "rustup on aarch64" bug class — open as a feature branch `fix/aarch64-rust-toolchain` in the current repo — lives in this seam.
- **Windows**: `winget install Rustlang.Rustup`, then `CARGO_HTTP_CAINFO = $env:CURL_CA_BUNDLE` is exported before any `cargo install` so cargo respects the corp CA.

### 1.6 Shell setup and dotfiles

- **Unix**: `~/.zshrc`, `~/.zprofile`, `~/.profile`, `~/.bashrc`, `~/.bash_profile` are all written or amended. Zsh config is split across `shell/zshrc.zsh`, `shell/aliases.zsh`, `shell/plugins.zsh`. `oh-my-zsh` is cloned at pinned tag `24.9.0` with a fallback to upstream `install.sh` if the tag clone fails (`install_mac.sh:1089-1106` is the offending fallback — pure unpinned curl-pipe-bash). `zsh-autosuggestions` is pinned to `v0.7.1`, `fast-syntax-highlighting` to `v1.55`, **and FSH must always load last** — this is repeated in CLAUDE.md, AGENTS.md, GEMINI.md, and the README.
- **Windows**: `$PROFILE` is rewritten with timestamped backup, keeping five most recent. PowerShell profile content lives in `shell/profile.ps1`.
- **Cyberwave** color schemes: `macos/Cyberwave.itermcolors` (iTerm2) and `windows/settings.json` (Windows Terminal) are deployed verbatim.

### 1.7 Zscaler / corporate-CA handling

This is the single most invasive concern in the codebase, touching every install script and most of the lib. Detection paths, in order:

- macOS (`install_mac.sh:368-437`): cached combined bundle in `~/.config/terminal-kniferoll/ca-bundle.pem`; `/Users/Shared/.certificates/zscaler.pem`; `/Library/Application Support/Zscaler/ZscalerRootCertificate-2048-SHA256.crt`; `security find-certificate` from the System keychain.
- Linux (`install_linux.sh:355-423`): cached bundle; `/usr/local/share/ca-certificates/zscaler.{pem,crt}`; `/etc/ssl/certs/zscaler.pem`; `/usr/share/ca-certificates/zscaler.pem`.
- Windows (`install_windows.ps1:664-859`): cached bundle in `%USERPROFILE%\.config\terminal-kniferoll\ca-bundle.pem`; `%USERPROFILE%\.certificates\zscaler.pem`; `C:\ProgramData\Zscaler\*`; `Cert:\LocalMachine\Root` + `Cert:\CurrentUser\Root` filtered by subject/issuer/FriendlyName matching "Zscaler".

The TLS preflight (`install_mac.sh:297-359`) does a TLS-1.2-enforced curl to GitHub's Homebrew install URL, distinguishing exit code 60 (cert error → call `setup_zscaler_trust --required`) from a returned HTML splash page (auto-accept attempt or manual prompt). The auto-accept logic at `install_mac.sh:175-257` parses form actions with grep+sed, collects up to 30 hidden fields, and POSTs them — this is brittle and acknowledged as such.

The exported environment variables that propagate the bundle: `CURL_CA_BUNDLE`, `SSL_CERT_FILE`, `NODE_EXTRA_CA_CERTS`, `REQUESTS_CA_BUNDLE`, `GIT_SSL_CAINFO`, `AWS_CA_BUNDLE`, `PIP_CERT`, `ZSC_PEM` (sentinel marker), and on macOS `HOMEBREW_CURLOPT_CACERT`, on Windows `CARGO_HTTP_CAINFO`. These are written into a managed env file (`zscaler-env.sh` / `zscaler-env.ps1`) that the rc files source.

### 1.8 RC-block sweep (the AWK state machine)

There are two implementations, which is itself a smell.

- `lib/rc_sweep.sh` (older, 280 lines): public API `sweep_rc_files` and `sweep_brew_shellenv_files`. Always rewrites the Zscaler block; uses a `cmp -s` idempotency guard for the brew block.
- `scripts/lib/sweep-zscaler.sh` + `scripts/lib/sweep-zscaler.awk` (newer, 104 + 194 lines): cleaner separation, idempotent for both blocks, AWK does the heavy lifting. This is the **intended modern path** and recent commits have migrated `install_mac.sh` and `install_linux.sh` to source it.

The AWK parser recognizes two region types — explicit `# BEGIN terminal-kniferoll zscaler` … `# END` markers, and "organic" regions that begin at a trigger line like `ZSC_PEM=` and extend until a non-Zscaler, non-blank line at depth 0 — and it preserves any Zscaler-related code inside a user function (depth > 0) untouched. There is a 14-test bash suite at `scripts/test-sweep.sh` and a 10-test PowerShell mirror at `scripts/test-sweep.ps1`.

### 1.9 Supply-chain guard

`lib/supply_chain_guard.sh:21` hardcodes `SC_RISK_TOLERANCE=1` (strict mode); `sc_install` always calls the safe path. The deferred-package framework, the inspect/OSINT UI, and the multi-tier risk modes (Strict / Balanced / Permissive / Manual) are all stubs. `docs/SUPPLY_CHAIN_RISK.md` documents the threat model and the deferred work but the code does not yet realize most of the design. This half-finished state is one of the strongest motivators for v2.

### 1.10 TUI selector and projector

`tui/selector/main.go` (454 lines) is a Bubble-Tea/Lipgloss menu that emits `KEY=true|false` lines for the shell installer to source. Falls back to "all checked" on non-TTY or Windows. **The Windows installer never uses it** — Windows uses `gum choose` from `charmbracelet/gum`, a separate binary.

`projector.py` (207 lines) is a Python orchestrator that runs a sequence of "scenes" (fastfetch, cbonsai, cmatrix, weathr, btop, trippy) with interactive speed control. Config at `~/.config/projector/config.json`. **It is conceptually orthogonal to the installer** and is bundled mostly because it shares a name and a flavor.

### 1.11 Mode flags and idempotency

`install.sh` exposes `--shell`, `--projector`, `--interactive`, `--full`, `--help`. Each platform script supports the same flags plus its own (`--no-casks` on mac, `-DryRun` and `-ZscalerStatus` on Windows). Idempotency is achieved by: `command -v` / `dpkg -s` / `brew list` checks before installing; marker-bracketed dotfile blocks; cache-and-compare for the brew block; timestamped backups (rotated to 5) before any destructive change.

### 1.12 Summary statistic

~5,917 lines of shell+PowerShell across the three monoliths, plus ~1,000 lines of supporting library, tests, and docs. Roughly 45 brew packages, 50+ apt packages, ~15 winget packages, 13 Nerd Font families, 4 Zscaler detection paths per platform.

---

## 2. Why a rewrite

The current architecture is not bad. It is *worn*. Specifically:

**Monolithic platform scripts conflate four concerns.** Each of `install_mac.sh`, `install_linux.sh`, `install_windows.ps1` is responsible for: (1) preflight and posture detection, (2) package-manager bootstrap and tool installation, (3) dotfile rendering and rc-block management, (4) corporate-CA detection and propagation. Those four concerns have different change rates, different testing needs, and different audiences. Bundling them into one ~1,500–2,750-line file means that a Zscaler bugfix forces re-reading the brew bootstrap; a new tool added to the inventory has to thread through preflight, install, dotfile, and Zscaler env. The result is the change-cost curve we have actually observed: every recent commit is a hotfix in one of these four planes, and each one risks regressions in the other three.

**The managed/unmanaged distinction is woven through every script instead of factored out.** A user on a personal Linux laptop with no corporate proxy still pays for every Zscaler check, every cached-bundle path probe, every TLS preflight, every comment block in their `~/.zshrc`. A user on a corporate Windows box still gets a script that has to wonder whether to skip Zscaler. That coupling is unsafe in both directions: open-source users get corporate-shaped artifacts in their dotfiles, and corporate users get a script that has to *remember* it is corporate every five hundred lines. Splitting the binary along this seam is the single largest simplification available.

**Two sweep implementations and a half-finished supply-chain guard are the visible tip of a decision-debt iceberg.** `lib/rc_sweep.sh` and `scripts/lib/sweep-zscaler.{sh,awk}` co-exist because the migration was started but never finished (`install_mac.sh:1008-1050` still sources both in some flows). `lib/supply_chain_guard.sh:21` hardcodes `SC_RISK_TOLERANCE=1` and stubs `sc_process_deferred()` — the design promised four risk tiers and an inspect UI, the code shipped one tier and a no-op. These are not bugs to fix; they are signals that the architecture cannot absorb the policies it wants to express.

**Platform detection is fragile in three named ways.** Linuxbrew detection in `install_linux.sh:708-752` requires a triple-check (explicit paths, PATH lookup, fallback) because `sudo` strips PATH and Linuxbrew can land in either `/home/linuxbrew/.linuxbrew` or `$HOME/.linuxbrew`. macOS's `/opt/homebrew/bin` is prepended to `PATH` *before* detection (`install_mac.sh` opening lines) for the same class of reason. Windows requires the bash dispatcher to special-case `MINGW*|MSYS*|CYGWIN*` and shell out to `powershell.exe` — meaning the universal `install.sh` already fails its universality on the platform it most needs to be universal on (`install.sh:51-55` has the comment "From native PowerShell, run install_windows.ps1 directly instead").

**The aarch64 / rustup bug class is structural, not local.** `install_linux.sh` pipes `sh.rustup.rs` (because there is no Linuxbrew rustup recipe most users want) and relies on rustup's own arch detection. The current `fix/aarch64-rust-toolchain` branch is open precisely because rustup's behavior on aarch64 Debian, in a corporate-proxied environment, with `CURL_CA_BUNDLE` set, produces edge cases the Linux script never explicitly handles. The fix is not to add a fourth special-case to `install_linux.sh`; it is to admit aarch64 is a first-class target and design two Linux scripts (Debian-family, Arch-family) that each handle x86_64 and aarch64 explicitly as a matrix dimension, not an afterthought.

**There is no real dry-run on Unix.** `install_windows.ps1` has `-DryRun`. `install_mac.sh` and `install_linux.sh` have no equivalent. A 1,500-line installer with no dry-run is a 1,500-line installer that has to be read forward to know what it will do, which is the worst-case ergonomics for an audit.

**There is no rollback story and no install manifest.** The script writes timestamped backups of dotfiles (good) but has no record of what packages it installed, at what versions, from what sources, with what checksums. If a user wants to know "what did kniferoll do to my machine in March," the answer is "diff your dotfiles and grep your shell history." That is not a trail; it is an absence.

**Trust posture leaks across surfaces.** The README on a public repo describes corporate-CA handling. The fast-syntax-highlighting "must load last" rule is documented in four files. The brew share-permissions hardening (`install_mac.sh:1038-1042`) exists because oh-my-zsh's compaudit complains; that is a workaround for someone else's tool, not a kniferoll concern. These are not individually bad; collectively they are a sign the project does not have a clean inside/outside boundary.

The rewrite addresses all eight of these points by collapsing the matrix, separating the postures into different repos, deleting the half-finished abstractions, and making each individual script short enough that the entire thing fits on one screen of mental working set.

---

## 3. Target matrix

Eight scripts. Four operating-system targets crossed with two security postures. No further axes — architecture (x86_64 / aarch64) is handled inside the Linux scripts as a matrix dimension, not a separate file, because the divergence is small and the duplication would buy nothing.

| OS target | Posture | Filename (provisional) | Notes |
|-----------|---------|------------------------|-------|
| macOS (Apple Silicon, arm64) | unmanaged | `unmanaged-mac-applesilicon-glide-cut.sh` | Homebrew on arm64; assumes user is admin of their machine. |
| macOS (Apple Silicon, arm64) | managed | `managed-mac-applesilicon-paper-slice.sh` | Adds Zscaler/corp-CA detection, MDM-aware preflight, TLS-1.2 fallback. |
| Windows 10/11 (x86_64) | unmanaged | `unmanaged-windows-broad-stroke.ps1` | PowerShell 7+, winget primary, Scoop secondary. |
| Windows 10/11 (x86_64) | managed | `managed-windows-clean-pass.ps1` | Adds corp-CA cert-store enumeration, `CARGO_HTTP_CAINFO`, group-policy-aware paths. |
| Linux Debian/Ubuntu (x86_64 + aarch64) | unmanaged | `unmanaged-debian-draw-line.sh` | apt + cargo + selective GitHub releases; arch-aware in the inventory. |
| Linux Debian/Ubuntu (x86_64 + aarch64) | managed | `managed-debian-fine-dice.sh` | Adds Zscaler/corp-CA paths under `/usr/local/share/ca-certificates/`, internal apt mirrors as a flag. |
| Linux Arch-family (x86_64 + aarch64) | unmanaged | `unmanaged-arch-push-cut.sh` | pacman + AUR helper detection; CachyOS, EndeavourOS, Manjaro all welcome. |
| Linux Arch-family (x86_64 + aarch64) | managed | `managed-arch-slow-pull.sh` | Same as above plus corp posture. Edge case: rolling release means version pins are looser; documented. |

### 3.1 Why Intel macOS is out of scope

Apple stopped shipping new Intel Macs in 2023. Apple announced the end of macOS Intel support for the next major release. By the time v2 of kniferoll is in active maintenance (mid-2026 onward), the Intel-Mac population among the kniferoll user base is statistically zero — the user community is dev/security/SRE on personal or corp-issued laptops, all of which are Apple Silicon for purchases in the last three years. Maintaining a script for a deprecated and shrinking arch is non-trivial: Homebrew's arm64 vs x86_64 prefix difference (`/opt/homebrew` vs `/usr/local`), the Rosetta translation surface, and the third-party-tool support gap (e.g., several Nerd Font and cargo crates have only arm64 native binaries) all add expense. The right call is: explicitly out of scope; users on Intel Mac fork the script if they need it.

### 3.2 Why arch is a matrix dimension on Linux but not a separate file

x86_64 and aarch64 differ on Linux in three ways relevant to kniferoll: (a) some apt/pacman packages have different names or different availability; (b) some GitHub-release assets are only published for one arch; (c) rustup behaves differently. None of these justify file-level duplication. Each is a per-tool conditional in a tools-inventory data structure: `if [[ $ARCH == aarch64 ]]; then SKIP some_x86_only_tool; fi`. Splitting into four Linux files instead of two would double the maintenance surface for a divergence that is minor and shrinking.

### 3.3 What the matrix excludes and why

- **WSL2** is folded into `unmanaged-debian-*` (and `managed-debian-*` if used in a corp environment) with a small `if-wsl` block that adjusts a few paths. WSL2 is Debian/Ubuntu running on a Microsoft hypervisor. It is not its own platform. (Open question: confirm with Chef.)
- **NixOS / nix-darwin** is excluded — Nix users have a different system model and a vastly more capable installer (Home Manager). v2 should not pretend to compete in that space.
- **FreeBSD / OpenBSD / Alpine / Fedora-RHEL family** are excluded as targets. They each have small but meaningful differences (different libc on Alpine, dnf on Fedora, ports on FreeBSD) that would each require a dedicated script. The four targets above cover ~95% of the kniferoll user base; the rest are documented as "you are welcome to fork."

---

## 4. Naming

Codenames matter because they will appear in URLs, file paths, log lines, error messages, and casual conversation for years. They have to be short enough to type, evocative enough to remember, and coherent as a family without being twee, fandom-specific, or distracting from the work.

### 4.1 Three candidate themes

**Theme one — Whetstone Grits.** A whetstone progresses from coarse to fine: 220, 400, 1000, 3000, 6000, 8000, 12000 grit. The metaphor is *sharpening progression*; each script is a stage of bringing a blade to working edge. Names would be `coarse-grit`, `medium-grit`, `mirror-grit`, etc. The metaphor *fits*: a kniferoll exists because someone honed their tools. But the family vocabulary is shallow (every name shares the second word "grit"), the progression implies an ordering kniferoll's eight scripts do not have, and the audience likely doesn't know which grit is which without a chart. Reject.

**Theme two — Brigade Stations.** A working kitchen runs a brigade with named stations: hot line, cold line, prep board, mise place, fire pass, sauce bench, service call, last call. The metaphor is *roles on a working line*; each script is a station that does its job and hands off. The vocabulary is rich, the metaphor extends the existing project name (`kniferoll` is what a chef carries), and the words are concrete. The downside is that "station" vocabulary is mildly inside-baseball — non-restaurant readers may parse `mise-place` as gibberish. Salvageable, but second choice.

**Theme three — Knife Motions.** A trained chef applies a small set of motions to material with a blade: rock cut, draw cut, glide cut, push cut, paper slice, fine dice, clean pass, slow pull, broad stroke. The metaphor is *the act of using a sharp tool with skill*. Each name is two short words; each is a real cutting technique that needs no chart to identify; the family vibe is "things a working knife does." Motions imply *action*, which is exactly what an installer is. They map cleanly onto filenames without becoming jargon. This is the strongest fit.

### 4.2 Chosen theme: Knife Motions

Eight names, every word distinct (no word appears twice across the set), each a real culinary cutting motion or technique:

| Codename | Posture | OS | Why this name for this slot |
|----------|---------|------|------------------------------|
| **glide-cut** | unmanaged | macOS Apple Silicon | The smooth, friction-free motion of a sharp blade through tomato skin. Apple Silicon is the most polished surface kniferoll runs on; an unmanaged Mac is what a glide cut feels like. |
| **paper-slice** | managed | macOS Apple Silicon | A paper-thin slice requires precision under constraint — a managed Mac is precision under corporate constraint. |
| **broad-stroke** | unmanaged | Windows | A long sweeping cut across the board. Unmanaged Windows is broad — winget, Scoop, Chocolatey, the full stack — and the script is, at v1, the longest of the three. |
| **clean-pass** | managed | Windows | One disciplined stroke from heel to tip with no fuss. The corp-Windows script is the one most likely to be audited. |
| **draw-line** | unmanaged | Linux Debian/Ubuntu | A single deliberate pull across the work. Debian/Ubuntu is the workhorse line — the canonical Linux script in v1. |
| **fine-dice** | managed | Linux Debian/Ubuntu | Small, uniform, patient. Maps to the tightest matrix axis: corp Linux on aarch64 small-board hardware (RPi4-class) is exactly what fine-dicing feels like. |
| **push-cut** | unmanaged | Linux Arch-family | Forward through dense material. Arch is forward-leaning, opinionated, sharp. |
| **slow-pull** | managed | Linux Arch-family | Deliberate cut applied with care, the inverse of push-cut. Managed Arch is the rarest and most deliberate combination. |

The full set:

```
unmanaged-mac-applesilicon-glide-cut.sh
managed-mac-applesilicon-paper-slice.sh
unmanaged-windows-broad-stroke.ps1
managed-windows-clean-pass.ps1
unmanaged-debian-draw-line.sh
managed-debian-fine-dice.sh
unmanaged-arch-push-cut.sh
managed-arch-slow-pull.sh
```

These read in a directory listing as a coherent family. They also work as shorthand: "I'm running glide-cut on my new MacBook." "Did fine-dice survive the apt-mirror migration?" The codenames carry meaning that the os-and-posture qualifiers don't.

### 4.3 Filename convention

The pattern is `{posture}-{os-family}-{arch-or-empty}-{codename}.{ext}`. macOS includes `applesilicon` because there is exactly one supported arch and naming it explicitly closes off any future ambiguity. Linux scripts handle two arches and so the arch is omitted (the script branches inside). Windows is x86_64-only for now and the arch is omitted.

The filenames are long. That is fine: they are typed once during install, referenced in docs and URLs after, and read aloud only in conversation. Length buys explicitness, which buys auditability.

---

## 5. Repo strategy

### 5.1 Recommendation: two repos, public + private

- **Public repo** (`albethere/kniferoll` — drop the `terminal-` prefix, it's redundant; the project is its own brand): holds the four unmanaged scripts, the shared library at `lib/`, the README, the demo material, the CI for the unmanaged scripts. Visibility: public. License: MIT. URL: `github.com/albethere/kniferoll`.
- **Private repo** (`albethere/kniferoll-galley`): holds the four managed scripts plus the corporate-CA infrastructure as a `corp/` overlay. "Galley" is the chef's term for the working kitchen — both an extension of the metaphor and an inside-the-house signal that this is the on-premises version. Visibility: private to the org. URL: `github.com/albethere/kniferoll-galley`.

### 5.2 Defense of the split

A monorepo with `unmanaged/` and `managed/` subdirectories under one visibility line cannot be made to work. If the monorepo is public, the managed scripts leak corporate hostnames, splash-page form actions, MDM expectations, internal apt-mirror URLs, and the *shape* of the corporate trust store — none of which should be on the open internet. If the monorepo is private, the public users cannot get to the unmanaged scripts at all, which defeats the whole "this is a public project with a corp overlay" intent. There is no setting in between.

A four-repo split (one per OS target × visibility) was considered and rejected: the duplication of shared library code and CI scaffolding across four public repos is a long-term maintenance loss. Two repos is the right granularity.

### 5.3 Boundary rules between the two repos

The public repo never references:
- corporate hostnames, IPs, or DNS suffixes
- specific corp-CA filenames or paths
- splash-page form selectors or form-field names
- MDM-detection commands or expectations
- internal apt mirrors, Artifactory hosts, internal package registries
- the words "Zscaler," "ZIA," "ZPA," or any specific proxy vendor

The public repo *may* reference, generically:
- "if you are behind a corporate TLS-inspecting proxy, see the managed scripts in the private repo"
- the standard env vars (`CURL_CA_BUNDLE`, `NODE_EXTRA_CA_CERTS`, etc.) — these are documented features of the upstream tools, not corporate secrets

The private repo *imports* the public lib by vendoring it: a `vendor/kniferoll/` subdirectory containing a tagged release of the public lib, with a manifest hash committed alongside. Updates are explicit `git subtree pull` (or equivalent) operations. No live submodule, no curl-fetch-at-install. Vendoring trades a small duplication cost for full audit independence.

### 5.4 Discoverability and shared code reuse

The public repo gets the full README treatment: demo GIF, install instructions, what-it-does table, the Knife Motions naming explainer, links to FLAVOR.md for voice. It is the front door of the project.

The private repo gets a minimal README that says "this is the managed-posture overlay of `kniferoll`; consult the public repo for general design; this repo's specific contents are: [list]" — and the contents list itself avoids names that would tip the corporate identity.

Shared library code lives in the public repo under `lib/`. The contract: no function in `lib/` may take a corporate-shaped argument, depend on the existence of a corp environment variable, or hardcode a path under `/usr/local/share/ca-certificates/`. The library's job is to provide neutral primitives (download-and-verify, write-rc-block, check-tool-installed, log-with-format) that managed scripts can compose with the corporate logic they overlay.

---

## 6. Architectural principles

The rewrite is governed by three values, in priority order: **simplicity, security, beauty**.

### 6.1 Simplicity

- **One script per (OS × posture).** No dynamic dispatch, no plugin abstraction, no per-tool framework. The eight scripts are eight standalone artifacts. A user can read any one of them in one sitting.
- **Tools are inline data, not a plugin system.** The tool inventory is a top-of-file array (or hash) read once. Adding a tool is one line; removing a tool is one line; auditing the inventory is reading the array. No `register_tool()` callbacks.
- **POSIX bash for Unix, PowerShell 7 for Windows.** No Python in the install path, no Go binary as a hard dependency, no third-party CLI required to run the installer. The Go TUI selector and the Python projector are post-install conveniences that live in their own packages.
- **No dispatcher.** The v1 `install.sh` exists because the three platform scripts share a name; with the eight v2 scripts named after their target, the user invokes the script for their target directly. There is no universal entrypoint, and that is correct: there is no universal install.
- **Configs are single-file canonical templates with no templating engine.** The Zsh and PowerShell profiles are written verbatim from the script. Variation is by env var or post-install user override, not by Jinja-shaped substitution.
- **One log format, one exit-code table, one rollback model.** All eight scripts share these via the shared library. A user who has used `glide-cut` already understands the logs, exit codes, and rollback story of `paper-slice`.
- **Delete the supply-chain-guard framework.** The v1 abstraction allowed four risk modes but only ever shipped one. v2's rule is hardcoded: no curl-pipe-bash, ever, in any posture. If a tool can only be installed by piping a script, it does not get installed by kniferoll. Document the exception, do not engineer around it.

### 6.2 Security

- **No `curl | bash` anywhere.** Every download lands as a file in a temp directory, gets its SHA256 verified against a checksum that is committed to the repo, and only then is executed (if executable) or moved into place (if a binary). The Homebrew bootstrap pattern in v1 (`download_to_tmp` + verified write) is the right pattern; v2 enforces it without exception.
- **Pinned versions and pinned checksums for every download.** No "latest." Bumping a version is an explicit PR with an updated checksum line. The Nerd Fonts soft-warn-and-continue pattern at `install_mac.sh:1369-1384` becomes a hard-fail.
- **Refuse to run as root unless explicitly invoked with `--root` and a documented reason.** The v1 scripts require sudo for individual operations (`sudo apt`, etc.) and that pattern continues — but the script itself runs as the user, never as root. `--root` is reserved for VM-bootstrap or container-image-build scenarios where there is no user yet.
- **Explicit handling of corp TLS interception in managed scripts only.** Managed scripts take a CA bundle path via `--ca-bundle` flag or `KR_CA_BUNDLE` env var (with auto-detection as fallback) and propagate it to: `CURL_CA_BUNDLE`, `SSL_CERT_FILE`, `NODE_EXTRA_CA_CERTS`, `REQUESTS_CA_BUNDLE`, `GIT_SSL_CAINFO`, `AWS_CA_BUNDLE`, `PIP_CERT`, `CARGO_HTTP_CAINFO` (Windows), `HOMEBREW_CURLOPT_CACERT` (macOS). Unmanaged scripts have no concept of a corp CA and refuse to read these env vars even if set — managed work belongs in managed scripts.
- **No silent overwrites of user dotfiles.** Every dotfile change creates a timestamped backup *and* prints the diff to stderr before applying. Dry-run mode prints the diff and does not apply.
- **Audit trail.** Every install writes a manifest to `~/.kniferoll/state/<codename>-<isots>.json`: tool name, version installed, source URL, SHA256 of downloaded artifact, install method, timestamp, exit status. `kniferoll status` (a small companion script) reads the most recent manifest and reports current state.
- **TLS 1.3 by default, TLS 1.2 fallback only in managed scripts.** Corporate proxies in 2026 should support TLS 1.3 nine years after RFC 8446. If they don't, that's a managed-script concern.
- **Network egress check in preflight.** A simple HEAD to a known-stable URL with the configured CA bundle. If it fails, abort before any partial install. Half-installs are worse than failures.

### 6.3 Beauty

- **Names matter.** The eight Knife Motions codenames are not decoration; they are part of the auditable surface. A log line that says `glide-cut: install brew (1/45)` is more humane than `install_mac.sh: install brew (1/45)` and more memorable than `phase-3-step-7`.
- **Output matters more than code.** The kitchen voice from `docs/FLAVOR.md` is preserved verbatim: one-liners for skip and success, box-bordered framing for security-relevant decisions, tactical not alarmist failure language. Variable names like `$GREEN`, `$ORANGE`, `$DIM` survive the rewrite. The Cyberwave palette stays.
- **The README is the doorway.** Single-page, demo-first, install-instruction-second. Do not put a feature matrix above the fold. The user should know in five seconds whether kniferoll is for them.
- **Filename hierarchy is human-readable.** `unmanaged-mac-applesilicon-glide-cut.sh` is long, and that's a feature: every part of the name carries information that a `ls` reveals.
- **Errors don't blame users.** "Could not install X — even the best chefs order takeout sometimes." stays. "Operation completed successfully" never appears.
- **Zero emoji in installer output.** The 🔪 in the README is fine; the installer prints only ASCII. Emoji renders inconsistently across terminals, themes, and SSH sessions, and that inconsistency is the opposite of beauty.
- **Documentation has voice.** ARCHITECTURE.md, FLAVOR.md, SUPPLY_CHAIN_RISK.md, and zscaler.md (in the private repo) all keep their first-person, declarative tone. Manifestos > manuals.

---

## 7. Per-script structure

Every one of the eight scripts follows the same skeleton. The skeleton lives as a documented contract in `lib/skeleton.md`; new scripts are diffs against the skeleton.

**Header block.** Shebang (`#!/usr/bin/env bash` or `#!/usr/bin/env pwsh`), strict mode (`set -Eeuo pipefail` for bash, `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` for PowerShell), then a 10-line comment header: codename, target, posture, version, build date, source repo URL, license, brief description, link to docs, hash of the shared lib version vendored.

**Preflight.** Six checks, in order, each with its own exit code:

1. OS check (`uname -s` / `$IsWindows`) — must match the script's target.
2. Arch check (`uname -m` / `$env:PROCESSOR_ARCHITECTURE`) — must match.
3. Shell version (bash ≥ 4 / PowerShell ≥ 7) — refuse otherwise.
4. Network egress (HEAD to `https://github.com/` with configured CA bundle) — abort if unreachable.
5. Posture check (managed scripts only): CA bundle resolvable from `--ca-bundle`, `KR_CA_BUNDLE`, or auto-detect path list.
6. Root check — refuse if EUID==0 and `--root` not passed.

Each preflight failure prints the specific reason and exits with the matching code (see exit-code table below). No preflight failure cascades into a half-install.

**Idempotency contract.** Running the script twice in succession on a clean state produces the same final state. Running it twice on a partially-completed state catches up the partial install without redoing finished work. Running it with `--force` reinstalls everything regardless of state.

**Mode flags** (uniform across all eight scripts):

- `--apply` (default): execute the install.
- `--dry-run`: print every step that would execute, every file that would change, every package that would be installed, every diff that would be applied — change nothing.
- `--check`: read the state manifest and report drift (what's installed, what's missing, what's out of sync) — change nothing.
- `--list`: print the tool inventory and exit.
- `--verbose`: enable per-step logging (default is per-phase).
- `--force`: re-execute install steps even if the state manifest says they're done.
- `--ca-bundle PATH` (managed only): explicit CA bundle path, overrides auto-detect.
- `--no-fonts`: skip the font installation phase (the longest phase).
- `--shell-only`: install only the shell environment (Zsh/PowerShell config + plugins + minimal tools).
- `--help`: usage and exit.

**Log format.** Every line: `<isots> <level> <codename> <phase> <step> | <message>`. Levels: `OK`, `INFO`, `WARN`, `SKIP`, `ERROR`. Logs go to stderr (for live tail) and to `~/.kniferoll/logs/<codename>-<isots>.log` (for after-the-fact audit). The split-terminal UI from `lib/split_terminal.sh` v1 is preserved as an opt-in (`--split-ui` flag), not a default — it's lovely but it conflicts with `--dry-run | less` and other piping patterns.

**Exit codes.**

| Code | Meaning |
|------|---------|
| 0 | Success. |
| 1 | User error (bad flag, bad path, etc.). |
| 2 | Preflight failed (OS / arch / shell / network / posture / root). |
| 3 | Download or checksum verification failed. |
| 4 | Mid-install failure (state is partial; manifest reflects partial). |
| 5 | Corp posture issue (managed scripts only): CA bundle invalid, splash page detected and not resolvable, MDM gate failed. |

**Rollback story.**

- **Reversible:** dotfile edits (every change has a timestamped backup; `kniferoll undo --dotfiles` restores the most recent backup); rc-block insertions (the AWK sweep can strip them on demand).
- **Not auto-reversible but trackable:** package installs (the manifest records what was installed; users can `apt remove` / `brew uninstall` / `Uninstall-Package` from the manifest list).
- **Documented:** what is and is not in each category lives in the README. No surprise irreversibility.

---

## 8. Competitive analysis

Eleven projects in the adjacent space. For each: what it does, where it beats kniferoll, where it loses, where it doesn't compete.

**chezmoi.** Mature dotfile manager: Go binary, templated dotfiles, encrypted secrets, declarative state, cross-platform. Beats kniferoll on dotfile sync (kniferoll has no concept of "sync these dotfiles across my three machines"). Loses on tool installation — chezmoi will run a script for you but won't tell you which tools to install. Different concern, no real overlap; a user can use both.

**dotbot.** Lighter dotfile manager, YAML config, Python. Same shape as chezmoi without the templating sophistication. Beats kniferoll on simplicity-of-dotfile-only, loses on everything else. Niche overlap.

**yadm.** Git-based dotfile manager. Treats `~` as a git working tree with a separate metadata directory. Beats kniferoll on transparency for git-native users, loses on tool installation. Niche overlap.

**GNU stow.** Symlink farm manager — point it at a dotfiles repo, it symlinks the contents into `~`. Bulletproof, manual, ancient, perfect for what it does. Beats kniferoll on "just give me symlinks." Loses on tool installation, on platform-specific logic, on Windows entirely. Useful as a *backend* — kniferoll v2 could optionally use stow under the hood for dotfiles, though the marginal win is small.

**Ansible (for personal use).** YAML playbooks, idempotent, runs over SSH or locally. Heavy: requires Python, requires the user to learn Ansible's mental model, optimized for fleet management. Beats kniferoll on "I already run Ansible at work and want my laptop in the same playbook." Loses on time-to-first-success for someone who has never seen Ansible. If a user has the Ansible muscle memory, kniferoll is not what they want.

**nix-darwin / Home Manager / nix flakes.** The most ambitious tool in the space: a fully declarative, reproducible, content-addressable system. Beats every other tool in the category on reproducibility and on "my machine is exactly this configuration." Loses on learning curve (Nix is a programming language and a package manager and a build system at once), on debuggability, on corporate-environment friction (Nix's substituters and TLS handling are a known source of pain in TLS-inspecting environments). If a user has invested in Nix, kniferoll is not what they want. If they haven't, kniferoll's whole pitch is "the simple version of this idea." A real but coexistent alternative.

**Homebrew Bundle / Brewfile.** A `Brewfile` lists what `brew bundle` should install. Beats kniferoll on "I just want a list of brew packages" — Brewfile is exactly that. Loses on Linux (Linuxbrew exists but is awkward), on Windows (no Homebrew), on dotfiles, on shell setup, on corp-CA. kniferoll v2 could *generate* a Brewfile as a side artifact for users who want one; that would be a small, polite addition.

**scoop + winget + Chocolatey.** Three Windows package managers. Each beats kniferoll on "I just want to install this one package." kniferoll's value is the curated selection and the dotfile/profile setup that wraps the install. The v2 Windows scripts (`broad-stroke`, `clean-pass`) use winget primary, Scoop secondary, Chocolatey not at all (its UAC self-elevation is a security smell). The pipeline pattern from v1 is preserved.

**devbox / mise / asdf.** Per-project runtime version managers. Beats kniferoll on "I need three Node versions for three projects." Different concern entirely; mise was actively *removed* from v1 due to supply-chain risk, and v2 does not bring it back. Users who want runtime version management add it themselves post-install; kniferoll does not own that surface.

**omakub.** Opinionated Ubuntu dev box installer (DHH's project). Beats kniferoll on "I want a beautiful one-shot Ubuntu setup with strong opinions." Loses on multi-OS (Ubuntu only), on Windows (zero), on managed/corporate posture. The closest direct analog to kniferoll's spirit but in a single platform. If a user is on Ubuntu and likes DHH's taste, omakub is the better choice. kniferoll is the answer when you want the same energy across four platforms with corp-aware sister scripts.

**dotfiles.io / ThePrimeagen-style init repos / atuin's bootstrap.** Personal dotfiles repos and tool-specific bootstraps. Beats kniferoll on "this is exactly how a famous dev configures their machine." Loses on being your own machine. kniferoll is a recipe; these are someone else's plate. They occupy adjacent shelves.

### 8.1 Where kniferoll v2 fits

kniferoll v2's niche is **opinionated, multi-OS, corp-CA-aware, beautiful, single-step terminal-environment setup for security/dev/SRE practitioners who work across personal and corporate machines**. The four-target × two-posture matrix is the differentiator: no other tool in this list cleanly handles "I have a personal MacBook, a work Windows laptop with Zscaler, and a Raspberry Pi 4 in my closet running Ubuntu" with matched-quality first-class scripts for each.

The realistic user is someone who:
- works in security or backend dev or SRE,
- moves between personal and corp machines weekly,
- wants Zsh + Oh-My-Zsh + a curated tool set (fzf, zoxide, ripgrep, bat, lsd, tmux, btop, jq, gh, starship, …),
- needs corporate TLS interception to *just work* without a half-day of CA-cert spelunking,
- values a beautiful terminal experience but does not want to maintain a Nix flake,
- reads shell scripts and wants the installer to be readable.

That user reaches for omakub on personal Ubuntu, for chezmoi for dotfile sync across machines, for nix-darwin if they've already drunk the Nix kool-aid — and for none of them when they need cross-platform corp-aware bootstrap. kniferoll v2 owns that gap.

If the user is a Nix devotee, kniferoll is wrong. If the user is on a single platform and wants the absolute minimum, Brewfile or omakub is better. If the user just wants dotfile sync, chezmoi wins. kniferoll is for the user who wants one named tool that does the whole opinionated terminal-environment-bootstrap job across their fleet.

---

## 9. Open questions

Decisions deferred to Chef. The first three are the ones I most want input on before phase 1 starts.

1. **Naming theme confirmation.** I have chosen Knife Motions and assigned all eight names with defenses. The runners-up were Whetstone Grits and Brigade Stations. If you prefer a different theme or want to adjust individual mappings (e.g., swap `glide-cut`/`paper-slice` between unmanaged and managed Mac), this is the moment.
2. **Repo split confirmation.** Default: public `albethere/kniferoll` + private `albethere/kniferoll-galley`. The alternative I considered and rejected was a monorepo with a private branch / private subtree — I think the visibility seam is too important to leave porous, but if you have a strong policy reason to monorepo (e.g., audit-trail unification, DR posture), I'll adjust.
3. **WSL2 status.** I propose folding WSL2 into `unmanaged-debian-draw-line.sh` (and the managed equivalent if the corp uses WSL2) with a small `if-wsl` branch. The alternative is making WSL2 a ninth target (`unmanaged-wsl2-knifeplay.sh`?). My take is that WSL2 is Debian/Ubuntu in a Microsoft hypervisor and does not deserve its own script, but Chef may know things about the corp WSL2 setup that I don't.
4. **Vendoring vs submodule for the public lib in the private repo.** I propose vendoring (committed `vendor/kniferoll/` directory + manifest hash). The alternatives are git submodule (live but spookier on clone) or a curl-fetch-at-install (security-fragile). Confirm.
5. **TUI selector and projector — keep, fold, or split?** v1 bundles a Go TUI selector and a Python projector that have nothing to do with the install proper. My recommendation is to split both into separate repos: `kniferoll-shell` (the post-install shell-experience runtime, which would own zoxide/starship/aliases-as-code) and `kniferoll-projector` (the animation orchestrator). This lets the v2 install scripts stay shell-native and dependency-light.
6. **Old `terminal-kniferoll` repo disposition.** Keep on the `main` branch as a frozen v1 reference, or delete in favor of v2? I recommend keeping it: it's documentation of "what we used to do and why." Tag the last v1 commit as `v1-final` and let it rest.
7. **Inventory bumps from v1 to v2.** v1 is dropping atuin and mise (already done). v2 should make explicit decisions about: Anthropic Claude CLI (currently winget-only on Windows; should it be cross-platform now?), `gum` (Windows-only in v1; promote to all platforms or remove?), the AI-CLI bucket (gemini-cli, claude — is this a v2 first-class category or an opt-in module?). I'd like Chef's call before phase 5.
8. **Telemetry stance.** No telemetry, ever, in any posture. I want this written into ARCHITECTURE.md as a one-line non-negotiable. Confirm.
9. **`kniferoll` as the new name.** Drop the `terminal-` prefix from the project, the binary, the repo. The prefix is redundant — what else would a knife roll be? Confirm or push back.
10. **Corp-side hostname/policy file format.** Managed scripts will accept a small `kniferoll-corp.toml` (or .json) at `/etc/kniferoll/corp.toml` or `~/.config/kniferoll/corp.toml` defining: CA bundle path, internal package mirror URLs, splash-page selectors, MDM-detection commands. Format and precedence to be designed in phase 5.

---

## 10. Phasing

Sequenced by what unlocks the most learning fastest, not by OS.

**Phase 0 — Approval.** Chef reviews this plan. Open questions resolved. Naming theme locked. Repo strategy approved. No code yet.

**Phase 1 — Skeleton and codenames.** Public repo created at `albethere/kniferoll`. Empty scaffolding for all four unmanaged scripts (header, preflight, mode flags, exit codes, log format, no install logic yet). Shared library `lib/` lifted from v1 with the obvious deletions (the half-finished supply-chain guard, the duplicate sweep). README, FLAVOR.md, ARCHITECTURE.md transferred and updated. Goal: a user can clone the repo, run `unmanaged-debian-draw-line.sh --dry-run`, and see the skeleton produce empty output without errors.

**Phase 2 — First slice (`draw-line`).** Implement `unmanaged-debian-draw-line.sh` end-to-end. apt + cargo + curated GitHub releases + Zsh setup + dotfile rendering + manifest + dry-run + check + force. This is the reference implementation. Every later script is a diff against this. Chosen for first because: (a) Debian/Ubuntu is the highest-volume target, (b) apt is the most predictable package manager, (c) the v1 Linux script is the canonical and best-tested.

**Phase 3 — Same hand, new arch (`push-cut`).** Implement `unmanaged-arch-push-cut.sh`. pacman + AUR helper detection. The shared inventory data structure is exercised for the first time across two distros; this stresses the "tools are inline data" principle. Bugs found here are reflected back into `draw-line`.

**Phase 4 — Cross the threshold (`glide-cut`).** Implement `unmanaged-mac-applesilicon-glide-cut.sh`. Homebrew. Different file paths (`~/.zshrc` vs `~/.zprofile` precedence, `/opt/homebrew` prefix, iTerm2 colorscheme deployment). The shared library proves itself across two OS families.

**Phase 5 — Mind the proxy (`fine-dice`).** Private repo created at `albethere/kniferoll-galley`. Public lib vendored. Implement `managed-debian-fine-dice.sh`. Corp-CA detection, propagation, splash-page handling, internal-mirror routing. Goal: get the corp posture *exactly right* on one script before extending to others. The corp-CA propagation is the highest-stakes code in v2; phase 5 is where it's invented.

**Phase 6 — Fill the matrix (`paper-slice`, `slow-pull`).** Port the corp-CA work from `fine-dice` into `managed-mac-applesilicon-paper-slice.sh` and `managed-arch-slow-pull.sh`. By now the pattern is set; these are diffs against `fine-dice` and their unmanaged twins.

**Phase 7 — Other shore (`broad-stroke`, `clean-pass`).** Windows. PowerShell 7. winget. Scoop. Both unmanaged and managed in the same phase because the corp-CA work for Windows is sufficiently different from Unix (cert store enumeration, `CARGO_HTTP_CAINFO`, group-policy paths) that it benefits from being designed against both audiences at once. This phase is the longest because PowerShell is foreign to most of the project's muscle memory.

**Phase 8 — Ship.** Demo GIFs. README polish. CI for the unmanaged repo. Smoke tests for the managed repo. Tag v1 of v2 (`v2.0.0`). Frozen v1 repo gets a `README` pointer to the new repos. Beads tracker updated. Done.

The phasing front-loads the highest-risk work (corp-CA in phase 5) only *after* the unmanaged shape is locked in three platforms. This means the corp design has three working examples to defend against, and the corp work is not allowed to leak back into the unmanaged path. That separation is the rewrite's central structural bet, and the phasing is built to enforce it.

---

## Verification

Plan-level verification before any code is written:

- Walk Chef through this document and resolve the open questions in section 9.
- Confirm naming theme and the eight assignments.
- Confirm repo split and ownership.
- Confirm WSL2, projector, and TUI dispositions.

Code-level verification per phase:

- Each script has a `--dry-run` that produces parseable output covered by a smoke test.
- Each script has a `--check` that reports drift against its own manifest.
- Each script's preflight has a unit-testable failure path for every exit code (2.1 through 2.6).
- The shared lib has a test suite ported and modernized from v1's `scripts/test-sweep.{sh,ps1}`.
- Phase 5's corp-CA propagation has integration tests that simulate a TLS-inspecting proxy (mitmproxy with a self-signed CA) and verify every propagated env var is set, every tool can curl through, and the manifest reflects the bundle source.

---

## Critical files referenced

- `~/Projects/terminal-kniferoll/install.sh:39-61` — entrypoint dispatch.
- `~/Projects/terminal-kniferoll/install_mac.sh:175-257, 297-359, 368-437, 1008-1050, 1038-1042, 1089-1106, 1369-1384` — auto-accept fragility, TLS preflight hard gate, corp-CA detection, brew bootstrap, share-perms hardening, oh-my-zsh fallback, fonts soft-warn.
- `~/Projects/terminal-kniferoll/install_linux.sh:355-423, 708-752, 980-1010` — Linux corp-CA detection, Linuxbrew bootstrap, sweep call sites.
- `~/Projects/terminal-kniferoll/install_windows.ps1:64-90, 664-859, 774-803, 1579-1630, 2068-2242, 2569-2677` — Win preflight, corp-CA detection, cert-store import, package bootstrap chain, profile content, gum menu.
- `~/Projects/terminal-kniferoll/lib/rc_sweep.sh:21, 31-45, 98-138, 218-247` — older sweep API, backup pruning, upsert logic.
- `~/Projects/terminal-kniferoll/lib/supply_chain_guard.sh:21, 33-47, 53-57` — hardcoded strict mode, sc_install bypass, deferred-stub.
- `~/Projects/terminal-kniferoll/scripts/lib/sweep-zscaler.{sh,awk}` — modern intended sweep.
- `~/Projects/terminal-kniferoll/docs/{ARCHITECTURE,FLAVOR,SUPPLY_CHAIN_RISK,zscaler}.md` — design intent.
- `~/Projects/terminal-kniferoll/CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.github/copilot-instructions.md` — agent instructions, FSH-last rule, idempotency mandate.
