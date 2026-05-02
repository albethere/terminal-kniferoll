# terminal-kniferoll v2 — Design Plan

## Context

`terminal-kniferoll` is the standalone, multi-platform terminal-environment installer at `~/Projects/terminal-kniferoll` (GitHub: `albethere/terminal-kniferoll`). Today it ships three monolithic install scripts — `install_mac.sh` (1,473 lines), `install_linux.sh` (1,635 lines), `install_windows.ps1` (2,748 lines) — plus a shared `lib/`, a Go TUI selector, a Python projector, and a tightly maintained set of voice/architecture/risk docs. The current repo is ~5,900 lines of installer code wrapped around what is, conceptually, a relatively small set of choices.

The current version works. That is not the same as it being right. Three years of layered hotfixes — Zscaler hard-gating, dual sweep parsers, supply-chain guards that are half-implemented, fragile platform detection branches, no real dry-run on Unix, no rollback story, soft-warn fallbacks for fonts that have no published checksums — have produced a system whose behavior nobody can hold in their head all at once. The recent git log is dominated by commits like `fix(linux): add cmp -s guard in upsert_rc_zscaler_block` and `fix(mac): remove configure_tool_certs; install rustup via brew` — these are not features. They are the smell of a design that has accumulated more responsibilities than its skeleton can carry cleanly.

This document proposes a complete from-scratch rewrite. The rewrite splits the project on the two axes that actually matter — operating system (4) and security posture (managed/unmanaged, 2) — into eight standalone scripts, each one short enough to read in one sitting. It defines a flat naming convention, a per-repo split that hard-segregates corporate assumptions out of the public surface, three governing principles in priority order (simplicity, security, beauty), a per-script skeleton, a competitive landscape positioning, an explicit list of decisions deferred to Chef, and a phasing plan that sequences by learning velocity rather than by platform.

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

The rewrite addresses all eight of these points by collapsing the matrix, separating the postures into independent repos, deleting the half-finished abstractions, and making each individual script short enough that the entire thing fits on one screen of mental working set.

---

## 3. Target matrix

Eight scripts. Four operating-system targets crossed with two security postures. No further axes — architecture (x86_64 / aarch64) is handled inside the Linux scripts as a matrix dimension, not a separate file, because the divergence is small and the duplication would buy nothing.

| OS target | Posture | Filename | Notes |
|-----------|---------|----------|-------|
| macOS (Apple Silicon, arm64) | unmanaged | `kniferoll-mac.sh` | Homebrew on arm64; assumes user is admin of their machine. |
| macOS (Apple Silicon, arm64) | managed | `kniferoll-managed-mac.sh` | Adds Zscaler/corp-CA detection, MDM-aware preflight, TLS-1.2 fallback. |
| Windows 10/11 (x86_64) | unmanaged | `kniferoll-windows.ps1` | PowerShell 7+, winget primary, Scoop secondary. |
| Windows 10/11 (x86_64) | managed | `kniferoll-managed-windows.ps1` | Adds corp-CA cert-store enumeration, `CARGO_HTTP_CAINFO`, group-policy-aware paths. |
| Linux Debian/Ubuntu (x86_64 + aarch64) | unmanaged | `kniferoll-linux-deb.sh` | apt + cargo + selective GitHub releases; arch-aware in the inventory. |
| Linux Debian/Ubuntu (x86_64 + aarch64) | managed | `kniferoll-managed-linux-deb.sh` | Adds Zscaler/corp-CA paths under `/usr/local/share/ca-certificates/`, internal apt mirrors as a flag. |
| Linux Arch-family (x86_64 + aarch64) | unmanaged | `kniferoll-linux-arch.sh` | pacman + AUR helper detection; CachyOS, EndeavourOS, Manjaro all welcome. |
| Linux Arch-family (x86_64 + aarch64) | managed | `kniferoll-managed-linux-arch.sh` | Same as above plus corp posture. Edge case: rolling release means version pins are looser; documented. |

### 3.1 Why Intel macOS is out of scope

Apple stopped shipping new Intel Macs in 2023. Apple announced the end of macOS Intel support for the next major release. By the time v2 of kniferoll is in active maintenance (mid-2026 onward), the Intel-Mac population among the kniferoll user base is statistically zero — the user community is dev/security/SRE on personal or corp-issued laptops, all of which are Apple Silicon for purchases in the last three years. Maintaining a script for a deprecated and shrinking arch is non-trivial: Homebrew's arm64 vs x86_64 prefix difference (`/opt/homebrew` vs `/usr/local`), the Rosetta translation surface, and the third-party-tool support gap (e.g., several Nerd Font and cargo crates have only arm64 native binaries) all add expense. The right call is: explicitly out of scope; users on Intel Mac fork the script if they need it.

### 3.2 Why arch is a matrix dimension on Linux but not a separate file

x86_64 and aarch64 differ on Linux in three ways relevant to kniferoll: (a) some apt/pacman packages have different names or different availability; (b) some GitHub-release assets are only published for one arch; (c) rustup behaves differently. None of these justify file-level duplication. Each is a per-tool conditional in a tools-inventory data structure: `if [[ $ARCH == aarch64 ]]; then SKIP some_x86_only_tool; fi`. Splitting into four Linux files instead of two would double the maintenance surface for a divergence that is minor and shrinking.

### 3.3 What the matrix excludes and why

- **WSL2** is folded into `kniferoll-linux-deb.sh` (and `kniferoll-managed-linux-deb.sh` if used in a corp environment) with a small `if-wsl` block that adjusts a few paths. WSL2 is Debian/Ubuntu running on a Microsoft hypervisor. It is not its own platform. (Open question: confirm with Chef.)
- **NixOS / nix-darwin** is excluded — Nix users have a different system model and a vastly more capable installer (Home Manager). v2 should not pretend to compete in that space.
- **FreeBSD / OpenBSD / Alpine / Fedora-RHEL family** are excluded as targets. They each have small but meaningful differences (different libc on Alpine, dnf on Fedora, ports on FreeBSD) that would each require a dedicated script. The four targets above cover ~95% of the kniferoll user base; the rest are documented as "you are welcome to fork."

---

## 4. Naming

### 4.1 Decision: flat, descriptive, no codename layer

The eight scripts are named for what they are, not for what they evoke. Each name is `kniferoll-<os-family>` for the unmanaged posture, or `kniferoll-managed-<os-family>` for the managed posture. The filename is the documentation; there is no separate codename a user has to learn.

| Posture | OS family | Script |
|---------|-----------|--------|
| unmanaged | macOS Apple Silicon | `kniferoll-mac.sh` |
| unmanaged | Windows | `kniferoll-windows.ps1` |
| unmanaged | Linux Debian/Ubuntu (x86_64 + aarch64) | `kniferoll-linux-deb.sh` |
| unmanaged | Linux Arch-family (x86_64 + aarch64) | `kniferoll-linux-arch.sh` |
| managed | macOS Apple Silicon | `kniferoll-managed-mac.sh` |
| managed | Windows | `kniferoll-managed-windows.ps1` |
| managed | Linux Debian/Ubuntu (x86_64 + aarch64) | `kniferoll-managed-linux-deb.sh` |
| managed | Linux Arch-family (x86_64 + aarch64) | `kniferoll-managed-linux-arch.sh` |

### 4.2 Why flat instead of themed

A codename family (Knife Motions: glide-cut, paper-slice, broad-stroke, clean-pass, draw-line, fine-dice, push-cut, slow-pull) was considered and rejected. Codenames have one advantage — memorable shorthand in conversation — and several costs: a user has to learn the mapping; SEO suffers ("which one is fine-dice?"); the names age poorly if the metaphor stops fitting; and they introduce a layer of indirection the auditable surface doesn't need. Flat names invert all four: zero learning cost, perfect SEO, no metaphor to maintain, and the filename answers "what does this script do" by itself.

The kitchen voice from `docs/FLAVOR.md` survives entirely in installer output, in error messages, in documentation. The scripts can call themselves `kniferoll-mac` and still print `"Slicing through dependencies..."` when they're working. Naming and voice are separate concerns; flattening one doesn't dilute the other.

### 4.3 Filename convention

Each Unix script ends in `.sh`; the Windows scripts end in `.ps1`. The pattern is `kniferoll[-managed]-<os-family>.<ext>`. `mac` is unambiguous — Apple Silicon is the only supported Mac arch. `linux-deb` covers Debian, Ubuntu, and their derivatives; `linux-arch` covers Arch, EndeavourOS, Manjaro, CachyOS. `windows` is x86_64 only. Architecture (x86_64 vs aarch64) is handled inside the Linux scripts as a runtime branch, not as a separate file.

---

## 5. Repo strategy

### 5.1 Recommendation: eight repos under `silo-agent`

The naming flattening makes a corresponding repo flattening natural. Each script lives in its own repo under the `silo-agent` GitHub account. There is no separate library repo: the shared `lib/` lives inside `kniferoll-linux-deb` (the reference implementation) and is vendored into the other seven repos at a specific tag. Visibility splits cleanly along the posture seam: the four unmanaged repos are public; the four managed repos are private.

**Public repos (4):**

- `silo-agent/kniferoll-mac`
- `silo-agent/kniferoll-windows`
- `silo-agent/kniferoll-linux-deb` — also hosts the shared `lib/`: download-and-verify, RC-block sweep, log format, exit-code helpers, manifest writer. Each tagged release (`v0.1.0`, `v1.0.0`, …) is simultaneously "the script at version X" and "the lib at version X." The other seven repos vendor `lib/` from a specific `kniferoll-linux-deb` tag.
- `silo-agent/kniferoll-linux-arch`

**Private repos (4):**

- `silo-agent/kniferoll-managed-mac`
- `silo-agent/kniferoll-managed-windows`
- `silo-agent/kniferoll-managed-linux-deb`
- `silo-agent/kniferoll-managed-linux-arch`

**Account shape.** `silo-agent` is currently a personal GitHub account, with potential to become an organization later. The plan keeps options open: the access-grant commands in §5.5 use the per-collaborator form, which works against both personal accounts and orgs. If/when `silo-agent` converts to an org, swap to the team-based form for less per-repo bookkeeping.

**Admin grants:** the `albethere` account (email `hello@silocrate.com`) gets full admin on every one of the eight repos. This is a permission-modification action and falls outside what kniferoll's design tooling will issue automatically — see §5.5 for the exact `gh` commands you (Chef) need to run after the repos are created.

### 5.2 Defense of the per-script split

A single monorepo can't hold this matrix cleanly because the public/private seam is too important to leave porous: managed scripts contain corporate hostnames, internal mirrors, MDM probes, and the *shape* of a corporate trust store, none of which belongs on the open internet. A two-repo split (one public catch-all, one private catch-all) was an earlier proposal; it works, but a per-script split has three concrete advantages worth the additional scaffolding cost:

1. **Independent versioning.** `kniferoll-mac@1.4.2` and `kniferoll-linux-deb@1.7.0` evolve at their own cadences. A bug in one OS's package layer doesn't pin the others to wait for a coordinated release.
2. **Granular access.** A specific contractor needs Linux-Debian access only? Grant it on one repo. No "everyone gets everything" pressure on shared resources.
3. **No accidental leakage.** Managed repos are physically separated from unmanaged. No shared CI yaml, no shared README, no risk of a corp hostname slipping into a public-facing file because someone forgot which directory they were editing in.

The cost is real and worth flagging: 8× the README scaffolding, 8× the CI workflow, and a release-coordination overhead that the two-repo split avoided. The shared `lib/` inside `kniferoll-linux-deb` absorbs most of the duplication at the code level — it becomes a versioned dependency rather than copy-pasted scaffolding — but each script repo still owns its own platform-specific concerns, its own tests, its own docs. The trade is intentional: more scaffolding, much cleaner audit boundaries.

### 5.3 Boundary rules

Public repos never reference:
- corporate hostnames, IPs, or DNS suffixes
- specific corp-CA filenames or paths
- MDM-detection commands or expectations
- internal apt mirrors, Artifactory hosts, or internal package registries
- the words "Zscaler," "ZIA," "ZPA," or any specific proxy vendor

Public repos may reference, generically:
- "If you are behind a corporate TLS-inspecting proxy, see the matching `kniferoll-managed-*` repo (private)."
- The standard env vars (`CURL_CA_BUNDLE`, `NODE_EXTRA_CA_CERTS`, etc.) — these are documented features of the upstream tools, not corporate secrets.

The `lib/` inside `kniferoll-linux-deb` is public and posture-agnostic: no function in it may take a corporate-shaped argument, depend on the existence of a corp environment variable, or hardcode a path under `/usr/local/share/ca-certificates/`. The library provides neutral primitives (download-and-verify, write-rc-block, check-tool-installed, log-with-format, write-manifest) that the managed scripts compose with their corporate logic in their own repos.

### 5.4 Discoverability and shared code reuse

Per-script repos lose the single-front-door discoverability of one umbrella repo. Mitigations:

- A pinned topic on every public repo (`topic:kniferoll`) so GitHub's tag search returns the family.
- Consistent naming (`kniferoll-*`) so a `gh search repos kniferoll` answers "what's the family" in one query.
- Each public repo's README includes a "Family" section linking to the three other public repos.
- The `kniferoll-linux-deb` README is the de facto project home page (since it carries the shared lib): it explains the architecture, links to all four public scripts, and points at the private overlays as "consult your corporate IT for access if applicable."

Shared code reuse is via `kniferoll-linux-deb` semver tags. Updating the lib means tagging a release of `kniferoll-linux-deb`; bumping a script's lib pin is a one-line PR in that consumer script's repo. The vendored copy and its checksum manifest are regenerated and committed in the same PR. No live submodules, no curl-fetch-without-checksum.

### 5.5 GitHub repo creation, access grants, and discoverability — what Chef runs

These commands stand up the eight repos, grant `albethere` admin access, and apply the discovery topic. Run them yourself authenticated as `silo-agent` (`gh auth status` to confirm). Modifying access controls and granting permissions on shared resources is on the prohibited-actions list, so the design tooling will not issue them automatically.

**Step 1 — create the four public repos:**

```
for r in kniferoll-mac kniferoll-windows kniferoll-linux-deb kniferoll-linux-arch; do
  gh repo create silo-agent/$r --public \
    --description "Opinionated terminal-environment installer ($r)"
done
```

**Step 2 — create the four private repos:**

```
for r in kniferoll-managed-mac kniferoll-managed-windows \
         kniferoll-managed-linux-deb kniferoll-managed-linux-arch; do
  gh repo create silo-agent/$r --private \
    --description "Corporate-CA-aware terminal-environment installer ($r)"
done
```

**Step 3 — grant `albethere` admin on all eight (per-collaborator form, works for personal account or org):**

```
for r in kniferoll-mac kniferoll-windows kniferoll-linux-deb kniferoll-linux-arch \
         kniferoll-managed-mac kniferoll-managed-windows \
         kniferoll-managed-linux-deb kniferoll-managed-linux-arch; do
  gh api repos/silo-agent/$r/collaborators/albethere -X PUT -f permission=admin
done
```

**Step 4 — apply discoverability topics to the four public repos:**

```
for r in kniferoll-mac kniferoll-windows kniferoll-linux-deb kniferoll-linux-arch; do
  gh api repos/silo-agent/$r/topics -X PUT \
    -f names='["kniferoll","terminal","installer","dotfiles","zsh","powershell"]'
done
```

**If `silo-agent` becomes a GitHub organization later,** swap step 3 for the team-based form, which is less per-repo bookkeeping when `albethere` should always have admin:

```
# (after silo-agent is converted to org and an `admins` team containing albethere exists)
for r in kniferoll-mac kniferoll-windows kniferoll-linux-deb kniferoll-linux-arch \
         kniferoll-managed-mac kniferoll-managed-windows \
         kniferoll-managed-linux-deb kniferoll-managed-linux-arch; do
  gh api orgs/silo-agent/teams/admins/repos/silo-agent/$r -X PUT -f permission=admin
done
```

The per-collaborator form in step 3 above is what to run today.

---

## 6. Architectural principles

The rewrite is governed by three values, in priority order: **simplicity, security, beauty**.

### 6.1 Simplicity

- **One script per (OS × posture).** No dynamic dispatch, no plugin abstraction, no per-tool framework. The eight scripts are eight standalone artifacts. A user can read any one of them in one sitting.
- **Tools are inline data, not a plugin system.** The tool inventory is a top-of-file array (or hash) read once. Adding a tool is one line; removing a tool is one line; auditing the inventory is reading the array. No `register_tool()` callbacks.
- **POSIX bash for Unix, PowerShell 7 for Windows.** No Python in the install path, no Go binary as a hard dependency, no third-party CLI required to run the installer. The Go TUI selector and the Python projector are post-install conveniences that live in their own packages.
- **No dispatcher.** The v1 `install.sh` exists because the three platform scripts share a name; with v2 each repo holds exactly one script named after its target, the user clones and invokes that script directly. There is no universal entrypoint, and that is correct: there is no universal install.
- **Configs are single-file canonical templates with no templating engine.** The Zsh and PowerShell profiles are written verbatim from the script. Variation is by env var or post-install user override, not by Jinja-shaped substitution.
- **One log format, one exit-code table, one rollback model.** All eight scripts share these via the `lib/` shipped in `kniferoll-linux-deb` and vendored into the other seven. A user who has used `kniferoll-linux-deb` already understands the logs, exit codes, and rollback story of `kniferoll-managed-mac`.
- **Delete the supply-chain-guard framework.** The v1 abstraction allowed four risk modes but only ever shipped one. v2's rule is hardcoded: no curl-pipe-bash, ever, in any posture. If a tool can only be installed by piping a script, it does not get installed by kniferoll. Document the exception, do not engineer around it.

### 6.2 Security

- **No `curl | bash` anywhere.** Every download lands as a file in a temp directory, gets its SHA256 verified against a checksum that is committed to the repo, and only then is executed (if executable) or moved into place (if a binary). The Homebrew bootstrap pattern in v1 (`download_to_tmp` + verified write) is the right pattern; v2 enforces it without exception.
- **Pinned versions and pinned checksums for every download.** No "latest." Bumping a version is an explicit PR with an updated checksum line. The Nerd Fonts soft-warn-and-continue pattern at `install_mac.sh:1369-1384` becomes a hard-fail.
- **Refuse to run as root unless explicitly invoked with `--root` and a documented reason.** The v1 scripts require sudo for individual operations (`sudo apt`, etc.) and that pattern continues — but the script itself runs as the user, never as root. `--root` is reserved for VM-bootstrap or container-image-build scenarios where there is no user yet.
- **Explicit handling of corp TLS interception in managed scripts only.** Managed scripts take a CA bundle path via `--ca-bundle` flag or `KR_CA_BUNDLE` env var (with auto-detection as fallback) and propagate it to: `CURL_CA_BUNDLE`, `SSL_CERT_FILE`, `NODE_EXTRA_CA_CERTS`, `REQUESTS_CA_BUNDLE`, `GIT_SSL_CAINFO`, `AWS_CA_BUNDLE`, `PIP_CERT`, `CARGO_HTTP_CAINFO` (Windows), `HOMEBREW_CURLOPT_CACERT` (macOS). Unmanaged scripts have no concept of a corp CA and refuse to read these env vars even if set — managed work belongs in managed scripts.
- **Internal-repos toggle (managed scripts only, off by default in v2.0).** Managed scripts include code paths for routing all package fetches through internal mirrors instead of public registries: apt sources lists, pacman repos, `CARGO_REGISTRIES_*`, npm registry URL, pip index URL, GitHub binary mirrors, Homebrew tap rewrites. The switch is `KR_INTERNAL_REPOS=1` env var or `--internal-repos` flag, fed by the corp policy file (open question §9.8). **In v2.0 the switch ships off**: managed scripts work end-to-end against public sources just like their unmanaged twins. The internal-mirror code paths exist, are syntactically valid, and have unit tests, but are not enabled until a follow-up release when corporate-mirror configuration is testable. This is intentional — managed scripts ship and are useful even without internal-mirror infrastructure ready, and the toggle is added as a discrete, testable change later (phase 9).
- **No splash-page bypass.** v1 included logic to auto-parse and submit Zscaler splash-page forms (`install_mac.sh:175-257`). v2 deliberately removes this. Setting up a managed shell does not require automated consent-page traversal — if a splash page intercepts an install-time download, the script errors with exit code 5 and instructs the user to open the URL in their browser, accept the splash page, and re-run. Auto-clicking through corporate consent screens is the kind of impersonation that should never live in this tool, even when it's convenient and even when v1 had it.
- **No silent overwrites of user dotfiles.** Every dotfile change creates a timestamped backup *and* prints the diff to stderr before applying. Dry-run mode prints the diff and does not apply.
- **Audit trail.** Every install writes a manifest to `~/.kniferoll/state/<script-name>-<isots>.json`: tool name, version installed, source URL, SHA256 of downloaded artifact, install method, timestamp, exit status. A `kniferoll status` companion script (shipped in `kniferoll-linux-deb/lib/` and vendored alongside `lib/` in every other repo) reads the most recent manifest and reports current state.
- **TLS 1.3 by default, TLS 1.2 fallback only in managed scripts.** Corporate proxies in 2026 should support TLS 1.3 nine years after RFC 8446. If they don't, that's a managed-script concern.
- **Network egress check in preflight.** A simple HEAD to a known-stable URL with the configured CA bundle. If it fails, abort before any partial install. Half-installs are worse than failures.

### 6.3 Beauty

- **Names are flat, not metaphorical.** `kniferoll-managed-linux-deb.sh` tells a reader the project (kniferoll), the posture (managed), and the OS family (linux-deb) without learning a codename map. The metaphor lives in the project name; the eight scripts inherit it without each needing their own alias.
- **Output matters more than code.** The kitchen voice from `docs/FLAVOR.md` is preserved verbatim: one-liners for skip and success, box-bordered framing for security-relevant decisions, tactical not alarmist failure language. Variable names like `$GREEN`, `$ORANGE`, `$DIM` survive the rewrite. The Cyberwave palette stays.
- **The README is the doorway.** Single-page, demo-first, install-instruction-second. Do not put a feature matrix above the fold. The user should know in five seconds whether kniferoll is for them.
- **Filename hierarchy is human-readable.** `kniferoll-managed-linux-deb.sh` is short and explicit — a reader sees the project, the posture, and the OS without learning anything new. The file name is its own table of contents.
- **Errors don't blame users.** "Could not install X — even the best chefs order takeout sometimes." stays. "Operation completed successfully" never appears.
- **Zero emoji in installer output.** The 🔪 in the README is fine; the installer prints only ASCII. Emoji renders inconsistently across terminals, themes, and SSH sessions, and that inconsistency is the opposite of beauty.
- **Documentation has voice.** ARCHITECTURE.md, FLAVOR.md, SUPPLY_CHAIN_RISK.md, and zscaler.md (in the private repos) all keep their first-person, declarative tone. Manifestos > manuals.

---

## 7. Per-script structure

Every one of the eight scripts follows the same skeleton. The skeleton lives as a documented contract at `kniferoll-linux-deb/lib/SKELETON.md`; new scripts are diffs against the skeleton.

**Header block.** Shebang (`#!/usr/bin/env bash` or `#!/usr/bin/env pwsh`), strict mode (`set -Eeuo pipefail` for bash, `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` for PowerShell), then a 10-line comment header: script name, target, posture, version, build date, source repo URL, license, brief description, link to docs, the `kniferoll-linux-deb` tag the vendored `lib/` was sourced from + its SHA256.

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

**Log format.** Every line: `<isots> <level> <script-name> <phase> <step> | <message>`. Levels: `OK`, `INFO`, `WARN`, `SKIP`, `ERROR`. Logs go to stderr (for live tail) and to `~/.kniferoll/logs/<script-name>-<isots>.log` (for after-the-fact audit). The split-terminal UI from `lib/split_terminal.sh` v1 is preserved as an opt-in (`--split-ui` flag), not a default — it's lovely but it conflicts with `--dry-run | less` and other piping patterns.

**Exit codes.**

| Code | Meaning |
|------|---------|
| 0 | Success. |
| 1 | User error (bad flag, bad path, etc.). |
| 2 | Preflight failed (OS / arch / shell / network / posture / root). |
| 3 | Download or checksum verification failed. |
| 4 | Mid-install failure (state is partial; manifest reflects partial). |
| 5 | Corp posture issue (managed scripts only): CA bundle invalid, splash page detected (user must accept in browser, then re-run — see §6.2), MDM gate failed. |

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

**scoop + winget + Chocolatey.** Three Windows package managers. Each beats kniferoll on "I just want to install this one package." kniferoll's value is the curated selection and the dotfile/profile setup that wraps the install. The v2 Windows scripts (`kniferoll-windows`, `kniferoll-managed-windows`) use winget primary, Scoop secondary, Chocolatey not at all (its UAC self-elevation is a security smell). The pipeline pattern from v1 is preserved.

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

1. **WSL2 status.** I propose folding WSL2 into `kniferoll-linux-deb.sh` (and `kniferoll-managed-linux-deb.sh` if used in corp WSL2) with a small `if-wsl` branch, rather than promoting it to a ninth target. WSL2 is Debian-on-Hyper-V and doesn't justify its own script — but you may know things about the corporate WSL2 setup (custom rootfs, internal mirrors, MDM hooks into the Hyper-V layer) that change the math.
2. **TUI selector and projector — keep, fold, or split off?** v1 bundles a Go TUI selector and a Python projector that have nothing to do with the install proper. My recommendation is to split both into dedicated repos under `silo-agent`: `silo-agent/kniferoll-shell` (the post-install shell-experience runtime, which would own zoxide/starship/aliases-as-code) and `silo-agent/kniferoll-projector` (the animation orchestrator). This lets the v2 install scripts stay shell-native and dependency-light.
3. **Vendoring mechanics from `kniferoll-linux-deb` to the other seven repos.** The lib lives inside `kniferoll-linux-deb`. Three viable mechanisms for getting a copy into each consumer at a pinned tag: (a) committed `vendor/lib/` directory + `vendor.sha256` regenerated on lib bumps — clean, portable, no install-time network, fully air-gapped-friendly; (b) `git subtree pull` from a tagged ref — preserves history but adds workflow learning; (c) `git submodule` pinned to a tag — live but spookier on clone, fragile in air-gapped environments. My recommendation is (a). Confirm.

The remaining five are deferred but lower-stakes:

4. **Old `terminal-kniferoll` repo disposition.** Keep on `main` as a frozen v1 reference, or delete in favor of the new family? I recommend keeping it; tag the last v1 commit as `v1-final` and let it rest as documentation of "what we used to do and why."
5. **Inventory bumps from v1 to v2.** v2 needs an explicit decision on: Anthropic Claude CLI (currently winget-only on Windows; should it be cross-platform now?), `gum` (Windows-only in v1; promote to all platforms or remove?), the AI-CLI bucket (gemini-cli, claude — first-class category or opt-in module?). I'd like Chef's call before phase 5.
6. **Telemetry stance.** No telemetry, ever, in any posture. I want this written into `kniferoll-linux-deb/docs/ARCHITECTURE.md` as a one-line non-negotiable. Confirm.
7. **`kniferoll` as the project name.** Drop the `terminal-` prefix from the project, the binary, the repo names. The prefix is redundant — what else would a knife roll be? Confirm or push back.
8. **Corp-side hostname/policy file format.** Managed scripts will accept a small `kniferoll-corp.toml` (or .json) at `/etc/kniferoll/corp.toml` or `~/.config/kniferoll/corp.toml` defining: CA bundle path, internal package mirror URLs, MDM-detection commands. (Notably *not* splash-page selectors — see the no-splash-bypass position in §6.2.) This is also the file that feeds the `KR_INTERNAL_REPOS` switch (§6.2). Format and precedence to be designed in phase 5.

### Resolved by Chef

- **Naming.** Flat scheme: `kniferoll-<os>` and `kniferoll-managed-<os>`. No codename theme.
- **Repo granularity.** Eight repos under `silo-agent`. No separate library repo; `lib/` lives in `kniferoll-linux-deb` and is vendored into the other seven.
- **`silo-agent` account shape.** Personal account today, possibly an organization later. Access-grant commands in §5.5 use the per-collaborator form, which works against both shapes.
- **Internal-repos toggle posture.** Built but off by default in v2.0 (§6.2). Code paths ship in managed scripts; the toggle gets a follow-up release once corporate mirrors are testable (phase 9).

---

## 10. Phasing

Sequenced by what unlocks the most learning fastest, not by OS.

**Phase 0 — Approval and access.** Chef reviews this plan. Open questions resolved. Naming locked (done). Repo strategy locked (done — eight repos, lib in `kniferoll-linux-deb`). The eight repos created under `silo-agent` (4 public + 4 private). Admin grants issued to `albethere` per §5.5. Discoverability topics applied to public repos. No code yet.

**Phase 1 — Skeleton.** Empty scaffolding committed to all four unmanaged script repos (header, preflight, mode flags, exit codes, log format, no install logic yet). `kniferoll-linux-deb/lib/` v0.1.0 stubs (download-and-verify, log format, exit-code helpers, manifest writer) — tag is cut when the script ships in phase 2; consumers (the other seven repos) vendor at that tag. README, FLAVOR.md, ARCHITECTURE.md drafted in `kniferoll-linux-deb/docs/`. Goal: a user can clone any unmanaged repo, run `kniferoll-<os> --dry-run`, and see the skeleton produce empty output without errors.

**Phase 2 — First slice (`kniferoll-linux-deb`).** Implement end-to-end. apt + cargo + curated GitHub releases + Zsh setup + dotfile rendering + manifest + dry-run + check + force. This is the reference implementation. Every later script is a diff against this. Chosen for first because: (a) Debian/Ubuntu is the highest-volume target, (b) apt is the most predictable package manager, (c) the v1 Linux script is the canonical and best-tested.

**Phase 3 — Same hand, new arch (`kniferoll-linux-arch`).** pacman + AUR helper detection. The shared inventory data structure is exercised across two distros for the first time; this stresses the "tools are inline data" principle. Bugs found here are reflected back into `kniferoll-linux-deb` (script and `lib/`) as appropriate; `kniferoll-linux-arch` vendors the updated lib tag.

**Phase 4 — Cross the threshold (`kniferoll-mac`).** Homebrew. Different file paths (`~/.zshrc` vs `~/.zprofile` precedence, `/opt/homebrew` prefix, iTerm2 colorscheme deployment). The lib proves itself across two OS families.

**Phase 5 — Mind the proxy (`kniferoll-managed-linux-deb`).** First managed-repo work. `kniferoll-linux-deb`'s lib bumped (e.g., v0.2.0) if it needs new primitives for corp posture. Implement: corp-CA detection (auto-detect path list + `--ca-bundle` override), CA bundle propagation across the env-var fan-out (§6.2), the **internal-repos toggle code paths** (off by default, per §6.2), and the corp policy file reader (per §9 OQ#8). Splash-page bypass is *not* implemented — if encountered, exit 5 with an instruction to accept in browser. Goal: get the corp posture *exactly right* on one script before extending to others. The corp-CA propagation is the highest-stakes code in v2; phase 5 is where it's invented.

**Phase 6 — Fill the matrix (`kniferoll-managed-mac`, `kniferoll-managed-linux-arch`).** Port the corp-CA work from `kniferoll-managed-linux-deb` into the other two managed Unix scripts. By now the pattern is set; these are diffs against phase 5 and their unmanaged twins.

**Phase 7 — Other shore (`kniferoll-windows`, `kniferoll-managed-windows`).** PowerShell 7. winget. Scoop. Both unmanaged and managed in the same phase because the corp-CA work for Windows is sufficiently different from Unix (cert store enumeration, `CARGO_HTTP_CAINFO`, group-policy paths) that it benefits from being designed against both audiences at once. This phase is the longest because PowerShell is foreign to most of the project's muscle memory.

**Phase 8 — Ship v2.0.** Demo GIFs. README polish. CI per public repo. Smoke tests for the managed repos (running internally). Tag `v1.0.0` on every script repo. The `KR_INTERNAL_REPOS` toggle ships *disabled* per §6.2; first-iteration v2.0 works against public sources end-to-end on every posture. Frozen v1 `terminal-kniferoll` repo gets a `README` pointer to the new family. Beads tracker updated. Done.

**Phase 9 (post-v2.0) — Internal-repos enablement.** Wire the off-by-default `KR_INTERNAL_REPOS` paths from phase 5 to a real corporate-mirror configuration (per resolved OQ #8). Test against staged internal mirrors. Tag managed scripts `v1.1.0` with the toggle ready for users who set the flag. The toggle stays per-user/per-host, never globally on by default.

The phasing front-loads the highest-risk work (corp-CA in phase 5) only *after* the unmanaged shape is locked in three platforms. This means the corp design has three working examples to defend against, and the corp work is not allowed to leak back into the unmanaged path. That separation is the rewrite's central structural bet, and the phasing is built to enforce it.

---

## Verification

Plan-level verification before any code is written:

- Walk Chef through this document and resolve the remaining open questions in section 9.
- Confirm the eight-repo strategy and the `silo-agent` setup.
- Confirm WSL2, projector, and TUI dispositions.
- Run the §5.5 commands to create the repos and issue the GitHub admin grants.

Code-level verification per phase:

- Each script has a `--dry-run` that produces parseable output covered by a smoke test.
- Each script has a `--check` that reports drift against its own manifest.
- Each script's preflight has a unit-testable failure path for every exit code (2.1 through 2.6).
- `kniferoll-linux-deb/lib/` has a test suite ported and modernized from v1's `scripts/test-sweep.{sh,ps1}`.
- Phase 5's corp-CA propagation has integration tests that simulate a TLS-inspecting proxy (mitmproxy with a self-signed CA) and verify every propagated env var is set, every tool can curl through, and the manifest reflects the bundle source. The internal-repos code paths have unit tests against a staged mirror config but ship disabled until phase 9.

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
