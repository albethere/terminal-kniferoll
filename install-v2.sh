#!/usr/bin/env bash
# ============================================================
#  install-v2.sh — Terminal Kniferoll
#  Kitchen Brigade — Field Deployment Script
#  Version: 2.0 — The "Actually Works This Time" Edition
# ============================================================
# DESIGN PRINCIPLES:
#   1. Skip anything already installed (idempotent re-runs)
#   2. Batch apt installs by group to reduce overhead
#   3. Use --fix-missing to survive stale mirror 404s
#   4. Detect real system arch before downloading .deb releases
#   5. Never let one failure abort the entire mission
# ============================================================

set -euo pipefail

# ─── ANSI Color Palette (256-color where supported) ───────────
RED='\033[0;31m';   GREEN='\033[0;32m';  YELLOW='\033[1;33m'
CYAN='\033[0;36m';  BOLD='\033[1m';     RESET='\033[0m'
DIM='\033[2m'
# Richer palette (knife/chef vibe: steel, heat, herb)
ORANGE='\033[38;5;208m'   # warning / heat
STEEL='\033[38;5;249m'   # neutral / metal
HERB='\033[38;5;106m'    # success accent
BLADE='\033[38;5;255m'   # bright highlight

# ─── Logging Helpers ─────────────────────────────────────────
info()    { echo -e "${CYAN}[⚙]${RESET} $*"; }
ok()      { echo -e "${GREEN}[✔]${RESET} ${HERB}$*${RESET}"; }
warn()    { echo -e "${ORANGE}[!]${RESET} $*"; }
err()     { echo -e "${RED}[✘]${RESET} $*"; }
banner()  { echo -e "\n${BOLD}${STEEL}━━━ ${BLADE}$*${RESET} ${STEEL}━━━${RESET}\n"; }
quip()    { echo -e "${DIM}    ⋮ $*${RESET}"; }

# ─── Global failure tracker ──────────────────────────────────
FAILED_TOOLS=()

# ─── Verify sudo access early ────────────────────────────────
check_sudo() {
    banner "Pre-Flight Authorization Check"
    quip "Sharp knives require a steady hand. Authenticate to continue."
    if ! sudo -v 2>/dev/null; then
        err "sudo authentication failed. Can't chop without clearance."
        exit 1
    fi
    ok "Credentials verified — you're cleared for the kitchen."
    # Keep sudo alive in background for the duration of the script
    ( while true; do sudo -n true; sleep 50; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
}

# ─── Detect system architecture ──────────────────────────────
detect_arch() {
    ARCH="$(dpkg --print-architecture)"      # e.g. amd64, arm64
    UNAME_ARCH="$(uname -m)"                 # e.g. x86_64, aarch64
    quip "Hull architecture confirmed: ${BOLD}${ARCH}${RESET}${DIM} (${UNAME_ARCH})"
}

# ─── Check if a binary is already on PATH ────────────────────
is_installed() {
    command -v "$1" &>/dev/null
}

# ─── apt: install a single package, skip if present ─────────
apt_install() {
    local check_bin="$1"
    local pkg="$2"
    local desc="${3:-$2}"

    if is_installed "$check_bin"; then
        ok "${desc} already aboard — skipping."
        return 0
    fi

    info "Installing ${desc}..."
    if sudo apt-get install -y --fix-missing -q "$pkg" 2>&1 | tail -3; then
        ok "${desc} installed."
    else
        warn "Could not install ${desc} — adding to the casualty report."
        FAILED_TOOLS+=("$pkg")
    fi
}

# ─── apt: batch-install a list of packages ───────────────────
apt_batch() {
    local section="$1"; shift
    local to_install=()

    banner "$section"

    for entry in "$@"; do
        local bin="${entry%%:*}"
        local pkg="${entry##*:}"
        if is_installed "$bin"; then
            ok "${pkg} already on deck — skipping."
        else
            to_install+=("$pkg")
        fi
    done

    if [[ ${#to_install[@]} -eq 0 ]]; then
        quip "Nothing to install in this section. Pantry already stocked."
        return 0
    fi

    info "Beaming aboard: ${to_install[*]}"
    if sudo apt-get install -y --fix-missing -q "${to_install[@]}" 2>&1 | grep -E '(Setting up|already installed|error|E:)'; then
        ok "Section '${section}' deployment complete."
    else
        warn "Partial failure in '${section}' — check logs."
        for pkg in "${to_install[@]}"; do FAILED_TOOLS+=("$pkg"); done
    fi
}

# ─── Install a .deb from a GitHub release ────────────────────
github_deb_install() {
    local check_bin="$1"
    local gh_repo="$2"
    local asset_pattern="$3"
    local tool_name="$4"

    if is_installed "$check_bin"; then
        ok "${tool_name} already in service — skipping GitHub fetch."
        return 0
    fi

    info "Acquiring ${tool_name} from GitHub (${gh_repo})..."
    quip "Hailing GitHub API... stand by."

    local download_url
    download_url=$(
        curl -fsSL "https://api.github.com/repos/${gh_repo}/releases/latest" \
        | grep "browser_download_url" \
        | grep "${asset_pattern}" \
        | grep -v "musl" \
        | head -1 \
        | cut -d'"' -f4
    )

    if [[ -z "$download_url" ]]; then
        quip "Native .deb not found. Attempting musl fallback (fingers crossed)..."
        download_url=$(
            curl -fsSL "https://api.github.com/repos/${gh_repo}/releases/latest" \
            | grep "browser_download_url" \
            | grep "${asset_pattern}" \
            | head -1 \
            | cut -d'"' -f4
        )
    fi

    if [[ -z "$download_url" ]]; then
        warn "Could not locate a .deb for ${tool_name} matching arch '${asset_pattern}'. Logging failure."
        FAILED_TOOLS+=("${tool_name}(github)")
        return 1
    fi

    local tmp_deb
    tmp_deb=$(mktemp /tmp/${tool_name}-XXXXXX.deb)
    quip "Downloading: ${download_url}"
    if curl -fsSL -o "$tmp_deb" "$download_url"; then
        if sudo dpkg -i "$tmp_deb"; then
            ok "${tool_name} installed from GitHub release."
        else
            warn "dpkg install failed for ${tool_name}. Attempting apt -f install to resolve deps..."
            sudo apt-get install -f -y -q || true
        fi
    else
        warn "Download failed for ${tool_name}."
        FAILED_TOOLS+=("${tool_name}(github)")
    fi
    rm -f "$tmp_deb"
}

# ─── Install via Cargo ────────────────────────────────────────
cargo_install() {
    local check_bin="$1"
    local crate="$2"
    local tool_name="${3:-$crate}"

    if is_installed "$check_bin"; then
        ok "${tool_name} already compiled and ready — skipping cargo build."
        return 0
    fi

    if ! is_installed "cargo"; then
        warn "cargo not found. Cannot install ${tool_name}. Did Rust deployment fail?"
        FAILED_TOOLS+=("${tool_name}(cargo)")
        return 1
    fi

    info "Compiling ${tool_name} from source (slow simmer — worth the wait)..."
    # shellcheck disable=SC1091
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
    if cargo install "$crate"; then
        ok "${tool_name} compiled and installed. Blade sharp."
    else
        warn "Cargo install failed for ${tool_name}."
        FAILED_TOOLS+=("${tool_name}(cargo)")
    fi
}

# ─── Install Rust via rustup ─────────────────────────────────
install_rust() {
    banner "Rust / Cargo — The Forge"

    if is_installed "rustc" && is_installed "cargo"; then
        ok "Rust already installed — $(rustc --version). Forge hot."
        return 0
    fi

    quip "Engaging rustup installer. This takes a moment — replicate some coffee."
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path; then
        # shellcheck disable=SC1091
        source "$HOME/.cargo/env"
        ok "Rust installed: $(rustc --version)"
    else
        warn "rustup installation failed. Cargo-dependent tools will be unavailable."
        FAILED_TOOLS+=("rust/cargo")
    fi
}

# ─── Install uv (Python package manager) ─────────────────────
install_uv() {
    if is_installed "uv"; then
        ok "uv already installed — skipping."
        return 0
    fi
    info "Installing uv (Python package manager)..."
    quip "uv is not in standard repos. Fetching from astral.sh..."
    if curl -LsSf https://astral.sh/uv/install.sh | sh; then
        ok "uv installed successfully."
    else
        warn "uv installation failed."
        FAILED_TOOLS+=("uv")
    fi
}

# ─── Install Oh My Zsh ────────────────────────────────────────
install_omz() {
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        ok "Oh My Zsh already colonizing ~/.oh-my-zsh — skipping."
        return 0
    fi
    info "Installing Oh My Zsh..."
    quip "This will not change your default shell mid-script."
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    ok "Oh My Zsh installed."
}

# ─── Add 1Password apt repository ────────────────────────────
add_1password_repo() {
    if [[ -f /etc/apt/sources.list.d/1password.list ]]; then
        ok "1Password repo already in sources.list.d — skipping."
        return 0
    fi
    info "Adding 1Password repository..."
    curl -sS https://downloads.1password.com/linux/keys/1password.asc \
      | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
    echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/${ARCH} stable main" \
      | sudo tee /etc/apt/sources.list.d/1password.list > /dev/null
    sudo apt-get update -q
    ok "1Password repo added."
}

# ─── Print mission summary ────────────────────────────────────
print_summary() {
    banner "Mission Debrief"
    if [[ ${#FAILED_TOOLS[@]} -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}ALL SYSTEMS NOMINAL.${RESET}"
        quip "Zero casualties. Kitchen closed clean."
    else
        echo -e "${YELLOW}${BOLD}MISSION COMPLETE WITH CASUALTIES:${RESET}"
        for t in "${FAILED_TOOLS[@]}"; do
            echo -e "  ${RED}✘${RESET}  ${t}"
        done
        quip "These tools could not be installed. Manual intervention recommended."
        quip "Likely cause: stale mirror (404) or architecture mismatch."
        quip "Try: sudo apt-get update && sudo apt-get install --fix-missing <pkg>"
    fi
    echo
}

# ═══════════════════════════════════════════════════════════════
#  MAIN DEPLOYMENT SEQUENCE
# ═══════════════════════════════════════════════════════════════

clear
echo -e "${BOLD}${CYAN}"
cat << 'BANNER'

  ╔══════════════════════════════════════════════════════════════════╗
  ║                                                                  ║
  ║    ★   T E R M I N A L   K N I F E R O L L   ★                   ║
  ║                          v 2 . 0                                 ║
  ║                                                                  ║
  ║    Kitchen Brigade — Field Deployment Script                      ║
  ║    "Sharp tools. Clean cuts. No leftovers."                       ║
  ║                                                                  ║
  ╚══════════════════════════════════════════════════════════════════╝

BANNER
echo -e "${RESET}"

check_sudo
detect_arch

# ─── Step 1: Update apt ──────────────────────────────────────
banner "Refreshing Package Database"
quip "Pinging all known starbases for package manifests..."
sudo apt-get update -q
ok "Package database refreshed."

# ─── Step 2: Repositories ────────────────────────────────────
banner "Adding Third-Party Repositories"
add_1password_repo

# ─── Step 3: Shell Environment ───────────────────────────────
banner "Shell Environment — Zsh + Oh My Zsh"
apt_install "zsh" "zsh" "Zsh shell"
apt_install "zsh-autosuggestions" "zsh-autosuggestions" "zsh-autosuggestions"
install_omz

# ─── Step 4: Core Security & Network Tools ───────────────────
apt_batch "Core Security Tooling" \
    "nmap:nmap" \
    "tcpdump:tcpdump" \
    "ngrep:ngrep" \
    "wireshark:wireshark" \
    "yara:yara" \
    "unbound:unbound" \
    "gnutls-certtool:gnutls-bin" \
    "hexyl:hexyl"

# ─── Step 5: Developer Utilities ─────────────────────────────
apt_batch "Developer Utilities" \
    "jq:jq" \
    "fzf:fzf" \
    "rg:ripgrep" \
    "micro:micro" \
    "sqlite3:sqlite3" \
    "lua5.4:lua5.4" \
    "m4:m4" \
    "lz4:lz4" \
    "exiftool:libimage-exiftool-perl" \
    "git:git" \
    "curl:curl" \
    "gzip:gzip"

# ─── Step 6: Build Dependencies ──────────────────────────────
apt_batch "Build & Crypto Dependencies" \
    "openssl:openssl" \
    "python3:python3" \
    "pip3:python3-pip" \
    "ruby:ruby" \
    "binutils:binutils" \
    "fc-cache:fontconfig" \
    "ncurses6-config:ncurses-bin" \
    "ca-certificates:ca-certificates" \
    "libssl-dev:libssl-dev"

# ─── Step 7: Python Tooling ──────────────────────────────────
apt_batch "Python Package Management" \
    "pipx:pipx" \
    "python3:python3-venv"

install_uv

# ─── Step 8: System Extras ───────────────────────────────────
apt_batch "System Extras" \
    "rclone:rclone" \
    "btop:btop" \
    "tmux:tmux" \
    "speedtest-cli:speedtest-cli" \
    "unzip:unzip"

# ─── Step 9: Fun/Aesthetic ───────────────────────────────────
apt_batch "Essential Crew Morale Tools" \
    "cmatrix:cmatrix" \
    "cbonsai:cbonsai"

# ─── Step 10: Golang ─────────────────────────────────────────
banner "Go Runtime"
apt_install "go" "golang" "Go (golang)"

# ─── Step 11: Node.js ────────────────────────────────────────
banner "Node.js Runtime"
apt_install "node" "nodejs" "Node.js"

# ─── Step 12: Fastfetch ──────────────────────────────────────
banner "Fastfetch — System Info Display"
apt_install "fastfetch" "fastfetch" "fastfetch"

# ─── Step 13: Rust + Cargo + cargo tools ─────────────────────
install_rust
cargo_install "weathr" "weathr" "weathr (weather CLI)"
cargo_install "trip" "trippy" "trippy (network pulse)"
cargo_install "tldr" "tealdeer" "tealdeer (tldr pages)"

# ─── Step 14: GitHub release installs (arch-safe) ────────────
banner "GitHub Release Installs — lsd & bat"
github_deb_install "lsd" "lsd-rs/lsd" "_${ARCH}.deb" "lsd"
github_deb_install "bat" "sharkdp/bat" "_${ARCH}.deb" "bat"

# ─── Step 15: 1Password CLI ──────────────────────────────────
banner "1Password CLI"
apt_install "op" "1password-cli" "1Password CLI"

# ─── Final Summary ───────────────────────────────────────────
print_summary

echo -e "${BOLD}${CYAN}Deployment complete. Knives sharp. Out.${RESET}"
echo -e "${DIM}Reminder: run 'chsh -s \$(which zsh)' to set Zsh as default shell.${RESET}"
echo -e "${DIM}Reminder: source ~/.cargo/env or restart your shell to activate Rust tools.${RESET}"
