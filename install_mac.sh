#!/usr/bin/env bash
# =============================================================================
# terminal-kniferoll | macOS Installer (Shell + Projector)
# =============================================================================

set -e

# --- Colors ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}[✔] ${1}${RESET}"; }
info() { echo -e "${CYAN}[*] ${1}${RESET}"; }
warn() { echo -e "${YELLOW}[!] ${1}${RESET}"; }
die()  { echo -e "${RED}[✘] FATAL: ${1}${RESET}" >&2; exit 1; }

# --- Flags ---
INSTALL_SHELL=true
INSTALL_PROJECTOR=true

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --shell) INSTALL_PROJECTOR=false ;;
        --projector) INSTALL_SHELL=false ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# --- Homebrew Check ---
if ! command -v brew &> /dev/null; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    ok "Homebrew verified"
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# ── 1. CORE ECOSYSTEM ────────────────────────────────────────────────────────
if [ "$INSTALL_SHELL" = true ]; then
    info "Installing shell environment (Oh My Zsh)..."
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
fi

# ── 2. SHARED TOOLING PAYLOAD ────────────────────────────────────────────────
info "Installing shared tooling payload (Homebrew)..."

BREW_PACKAGES=(
    atuin bat binutils btop ca-certificates cbonsai certifi cmatrix exiftool
    fastfetch fontconfig freetype fzf gh git gnutls go gzip
    harfbuzz hashcat hexyl jq lolcat lsd lua lz4 lzo m4 micro ncurses ngrep
    nmap node openjdk openssl@3 pipx python@3.11 ripgrep ruby rustup
    sd speedtest-cli sqlite tcpdump tealdeer tmux unbound uv wireshark wtfis
    zoxide zsh-autosuggestions zsh-fast-syntax-highlighting
)

for pkg in "${BREW_PACKAGES[@]}"; do
    if ! brew list "$pkg" &> /dev/null 2>&1; then
        info "Installing $pkg..."
        brew install "$pkg"
    else
        ok "$pkg verified"
    fi
done

# ── 3. PROJECTOR SPECIFIC DEPS ───────────────────────────────────────────────
if [ "$INSTALL_PROJECTOR" = true ]; then
    info "Verifying Projector dependencies (weathr)..."
    if ! command -v weathr &>/dev/null; then
        cargo install weathr
    fi
fi

# ── 4. CONFIG DEPLOYMENT ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$INSTALL_SHELL" = true ]; then
    info "Deploying shell configurations..."
    mkdir -p "$HOME/.shell"
    cp "$SCRIPT_DIR/shell/zshrc.zsh" "$HOME/.zshrc"
    cp "$SCRIPT_DIR/shell/aliases.zsh" "$HOME/.shell/aliases.zsh"
    cp "$SCRIPT_DIR/shell/plugins.zsh" "$HOME/.shell/plugins.zsh"
    
    # OS-Specific Alias for Tailscale on macOS
    if [[ ! -f "$HOME/.shell/aliases_mac.zsh" ]]; then
        echo 'alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"' > "$HOME/.shell/aliases_mac.zsh"
        echo 'alias sudo="sudo -E"' >> "$HOME/.shell/aliases_mac.zsh"
    fi
    if ! grep -q "aliases_mac.zsh" "$HOME/.zshrc"; then
        echo '[[ -f "$HOME/.shell/aliases_mac.zsh" ]] && source "$HOME/.shell/aliases_mac.zsh"' >> "$HOME/.zshrc"
    fi
fi

if [ "$INSTALL_PROJECTOR" = true ]; then
    info "Deploying Projector configuration..."
    mkdir -p "$HOME/.config/projector"
    if [ ! -f "$HOME/.config/projector/config.json" ]; then
        cp "$SCRIPT_DIR/projector/config.json.default" "$HOME/.config/projector/config.json"
    fi
    chmod +x "$SCRIPT_DIR/projector.py"
fi

ok "Installation Complete!"
