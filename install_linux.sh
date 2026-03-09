#!/usr/bin/env bash
# =============================================================================
# terminal-kniferoll | Linux Installer (Shell + Projector)
# =============================================================================

set -e

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}[✔] ${1}${RESET}"; }
info() { echo -e "${CYAN}[*] ${1}${RESET}"; }
warn() { echo -e "${YELLOW}[!] ${1}${RESET}"; }
die()  { echo -e "${RED}[✘] FATAL: ${1}${RESET}" >&2; exit 1; }

# --- Flags ---
INSTALL_SHELL=true
INSTALL_PROJECTOR=true
MODE="passive"

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --shell) INSTALL_PROJECTOR=false ;;
        --projector) INSTALL_SHELL=false ;;
        --interactive) MODE="interactive" ;;
        --passive) MODE="passive" ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

ask_proceed() {
    if [[ "$MODE" == "interactive" ]]; then
        echo -en "\033[0;36m[?] ${1} [Y/n] \033[0m"
        read -r prompt_reply
        if [[ -z "$prompt_reply" || "$prompt_reply" =~ ^[Yy]$ ]]; then
            return 0
        else
            echo -e "\033[1;33m[-] Skipping...\033[0m"
            return 1
        fi
    fi
    return 0
}

# --- OS Gate ---
if command -v apt-get &> /dev/null; then
    PKG_MGR="apt"
    info "Detected Debian/Ubuntu-based system."
elif command -v pacman &> /dev/null; then
    PKG_MGR="pacman"
    info "Detected Arch/CachyOS-based system."
    # Check for AUR helpers
    if command -v yay &> /dev/null; then
        AUR_HELPER="yay"
    elif command -v paru &> /dev/null; then
        AUR_HELPER="paru"
    fi
else
    die "Unsupported Linux distribution. No apt or pacman found."
fi

# --- sudo check ---
SUDO=""
if [[ "$EUID" -ne 0 ]]; then
    if command -v sudo &>/dev/null; then
        SUDO="sudo"
    else
        die "sudo is not installed and you are not root. Cannot proceed."
    fi
fi

# ── 1. CORE ECOSYSTEM ────────────────────────────────────────────────────────
if ask_proceed "Update package repositories?"; then
if [[ "$PKG_MGR" == "apt" ]]; then
    info "Refreshing apt package list..."
    $SUDO apt-get update -qq
elif [[ "$PKG_MGR" == "pacman" ]]; then
    info "Refreshing pacman package list..."
    $SUDO pacman -Sy --noconfirm
fi

fi

# ── 1.5. 1Password CLI (op) ─────────────────────────────────────────────────
if ask_proceed "Install 1Password CLI?"; then
if ! command -v op &>/dev/null; then
  if [[ "$PKG_MGR" == "apt" ]]; then
      info "Adding 1Password repository (APT)..."
      curl -sS https://downloads.1password.com/linux/debian/gpg | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/1password-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | $SUDO tee /etc/apt/sources.list.d/1password.list
      $SUDO apt-get update -qq
      $SUDO apt-get install -y 1password-cli
  elif [[ "$PKG_MGR" == "pacman" ]]; then
      info "Installing 1Password CLI (Pacman)..."
      $SUDO pacman -S --noconfirm 1password-cli
  fi
  mkdir -p $HOME/.1password && $SUDO chown -R "$USER":"$USER" $HOME/.1password
fi

fi

if [ "$INSTALL_SHELL" = true ]; then
    if ask_proceed "Install Base Shell environment (Zsh + Oh My Zsh)?"; then
    info "Installing shell environment (Zsh + Oh My Zsh)..."
    if ! command -v zsh &> /dev/null; then
        if [[ "$PKG_MGR" == "apt" ]]; then $SUDO apt-get install -y zsh; else $SUDO pacman -S --noconfirm zsh; fi
        chsh -s "$(which zsh)"
    fi
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    fi
fi

# ── 2. SHARED TOOLING PAYLOAD (2026 STANDARDS) ──────────────────────────────
if ask_proceed "Install Shared Tooling Payload (2026 Standards)?"; then
info "Installing 2026-standard tooling payload..."

if [[ "$PKG_MGR" == "apt" ]]; then
    APT_PACKAGES=(
        1password-cli binutils btop ca-certificates curl exiftool fastfetch fontconfig
        fzf git gnutls-bin golang gzip hexyl jq libssl-dev lua5.4 lz4 m4 micro
        ncurses-bin ngrep nmap nodejs openssl pipx python3 python3-pip python3-venv
        rclone ripgrep ruby rustup speedtest-cli sqlite3 tcpdump tealdeer tmux unbound uv
        wireshark yara zsh-autosuggestions cmatrix cbonsai
        nushell yazi mise trippy atuin zoxide starship lolcat
    )
    for pkg in "${APT_PACKAGES[@]}"; do
        if dpkg -s "$pkg" &> /dev/null 2>&1; then ok "$pkg verified"; else
            info "Installing $pkg..."
            $SUDO apt-get install -y -qq "$pkg" || warn "Could not install $pkg"
        fi
    done
elif [[ "$PKG_MGR" == "pacman" ]]; then
    PACMAN_PACKAGES=(
        1password-cli binutils btop ca-certificates curl exiftool fastfetch fontconfig
        fzf git gnutls go gzip hexyl jq openssl lua lz4 m4 micro
        ncurses ngrep nmap nodejs python-pipx python python-pip
        rclone ripgrep ruby rustup speedtest-cli sqlite tcpdump tealdeer tmux unbound uv
        wireshark-cli yara zsh-autosuggestions cmatrix
        nushell yazi mise trippy atuin zoxide starship lolcat
    )
    for pkg in "${PACMAN_PACKAGES[@]}"; do
        if pacman -Qi "$pkg" &> /dev/null; then ok "$pkg verified"; else
            info "Installing $pkg..."
            $SUDO pacman -S --noconfirm "$pkg" || warn "Could not install $pkg"
        fi
    done
    # cbonsai is often AUR
    if ! command -v cbonsai &>/dev/null; then
        if [[ -n "$AUR_HELPER" ]]; then
            info "Installing cbonsai via $AUR_HELPER..."
            $AUR_HELPER -S --noconfirm cbonsai
        fi
    fi
fi

fi

# ── 3. PROJECTOR SPECIFIC DEPS ───────────────────────────────────────────────
if [ "$INSTALL_PROJECTOR" = true ]; then
    if ask_proceed "Install Projector specific dependencies (Rust/Cargo, weathr)?"; then
    info "Verifying Projector dependencies (Rust/Cargo, weathr)..."
    if ! command -v cargo &>/dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
        source "$HOME/.cargo/env"
    fi
    if ! command -v weathr &>/dev/null; then
        cargo install weathr
    fi
    fi
fi

# ── 4. MODERN RUST/PYTHON CLI TOOLS ──────────────────────────────────────────
if ask_proceed "Install Modern CLI Tools (lsd, bat, sd, atuin, etc.)?"; then
install_github_deb() {
    local repo="$1"
    local pattern="$2"
    local name="$3"
    if command -v "$name" &>/dev/null; then ok "$name verified"; return; fi
    info "Installing $name from GitHub releases..."
    local url
    url=$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
        | grep browser_download_url | grep "$pattern" | head -1 | cut -d '"' -f4)
    if [ -n "$url" ]; then
        local tmpfile=$(mktemp /tmp/"$name"-XXXXXX.deb)
        curl -fsSL "$url" -o "$tmpfile"
        $SUDO dpkg -i "$tmpfile"
        rm -f "$tmpfile"
    fi
}

install_github_deb "lsd-rs/lsd" "amd64.deb" "lsd"
install_github_deb "sharkdp/bat" "amd64.deb" "bat"
install_github_deb "chmln/sd" "x86_64-unknown-linux-gnu" "sd"

if ! command -v atuin &> /dev/null; then
    bash <(curl -fsSL https://setup.atuin.sh) || cargo install atuin
fi
if ! command -v zoxide &> /dev/null; then
    curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
fi
if ! command -v wtfis &> /dev/null; then
    pipx install wtfis
    pipx ensurepath
fi
if ! command -v lolcat &> /dev/null; then
    $SUDO gem install lolcat || pip3 install --quiet lolcat
fi

fi

# ── 5. ZSH PLUGINS ───────────────────────────────────────────────────────────
if [ "$INSTALL_SHELL" = true ]; then
    if ask_proceed "Install ZSH Plugins (autosuggestions, syntax-highlighting)?"; then
    ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    mkdir -p "$ZSH_CUSTOM/plugins"
    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    fi
    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-fast-syntax-highlighting" ]; then
        git clone --depth=1 https://github.com/zdharma-continuum/fast-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-fast-syntax-highlighting"
    fi
    fi
fi

# ── 6. JETBRAINSMONO NERD FONT ───────────────────────────────────────────────
if ask_proceed "Install JetBrainsMono Nerd Font?"; then
FONT_DIR="$HOME/.local/share/fonts"
if ! fc-list | grep -qi "JetBrainsMono" &>/dev/null; then
    info "Installing JetBrainsMono Nerd Font..."
    mkdir -p "$FONT_DIR/JetBrainsMono"
    TMP_ZIP=$(mktemp /tmp/font-XXXXXX.zip)
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" -o "$TMP_ZIP"
    unzip -q "$TMP_ZIP" -d "$FONT_DIR/JetBrainsMono"
    fc-cache -f
    rm -f "$TMP_ZIP"
fi

fi

# ── 7. CONFIG DEPLOYMENT ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$INSTALL_SHELL" = true ]; then
    if ask_proceed "Deploy Shell configurations (.zshrc, aliases, plugins)?"; then
    info "Deploying shell configurations..."
    mkdir -p "$HOME/.shell"
    cp "$SCRIPT_DIR/shell/zshrc.zsh" "$HOME/.zshrc"
    cp "$SCRIPT_DIR/shell/aliases.zsh" "$HOME/.shell/aliases.zsh"
    cp "$SCRIPT_DIR/shell/plugins.zsh" "$HOME/.shell/plugins.zsh"
    fi
fi

if [ "$INSTALL_PROJECTOR" = true ]; then
    if ask_proceed "Deploy Projector configuration?"; then
    info "Deploying Projector configuration..."
    mkdir -p "$HOME/.config/projector"
    if [ ! -f "$HOME/.config/projector/config.json" ]; then
        cp "$SCRIPT_DIR/projector/config.json.default" "$HOME/.config/projector/config.json"
    fi
    chmod +x "$SCRIPT_DIR/projector.py"
    fi
fi

ok "Installation Complete!"
