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

Ten installer scripts. Five operating-system targets crossed with two security postures. No further axes — architecture (x86_64 / aarch64) is handled inside the Linux scripts as a matrix dimension, not a separate file, because the divergence is small and the duplication would buy nothing.

| OS target | Posture | Repo | Entry | Notes |
|-----------|---------|------|-------|-------|
| macOS (Apple Silicon, arm64) | unmanaged | `silo-agent/kniferoll-mac` | `install.sh` | Homebrew on arm64; assumes user is admin of their machine. |
| macOS (Apple Silicon, arm64) | managed | `silo-agent/kniferoll-managed-mac` | `install.sh` | Adds Zscaler/corp-CA detection, MDM-aware preflight, TLS-1.2 fallback. |
| Windows 10/11 (x86_64) | unmanaged | `silo-agent/kniferoll-windows` | `install.ps1` | PowerShell 7+, winget primary, Scoop secondary. |
| Windows 10/11 (x86_64) | managed | `silo-agent/kniferoll-managed-windows` | `install.ps1` | Adds corp-CA cert-store enumeration, `CARGO_HTTP_CAINFO`, group-policy-aware paths. |
| Linux Debian/Ubuntu (x86_64 + aarch64) | unmanaged | `silo-agent/kniferoll-linux-deb` | `install.sh` | apt + cargo + selective GitHub releases; arch-aware in the inventory. Native Linux only — refuses on WSL2 (suggests `kniferoll-wsl2`). |
| Linux Debian/Ubuntu (x86_64 + aarch64) | managed | `silo-agent/kniferoll-managed-linux-deb` | `install.sh` | Adds Zscaler/corp-CA paths under `/usr/local/share/ca-certificates/`, internal-mirror toggle (off by default). |
| Linux Arch-family (x86_64 + aarch64) | unmanaged | `silo-agent/kniferoll-linux-arch` | `install.sh` | pacman + AUR helper detection; CachyOS, EndeavourOS, Manjaro all welcome. |
| Linux Arch-family (x86_64 + aarch64) | managed | `silo-agent/kniferoll-managed-linux-arch` | `install.sh` | Same as above plus corp posture. Edge case: rolling release means version pins are looser; documented. |
| WSL2 Debian/Ubuntu (x86_64) | unmanaged | `silo-agent/kniferoll-wsl2` | `install.sh` | Debian/Ubuntu inside WSL2 only; refuses on other WSL distros and on WSL1. Handles `/etc/resolv.conf` lock, `/etc/wsl.conf`, time drift. See §3.4. |
| WSL2 Debian/Ubuntu (x86_64) | managed | `silo-agent/kniferoll-managed-wsl2` | `install.sh` | Same WSL2 handling plus corp-CA from the Windows trust store via `/mnt/c/`. See §3.4. |

### 3.1 Why Intel macOS is out of scope

Apple stopped shipping new Intel Macs in 2023. Apple announced the end of macOS Intel support for the next major release. By the time v2 of kniferoll is in active maintenance (mid-2026 onward), the Intel-Mac population among the kniferoll user base is statistically zero — the user community is dev/security/SRE on personal or corp-issued laptops, all of which are Apple Silicon for purchases in the last three years. Maintaining a script for a deprecated and shrinking arch is non-trivial: Homebrew's arm64 vs x86_64 prefix difference (`/opt/homebrew` vs `/usr/local`), the Rosetta translation surface, and the third-party-tool support gap (e.g., several Nerd Font and cargo crates have only arm64 native binaries) all add expense. The right call is: explicitly out of scope; users on Intel Mac fork the script if they need it.

### 3.2 Why arch is a matrix dimension on Linux but not a separate file

x86_64 and aarch64 differ on Linux in three ways relevant to kniferoll: (a) some apt/pacman packages have different names or different availability; (b) some GitHub-release assets are only published for one arch; (c) rustup behaves differently. None of these justify file-level duplication. Each is a per-tool conditional in a tools-inventory data structure: `if [[ $ARCH == aarch64 ]]; then SKIP some_x86_only_tool; fi`. Splitting into four Linux files instead of two would double the maintenance surface for a divergence that is minor and shrinking.

### 3.3 What the matrix excludes and why

- **NixOS / nix-darwin** is excluded — Nix users have a different system model and a vastly more capable installer (Home Manager). v2 should not pretend to compete in that space.
- **FreeBSD / OpenBSD / Alpine / Fedora-RHEL family** are excluded as targets. They each have small but meaningful differences (different libc on Alpine, dnf on Fedora, ports on FreeBSD) that would each require a dedicated script. The five targets above cover ~95% of the kniferoll user base; the rest are documented as "you are welcome to fork."
- **WSL1** is explicitly refused — WSL2 is the supported boundary. WSL1's filesystem and process model differ enough that the WSL2 networking/wsl.conf dance doesn't transfer. The WSL2 script detects WSL1 in preflight and exits 2.

### 3.4 Why WSL2 deserves its own script

WSL2 looks like Debian/Ubuntu from the user's prompt — `apt`, `bash`, `/home`, the works. But the boot, network, and filesystem layers underneath are Microsoft's, not the kernel's, and they impose constraints that turn an `if-wsl` branch on the Debian script into a bog of special cases. v2 promotes WSL2 to its own pair of repos and treats it as a peer target.

The non-trivial concerns that justify a dedicated script:

**`/etc/resolv.conf` is regenerated on every reboot.** WSL2's default behavior (`network.generateResolvConf=true` in `/etc/wsl.conf`) re-creates `/etc/resolv.conf` from the Windows host's DNS servers each time the VM starts. Corporate Windows hosts often serve DNS that WSL2 cannot reach (split-horizon, internal-only resolvers); even on home machines the auto-generated content may point at IPv6-only resolvers or the host gateway, both of which fail in subtle ways. The fix is a four-step dance: stop the auto-generation in `/etc/wsl.conf`, write a known-good `/etc/resolv.conf`, lock the file with `sudo chattr +i /etc/resolv.conf` so it survives a `wsl --shutdown`, and reboot for `wsl.conf` to take effect. The unlock for future edits is `sudo chattr -i /etc/resolv.conf` — documented prominently because the immutable bit confuses anyone who later tries `sudo vi /etc/resolv.conf` and gets `operation not permitted`.

**`/etc/wsl.conf` is the WSL-side master switch.** Beyond `[network] generateResolvConf=false`, the install writes:

- `[boot] systemd=true` — enables systemd. Default-on in Win11 23H2+ but not earlier; force-enable for consistency. Required for any tool that registers a systemd unit, and for `systemd-timesyncd` (see time drift below).
- `[interop] enabled=true` (default) and `appendWindowsPath=false` (opinionated) — keeps Windows PATH out of WSL2 unless the user explicitly imports it. The default `appendWindowsPath=true` produces a `$PATH` cluttered with Windows binaries that conflict with their Linux equivalents (`node`, `python`, `where`, etc.). Flipping to false is right for a dev environment, with a documented opt-in via flag for users who *do* want Windows binaries on PATH.
- `[automount] enabled=true options="metadata,umask=22,fmask=11"` — `metadata` lets Linux respect `chmod`/`chown` on `/mnt/c/`, which matters for any tool that cares about file modes (gpg keys, ssh keys, anything `chmod 600`).

Existing `/etc/wsl.conf` and `/etc/resolv.conf` are backed up timestamped before edit, per the §6.2 dotfile-edit principle.

**Reboot required.** `/etc/wsl.conf` changes take effect after the WSL2 VM is shut down and restarted, which is a Windows-side operation: `wsl --shutdown` from PowerShell, then any subsequent `wsl` invocation cold-starts the VM with the new config. The install script's post-install summary prints: "Run `wsl --shutdown` from Windows PowerShell, then re-open WSL2, to apply the network changes."

**Distro filtering.** The script detects WSL2 via `/proc/sys/kernel/osrelease` containing "microsoft" or "WSL" (case-insensitive) and the distro via `/etc/os-release`. If the distro isn't Debian or an Ubuntu LTS, the script exits 2 with a message telling the user this script is for Debian/Ubuntu under WSL2 only. Symmetrically, `kniferoll-linux-deb` detects WSL2 and exits 2, suggesting `kniferoll-wsl2`. WSL1 detected via `WSL_INTEROP` or kernel signature also exits 2.

**Filesystem boundary.** The script never installs anything into `/mnt/c/` or any Windows-side path. All artifacts land in the Linux user's home directory. `/mnt/c/` is read-only-or-config-only — for instance, reading the corp CA bundle from a Windows-exported PEM (managed posture below).

**Time drift.** WSL2's clock drifts after the Windows host sleeps and resumes. With `[boot] systemd=true` set above, the script `apt install systemd-timesyncd` and enables it, which keeps the clock close-enough across host sleeps. Documented in the post-install summary.

**DNS choice.** `1.1.1.1` (Cloudflare) and `8.8.8.8` (Google) are the unmanaged defaults — public, fast, neutral. The managed script defaults differ: it tries to read corp DNS servers from the Windows host (`ipconfig /all` via interop) before falling back to the public defaults. Override with `--dns 9.9.9.9,1.0.0.1` or `KR_WSL_DNS=...`. A `kniferoll-wsl2 dns --set ...` companion handles the lock-edit-relock dance idempotently for users who want to change DNS later without thinking about `chattr`.

**Memory cap.** `~/.wslconfig` on the Windows side (`%USERPROFILE%\.wslconfig`) is what caps WSL2's VM memory. The install script does *not* edit this — it lives in the Windows filesystem, requires Windows-side write access, and is per-user-on-Windows rather than per-WSL-distro. The post-install summary recommends: "If you haven't capped WSL2 memory yet, consider creating `%USERPROFILE%\.wslconfig` with `[wsl2] memory=8GB swap=2GB` (adjust to your machine)."

**Networking modes.** Win11 23H2+ ships a `networkingMode=mirrored` option (in `~/.wslconfig`) that solves a class of corporate-VPN routing issues that the default NAT mode silently breaks. Documented; not auto-switched (Windows-side per-user setting).

**Corp posture additions** (managed-wsl2 only). The corp CA usually lives in the Windows trust store, not the Linux trust store. The managed script reads it via one of three paths:

1. `$KR_CA_BUNDLE` points at a Windows-exported PEM mounted via `/mnt/c/...` (recommended; user does the export once with a documented PowerShell one-liner).
2. The corp CA is already deployed to the WSL2 distro's `/usr/local/share/ca-certificates/` (e.g., by IT image or a previous run); script verifies and runs `update-ca-certificates`.
3. Auto-export via interop: `powershell.exe -Command "Get-ChildItem Cert:\LocalMachine\Root | Where-Object Subject -match '<corp-issuer>' | Export-Certificate -FilePath C:\temp\corp-ca.cer"`. Clever but fragile — behind a `--auto-export-ca` flag, off by default.

Internal package mirrors (the §6.2 toggle) work from WSL2 only when the Windows host can reach them. If the corp VPN doesn't tunnel WSL2 traffic by default, the user is told to switch to mirrored networking mode (above) or ask IT to configure WSL2 routing. The script does not auto-fix VPN routing.

---

## 4. Naming convention

Each repo is `silo-agent/kniferoll-<os>` (unmanaged) or `silo-agent/kniferoll-managed-<os>` (managed); inside every repo the entry script is `install.sh` (Unix) or `install.ps1` (Windows). The repo name carries the OS and posture, so the script name doesn't need to repeat them. Descriptive names beat themed ones for an installer: filenames are URL-legible, grep-able, and free of the insider-knowledge tax that codenames impose on new contributors. Kitchen-voice character belongs in `docs/FLAVOR.md` and the installer's runtime output, not in ten individual aliases.

`mac` resolves to Apple Silicon (the only supported macOS arch); `linux-deb` covers native Debian/Ubuntu and derivatives across x86_64 and aarch64 (refuses to run on WSL2 — see `wsl2` below); `linux-arch` covers Arch, EndeavourOS, Manjaro, CachyOS across the same two arches; `windows` is x86_64 only; `wsl2` covers Debian/Ubuntu under WSL2 on x86_64 (Windows-on-ARM with aarch64 WSL2 is a fork-it-yourself case).

---

## 5. Repo strategy

### 5.1 Layout

Thirteen repos when complete: ten per-OS installer repos, two coordination repos, one ancillary projector repo. Eight of the per-OS repos exist; five repos are still to be created.

**Per-OS repos (extant under `silo-agent`, `albethere` admin):**

| Visibility | Repo | Posture |
|------------|------|---------|
| Public | `silo-agent/kniferoll-mac` | unmanaged |
| Public | `silo-agent/kniferoll-windows` | unmanaged |
| Public | `silo-agent/kniferoll-linux-deb` | unmanaged |
| Public | `silo-agent/kniferoll-linux-arch` | unmanaged |
| Private | `silo-agent/kniferoll-managed-mac` | managed |
| Private | `silo-agent/kniferoll-managed-windows` | managed |
| Private | `silo-agent/kniferoll-managed-linux-deb` | managed |
| Private | `silo-agent/kniferoll-managed-linux-arch` | managed |

**Per-OS repos (to be created — WSL2 promotion, see §3.4):**

| Visibility | Repo | Posture |
|------------|------|---------|
| Public | `silo-agent/kniferoll-wsl2` | unmanaged |
| Private | `silo-agent/kniferoll-managed-wsl2` | managed |

**Coordination repos (to be created — see §5b):**

| Visibility | Repo | Role |
|------------|------|------|
| Public | `silo-agent/kniferoll-unpack` | Public-posture coordinator. Carries the user-facing `unpack` dispatcher AND the canonical shared `lib/`. |
| Private | `silo-agent/kniferoll-managed-unpack` | Managed-posture coordinator. Carries the corp-flavored `unpack` dispatcher AND the managed-only `managed-lib/`. |

**Ancillary repo (to be created — projector split-off, see §9 resolved):**

| Visibility | Repo | Role |
|------------|------|------|
| Public | `silo-agent/kniferoll-projector` | Optional terminal-animation orchestrator. Decoupled from the installer. Each per-OS repo's `--projector` flag clones and invokes it; nothing in the projector ships in the per-OS default tool inventory. |

Inside each per-OS repo the entry script is `install.sh` (Unix repos) or `install.ps1` (Windows repos). The repo name disambiguates the OS and posture; the entry script doesn't need to repeat that information. A user can either go through the unpack dispatcher (the OS-agnostic happy path, §5b.4) or clone the per-OS repo directly:

```
git clone https://github.com/silo-agent/kniferoll-mac.git
cd kniferoll-mac
./install.sh
```

`silo-agent` is a personal GitHub account today, with potential to convert to an org later. The access grants on each repo were issued in the per-collaborator form, which keeps working unchanged after a personal-to-org conversion. If/when conversion happens, an `admins` team grant becomes the more ergonomic shape; that's a one-time migration and is not blocking.

**Commands for creating the five new repos and granting `albethere` admin** (run as `silo-agent` once you're ready):

```
# Public: WSL2 unmanaged, both unpack/coordination, projector ancillary
gh repo create silo-agent/kniferoll-wsl2 --public \
  --description "Opinionated terminal-environment installer for WSL2 Debian/Ubuntu"
gh repo create silo-agent/kniferoll-unpack --public \
  --description "Public-posture coordinator + canonical shared lib for the kniferoll family"
gh repo create silo-agent/kniferoll-projector --public \
  --description "Optional terminal-animation orchestrator (opt-in companion to the kniferoll installers)"

# Private: WSL2 managed, managed-unpack
gh repo create silo-agent/kniferoll-managed-wsl2 --private \
  --description "Corporate-CA-aware terminal-environment installer for WSL2 Debian/Ubuntu"
gh repo create silo-agent/kniferoll-managed-unpack --private \
  --description "Managed-posture coordinator + managed-lib for the kniferoll family"

# Admin grants for albethere on all five
for r in kniferoll-wsl2 kniferoll-unpack kniferoll-projector \
         kniferoll-managed-wsl2 kniferoll-managed-unpack; do
  gh api repos/silo-agent/$r/collaborators/albethere -X PUT -f permission=admin
done

# Discoverability topics on the four new public repos (reuse + adjust per repo if useful)
for r in kniferoll-wsl2 kniferoll-unpack kniferoll-projector; do
  gh api repos/silo-agent/$r/topics -X PUT \
    -f names='["kniferoll","terminal","installer","dotfiles","zsh","powershell"]'
done
```

### 5.2 Public/private split

The split runs along the posture seam, not the OS axis. Unmanaged repos are public because they are the front door — anyone running an installer on a personal machine should be able to read every line that's about to touch their dotfiles. Managed repos are private because they accumulate corporate-shaped knowledge — internal mirror URLs, MDM detection probes, the path layout of a particular org's trust store, the CA-bundle locations a particular IT department deploys — none of which belongs on the open internet.

The boundary rules below keep the public surface clean.

**Public repos never reference:**
- corporate hostnames, IPs, or DNS suffixes
- specific corp-CA filenames or paths
- MDM-detection commands or expectations
- internal apt mirrors, Artifactory hosts, or internal package registries
- the words "Zscaler," "ZIA," "ZPA," or any specific proxy vendor

**Public repos may reference, generically:**
- "If you are behind a corporate TLS-inspecting proxy, see the matching `kniferoll-managed-*` repo (private)."
- Standard env vars (`CURL_CA_BUNDLE`, `NODE_EXTRA_CA_CERTS`, etc.) — these are documented features of upstream tools, not corporate secrets.

The `lib/` inside `kniferoll-unpack` (see §5b) is public and posture-agnostic. No function in it may take a corporate-shaped argument, depend on a corp environment variable, or hardcode a path under `/usr/local/share/ca-certificates/`. The lib provides neutral primitives; managed-only utilities live in `kniferoll-managed-unpack/managed-lib/` and are composed on top of the public lib in the managed repos. The dependency direction is strict and one-way: public → public; private → public; never the reverse (§5b.3).

### 5.3 Shared code reuse

Shared library code lives in the two coordination repos: `silo-agent/kniferoll-unpack` (public, posture-agnostic primitives) and `silo-agent/kniferoll-managed-unpack` (private, managed-only utilities layered on top of the public ones). The eight per-OS repos consume these libraries via **git subtree**, with a `make sync-core` target in each consumer's `Makefile`. The §5b coordination layer covers the mechanics, the posture-isolation invariants, and the bootstrap UX in detail.

The short version: each per-OS repo carries a tracked subtree of the upstream `lib/` (and, for the managed four, a second subtree of `managed-lib/`); subtree pulls are squashed (`--squash`) so consumer histories stay flat; the merge commits make upstream provenance auditable in `git log` rather than via sidecar files; bumps are one PR per consumer that wants the update; consumers can land bumps independently with no batch coordination.

A previous revision of this plan proposed hosting `lib/` inside `kniferoll-linux-deb` (the reference implementation), with vendoring into the other seven. That option is superseded by the coordination layer, which absorbs three responsibilities at once — bootstrap entry, shared lib hosting, and posture isolation enforcement — and avoids `kniferoll-linux-deb` carrying a dual identity it didn't need.

### 5.4 Branch and release conventions

Across all eight repos:

- **Branches.** `main` is the only long-lived branch. Work happens on `feat/<short>` or `fix/<short>` branches, lands via PR, and the branch is deleted on merge. No long-lived feature branches. Branch protection on `main`: required PR review, required passing CI, no force-push.
- **Tags.** Semver, `v`-prefixed (`v1.0.0`, `v1.1.0`). Each repo versions independently — `kniferoll-mac@v1.4.2` and `kniferoll-windows@v1.7.0` are normal. Tags are signed where the local environment supports it.
- **Releases.** The four public repos use GitHub Releases for changelog visibility. The four private repos tag only; the script in the working tree at a given tag *is* the artifact.
- **Lib bumps.** Tagging a release of `kniferoll-unpack` (or `kniferoll-managed-unpack`) flags consumers. Each consumer's bump is `make sync-core` followed by a one-PR merge — the subtree-pull squash commit records the sync, the working-tree diff is the actual change. Consumers land bumps independently; no batch coordination required.
- **CI on PR.** Each public repo runs a smoke test on PR (preflight + `--dry-run` + `--check`) on a Debian, Arch, or macOS GitHub-hosted runner as appropriate. Private repos run the same smoke shape on internal runners.
- **Cross-repo design changes.** A change to the per-script skeleton or log format starts as a PR to `kniferoll-unpack` updating `lib/` (and `lib/SKELETON.md`), ships in a tagged release, and propagates as ordinary `make sync-core` PRs in each consumer repo.

---

## 5b. Coordination layer

The two coordination repos sit on top of the eight per-OS repos and absorb three responsibilities: user-facing bootstrap, shared library hosting, and posture isolation enforcement. The naming preserves the kitchen metaphor — "unpack" is what a chef does on arrival at a new station, opening their knife roll and laying out tools — and also literally describes what these repos do at install time.

### 5b.1 Shape: bootstrap entry and shared library, in one repo per posture

`kniferoll-unpack` (public) is both the user-facing entry point AND the canonical home of the shared library. Layout:

```
silo-agent/kniferoll-unpack/
├── unpack                         # OS-detection dispatcher (bash)
├── unpack.ps1                     # Windows PowerShell counterpart
├── lib/                           # Canonical shared library
│   ├── download_verify.sh
│   ├── rc_sweep.awk
│   ├── log_format.sh
│   ├── manifest_writer.sh
│   ├── exit_codes.sh
│   ├── SKELETON.md                # Per-script skeleton contract
│   └── VERSION                    # Human-readable upstream tag pointer
├── docs/
│   ├── ARCHITECTURE.md            # Canonical architecture doc
│   ├── FLAVOR.md
│   └── SUPPLY_CHAIN_RISK.md
├── Makefile
└── README.md                      # The de-facto project home page
```

`kniferoll-managed-unpack` (private) mirrors the shape with managed-only additions:

```
silo-agent/kniferoll-managed-unpack/
├── unpack                         # Managed-flavored dispatcher (CA bundle preflight)
├── unpack.ps1
├── lib/                           # Subtree of kniferoll-unpack/lib (read-only consumer)
├── managed-lib/                   # Managed-only utilities (canonical)
│   ├── ca_detection.sh
│   ├── ca_propagation.sh
│   ├── mdm_probes.sh
│   └── internal_repos.sh
├── docs/
│   └── managed-architecture.md    # Managed-specific architecture (private)
├── Makefile
└── README.md
```

Three options were considered. (a) pure bootstrap with no install logic leaves the lib homeless and forces a separate decision about where shared code lives. (b) shared library only leaves users without a single entry point and makes them figure out which per-OS repo to clone. (c) both — bootstrap script plus shared lib in one repo — gives the user one address (`kniferoll-unpack`), gives the shared lib a natural home, and keeps the per-OS repos runnable standalone for advanced users via direct cloning. Option (c) is the design.

Per-OS repos remain valid standalone entry points. A user who knows what they want can `git clone https://github.com/silo-agent/kniferoll-mac && ./install.sh` and skip the dispatcher. The unpack repo's job is to make the OS-agnostic case ergonomic, not to be required.

### 5b.2 Subtree mechanics

Each consumer carries a `lib/` directory (and `managed-lib/` for the managed per-OS repos) that is a tracked git subtree of the upstream coordination repo. Updates pull via `make sync-core` — never a manual `cp -r`, never a submodule.

For public per-OS repos (`kniferoll-mac`, `-windows`, `-linux-deb`, `-linux-arch`):

```make
.PHONY: sync-core
sync-core:
	git subtree pull --prefix=lib \
		https://github.com/silo-agent/kniferoll-unpack main \
		--squash -m "subtree: sync lib from kniferoll-unpack"
```

For managed per-OS repos (`kniferoll-managed-*`), two targets:

```make
.PHONY: sync-core
sync-core: sync-public-lib sync-managed-lib

.PHONY: sync-public-lib
sync-public-lib:
	git subtree pull --prefix=lib \
		https://github.com/silo-agent/kniferoll-unpack main \
		--squash -m "subtree: sync lib from kniferoll-unpack"

.PHONY: sync-managed-lib
sync-managed-lib:
	git subtree pull --prefix=managed-lib \
		https://github.com/silo-agent/kniferoll-managed-unpack main \
		--squash -m "subtree: sync managed-lib from kniferoll-managed-unpack"
```

For `kniferoll-managed-unpack` itself (which subtrees the public lib into its own `lib/`):

```make
.PHONY: sync-core
sync-core:
	git subtree pull --prefix=lib \
		https://github.com/silo-agent/kniferoll-unpack main \
		--squash -m "subtree: sync lib from kniferoll-unpack"
```

Subtree over submodules: submodules require `git clone --recurse-submodules` and silently fail in air-gap or restricted-network environments. Subtree leaves a normal commit history that any clone gets fully and offline. Submodules across eight consumer repos pointing at one core repo also mean every core update is eight PRs *plus* eight submodule pointer updates; subtree collapses that to eight `make sync-core` PRs, period.

Subtree over manual vendoring: subtree's merge commits put upstream provenance in `git log` rather than in a sidecar `.sha256` file. The `--squash` flag keeps the consumer's history flat — the merge commit records the sync, the per-file diffs are visible inside it, and the upstream's full history doesn't enter the consumer's log. A small `lib/VERSION` file inside the subtree records the upstream tag at last sync, for humans browsing without `git log` open.

A core update is one PR per consumer that wants the bump — eight consumers in the worst case. There is no enforcement that all consumers must bump together; a stale consumer just runs older lib code, which is fine.

### 5b.3 Posture isolation: strict one-way dependency

`kniferoll-unpack` (public) NEVER subtree-pulls from `kniferoll-managed-unpack`. NEVER references its existence. NEVER has a code path that imports, sources, or depends on managed-side code. The public surface stands alone, fully audit-able without seeing the private side.

`kniferoll-managed-unpack` (private) DOES subtree-pull from `kniferoll-unpack/lib/` (into its own `lib/`). Managed-only utilities live in `managed-lib/`. The dependency graph:

```
kniferoll-unpack (public)
   │
   ├──→ kniferoll-mac, kniferoll-windows, kniferoll-linux-deb, kniferoll-linux-arch
   │       (subtree of lib/)
   │
   ├──→ kniferoll-managed-unpack
   │       (subtree of lib/)
   │
   └──→ kniferoll-managed-mac, kniferoll-managed-windows,
        kniferoll-managed-linux-deb, kniferoll-managed-linux-arch
            (subtree of lib/, plus subtree of managed-lib/ from kniferoll-managed-unpack)
```

Why one-way: anything in the private repos may carry corporate assumptions — mirror URLs, MDM probe shapes, CA-bundle path layouts. Anything in the public repos is inspectable by anyone on the internet. If public depended on private, the public surface would carry whatever changes propagate from the private side, and the audit boundary would dissolve. One-way means the public side never reads the private side. The private side reads the public side, layers managed-only code on top, and ships the combined result to the four managed per-OS repos.

The boundary is enforced by convention, not by tooling — there is no automatic check that `kniferoll-unpack` doesn't accidentally reference `kniferoll-managed-unpack`. CI in `kniferoll-unpack` includes a grep step that fails the build if any tracked file contains the word "managed-unpack" outside of explicit "see also" links in markdown. Cheap, effective, fail-loud.

### 5b.4 Bootstrap UX

**Unmanaged users** — the OS-agnostic happy path:

```
git clone https://github.com/silo-agent/kniferoll-unpack
cd kniferoll-unpack
./unpack
```

The `./unpack` script:
1. Sources `lib/` (which is in this repo).
2. Detects OS via `uname -s` (or `$IsWindows` for `unpack.ps1`).
3. Resolves which per-OS repo to clone (`kniferoll-mac`, `-windows`, `-linux-deb`, `-linux-arch`).
4. Clones it into a sibling directory (default) or the current working directory (`--here`).
5. Execs that repo's `install.sh` / `install.ps1`, forwarding any flags.

If the per-OS repo is already cached, `./unpack` updates it via `git pull --ff-only` before exec'ing. Idempotent: re-running `./unpack` after a successful install is safe (the per-OS install.sh is itself idempotent per §6.1).

**Managed users** — same shape, but with hard preflight:

```
export KR_CA_BUNDLE=/path/to/corp-ca.pem      # if known; else auto-detect
git clone https://github.com/silo-agent/kniferoll-managed-unpack
cd kniferoll-managed-unpack
./unpack
```

The managed `unpack` runs a hard preflight before any clone or exec: it sources `managed-lib/ca_detection.sh` and tries (in order) `$KR_CA_BUNDLE`, the auto-detect path list per OS, and an explicit `--ca-bundle PATH` flag. If none resolves to a readable PEM containing a corporate CA chain, `unpack` exits with code 5 and prints a remediation block — what file to provide, what env var to set, where corporate IT typically deposits the bundle on this OS. Only after the preflight passes does it clone the matching managed per-OS repo and exec its `install.sh` / `install.ps1`.

**Standalone use (advanced, both postures):**

The per-OS repos remain runnable standalone for users who know which they want:

```
# Unmanaged
git clone https://github.com/silo-agent/kniferoll-mac
cd kniferoll-mac
./install.sh

# Managed (still requires CA bundle, just bypasses the dispatcher)
export KR_CA_BUNDLE=/path/to/corp-ca.pem
git clone https://github.com/silo-agent/kniferoll-managed-mac
cd kniferoll-managed-mac
./install.sh
```

Each per-OS repo ships with `lib/` (and `managed-lib/` for managed) already vendored via subtree, so a fresh clone is fully self-contained — no second clone of the unpack repo required. The unpack dispatcher is a convenience for the OS-agnostic case, not a dependency.

---

## 6. Architectural principles

The rewrite is governed by three values, in priority order: **simplicity, security, beauty**.

### 6.1 Simplicity

- **One script per (OS × posture).** No dynamic dispatch, no plugin abstraction, no per-tool framework. The ten scripts are ten standalone artifacts. A user can read any one of them in one sitting.
- **Tools are inline data, not a plugin system.** The tool inventory is a top-of-file array (or hash) read once. Adding a tool is one line; removing a tool is one line; auditing the inventory is reading the array. No `register_tool()` callbacks.
- **POSIX bash for Unix, PowerShell 7 for Windows.** No Python in the install path, no Go binary as a hard dependency, no third-party CLI required to run the installer. The Go TUI selector and the Python projector are post-install conveniences that live in their own packages.
- **No dispatcher.** The v1 `install.sh` exists because the three platform scripts share a name and a directory; v2 puts each script in its own repo, so each repo's `install.sh` (or `install.ps1`) is unambiguously the one for that target. There is no universal entrypoint, and that is correct: there is no universal install.
- **Configs are single-file canonical templates with no templating engine.** The Zsh and PowerShell profiles are written verbatim from the script. Variation is by env var or post-install user override, not by Jinja-shaped substitution.
- **One log format, one exit-code table, one rollback model.** All eight per-OS scripts share these via the `lib/` subtreed from `kniferoll-unpack` (see §5b). A user who has used `kniferoll-linux-deb` already understands the logs, exit codes, and rollback story of `kniferoll-managed-mac`.
- **Delete the supply-chain-guard framework.** The v1 abstraction allowed four risk modes but only ever shipped one. v2's rule is hardcoded: no curl-pipe-bash, ever, in any posture. If a tool can only be installed by piping a script, it does not get installed by kniferoll. Document the exception, do not engineer around it.

### 6.2 Security

- **No `curl | bash` anywhere.** Every download lands as a file in a temp directory, gets its SHA256 verified against a checksum that is committed to the repo, and only then is executed (if executable) or moved into place (if a binary). The Homebrew bootstrap pattern in v1 (`download_to_tmp` + verified write) is the right pattern; v2 enforces it without exception.
- **Pinned versions and pinned checksums for every download.** No "latest." Bumping a version is an explicit PR with an updated checksum line. The Nerd Fonts soft-warn-and-continue pattern at `install_mac.sh:1369-1384` becomes a hard-fail.
- **Cooling-off period: 7 days from upstream release.** When pinning a new version of any tool, font, or cargo crate, maintainers wait at least 7 days from the upstream release date before merging the bump PR. Most supply-chain attacks (yanked malicious packages, compromised maintainer accounts, registry takeovers) get caught within hours-to-days; a 7-day floor lets the community immune system do its work before kniferoll's CI starts feeding compromised artifacts to users. The pinned-version table records `released_at` ISO date alongside each version string; CI on bump PRs verifies `today - released_at >= 7 days` and fails otherwise. Emergency security bumps (CVEs, urgent patches) override via `--allow-fresh` with a documented reason in the PR body.
- **Lean dependency surface.** Every tool in the default inventory earns its slot. The projector stack (weathr, trippy, the animation runtime) lives in `silo-agent/kniferoll-projector` and is opt-in via `--projector` — none of it lands in a per-OS repo's default install. If a tool is "nice to have" but not load-bearing for the shell experience, it goes in an opt-in flag, not the default. Smaller default inventory means fewer pinned versions to track, fewer CVE windows, fewer cooling-off-period bumps to coordinate.
- **Refuse to run as root unless explicitly invoked with `--root` and a documented reason.** The v1 scripts require sudo for individual operations (`sudo apt`, etc.) and that pattern continues — but the script itself runs as the user, never as root. `--root` is reserved for VM-bootstrap or container-image-build scenarios where there is no user yet.
- **Explicit handling of corp TLS interception in managed scripts only.** Managed scripts take a CA bundle path via `--ca-bundle` flag or `KR_CA_BUNDLE` env var (with auto-detection as fallback) and propagate it to: `CURL_CA_BUNDLE`, `SSL_CERT_FILE`, `NODE_EXTRA_CA_CERTS`, `REQUESTS_CA_BUNDLE`, `GIT_SSL_CAINFO`, `AWS_CA_BUNDLE`, `PIP_CERT`, `CARGO_HTTP_CAINFO` (Windows), `HOMEBREW_CURLOPT_CACERT` (macOS). Unmanaged scripts have no concept of a corp CA and refuse to read these env vars even if set — managed work belongs in managed scripts.
- **Internal-repos toggle (managed scripts only, off by default in v2.0).** Managed scripts include code paths for routing all package fetches through internal mirrors instead of public registries: apt sources lists, pacman repos, `CARGO_REGISTRIES_*`, npm registry URL, pip index URL, GitHub binary mirrors, Homebrew tap rewrites. The switch is `KR_INTERNAL_REPOS=1` env var or `--internal-repos` flag, fed by the corp policy file (open question §9.8). **In v2.0 the switch ships off**: managed scripts work end-to-end against public sources just like their unmanaged twins. The internal-mirror code paths exist, are syntactically valid, and have unit tests, but are not enabled until a follow-up release when corporate-mirror configuration is testable. This is intentional — managed scripts ship and are useful even without internal-mirror infrastructure ready, and the toggle is added as a discrete, testable change later (phase 9).
- **No splash-page bypass.** v1 included logic to auto-parse and submit Zscaler splash-page forms (`install_mac.sh:175-257`). v2 deliberately removes this. Setting up a managed shell does not require automated consent-page traversal — if a splash page intercepts an install-time download, the script errors with exit code 5 and instructs the user to open the URL in their browser, accept the splash page, and re-run. Auto-clicking through corporate consent screens is the kind of impersonation that should never live in this tool, even when it's convenient and even when v1 had it.
- **No silent overwrites of user dotfiles.** Every dotfile change creates a timestamped backup *and* prints the diff to stderr before applying. Dry-run mode prints the diff and does not apply.
- **Audit trail.** Every install writes a manifest to `~/.kniferoll/state/<repo>-<isots>.json` (e.g., `kniferoll-managed-mac-2026-05-02T01-15-04Z.json`): tool name, version installed, source URL, SHA256 of downloaded artifact, install method, timestamp, exit status. A `kniferoll status` companion (shipped in `kniferoll-unpack/lib/` and subtreed into every per-OS repo) reads the most recent manifest and reports current state.
- **TLS 1.3 by default, TLS 1.2 fallback only in managed scripts.** Corporate proxies in 2026 should support TLS 1.3 nine years after RFC 8446. If they don't, that's a managed-script concern.
- **Network egress check in preflight.** A simple HEAD to a known-stable URL with the configured CA bundle. If it fails, abort before any partial install. Half-installs are worse than failures.

### 6.3 Beauty

- **Names are flat, not metaphorical.** `silo-agent/kniferoll-managed-linux-deb` tells a reader the org, the project, the posture, and the OS family without learning a codename map. The metaphor lives in the project name; the eight repos inherit it without each needing their own alias.
- **Output matters more than code.** The kitchen voice from `docs/FLAVOR.md` is preserved verbatim: one-liners for skip and success, box-bordered framing for security-relevant decisions, tactical not alarmist failure language. Variable names like `$GREEN`, `$ORANGE`, `$DIM` survive the rewrite. The Cyberwave palette stays.
- **The README is the doorway.** Single-page, demo-first, install-instruction-second. Do not put a feature matrix above the fold. The user should know in five seconds whether kniferoll is for them.
- **The path hierarchy is human-readable.** `silo-agent/kniferoll-managed-linux-deb/install.sh` reads as org → project-posture-os → entry. A reader sees what they're running before opening the file.
- **Errors don't blame users.** "Could not install X — even the best chefs order takeout sometimes." stays. "Operation completed successfully" never appears.
- **Zero emoji in installer output.** The 🔪 in the README is fine; the installer prints only ASCII. Emoji renders inconsistently across terminals, themes, and SSH sessions, and that inconsistency is the opposite of beauty.
- **Documentation has voice.** ARCHITECTURE.md, FLAVOR.md, SUPPLY_CHAIN_RISK.md, and zscaler.md (in the private repos) all keep their first-person, declarative tone. Manifestos > manuals.

---

## 6b. TUI selector parity across OSes

The macOS installer in v1 carries a TUI selector that is significantly more advanced than what `install_linux.sh` or `install_windows.ps1` do. v2 ports that capability to all four OS targets — tailored per platform, not copied verbatim. The contract is the contract; the implementation per OS is whatever fits the platform best.

### 6b.1 The TUI contract (source of truth: macOS v1)

v1's macOS TUI lives in two places: a Bubbletea Go binary at `tui/selector/main.go` invoked from `install_mac.sh:556-622`, and a bash fallback (`show_menu` at `install_mac.sh:603-623`, `show_custom_menu` at `581-601`) used when the Go binary can't build. The Bubbletea implementation is the user-facing experience; the bash fallback is the safety net.

v2 keeps the *behavior*, drops Go as a hard dependency, and puts the implementation inside each install script.

**Top-level menu (single select).**

1. Full install
2. Shell only
3. Projector only
4. Custom

**Custom sub-categories (multi-select).**

1. Shell environment (Zsh / PowerShell, plugins, dotfiles)
2. AI Tools (gemini-cli, Anthropic Claude — pending §9 OQ#3)
3. Developer Tools (bat, fzf, jq, ripgrep, lsd, micro, tmux, starship, btop, language toolchains)
4. Package Managers (npm, yarn, pipx, uv, rustup)
5. Security Tools (1Password CLI, nmap, openssl, yara, wtfis, ngrep, wireshark)
6. Cloud / CLI (AWS CLI, rclone)
7. Nerd Fonts (13 families pinned at v3.4.0)
8. Projector Stack (weathr, trippy, animation runtime)
9. Desktop Apps (macOS only: iTerm2, Keka)

**State flow.** Top-level is single-select. Custom is multi-select. First-run defaults: all sub-categories checked (the v1 default and the safe fallback when anything goes sideways). Subsequent runs read prior selections from `state.json` and present those as defaults.

**Visual affordances (floor every implementation must clear).** A banner identifying script + posture + OS, a divider, a cursor glyph on the focused row, multi-select checkboxes that distinguish by both glyph and color (`[✓]` / `[ ]`), and a bottom help bar listing the keys in plain text: `SPACE toggle · ENTER confirm · a toggle all · q abort`. Cyberwave palette where color is supported. Alt-screen rendering where the platform supports it, so the menu leaves scrollback unchanged on exit.

**Keyboard contract.** Up / `k` — cursor up. Down / `j` — cursor down. Space — toggle focused item. `a` — toggle-all (any unchecked → check all; else uncheck all). Enter — confirm and exit. `q` or Ctrl+C — abort.

**One change from v1.** Aborting in v1's Bubbletea silently defaulted to "install everything" (`tui/selector/main.go:379-382`). v2 considers that a footgun: aborting exits non-zero with `selection aborted; nothing installed`, and the user re-runs. Quiet success on abort is worse than loud failure.

**Output contract.** The TUI emits `KEY=true|false` lines on stdout, one per sub-category, in a stable order. The install script captures stdout and sources the lines as shell variables (bash) or a hash-table (PowerShell). This seam — between the TUI and the rest of the script — is identical across all four OSes and must not vary.

### 6b.2 State persistence

Every run writes the user's confirmed selection to `~/.kniferoll/state.json` on Unix, `%APPDATA%\kniferoll\state.json` on Windows. Format:

```json
{
  "schema": 1,
  "last_run_iso": "2026-05-02T14:30:00Z",
  "preset": "custom",
  "selections": {
    "shell_env": true,
    "ai_tools": false,
    "dev_tools": true,
    "pkg_mgrs": true,
    "security": false,
    "cloud_cli": true,
    "fonts": true,
    "projector": false,
    "desktop_apps": true
  }
}
```

On subsequent runs the TUI reads `state.json` and presents saved selections as defaults. First run (no file) falls back to all-checked.

`--non-interactive` bypasses the TUI entirely and runs with last-saved selections. If no `state.json` exists, `--non-interactive` runs the conservative "Full install" preset (matching v1 batch-mode behavior). This flag is the ergonomic answer to CI usage *and* to re-running after a partial failure — the user fixes the cause, runs `install.sh --non-interactive`, and gets exactly the same selections they confirmed last time.

`--dry-run` reads `state.json`, prints what would be selected, does not prompt, does not modify `state.json`.

### 6b.3 Per-OS implementation

**macOS (`kniferoll-mac` / `kniferoll-managed-mac`) — pure bash, re-exec'd under brewed bash 4+.**

A bash-only TUI using ANSI escapes and `read -rsn1` for keystroke handling. Pure bash hits the §6.1 "no Go binary as a hard dependency" mandate and drops the Bubbletea binary. The TUI is ~250 lines, ships in `lib/tui.sh`, no external deps.

The catch: macOS Apple Silicon ships with bash 3.2, which lacks associative arrays and `mapfile` — both of which the TUI uses. `install.sh`'s preamble checks `BASH_VERSION`, locates a brewed bash 4+ at `/opt/homebrew/bin/bash` or `/usr/local/bin/bash`, and re-execs itself under it. If neither exists, the script falls back to sequential yes/no prompts (the v1 `show_custom_menu` pattern). The README documents this: "macOS ships with bash 3.2; we use a brewed bash for the TUI and re-exec automatically — if Homebrew isn't installed yet, the script bootstraps it before the TUI runs."

**Linux Debian/Ubuntu (`kniferoll-linux-deb` / `kniferoll-managed-linux-deb`) — gum primary, whiptail fallback.**

Primary: `gum choose --header --no-limit --selected=...` from charmbracelet. gum produces the closest aesthetic match to the macOS Bubbletea look (same author, same `lipgloss` backend) and handles the keyboard contract natively. gum is installed in the script's preflight if missing — a small early apt install before the TUI runs.

Fallback: `whiptail`, which ships in default Ubuntu/Debian and works without network. `whiptail --checklist` is less pretty than gum but covers the multi-select contract with full keyboard navigation.

Last-resort: sequential yes/no prompts (the equivalent of v1's `show_custom_menu`). Cascade is gum → whiptail → sequential, runtime-detected; first available wins.

**Linux Arch (`kniferoll-linux-arch` / `kniferoll-managed-linux-arch`) — same as Debian, different bootstrap.**

gum primary (from AUR via the configured helper, or from charmbracelet's release binary), whiptail fallback (from `core`, bundled with `libnewt`). Sequential as last-resort. The only divergence from Debian is the install command if gum is missing during preflight: `pacman -S gum` or `<aur-helper> -S gum-bin` instead of `apt install`.

**WSL2 (`kniferoll-wsl2` / `kniferoll-managed-wsl2`) — inherits the Debian implementation.**

WSL2 uses the same gum-primary, whiptail-fallback chain as `kniferoll-linux-deb`; the Linux TUI implementation is sourced from the same place (subtreed `lib/`). The only WSL2-specific TUI consideration is that the corp-CA preflight banner (§6b.4) reads from `/mnt/c/...` paths in addition to the standard Linux trust-store paths. No new TUI code; just one more entry in the auto-detect path list.

**Windows (`kniferoll-windows` / `kniferoll-managed-windows`) — pure PowerShell, idiomatic.**

Not a port of the bash TUI shape. Written PowerShell-first.

Primary: `Out-GridView -PassThru -Title "..."`. `Out-GridView` is built into most PowerShell installs and provides a GUI-flavored checkbox list; `-PassThru` returns the selected items. Native, zero external deps, keyboardable.

Fallback: a `Read-Host`-based menu that renders categories with numbered toggles. User types a number to flip a row's state, types `done` (or empty Enter) to confirm. Less polished but works in any PowerShell session, including remote/headless.

`PSReadLine` selection menus are *not* used unless `PSReadLine` is already loaded. The v2 install path won't pull in PSReadLine just for the TUI — avoiding extra module loads is cheap insurance against version conflicts.

### 6b.4 Managed-posture surfacing

Managed scripts run an additional layer in the TUI. Before any sub-category list is shown, the menu surfaces the corp-CA preflight result:

```
[CORP-CA]  OK  Detected: /etc/ssl/certs/corp.pem  (loaded)
```

or

```
[CORP-CA]  ERR Not found. Set $KR_CA_BUNDLE or pass --ca-bundle PATH.
              Network-dependent items will be unselectable below.
```

Items that require network (every category except a managed-shell-only install) are visibly marked unavailable when the corp-CA preflight has failed. The user can still see the categories — important for understanding what the script *would* do — but cannot select them in this state.

If the user tries to confirm with greyed items still selected, the script returns a hard error and instructs the user to either fix the CA bundle (the recommended path) or unselect the network-dependent items (the workaround path). No auto-bypass; no quiet skip.

### 6b.5 Cross-cutting principles

- **Keyboard-only.** Every implementation must work without a mouse. macOS, Linux gum/whiptail, and Windows `Read-Host` are keyboard-native; Windows `Out-GridView` is mouse-friendly but also fully keyboardable (Tab, arrows, Space, Enter).
- **Sane defaults on first run.** All sub-categories checked. Matches v1.
- **Previous selections remembered.** `~/.kniferoll/state.json` (or platform equivalent) is the source. Written on confirm; read on every subsequent run.
- **Dry-run shows would-select without prompting.** `--dry-run` reads `state.json` and prints; never opens a TUI.
- **`--non-interactive` skips the TUI entirely.** Uses last-saved selections; falls back to "Full install" if none. Designed for CI and for resuming after a partial failure.
- **Aborts are loud, not quiet.** `q` or Ctrl+C exits non-zero with `selection aborted; nothing installed`. This is the one place v2 explicitly breaks v1's behavior; v1's silent default-everything-on-abort was a footgun.

### 6b.6 Honest divergence

The contract — categories, output format, state file, keyboard intent (toggle / confirm / abort / toggle-all) — is identical across the four OSes. What necessarily diverges:

- **Visual style.** macOS pure-bash ANSI ≈ Linux gum (both lipgloss-flavored when gum is present) ≈ macOS-Bubbletea-v1 in look and feel. Windows `Out-GridView` is a grid widget, not an ANSI list, and looks Windows-y. Pretending the four are byte-identical would be worse than letting each platform look like itself.
- **Bash-version requirements.** macOS re-execs to bash 4+ under Homebrew. Linux uses bash 4+ natively (every supported distro ships it). Windows is PowerShell 7+. Each per-OS README documents the version requirement and the fallback chain.
- **Fallback chains.** macOS: pure-bash TUI → sequential yes/no (when no brewed bash). Linux: gum → whiptail → sequential. Windows: `Out-GridView` → `Read-Host`. Documented per-script.

These divergences are intentional and called out in the docs. Uniformity-by-pretense would be worse than uniformity-by-contract.

---

## 7. Per-script structure

Every one of the ten scripts follows the same skeleton. The skeleton lives as a documented contract at `kniferoll-unpack/lib/SKELETON.md` and is subtreed alongside the rest of `lib/` into every per-OS repo; new scripts are diffs against the skeleton.

**Header block.** Shebang (`#!/usr/bin/env bash` or `#!/usr/bin/env pwsh`), strict mode (`set -Eeuo pipefail` for bash, `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'` for PowerShell), then a 10-line comment header: repo name, target OS, posture, version, build date, source repo URL, license, brief description, link to docs, the `kniferoll-unpack@<tag>` the subtreed `lib/` was sourced from (read from `lib/VERSION`).

**Preflight.** Six checks, in order, each with its own exit code:

1. OS check (`uname -s` / `$IsWindows`) — must match the script's target.
2. Arch check (`uname -m` / `$env:PROCESSOR_ARCHITECTURE`) — must match.
3. Shell version (bash ≥ 4 / PowerShell ≥ 7) — refuse otherwise.
4. Network egress (HEAD to `https://github.com/` with configured CA bundle) — abort if unreachable.
5. Posture check (managed scripts only): CA bundle resolvable from `--ca-bundle`, `KR_CA_BUNDLE`, or auto-detect path list.
6. Root check — refuse if EUID==0 and `--root` not passed.

Each preflight failure prints the specific reason and exits with the matching code (see exit-code table below). No preflight failure cascades into a half-install.

**Idempotency contract.** Running the script twice in succession on a clean state produces the same final state. Running it twice on a partially-completed state catches up the partial install without redoing finished work. Running it with `--force` reinstalls everything regardless of state.

**Mode flags** (uniform across all ten scripts):

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

**Log format.** Every line: `<isots> <level> <repo> <phase> <step> | <message>`. Levels: `OK`, `INFO`, `WARN`, `SKIP`, `ERROR`. The `<repo>` token is the bare repo name (e.g., `kniferoll-managed-mac`), since every script's filename is just `install.sh` and would not disambiguate. Logs go to stderr (for live tail) and to `~/.kniferoll/logs/<repo>-<isots>.log` (for after-the-fact audit). The split-terminal UI from v1's `lib/split_terminal.sh` is preserved as an opt-in (`--split-ui` flag), not a default — it's lovely but it conflicts with `--dry-run | less` and other piping patterns.

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

kniferoll v2's niche is **opinionated, multi-OS, corp-CA-aware, beautiful, single-step terminal-environment setup for security/dev/SRE practitioners who work across personal and corporate machines**. The five-target × two-posture matrix is the differentiator: no other tool in this list cleanly handles "I have a personal MacBook, a work Windows laptop with Zscaler, an Ubuntu desktop at home, a corp WSL2 environment for daily work, and a Raspberry Pi 4 in my closet" with matched-quality first-class scripts for each.

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

One remains. Everything else is resolved (see below) or scoped to a phase boundary.

1. **Inventory bumps from v1 to v2.** Anthropic Claude CLI (winget-only in v1 — cross-platform in v2?), the AI-CLI bucket as a whole (gemini-cli, claude — first-class category, opt-in module, or out?). The `gum` part of this question is implicitly resolved by §6b's TUI recommendation (gum is in-scope on Linux as the TUI primary; whether it's *also* a user-facing tool is a separate inventory call). Needs an answer before phase 6.

**Phase-6 design detail (deferred, not blocking phase 1):** corp-side policy file format. Managed scripts will accept a small `kniferoll-corp.toml` (or .json) at `/etc/kniferoll/corp.toml` or `~/.config/kniferoll/corp.toml` defining: CA bundle path, internal package mirror URLs, MDM-detection commands. (Notably *not* splash-page selectors — see §6.2.) This is also the file that feeds the `KR_INTERNAL_REPOS` switch. Designed in phase 6.

### Resolved

- **Naming.** Flat: `kniferoll-<os>` and `kniferoll-managed-<os>`. Entry script inside each per-OS repo is `install.sh` (Unix) / `install.ps1` (Windows).
- **Repo granularity.** Thirteen repos under `silo-agent` when complete: ten per-OS (eight extant + two WSL2 to-be-created), two coordination (to-be-created), one ancillary projector (to-be-created). See §5.1, §5b, §3.4.
- **WSL2 promotion.** Its own pair of repos (`kniferoll-wsl2` + `kniferoll-managed-wsl2`); not folded into linux-deb. Justified by the resolv.conf lock dance, `/etc/wsl.conf` editing, distro filtering, time drift, the cross-boundary corp-CA story, and the WSL1 refusal. See §3.4.
- **Projector disposition.** Split into `silo-agent/kniferoll-projector` (public, ancillary). Opt-in via each per-OS repo's `--projector` flag. Nothing from the projector ships in any per-OS default tool inventory; iterates on its own cadence.
- **Coordination layer shape.** Bootstrap entry + shared library in one repo per posture. Per-OS repos consume via subtree (§5b.1).
- **Shared-code mechanism.** Git subtree with `make sync-core`. Squashed merge commits, `lib/VERSION` for human-readable upstream tag, no submodules, no manual vendoring. (§5b.2)
- **Posture isolation.** Strict one-way dependency: public never reads private, private subtrees public, never the reverse. CI grep-fails any `managed-unpack` reference in `kniferoll-unpack`. (§5b.3)
- **Account shape.** Personal account today, possibly org later. Per-collaborator grants today; team grants on org conversion.
- **TUI selector.** Per-OS in-script implementation; behavior matches the macOS contract documented in §6b. WSL2 inherits the Linux-Debian implementation. Not a separate repo, not a separate binary.
- **Internal-repos toggle.** Built but off by default in v2.0 (§6.2). Phase 10 wires it on.
- **Splash-page bypass.** Never. v1's auto-form-submit logic does not come forward.
- **Cooling-off period.** 7 days from upstream release before any version pin lands. CI-enforced. Emergency override via `--allow-fresh` with documented reason. (§6.2)
- **Lean default inventory.** Every default tool earns its slot. The projector stack and other "nice-to-have" tools are opt-in flags or live in their own repos. (§6.2)
- **Pedagogy norm.** Every non-trivial agent contribution produces a code deep dive in `docs/deep-dives/<feature>.md`. Documented in §11; canonical contract in `kniferoll-unpack/docs/PEDAGOGY.md`; per-repo agent instructions point at it.
- **Project name.** `kniferoll`. The `terminal-` prefix is dead.
- **Old `terminal-kniferoll` repo.** Keep on `main` as a frozen v1 reference. Tag the last v1 commit `v1-final`. Let it rest as documentation of what we used to do and why.
- **Telemetry.** None, ever, in any posture. Recorded in `kniferoll-unpack/docs/ARCHITECTURE.md` as a non-negotiable.

---

## 10. Phasing

Sequenced by what unlocks the most learning fastest, not by OS.

**Phase 0 — Pre-flight.** Eight per-OS repos exist; admin grants done; naming and repo strategy locked. Remaining: create the five new repos (`kniferoll-wsl2`, `kniferoll-managed-wsl2`, `kniferoll-unpack`, `kniferoll-managed-unpack`, `kniferoll-projector`) per the §5.1 command block, grant `albethere` admin on each, apply discoverability topics. Resolve the one remaining open question (§9: inventory bumps) before phase 6. No installer code yet.

**Phase 1 — Skeleton.** `kniferoll-unpack` gets its initial structure: stubbed `unpack` dispatcher, `lib/` skeleton (download-and-verify, log format, exit-code helpers, manifest writer, `SKELETON.md`, `PEDAGOGY.md`), `docs/` with `ARCHITECTURE.md` + `FLAVOR.md` first drafts. Tag `kniferoll-unpack@v0.1.0`. Each of the five unmanaged per-OS repos (`kniferoll-mac`, `-windows`, `-linux-deb`, `-linux-arch`, `-wsl2`) commits its `install.sh` / `install.ps1` skeleton (header, preflight, mode flags, exit codes, log format — no install logic yet) and runs `make sync-core` to subtree the v0.1.0 lib. `kniferoll-projector` gets its own minimal scaffold: README pointing at its purpose as opt-in, an empty `install.sh` stub. Goal: a user can clone any unmanaged per-OS repo, run `./install.sh --dry-run`, and see the skeleton produce empty output. The unpack dispatcher's OS detection works end-to-end for the unmanaged path.

**Phase 2 — First slice: `kniferoll-linux-deb`.** Implement end-to-end. apt + cargo + curated GitHub releases + Zsh setup + dotfile rendering + manifest + `--dry-run` + `--check` + `--force` + `--non-interactive`. The TUI selector ships in this phase as the reference contract for the others (per §6b). The WSL2-detection-and-refuse preflight ships here too, suggesting `kniferoll-wsl2` to anyone who runs `kniferoll-linux-deb` inside WSL. Every later script is a diff against this. First because: (a) Debian/Ubuntu is the highest-volume target, (b) apt is the most predictable package manager, (c) the v1 Linux script is canonical and best-tested. Cut `kniferoll-linux-deb@v1.0.0`.

**Phase 3 — Same hand, new arch: `kniferoll-linux-arch`.** pacman + AUR helper detection. The shared inventory data structure is exercised across two distros for the first time; this stresses the "tools are inline data" principle. Bugs found here are reflected back into `kniferoll-unpack/lib/` (and bumped on each consumer via `make sync-core`).

**Phase 4 — Cross the threshold: `kniferoll-mac`.** Homebrew, different file paths (`~/.zshrc` vs `~/.zprofile` precedence, `/opt/homebrew` prefix, iTerm2 colorscheme deployment). The TUI ports to brewed-bash-4 with associative-array selection state and persistence (§6b). The lib proves itself across two OS families.

**Phase 5 — Cross the boundary: `kniferoll-wsl2`.** WSL2-specific work: the resolv.conf lock dance (delete → write 1.1.1.1/8.8.8.8 → `chattr +i`), `/etc/wsl.conf` editing (`generateResolvConf=false`, `systemd=true`, `appendWindowsPath=false`, automount `metadata`), distro filtering (Debian/Ubuntu only; refuse other WSL distros and WSL1), `systemd-timesyncd` for clock drift, the `kniferoll-wsl2 dns --set ...` companion command for future DNS edits. The rest of the install logic is largely shared with `kniferoll-linux-deb` via the lib subtree — the WSL2 script's job is to layer the WSL specifics on top, not re-implement the Debian install.

**Phase 6 — Mind the proxy: `kniferoll-managed-unpack` + `kniferoll-managed-linux-deb`.** First managed-repo work. Stand up `kniferoll-managed-unpack`: stub `unpack` dispatcher with hard CA preflight, subtree `kniferoll-unpack/lib/` into `lib/`, seed `managed-lib/` (canonical: `ca_detection.sh`, `ca_propagation.sh`, `mdm_probes.sh`, `internal_repos.sh`). Bump `kniferoll-unpack/lib/` (e.g., to `v0.2.0`) if new primitives are needed for corp posture. Implement `kniferoll-managed-linux-deb`: corp-CA detection, CA bundle propagation across the env-var fan-out (§6.2), the **internal-repos toggle code paths** (off by default, per §6.2), the corp policy file reader. No splash-page bypass — exit 5 with browser remediation. Goal: get the corp posture *exactly right* on one script before extending. The corp-CA propagation is the highest-stakes code in v2.

**Phase 7 — Fill the matrix: `kniferoll-managed-mac`, `kniferoll-managed-linux-arch`, `kniferoll-managed-wsl2`.** Port the corp-CA work from phase 6 into the other three managed Unix scripts. `kniferoll-managed-wsl2` adds the cross-boundary trust-store story: `$KR_CA_BUNDLE` resolution from `/mnt/c/...`, the documented PowerShell one-liner for exporting the corp CA from the Windows trust store, and the optional `--auto-export-ca` interop path (off by default). By now the pattern is set; these are diffs against phase 6 and their unmanaged twins.

**Phase 8 — Other shore: `kniferoll-windows`, `kniferoll-managed-windows`.** PowerShell 7. winget. Scoop. Both unmanaged and managed in the same phase because the corp-CA work for Windows is sufficiently different from Unix (cert store enumeration, `CARGO_HTTP_CAINFO`, group-policy paths) that it benefits from being designed against both audiences at once. The Windows TUI follows the §6b PowerShell-idiomatic recommendation (`Out-GridView` primary, `Read-Host` menu fallback). The longest phase, because PowerShell is foreign to most of the project's muscle memory.

**Phase 9 — Ship v2.0.** Demo GIFs. README polish (per-repo READMEs and `kniferoll-unpack/README.md` as the de-facto home page). CI per public repo. Smoke tests for the managed repos (running internally). Tag `v1.0.0` on every per-OS repo, on `kniferoll-unpack` / `kniferoll-managed-unpack`, and on `kniferoll-projector` (independent cadence after this point). `KR_INTERNAL_REPOS` ships *disabled* per §6.2; v2.0 works end-to-end against public sources on every posture. The frozen `albethere/terminal-kniferoll` repo gets a `README` pointer to the new family and a `v1-final` tag on its last commit.

**Phase 10 (post-v2.0) — Internal-repos enablement.** Wire the off-by-default `KR_INTERNAL_REPOS` paths from phase 6 to a real corporate-mirror configuration. Test against staged internal mirrors. Tag managed scripts `v1.1.0` with the toggle ready for users who set the flag. The toggle stays per-user/per-host, never globally on by default.

Phasing front-loads the highest-risk work (corp-CA in phase 6) only *after* the unmanaged shape is locked in four platforms (deb, arch, mac, wsl2). The corp design has four working examples to defend against, and the corp work is not allowed to leak back into the unmanaged path. That separation is the rewrite's central structural bet, and the phasing is built to enforce it.

---

## 11. Pedagogy: code deep dives for the human operator

This rewrite is also a learning vehicle. Chef is moving from SOC operator into AI-driven detection engineering — a role where the work is increasingly mediated by agents but the human still has to *understand* the code well enough to debug, extend, and trust it. Code that an agent shipped without explanation is code that becomes opaque the next time it breaks at 11pm. Detection engineering at scale will increasingly mean reading code that an agent wrote at 3am and acting on it at 9am; the half-life of "I'll just ask the agent again" is short, the half-life of "I read the deep dive once and now I understand this module" is long.

The norm: every agent contribution to a kniferoll repo produces a *code deep dive* alongside. Deep dives are a separate artifact from PR descriptions and from inline comments. They live in `docs/deep-dives/<feature>.md` inside the repo where the change lands.

### 11.1 What a deep dive is for

PR descriptions answer "what changed and why this PR exists." Inline comments answer "what was non-obvious about this single line or block." Deep dives answer the question between those two: *if you opened this module fresh next year, what would you need to know to read it confidently and modify it without breaking everything?*

The audience is the human operator (Chef primarily; future contributors secondarily). The audience is not the agent that wrote the code — agents will read the actual code. The deep dive exists so the human stays in the loop *and* builds standing knowledge.

### 11.2 What a deep dive contains

Six sections, in order:

1. **What this code does (high-level).** One paragraph. Pretend the reader has never seen the file. Name the inputs, outputs, side effects. No jargon without footnoting.
2. **Why it's structured this way (design rationale).** Two to four paragraphs. Why this function vs that one, why this data structure, why this control flow. Where alternatives were considered, mention them and why they lost.
3. **Walkthrough.** Line-by-line or block-by-block, in the order the reader would encounter them. Quote the actual code in fenced blocks. Annotate every decision a reader might pause on. This is the long part.
4. **Extension points.** "If you wanted to add support for X, you would change Y and Z." One paragraph per likely future change.
5. **Pitfalls.** "If you change X without also changing Y, you'll silently break Z." Concrete failure modes, observed-or-predicted.
6. **References.** External standards, RFCs, upstream docs that govern the behavior. Linked, not paraphrased.

### 11.3 Cadence

- **Required:** any PR that adds a new module, changes a public API, or touches the AWK / regex / parsing surfaces.
- **Strongly encouraged:** any PR that fixes a non-trivial bug. The deep dive captures *why* the bug existed, which is itself a learning artifact.
- **Optional:** typo fixes, dependency bumps without behavior change, formatting-only PRs.

A deep dive does not gate a PR's merge. CI checks for its presence on required PRs and posts an informational comment if missing; the maintainer decides whether to block on it. The norm is shaped by example, not by tooling.

### 11.4 Where this lives in the agent instructions

Each repo's `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, and `.github/copilot-instructions.md` includes a directive: *"When you write or modify non-trivial code in this repo, also write a `docs/deep-dives/<feature>.md` per the contract in `kniferoll-unpack/docs/PEDAGOGY.md`."* The contract is canonical in `kniferoll-unpack/docs/PEDAGOGY.md` (subtreed into every consumer's `lib/`-adjacent docs); per-repo agent instructions point at it rather than restating it.

### 11.5 Why this matters here specifically

Chef's move from SOC into AI-driven detection engineering is the proximate reason. The deeper reason is that any project where agents do most of the typing and a human does most of the deciding needs a feedback channel that's slower than chat and faster than re-reading the source. Deep dives are that channel. They're written for the human, by the agent, at the moment the code is freshest in the agent's context — and they accumulate as a corpus the human can read in any order, at any time, to keep their model of the system current.

Building deep dives into the project rhythm from day one is cheaper than retrofitting them later, when the modules already exist and nobody remembers the context. v1's `docs/` was a handful of short manifestos that aged well; v2's `docs/deep-dives/` should be a much larger collection that ages just as well because it's tied directly to code-as-shipped, with the kind of detail that survives staffing changes, hardware changes, and the inevitable "what was I thinking when I wrote this?" moment six months out.

---

## Verification

Plan-level verification before any code is written:

- Resolve the one remaining open question in §9 (inventory bumps).
- Run the §5.1 command block to create the five new repos and grant `albethere` admin.

Code-level verification per phase:

- Each `install.sh` / `install.ps1` has a `--dry-run` (or `-DryRun`) that produces parseable output covered by a smoke test.
- Each `install.sh` / `install.ps1` has a `--check` that reports drift against its own manifest.
- Each script's preflight has a unit-testable failure path for every exit code (2.1 through 2.6).
- `kniferoll-unpack/lib/` has a test suite ported and modernized from v1's `scripts/test-sweep.{sh,ps1}`.
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
