#!/usr/bin/env bash
# =============================================================================
# terminal-kniferoll | macOS Installer (Shell + Projector)
# =============================================================================

set -Eeuo pipefail

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

on_error() {
    local line="$1"
    local cmd="$2"
    warn "Unexpected failure at line ${line}: ${cmd}"
}
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

run_optional() {
    local desc="$1"
    shift
    info "$desc"
    if "$@"; then
        ok "$desc"
        return 0
    fi
    warn "$desc failed; continuing"
    return 1
}

download_to_tmp() {
    local url="$1"
    local pattern="$2"
    local tmp_file
    local old_umask
    old_umask="$(umask)"
    umask 077
    tmp_file="$(mktemp "/tmp/${pattern}")"
    umask "$old_umask"
    chmod 600 "$tmp_file"
    curl -fsSL "$url" -o "$tmp_file"
    echo "$tmp_file"
}

append_if_missing() {
    local file="$1"
    local line="$2"
    touch "$file"
    grep -Fq "$line" "$file" || echo "$line" >> "$file"
}

ask_yes_no() {
    local prompt="$1"
    if [[ "$MODE" != "interactive" ]]; then
        return 0
    fi
    echo -en "${CYAN}[?] ${prompt} [Y/n] ${RESET}"
    read -r prompt_reply
    [[ -z "$prompt_reply" || "$prompt_reply" =~ ^[Yy]$ ]]
}

ensure_rust_toolchain() {
    if ! command -v cargo &>/dev/null; then
        local rustup_script
        rustup_script="$(download_to_tmp "https://sh.rustup.rs" "rustup-init-XXXXXX.sh")"
        run_optional "Installing Rust via rustup" bash "$rustup_script" -y --quiet
        rm -f "$rustup_script"
        [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
    fi
    if command -v rustup &>/dev/null; then
        if ! rustup show active-toolchain &>/dev/null; then
            run_optional "Configuring rustup default stable toolchain" rustup default stable
            [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
        fi
        if ! cargo --version &>/dev/null; then
            run_optional "Repairing Rust toolchain via rustup stable default" rustup default stable
            [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
        fi
    fi
}

# --- Flags ---
INSTALL_SHELL=true
INSTALL_PROJECTOR=true
MODE="passive"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --shell) INSTALL_PROJECTOR=false ;;
        --projector) INSTALL_SHELL=false ;;
        --interactive) MODE="interactive" ;;
        --passive) MODE="passive" ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# --- Homebrew Check ---
if ! command -v brew &> /dev/null; then
    brew_script="$(download_to_tmp "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" "homebrew-install-XXXXXX.sh")"
    run_optional "Installing Homebrew" /bin/bash "$brew_script"
    rm -f "$brew_script"
else
    ok "Homebrew verified"
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

if command -v brew &>/dev/null; then
    BREW_BIN="$(command -v brew)"
    append_if_missing "$HOME/.zprofile" "command -v brew >/dev/null && eval \"\$(brew shellenv)\""
fi

DO_CORE=true
DO_SHELL="$INSTALL_SHELL"
DO_SECURITY=true
DO_PROJECTOR="$INSTALL_PROJECTOR"

if [[ "$MODE" == "interactive" ]]; then
    ask_yes_no "Install/update core prerequisites?" || DO_CORE=false
    if [[ "$INSTALL_SHELL" == "true" ]]; then
        ask_yes_no "Install shell experience (zsh/oh-my-zsh/plugins/config)?" || DO_SHELL=false
    fi
    ask_yes_no "Install security/developer tools (1Password, shared payload, Homebrew gcc, Gemini CLI)?" || DO_SECURITY=false
    if [[ "$INSTALL_PROJECTOR" == "true" ]]; then
        ask_yes_no "Install projector stack (Rust/toolchain, weathr, fonts, projector config)?" || DO_PROJECTOR=false
    fi
fi

# ── 1. CORE ECOSYSTEM ────────────────────────────────────────────────────────
if [[ "$DO_CORE" == "true" ]]; then
    run_optional "Updating Homebrew taps" brew update
fi

if [ "$DO_SHELL" = true ]; then
    info "Installing shell environment (Oh My Zsh)..."
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        omz_script="$(download_to_tmp "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" "ohmyzsh-install-XXXXXX.sh")"
        run_optional "Installing Oh My Zsh" sh "$omz_script" "" --unattended
        rm -f "$omz_script"
    fi
fi

# ── 2. SHARED TOOLING PAYLOAD ────────────────────────────────────────────────
if [[ "$DO_SECURITY" == "true" ]]; then
    info "Installing shared tooling payload (Homebrew)..."
    BREW_PACKAGES=(
        1password-cli atuin bat binutils btop ca-certificates cbonsai certifi cmatrix exiftool
        fastfetch fontconfig freetype fzf gh git gnutls go gzip
        harfbuzz hashcat hexyl jq lolcat lsd lua lz4 lzo m4 micro ncurses ngrep
        nmap node openjdk openssl@3 pipx python@3.11 rclone ripgrep ruby rustup
        sd speedtest-cli sqlite tcpdump tealdeer tmux unbound uv wireshark wtfis
        zoxide zsh-autosuggestions zsh-fast-syntax-highlighting gcc
    )
    for pkg in "${BREW_PACKAGES[@]}"; do
        if brew list "$pkg" &> /dev/null 2>&1; then
            ok "$pkg verified"
        else
            run_optional "Installing $pkg" brew install "$pkg"
        fi
    done

    if ! command -v gemini &>/dev/null; then
        run_optional "Installing Gemini CLI via Homebrew" brew install gemini-cli
        if ! command -v gemini &>/dev/null && command -v npm &>/dev/null; then
            run_optional "Installing Gemini CLI with npm fallback" npm install -g @google/gemini-cli
        fi
    else
        ok "Gemini CLI already installed"
    fi
fi

# ── 3. PROJECTOR SPECIFIC DEPS ───────────────────────────────────────────────
if [ "$DO_PROJECTOR" = true ]; then
    ensure_rust_toolchain
    if ! command -v weathr &>/dev/null; then
        run_optional "Installing weathr via cargo" cargo install weathr
    fi
fi

# ── 4. CONFIG DEPLOYMENT ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$DO_SHELL" = true ]; then
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

if [ "$DO_PROJECTOR" = true ]; then
    info "Deploying Projector configuration..."
    mkdir -p "$HOME/.config/projector"
    if [ ! -f "$HOME/.config/projector/config.json" ]; then
        cp "$SCRIPT_DIR/projector/config.json.default" "$HOME/.config/projector/config.json"
    fi
    chmod +x "$SCRIPT_DIR/projector.py"
fi

ok "Installation Complete!"
