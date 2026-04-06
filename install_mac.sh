#!/usr/bin/env bash
# =============================================================================
# terminal-kniferoll | macOS Installer (Shell + Projector)
# =============================================================================
#
# Supply chain controls: lib/supply_chain_guard.sh is sourced below.
# Set SC_RISK_TOLERANCE=1..4 in environment to bypass the interactive prompt.
# Set SC_ALLOW_RISKY=1 to match pre-guard (permissive) behavior in automation.
# =============================================================================

set -Eeuo pipefail
export HOMEBREW_NO_AUTO_UPDATE=1

# ── TTY-guarded color palette ─────────────────────────────────────────────────
if [ -t 1 ]; then
  RED='\033[0;31m';   GREEN='\033[0;32m';  YELLOW='\033[1;33m'
  CYAN='\033[0;36m';  BOLD='\033[1m';      DIM='\033[2m';       RESET='\033[0m'
  ORANGE='\033[38;5;208m'; STEEL='\033[38;5;249m'
  HERB='\033[38;5;106m';   BLADE='\033[38;5;255m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; RESET=''
  ORANGE=''; STEEL=''; HERB=''; BLADE=''
fi

# ── Log file ──────────────────────────────────────────────────────────────────
LOG_FILE="$HOME/.terminal-kniferoll/logs/install_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

_log() {
  local level="$1" msg="$2"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $msg" >> "$LOG_FILE"
}

# ── Logging helpers ───────────────────────────────────────────────────────────
ok()     { echo -e "${GREEN}[✓]${RESET} ${HERB}$*${RESET}";   _log "OK"    "$*"; }
info()   { echo -e "${CYAN}[→]${RESET} $*";                   _log "INFO"  "$*"; }
warn()   { echo -e "${ORANGE}[~]${RESET} $*";                 _log "WARN"  "$*"; }
skip()   { echo -e "${DIM}[~] skip: $*${RESET}";              _log "SKIP"  "$*"; }
err()    { echo -e "${RED}[✗]${RESET} $*";                    _log "ERROR" "$*"; }
die()    { echo -e "${RED}[✗] FATAL: $*${RESET}" >&2;         _log "ERROR" "FATAL: $*"; exit 1; }
banner() { echo -e "\n${BOLD}${CYAN}[ $* ]${RESET}";          _log "INFO"  "=== $* ==="; }
quip()   { echo -e "${DIM}  ⋮ $*${RESET}"; }

# ── Failed tools tracker ──────────────────────────────────────────────────────
FAILED_TOOLS=()

on_error() { warn "Unexpected failure at line $1: $2"; }
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

# ── Helper: run with soft failure ────────────────────────────────────────────
run_optional() {
    local desc="$1"; shift
    info "$desc"
    if (set +Ee; "$@"); then ok "$desc"; return 0; fi
    warn "$desc — failed, continuing"
    return 0
}

# ── Helper: download URL to a secure temp file ───────────────────────────────
download_to_tmp() {
    local url="$1" pattern="$2" tmp_file old_umask
    old_umask="$(umask)"
    umask 077
    tmp_file="$(mktemp "/tmp/${pattern}")"
    umask "$old_umask"
    chmod 600 "$tmp_file"
    curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$tmp_file"
    echo "$tmp_file"
}

# ── Helper: append line to file if absent ────────────────────────────────────
append_if_missing() {
    local file="$1" line="$2"
    touch "$file"
    grep -Fq "$line" "$file" || echo "$line" >> "$file"
}

# ── Helper: yes/no prompt ────────────────────────────────────────────────────
ask_yes_no() {
    local prompt="$1"
    echo -en "${CYAN}[?] ${prompt} [Y/n] ${RESET}"
    read -r _reply
    [[ -z "$_reply" || "$_reply" =~ ^[Yy]$ ]]
}

# ── Helper: check if binary is on PATH ───────────────────────────────────────
is_installed() { command -v "$1" &>/dev/null; }

# ── Cleanup: tools explicitly removed from this project ──────────────────────
cleanup_removed_tools() {
    local did_work=false

    # ── atuin — removed 2026-04-05: supply chain risk
    if is_installed "atuin" || brew list atuin &>/dev/null 2>&1; then
        did_work=true
        warn "atuin found — evicting (cut: supply chain risk)"
        brew list atuin &>/dev/null 2>&1 && \
            run_optional "Removing atuin (brew)" brew uninstall atuin || true
        [[ -d "$HOME/.atuin" ]] && \
            run_optional "Removing ~/.atuin data dir" rm -rf "$HOME/.atuin"
        [[ -f "$HOME/.zshrc" ]] && \
            sed -i '' '/command -v atuin.*atuin init zsh/d' "$HOME/.zshrc" 2>/dev/null || true
        ok "atuin — evicted"
    fi

    # ── mise — removed 2026-04-05: supply chain risk
    if is_installed "mise" || brew list mise &>/dev/null 2>&1; then
        did_work=true
        warn "mise found — evicting (cut: supply chain risk)"
        brew list mise &>/dev/null 2>&1 && \
            run_optional "Removing mise (brew)" brew uninstall mise || true
        [[ -d "$HOME/.local/share/mise" ]] && \
            run_optional "Removing ~/.local/share/mise data dir" \
                rm -rf "$HOME/.local/share/mise"
        ok "mise — evicted"
    fi

    "$did_work" || skip "No removed tools found — clean slate"
}

# ── Feature: ensure Rust toolchain ───────────────────────────────────────────
ensure_rust_toolchain() {
    if ! is_installed "cargo"; then
        local rustup_script
        rustup_script="$(download_to_tmp "https://sh.rustup.rs" "rustup-init-XXXXXX.sh")"
        run_optional "Installing Rust via rustup" bash "$rustup_script" -y --quiet
        rm -f "$rustup_script"
        [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env" || true
    fi
    if is_installed "rustup"; then
        rustup show active-toolchain &>/dev/null || \
            run_optional "Configuring rustup default stable" rustup default stable
        is_installed "cargo" || run_optional "Repairing Rust toolchain" rustup default stable
        [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env" || true
    fi
}

# ── Mission summary ───────────────────────────────────────────────────────────
print_summary() {
    banner "MISSION DEBRIEF"
    if [[ ${#FAILED_TOOLS[@]} -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}  ALL SYSTEMS NOMINAL — zero casualties.${RESET}"
    else
        echo -e "${YELLOW}${BOLD}  MISSION COMPLETE WITH CASUALTIES:${RESET}"
        for t in "${FAILED_TOOLS[@]}"; do echo -e "  ${RED}[✗]${RESET}  $t"; done
        quip "Try: brew install <pkg> to retry failed items"
    fi
    echo
    echo -e "${DIM}  [→] Log saved to: ${LOG_FILE}${RESET}"
    _log "INFO" "Install complete. Failures: ${#FAILED_TOOLS[@]}"
}

# ── Help text ─────────────────────────────────────────────────────────────────
show_help() {
    echo "Usage: install_mac.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --shell          Install shell environment only (skip projector)"
    echo "  --projector      Install projector tools only (skip shell)"
    echo "  --interactive    Force interactive menu"
    echo "  --help           Show this help message and exit"
    echo ""
    echo "Default: shows install menu (TTY) or full install (non-TTY)."
}

# ── Install menus ─────────────────────────────────────────────────────────────
show_custom_menu() {
    echo -e "\n${BOLD}${CYAN}[ CUSTOM — select tool groups ]${RESET}\n"
    ask_yes_no "  Shell environment (Zsh, Oh My Zsh, plugins, configs)?" \
        && INSTALL_SHELL=true || INSTALL_SHELL=false
    ask_yes_no "  Core security & developer tools?" \
        && DO_SECURITY=true || DO_SECURITY=false
    ask_yes_no "  Projector stack (Rust, weathr, JetBrains font, config)?" \
        && INSTALL_PROJECTOR=true || INSTALL_PROJECTOR=false
}

show_menu() {
    echo -e "\n${BOLD}${BLADE}  What would you like to install?${RESET}\n"
    echo -e "  ${CYAN}[1]${RESET} Full install     — Shell environment + Terminal projector ${DIM}(recommended)${RESET}"
    echo -e "  ${CYAN}[2]${RESET} Shell only       — Zsh, Oh My Zsh, plugins, aliases"
    echo -e "  ${CYAN}[3]${RESET} Projector only   — Terminal animation suite (weather, bonsai, fastfetch)"
    echo -e "  ${CYAN}[4]${RESET} Custom           — Choose individual tool groups"
    echo
    echo -en "${CYAN}  Choice [1-4]: ${RESET}"
    read -r _choice
    case "$_choice" in
        1) INSTALL_SHELL=true;  INSTALL_PROJECTOR=true ;;
        2) INSTALL_SHELL=true;  INSTALL_PROJECTOR=false ;;
        3) INSTALL_SHELL=false; INSTALL_PROJECTOR=true ;;
        4) show_custom_menu ;;
        *) warn "Invalid choice — defaulting to full install"
           INSTALL_SHELL=true; INSTALL_PROJECTOR=true ;;
    esac
}

# ── Flag parsing ──────────────────────────────────────────────────────────────
INSTALL_SHELL=true
INSTALL_PROJECTOR=true
EXPLICIT_FLAG=false
MODE="${MODE:-batch}"
DO_SECURITY=true

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --shell)       INSTALL_SHELL=true; INSTALL_PROJECTOR=false; EXPLICIT_FLAG=true ;;
        --projector)   INSTALL_SHELL=false; INSTALL_PROJECTOR=true; EXPLICIT_FLAG=true ;;
        --interactive) MODE=interactive ;;
        --help)        show_help; exit 0 ;;
        *) err "Unknown parameter: $1"; show_help; exit 1 ;;
    esac
    shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Supply chain guard ────────────────────────────────────────────────────────
# shellcheck source=lib/supply_chain_guard.sh
source "$SCRIPT_DIR/lib/supply_chain_guard.sh"

# ── ASCII banner ──────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
  ╔════════════════════════════════════╗
  ║  ⌁  terminal-kniferoll            ║
  ║     sharp tools. clean cuts.      ║
  ╚════════════════════════════════════╝
BANNER
echo -e "${RESET}"
quip "Log: $LOG_FILE"
echo

# ── Homebrew bootstrap ────────────────────────────────────────────────────────
if ! is_installed "brew"; then
    brew_script="$(download_to_tmp \
        "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" \
        "homebrew-install-XXXXXX.sh")"
    run_optional "Installing Homebrew" env NONINTERACTIVE=1 /bin/bash "$brew_script"
    rm -f "$brew_script"
else
    skip "Homebrew already installed"
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

if is_installed "brew"; then
    append_if_missing "$HOME/.zprofile" \
        'command -v brew >/dev/null && eval "$(brew shellenv)"'
fi

# ── Show menu or use defaults ─────────────────────────────────────────────────
if [[ "$EXPLICIT_FLAG" == "false" ]] && { [[ -t 0 ]] || [[ "$MODE" == "interactive" ]]; }; then
    show_menu
fi

# ── Resolve deployment flags ──────────────────────────────────────────────────
DO_SHELL="$INSTALL_SHELL"
DO_PROJECTOR="$INSTALL_PROJECTOR"

# ── Supply chain risk policy (interactive TTY only; no-op in batch/CI) ────────
sc_set_risk_tolerance

# ── Evict tools removed from this project ─────────────────────────────────────
banner "HOUSEKEEPING — EVICTING REMOVED TOOLS"
cleanup_removed_tools

# ────────────────────────────────────────────────────────────────────────────
# 1. CORE PREREQUISITES
# ────────────────────────────────────────────────────────────────────────────
banner "CORE PREREQUISITES"
run_optional "Updating Homebrew" brew update

# ────────────────────────────────────────────────────────────────────────────
# 2. SHELL ENVIRONMENT
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_SHELL" == "true" ]]; then
    banner "SHELL ENVIRONMENT"

    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        # Pinned to a specific release tag instead of piping master/install.sh.
        # Update OMZ_TAG when upgrading. Tags: https://github.com/ohmyzsh/ohmyzsh/tags
        local OMZ_TAG="24.9.0"
        info "Cloning Oh My Zsh at tag ${OMZ_TAG} (pinned)"
        if ! git clone --depth 1 --branch "$OMZ_TAG" \
                https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" 2>/dev/null; then
            # Tag may not exist yet — fall back to unattended script install with a warning
            warn "Tag ${OMZ_TAG} not found in ohmyzsh/ohmyzsh — falling back to install.sh (unpinned)"
            local omz_script
            omz_script="$(download_to_tmp \
                "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" \
                "ohmyzsh-install-XXXXXX.sh")"
            RUNZSH=no CHSH=no run_optional "Installing Oh My Zsh (unpinned)" \
                bash "$omz_script" --unattended
            rm -f "$omz_script"
        else
            ok "Oh My Zsh cloned at ${OMZ_TAG}"
        fi
    else
        skip "Oh My Zsh already installed"
    fi

    ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    mkdir -p "$ZSH_CUSTOM/plugins"

    # Plugin versions — update tags here when upgrading
    # zsh-autosuggestions tags: https://github.com/zsh-users/zsh-autosuggestions/tags
    local ZSH_AUTOSUG_TAG="v0.7.1"
    # fast-syntax-highlighting tags: https://github.com/zdharma-continuum/fast-syntax-highlighting/tags
    local ZSH_FSH_TAG="v1.55"

    [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] || \
        run_optional "Installing zsh-autosuggestions ${ZSH_AUTOSUG_TAG}" \
            git clone --depth=1 --branch "$ZSH_AUTOSUG_TAG" \
                https://github.com/zsh-users/zsh-autosuggestions \
                "$ZSH_CUSTOM/plugins/zsh-autosuggestions"

    # fast-syntax-highlighting MUST be last plugin loaded
    [[ -d "$ZSH_CUSTOM/plugins/fast-syntax-highlighting" ]] || \
        run_optional "Installing fast-syntax-highlighting ${ZSH_FSH_TAG}" \
            git clone --depth=1 --branch "$ZSH_FSH_TAG" \
                https://github.com/zdharma-continuum/fast-syntax-highlighting \
                "$ZSH_CUSTOM/plugins/fast-syntax-highlighting"

    banner "DEPLOYING SHELL CONFIGS"
    mkdir -p "$HOME/.shell"
    cp "$SCRIPT_DIR/shell/zshrc.zsh"   "$HOME/.zshrc"
    cp "$SCRIPT_DIR/shell/aliases.zsh" "$HOME/.shell/aliases.zsh"
    cp "$SCRIPT_DIR/shell/plugins.zsh" "$HOME/.shell/plugins.zsh"
    ok "Shell configurations deployed"

    # macOS-specific aliases
    if [[ ! -f "$HOME/.shell/aliases_mac.zsh" ]]; then
        echo 'alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"' \
            > "$HOME/.shell/aliases_mac.zsh"
        echo 'alias sudo="sudo -E"' >> "$HOME/.shell/aliases_mac.zsh"
    fi
    grep -q "aliases_mac.zsh" "$HOME/.zshrc" || \
        echo '[[ -f "$HOME/.shell/aliases_mac.zsh" ]] && source "$HOME/.shell/aliases_mac.zsh"' \
            >> "$HOME/.zshrc"
fi

# ────────────────────────────────────────────────────────────────────────────
# 3. SECURITY / DEVELOPER TOOLS
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_SECURITY" == "true" ]]; then
    # 1Password CLI
    if is_installed "op"; then
        skip "1Password CLI already installed"
    else
        run_optional "Installing 1Password CLI" brew install --cask 1password-cli
        is_installed "op" || warn "1Password CLI (op) not found on PATH after install"
    fi
    mkdir -p "$HOME/.1password"

    banner "SECURITY AND DEVELOPER TOOLS"
    # atuin and mise removed 2026-04-05 — supply chain risk (see docs/SUPPLY_CHAIN_RISK.md)
    BREW_PACKAGES=(
        bat binutils btop ca-certificates cbonsai cmatrix exiftool
        fastfetch fontconfig freetype fzf gcc gh git gnutls go gzip
        harfbuzz hexyl jq lolcat lsd lua lz4 lzo m4 micro ncurses ngrep
        nmap node nushell openjdk openssl@3 pipx python@3.11 rclone ripgrep ruby
        rustup speedtest-cli sqlite starship tcpdump tealdeer tmux unbound uv
        wireshark yazi yara zoxide zsh-autosuggestions zsh-fast-syntax-highlighting
    )
    for pkg in "${BREW_PACKAGES[@]}"; do
        if brew list "$pkg" &>/dev/null 2>&1; then
            skip "$pkg"
        else
            run_optional "Installing $pkg" brew install "$pkg" || FAILED_TOOLS+=("$pkg")
        fi
    done

    # Gemini CLI
    if ! is_installed "gemini"; then
        run_optional "Installing Gemini CLI" brew install gemini-cli
        ! is_installed "gemini" && is_installed "npm" && \
            run_optional "Installing Gemini CLI (npm fallback)" \
                npm install -g @google/gemini-cli || true
    else
        skip "Gemini CLI already installed"
    fi

    # wtfis via pipx
    is_installed "wtfis" || {
        run_optional "Installing wtfis via pipx" pipx install wtfis
        run_optional "Configuring pipx path"     pipx ensurepath
    }
fi

# ────────────────────────────────────────────────────────────────────────────
# 4. PROJECTOR STACK
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_PROJECTOR" == "true" ]]; then
    banner "PROJECTOR STACK"
    ensure_rust_toolchain

    is_installed "weathr" || run_optional "Installing weathr via cargo" cargo install weathr
    is_installed "trip"   || run_optional "Installing trippy via cargo" cargo install trippy

    # JetBrainsMono Nerd Font (macOS uses ~/Library/Fonts)
    FONT_DIR="$HOME/Library/Fonts"
    if ! find "$FONT_DIR" -maxdepth 1 -iname "*JetBrainsMono*" -print -quit 2>/dev/null | grep -q .; then
        banner "JETBRAINSMONO NERD FONT"
        mkdir -p "$FONT_DIR"
        font_zip="$(mktemp /tmp/font-XXXXXX.zip)"
        font_extract="$(mktemp -d /tmp/font-extract-XXXXXX)"
        # Pinned to v3.4.0 — update version here when upgrading
        run_optional "Downloading JetBrainsMono Nerd Font" \
            curl --proto '=https' --tlsv1.2 -fsSL \
                "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip" \
                -o "$font_zip"
        run_optional "Extracting font" unzip -q "$font_zip" -d "$font_extract"
        run_optional "Copying font files" find "$font_extract" -name "*.ttf" -exec cp {} "$FONT_DIR/" \;
        rm -rf "$font_zip" "$font_extract"
    else
        skip "JetBrainsMono Nerd Font already installed"
    fi

    banner "PROJECTOR CONFIGURATION"
    mkdir -p "$HOME/.config/projector"
    [[ -f "$HOME/.config/projector/config.json" ]] || \
        cp "$SCRIPT_DIR/projector/config.json.default" "$HOME/.config/projector/config.json"
    [[ -f "$SCRIPT_DIR/projector.py" ]] && chmod +x "$SCRIPT_DIR/projector.py" || true
    ok "Projector configuration deployed"
fi

# ────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ────────────────────────────────────────────────────────────────────────────
sc_process_deferred
print_summary
sc_summary
echo -e "${BOLD}${CYAN}>>> mission complete. knives sharp. out.${RESET}"
echo -e "${DIM}    Reminder: restart your shell or run 'source ~/.zshrc' to activate.${RESET}"
