#!/usr/bin/env bash
# =============================================================================
# terminal-kniferoll | Linux Installer (Shell + Projector)
# =============================================================================

set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
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
    if (set +Ee; "$@"); then
        ok "$desc"
        return 0
    fi
    warn "$desc failed; continuing"
    return 0
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

# --- Feature Functions ---

ensure_rust_toolchain() {
    if ! command -v cargo &>/dev/null; then
        local rustup_script
        rustup_script="$(download_to_tmp "https://sh.rustup.rs" "rustup-init-XXXXXX.sh")"
        run_optional "Installing Rust via rustup" bash "$rustup_script" -y --quiet
        rm -f "$rustup_script"
        [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env" || true
    fi

    if command -v rustup &>/dev/null; then
        if ! rustup show active-toolchain &>/dev/null; then
            run_optional "Configuring rustup default stable toolchain" rustup default stable
            [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env" || true
        fi
        if ! cargo --version &>/dev/null; then
            run_optional "Repairing Rust toolchain via rustup default stable" rustup default stable
            [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env" || true
        fi
    fi
}

install_1password_cli() {
    if command -v op &>/dev/null; then
        ok "1Password CLI already installed"
        return 0
    fi

    if [[ "$PKG_MGR" == "apt" ]]; then
        run_optional "Installing 1Password apt prerequisites" bash -c "$SUDO apt-get install -y -qq curl gnupg ca-certificates"
        run_optional "Creating 1Password keyring directory" bash -c "$SUDO install -d -m 0755 /usr/share/keyrings"

        local key_ascii_tmp
        local key_tmp
        local old_umask
        old_umask="$(umask)"
        umask 077
        key_ascii_tmp="$(mktemp /tmp/1password-key-ascii-XXXXXX.asc)"
        key_tmp="$(mktemp /tmp/1password-key-XXXXXX.gpg)"
        umask "$old_umask"
        chmod 600 "$key_ascii_tmp" "$key_tmp"
        run_optional "Downloading 1Password signing key" curl -fsSL "https://downloads.1password.com/linux/keys/1password.asc" -o "$key_ascii_tmp"
        if [[ ! -s "$key_ascii_tmp" ]]; then
            warn "1Password signing key download produced an empty file; skipping 1Password setup"
            rm -f "$key_ascii_tmp" "$key_tmp"
            return 0
        fi
        run_optional "Dearmoring 1Password signing key" bash -c "gpg --dearmor < '$key_ascii_tmp' > '$key_tmp'"
        run_optional "Installing 1Password signing key to trusted keyrings" bash -c "$SUDO install -m 0644 '$key_tmp' /usr/share/keyrings/1password-archive-keyring.gpg"
        rm -f "$key_ascii_tmp"
        rm -f "$key_tmp"

        local arch
        arch="$(dpkg --print-architecture)"
        run_optional "Writing 1Password apt repository entry" bash -c "echo 'deb [arch=${arch} signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/${arch} stable main' | $SUDO tee /etc/apt/sources.list.d/1password.list >/dev/null"
        run_optional "Refreshing apt after adding 1Password repository" bash -c "$SUDO apt-get update -qq"
        run_optional "Installing 1Password CLI" bash -c "$SUDO apt-get install -y 1password-cli"
    elif [[ "$PKG_MGR" == "pacman" ]]; then
        run_optional "Installing 1Password CLI with pacman" bash -c "$SUDO pacman -S --noconfirm 1password-cli"
    fi

    mkdir -p "$HOME/.1password"
    run_optional "Ensuring ~/.1password ownership" bash -c "$SUDO chown -R '$USER':'$USER' '$HOME/.1password'"
}

install_homebrew_and_gemini() {
    local brew_bin=""
    if command -v brew &>/dev/null; then
        brew_bin="$(command -v brew)"
        ok "Homebrew already installed"
    else
        if [[ "$PKG_MGR" == "apt" ]]; then
            run_optional "Installing Homebrew build prerequisites (apt)" bash -c "$SUDO apt-get install -y -qq build-essential procps curl file git"
        fi
        local brew_script
        brew_script="$(download_to_tmp "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" "homebrew-install-XXXXXX.sh")"
        run_optional "Installing Homebrew" env NONINTERACTIVE=1 /bin/bash "$brew_script"
        rm -f "$brew_script"

        if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
            brew_bin="/home/linuxbrew/.linuxbrew/bin/brew"
        elif [[ -x "$HOME/.linuxbrew/bin/brew" ]]; then
            brew_bin="$HOME/.linuxbrew/bin/brew"
        fi
    fi

    if [[ -z "$brew_bin" ]] && command -v brew &>/dev/null; then
        brew_bin="$(command -v brew)"
    fi

    if [[ -n "$brew_bin" ]]; then
        eval "$("$brew_bin" shellenv)"
        append_if_missing "$HOME/.zshrc" "command -v brew >/dev/null && eval \"\$(brew shellenv)\""
        append_if_missing "$HOME/.bashrc" "command -v brew >/dev/null && eval \"\$(brew shellenv)\""

        run_optional "Updating Homebrew taps" brew update
        run_optional "Installing gcc with Homebrew" brew install gcc

        if ! command -v gemini &>/dev/null; then
            run_optional "Installing Gemini CLI with Homebrew" brew install gemini-cli
            if ! command -v gemini &>/dev/null && command -v npm &>/dev/null; then
                run_optional "Installing Gemini CLI with npm fallback" npm install -g @google/gemini-cli
            fi
        else
            ok "Gemini CLI already installed"
        fi
    else
        warn "Homebrew not available; skipping Homebrew-based installs"
    fi
}

install_github_deb() {
    local repo="$1"
    local pattern="$2"
    local name="$3"
    if command -v "$name" &>/dev/null; then
        ok "$name verified"
        return 0
    fi
    if [[ "$PKG_MGR" != "apt" ]]; then return 0; fi
    info "Installing $name from GitHub releases..."
    local url
    local curl_args=(-fsSL)
    if [[ -n "${GITHUB_TOKEN:-}" && "${GITHUB_TOKEN}" =~ ^[A-Za-z0-9_-]+$ ]]; then
        curl_args+=(-H "Authorization: token ${GITHUB_TOKEN}")
    fi
    if command -v jq &>/dev/null; then
        url=$(curl "${curl_args[@]}" "https://api.github.com/repos/${repo}/releases/latest" | jq -r --arg p "$pattern" '.assets[]?.browser_download_url | select(test($p))' | head -1 || true)
    else
        url=$(curl "${curl_args[@]}" "https://api.github.com/repos/${repo}/releases/latest" | grep browser_download_url | grep -E "$pattern" | head -1 | cut -d '"' -f4 || true)
    fi
    [[ -n "$url" ]] || { warn "No ${name} release artifact matched ${pattern}"; return 0; }
    local tmpfile
    tmpfile="$(mktemp /tmp/"$name"-XXXXXX.deb)"
    run_optional "Downloading ${name} release package" curl -fsSL "$url" -o "$tmpfile"
    run_optional "Installing ${name} deb package" bash -c "$SUDO dpkg -i '$tmpfile'"
    rm -f "$tmpfile"
}

# --- Flags ---
MODE="${MODE:-batch}"
INSTALL_SHELL=true
INSTALL_PROJECTOR=true

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --shell) INSTALL_PROJECTOR=false ;;
        --projector) INSTALL_SHELL=false ;;
        --interactive) MODE=interactive ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# --- OS Gate (Detect) ---
if command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
    info "Detected Debian/Ubuntu-based system."
elif command -v pacman &>/dev/null; then
    PKG_MGR="pacman"
    info "Detected Arch/CachyOS-based system."
    if command -v yay &>/dev/null; then
        AUR_HELPER="yay"
    elif command -v paru &>/dev/null; then
        AUR_HELPER="paru"
    else
        AUR_HELPER=""
    fi
else
    die "Unsupported Linux distribution. No apt-get or pacman found."
fi

SUDO=""
if [[ "$EUID" -ne 0 ]]; then
    command -v sudo &>/dev/null || die "sudo is not installed and you are not root. Cannot proceed."
    SUDO="sudo"
fi

# --- Mode Check + Interactive Questions ---
DO_CORE=true
DO_SHELL="$INSTALL_SHELL"
DO_SECURITY=true
DO_PROJECTOR="$INSTALL_PROJECTOR"

if [[ "$MODE" == "interactive" ]]; then
    ask_yes_no "Install/update core package manager prerequisites?" || DO_CORE=false
    if [[ "$INSTALL_SHELL" == "true" ]]; then
        ask_yes_no "Install shell experience (zsh/oh-my-zsh/plugins/config)?" || DO_SHELL=false
    fi
    ask_yes_no "Install security/developer tools (1Password, shared payload, Homebrew, Gemini CLI)?" || DO_SECURITY=false
    if [[ "$INSTALL_PROJECTOR" == "true" ]]; then
        ask_yes_no "Install projector stack (Rust/toolchain, weathr, fonts, projector config)?" || DO_PROJECTOR=false
    fi
fi

# ── 1. CORE PREREQUISITES ────────────────────────────────────────────────────
if [[ "$DO_CORE" == "true" ]]; then
    if [[ "$PKG_MGR" == "apt" ]]; then
        run_optional "Refreshing apt package list" bash -c "$SUDO apt-get update -qq"
        run_optional "Installing core apt prerequisites" bash -c "$SUDO apt-get install -y -qq ca-certificates curl gnupg unzip fontconfig"
    else
        run_optional "Refreshing pacman package list" bash -c "$SUDO pacman -Sy --noconfirm"
        run_optional "Installing core pacman prerequisites" bash -c "$SUDO pacman -S --noconfirm ca-certificates curl gnupg unzip fontconfig"
    fi
fi

# ── 2. SHELL EXPERIENCE ──────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$DO_SHELL" == "true" ]]; then
    info "Installing shell environment..."
    if ! command -v zsh &>/dev/null; then
        if [[ "$PKG_MGR" == "apt" ]]; then
            run_optional "Installing zsh via apt" bash -c "$SUDO apt-get install -y zsh"
        else
            run_optional "Installing zsh via pacman" bash -c "$SUDO pacman -S --noconfirm zsh"
        fi
    fi

    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        omz_script="$(download_to_tmp "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" "ohmyzsh-install-XXXXXX.sh")"
        run_optional "Installing Oh My Zsh" sh "$omz_script" --unattended
        rm -f "$omz_script"
    else
        ok "Oh My Zsh already installed"
    fi

    if command -v zsh &>/dev/null; then
        run_optional "Setting default shell to zsh" chsh -s "$(command -v zsh)"
    fi

    ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    mkdir -p "$ZSH_CUSTOM/plugins"
    [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] || run_optional "Installing zsh-autosuggestions plugin" git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    [[ -d "$ZSH_CUSTOM/plugins/zsh-fast-syntax-highlighting" ]] || run_optional "Installing zsh-fast-syntax-highlighting plugin" git clone --depth=1 https://github.com/zdharma-continuum/fast-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-fast-syntax-highlighting"

    info "Deploying shell configurations..."
    mkdir -p "$HOME/.shell"
    cp "$SCRIPT_DIR/shell/zshrc.zsh" "$HOME/.zshrc"
    cp "$SCRIPT_DIR/shell/aliases.zsh" "$HOME/.shell/aliases.zsh"
    cp "$SCRIPT_DIR/shell/plugins.zsh" "$HOME/.shell/plugins.zsh"
fi

# ── 3. SECURITY/DEVELOPER TOOLS ──────────────────────────────────────────────
if [[ "$DO_SECURITY" == "true" ]]; then
    install_1password_cli
    install_homebrew_and_gemini

    info "Installing shared tooling payload..."

    if [[ "$PKG_MGR" == "apt" ]]; then
        APT_PACKAGES=(
            binutils btop exiftool fastfetch fzf git gnutls-bin golang gzip hexyl jq
            libssl-dev lua5.4 lz4 m4 micro ncurses-bin ngrep nmap nodejs openssl pipx
            python3 python3-pip python3-venv rclone ripgrep ruby rustup speedtest-cli
            sqlite3 tcpdump tealdeer tmux unbound wireshark yara zsh-autosuggestions
            cmatrix cbonsai zoxide starship
        )
        for pkg in "${APT_PACKAGES[@]}"; do
            if dpkg -s "$pkg" &>/dev/null 2>&1; then
                ok "$pkg verified"
            else
                run_optional "Installing $pkg" bash -c "$SUDO apt-get install -y -qq '$pkg'"
            fi
        done

        # Packages not in Debian 12 repos — install via dedicated methods
        if ! command -v uv &>/dev/null; then
            run_optional "Installing uv via pipx" pipx install uv
        fi
        if ! command -v nu &>/dev/null; then
            if command -v cargo &>/dev/null; then
                run_optional "Installing nushell via cargo" cargo install nu
            else
                warn "nushell not available (not in apt, no cargo); skipping"
            fi
        fi
        if ! command -v yazi &>/dev/null; then
            if command -v cargo &>/dev/null; then
                run_optional "Installing yazi via cargo" cargo install yazi-fm yazi-cli
            else
                warn "yazi not available (not in apt, no cargo); skipping"
            fi
        fi
        if ! command -v mise &>/dev/null; then
            run_optional "Installing mise via install script" bash -c 'curl -fsSL https://mise.jdx.dev/install.sh | sh'
        fi
        if ! command -v atuin &>/dev/null; then
            run_optional "Installing atuin via install script" bash -c 'curl -fsSL https://setup.atuin.sh | sh'
        fi
    else
        PACMAN_PACKAGES=(
            binutils btop exiftool fastfetch fzf git gnutls go gzip hexyl jq openssl lua
            lz4 m4 micro ncurses ngrep nmap nodejs python-pipx python python-pip rclone
            ripgrep ruby rustup speedtest-cli sqlite tcpdump tealdeer tmux unbound uv
            wireshark-cli yara zsh-autosuggestions cmatrix nushell yazi mise
            atuin zoxide starship
        )
        for pkg in "${PACMAN_PACKAGES[@]}"; do
            if pacman -Qi "$pkg" &>/dev/null; then
                ok "$pkg verified"
            else
                run_optional "Installing $pkg" bash -c "$SUDO pacman -S --noconfirm '$pkg'"
            fi
        done

        if ! command -v cbonsai &>/dev/null && [[ -n "${AUR_HELPER:-}" ]]; then
            run_optional "Installing cbonsai via ${AUR_HELPER}" "$AUR_HELPER" -S --noconfirm cbonsai
        fi
    fi

    install_github_deb "lsd-rs/lsd" "lsd_.*_amd64\\.deb" "lsd"
    install_github_deb "sharkdp/bat" "bat_[0-9].*_amd64\\.deb" "bat"

    # sd ships as .tar.gz, not .deb — install via cargo as fallback
    if ! command -v sd &>/dev/null; then
        if command -v cargo &>/dev/null; then
            run_optional "Installing sd via cargo" cargo install sd
        else
            warn "sd not available (no .deb, no cargo); skipping"
        fi
    fi

    if ! command -v wtfis &>/dev/null; then
        run_optional "Installing wtfis with pipx" pipx install wtfis
        run_optional "Ensuring pipx path configured" pipx ensurepath
    fi
    if ! command -v lolcat &>/dev/null; then
        run_optional "Installing lolcat via gem" bash -c "$SUDO gem install lolcat"
    fi
fi

# ── 4. PROJECTOR STACK ────────────────────────────────────────────────────────
if [[ "$DO_PROJECTOR" == "true" ]]; then
    ensure_rust_toolchain

    if command -v cargo &>/dev/null && ! command -v weathr &>/dev/null; then
        run_optional "Installing weathr via cargo" cargo install weathr
    fi
    if command -v cargo &>/dev/null && ! command -v trip &>/dev/null; then
        run_optional "Installing trippy via cargo" cargo install trippy
    fi

    FONT_DIR="$HOME/.local/share/fonts"
    if ! fc-list | grep -qi "JetBrainsMono" &>/dev/null; then
        info "Installing JetBrainsMono Nerd Font..."
        mkdir -p "$FONT_DIR/JetBrainsMono"
        TMP_ZIP="$(mktemp /tmp/font-XXXXXX.zip)"
        run_optional "Downloading JetBrainsMono Nerd Font" curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" -o "$TMP_ZIP"
        run_optional "Extracting JetBrainsMono Nerd Font" unzip -q "$TMP_ZIP" -d "$FONT_DIR/JetBrainsMono"
        run_optional "Refreshing font cache" fc-cache -f
        rm -f "$TMP_ZIP"
    else
        ok "JetBrainsMono Nerd Font already installed"
    fi

    info "Deploying Projector configuration..."
    mkdir -p "$HOME/.config/projector"
    [[ -f "$HOME/.config/projector/config.json" ]] || cp "$SCRIPT_DIR/projector/config.json.default" "$HOME/.config/projector/config.json"
    [[ -f "$SCRIPT_DIR/projector.py" ]] && chmod +x "$SCRIPT_DIR/projector.py"
fi

ok "Installation Complete!"
