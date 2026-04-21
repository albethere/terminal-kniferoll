#!/usr/bin/env bash
# =============================================================================
# terminal-kniferoll | macOS Installer (Shell + Projector)
# =============================================================================
#
# Supply chain controls: lib/supply_chain_guard.sh is sourced below.
# Always runs in strict mode (TLS enforced, hashes verified where available).
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
# Respects CURL_CA_BUNDLE if set (Zscaler managed-device mode).
download_to_tmp() {
    local url="$1" pattern="$2" tmp_file old_umask
    old_umask="$(umask)"
    umask 077
    tmp_file="$(mktemp "/tmp/${pattern}")"
    umask "$old_umask"
    chmod 600 "$tmp_file"
    local curl_opts=(--proto '=https' --tlsv1.2 -fsSL)
    [[ -n "${CURL_CA_BUNDLE:-}" && -f "${CURL_CA_BUNDLE}" ]] && \
        curl_opts+=(--cacert "$CURL_CA_BUNDLE")
    curl "${curl_opts[@]}" "$url" -o "$tmp_file"
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

# ── Helper: check if macOS .app is installed ─────────────────────────────────
is_app_installed() {
    [[ -d "/Applications/$1.app" ]] || [[ -d "$HOME/Applications/$1.app" ]]
}

# ── Helper: detect MDM-managed / restricted device ───────────────────────────
is_restricted_device() {
    profiles status -type enrollment 2>/dev/null | grep -qi "yes"
}

# ── Zscaler managed-device cert trust ────────────────────────────────────────
# Must be called BEFORE any curl/Homebrew operations on managed macOS devices.
# Builds a combined CA bundle (macOS system roots + Zscaler) and sets
# CURL_CA_BUNDLE / HOMEBREW_CURLOPT_CACERT so brew bootstrap succeeds behind
# Zscaler TLS interception.
#
# Detection order (macOS-only paths — no Linux paths in this script):
#   1. Previously built combined bundle  (fast path on re-run)
#   2. LM standard path: /Users/Shared/.certificates/zscaler.pem
#      (Liberty Mutual Zscaler Developer Onboarding doc, Dec 2025)
#   3. Zscaler app path  (ZIA/ZPA client may write cert here)
#   4. System Keychain export  (MDM-enrolled device without Zscaler app)
setup_zscaler_trust() {
    local zsc_pem=""
    local bundle_dir="$HOME/.config/terminal-kniferoll"
    local combined_bundle="$bundle_dir/ca-bundle.pem"
    mkdir -p "$bundle_dir"

    # 1. Fast path — prior installer run already built the bundle
    if [[ -s "$combined_bundle" ]]; then
        export CURL_CA_BUNDLE="$combined_bundle"
        export HOMEBREW_CURLOPT_CACERT="$combined_bundle"
        export ZSC_PEM="$combined_bundle"
        ok "Zscaler trust: using cached CA bundle"
        return 0
    fi

    # 2. LM standard path — engineers place the cert here per LM onboarding doc
    if [[ -s "/Users/Shared/.certificates/zscaler.pem" ]]; then
        zsc_pem="/Users/Shared/.certificates/zscaler.pem"
        info "Zscaler cert found at LM standard path (/Users/Shared/.certificates/)"
    fi

    # 3. Zscaler app path (ZIA/ZPA client default on macOS)
    if [[ -z "$zsc_pem" ]]; then
        local _zsc_app="/Library/Application Support/Zscaler/ZscalerRootCertificate-2048-SHA256.crt"
        if [[ -f "$_zsc_app" ]]; then
            zsc_pem="$_zsc_app"
            info "Zscaler cert found at Zscaler app path"
        fi
    fi

    # 4. System Keychain export (MDM-enrolled without Zscaler app or manual cert)
    if [[ -z "$zsc_pem" ]]; then
        local _tmp_ks; _tmp_ks="$(mktemp /tmp/zscaler-ks-XXXXXX.pem)"
        chmod 600 "$_tmp_ks"
        if security find-certificate -c "Zscaler" -a -p \
                /Library/Keychains/System.keychain > "$_tmp_ks" 2>/dev/null \
                && [[ -s "$_tmp_ks" ]]; then
            zsc_pem="$_tmp_ks"
            info "Zscaler cert exported from System Keychain"
        else
            rm -f "$_tmp_ks"
        fi
    fi

    if [[ -z "$zsc_pem" ]]; then
        skip "No Zscaler cert detected — assuming standard TLS (non-managed device)"
        return 0
    fi

    # Build combined bundle: macOS system roots + System keychain + Zscaler cert
    info "Building combined CA bundle for managed-device trust..."
    {
        security find-certificate -a -p \
            /System/Library/Keychains/SystemRootCertificates.keychain 2>/dev/null || true
        security find-certificate -a -p \
            /Library/Keychains/System.keychain 2>/dev/null || true
        cat "$zsc_pem"
    } > "$combined_bundle"
    chmod 644 "$combined_bundle"

    export CURL_CA_BUNDLE="$combined_bundle"
    export HOMEBREW_CURLOPT_CACERT="$combined_bundle"
    export ZSC_PEM="$combined_bundle"
    ok "Zscaler trust configured — $(wc -l < "$combined_bundle") cert lines in bundle"
    quip "curl, brew, git, npm, yarn, and aws cli will trust this bundle"
}

# ── Configure installed tools to trust the Zscaler CA ────────────────────────
# Commands sourced from LM Zscaler Developer Onboarding doc (HES, Dec 2025).
# Call this AFTER tools are installed so config commands exist.
configure_tool_certs() {
    [[ -z "${ZSC_PEM:-}" ]] && return 0
    banner "ZSCALER CERT TRUST — TOOL CONFIGURATION"

    # git — http.sslCAInfo
    is_installed "git" && \
        run_optional "git: trusting Zscaler CA" \
            git config --global http.sslCAInfo "$ZSC_PEM"

    # npm — global config (-g flag per LM doc)
    is_installed "npm" && \
        run_optional "npm: trusting Zscaler CA" \
            npm config -g set cafile "$ZSC_PEM"

    # yarn — strict-ssl first, then cafile (per LM doc)
    if is_installed "yarn"; then
        run_optional "yarn: enabling strict-ssl" \
            yarn config set strict-ssl true
        run_optional "yarn: trusting Zscaler CA" \
            yarn config set cafile "$ZSC_PEM"
    fi

    # AWS CLI — default profile + saml profile (per LM doc)
    if is_installed "aws"; then
        run_optional "aws: trusting Zscaler CA (default profile)" \
            aws configure set ca_bundle "$ZSC_PEM"
        run_optional "aws: trusting Zscaler CA (saml profile)" \
            aws --profile saml configure set ca_bundle "$ZSC_PEM" 2>/dev/null || true
    fi

    # pip / pip3 — pip config set global.cert (per LM doc)
    is_installed "pip" && \
        run_optional "pip: trusting Zscaler CA" \
            pip config set global.cert "$ZSC_PEM" 2>/dev/null || true
    is_installed "pip3" && \
        run_optional "pip3: trusting Zscaler CA" \
            pip3 config set global.cert "$ZSC_PEM" 2>/dev/null || true

    # Java keystore — keytool -import into $JAVA_HOME cacerts (per LM doc)
    # Requires -noprompt to suppress interactive "Trust this certificate?" prompt
    local _java_home=""
    if [[ -n "${JAVA_HOME:-}" && -d "$JAVA_HOME" ]]; then
        _java_home="$JAVA_HOME"
    elif [[ -x /usr/libexec/java_home ]]; then
        _java_home="$(/usr/libexec/java_home 2>/dev/null || true)"
    fi
    if [[ -n "$_java_home" ]] && is_installed "keytool"; then
        local _cacerts="$_java_home/lib/security/cacerts"
        [[ ! -f "$_cacerts" ]] && _cacerts="$_java_home/jre/lib/security/cacerts"
        if [[ -f "$_cacerts" ]]; then
            if keytool -list -alias "Zscaler" \
                    -keystore "$_cacerts" -storepass "changeit" &>/dev/null 2>&1; then
                skip "Java keystore: Zscaler CA already imported"
            else
                run_optional "Java keystore: importing Zscaler CA" \
                    keytool -import -noprompt -alias "Zscaler" \
                        -keystore "$_cacerts" -storepass "changeit" \
                        -file "$ZSC_PEM"
            fi
        fi
    fi

    ok "Tool cert configuration complete"
}

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
    echo "  --no-casks       Skip desktop application cask installs (iTerm2, Keka)"
    echo "  --interactive    Force interactive menu"
    echo "  --help           Show this help message and exit"
    echo ""
    echo "Default: shows grouped TUI (TTY) or full install (non-TTY)."
}

# ── TUI selector (bubbletea) ──────────────────────────────────────────────────
TUI_SELECTOR="$HOME/.terminal-kniferoll/bin/selector"

build_tui_selector() {
    local src="$SCRIPT_DIR/tui/selector"
    [[ -d "$src" ]] || return 1
    is_installed "go" || return 1
    mkdir -p "$(dirname "$TUI_SELECTOR")"
    # Rebuild if source is newer than binary
    if [[ ! -x "$TUI_SELECTOR" || "$src/main.go" -nt "$TUI_SELECTOR" ]]; then
        info "Building TUI selector..."
        (cd "$src" && go mod tidy 2>/dev/null && \
            go build -o "$TUI_SELECTOR" . 2>/dev/null) || return 1
        ok "TUI selector built"
    fi
    return 0
}

run_tui_selector() {
    local output
    output="$("$TUI_SELECTOR" --mac)"
    while IFS='=' read -r key val; do
        [[ -n "$key" ]] && declare -g "$key"="$val"
    done <<< "$output"
}

# ── Fallback bash menu ────────────────────────────────────────────────────────
show_custom_menu() {
    echo -e "\n${BOLD}${CYAN}[ CUSTOM — select tool groups ]${RESET}\n"
    ask_yes_no "  Shell environment (Zsh, Oh My Zsh, plugins, configs)?" \
        && DO_SHELL=true || DO_SHELL=false
    ask_yes_no "  AI Tools (Gemini CLI)?" \
        && DO_AI_TOOLS=true || DO_AI_TOOLS=false
    ask_yes_no "  Developer Tools (bat, fzf, jq, go, python, node...)?" \
        && DO_DEV_TOOLS=true || DO_DEV_TOOLS=false
    ask_yes_no "  Package Managers (npm, yarn, pipx, uv, rustup)?" \
        && DO_PKG_MGRS=true || DO_PKG_MGRS=false
    ask_yes_no "  Security Tools (1Password, nmap, openssl, yara, wtfis)?" \
        && DO_SECURITY=true || DO_SECURITY=false
    ask_yes_no "  Cloud / CLI (awscli, rclone)?" \
        && DO_CLOUD_CLI=true || DO_CLOUD_CLI=false
    ask_yes_no "  Nerd Fonts?" \
        && DO_FONTS=true || DO_FONTS=false
    ask_yes_no "  Projector stack (weathr, trippy, terminal animation)?" \
        && DO_PROJECTOR=true || DO_PROJECTOR=false
    ask_yes_no "  Desktop applications (iTerm2, Keka)?" \
        && DO_DESKTOP=true || DO_DESKTOP=false
}

show_menu() {
    echo -e "\n${BOLD}${BLADE}  What would you like to install?${RESET}\n"
    echo -e "  ${CYAN}[1]${RESET} Full install     — everything ${DIM}(recommended)${RESET}"
    echo -e "  ${CYAN}[2]${RESET} Shell only       — Zsh, Oh My Zsh, plugins, aliases"
    echo -e "  ${CYAN}[3]${RESET} Projector only   — Terminal animation suite"
    echo -e "  ${CYAN}[4]${RESET} Custom           — Choose individual tool groups"
    echo
    echo -en "${CYAN}  Choice [1-4]: ${RESET}"
    read -r _choice
    case "$_choice" in
        1) : ;;  # all defaults are true
        2) DO_SHELL=true; DO_AI_TOOLS=false; DO_DEV_TOOLS=false; DO_PKG_MGRS=false
           DO_SECURITY=false; DO_CLOUD_CLI=false; DO_FONTS=false
           DO_PROJECTOR=false; DO_DESKTOP=false ;;
        3) DO_SHELL=false; DO_AI_TOOLS=false; DO_DEV_TOOLS=false; DO_PKG_MGRS=false
           DO_SECURITY=false; DO_CLOUD_CLI=false; DO_FONTS=true
           DO_PROJECTOR=true; DO_DESKTOP=false ;;
        4) show_custom_menu ;;
        *) warn "Invalid choice — defaulting to full install" ;;
    esac
}

# ── Flag parsing ──────────────────────────────────────────────────────────────
# All categories default to true (install everything)
DO_SHELL=true
DO_AI_TOOLS=true
DO_DEV_TOOLS=true
DO_PKG_MGRS=true
DO_SECURITY=true
DO_CLOUD_CLI=true
DO_FONTS=true
DO_PROJECTOR=true
DO_DESKTOP=true

EXPLICIT_FLAG=false
MODE="${MODE:-batch}"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --shell)
            DO_SHELL=true; DO_AI_TOOLS=false; DO_DEV_TOOLS=false; DO_PKG_MGRS=false
            DO_SECURITY=false; DO_CLOUD_CLI=false; DO_FONTS=false
            DO_PROJECTOR=false; DO_DESKTOP=false; EXPLICIT_FLAG=true ;;
        --projector)
            DO_SHELL=false; DO_AI_TOOLS=false; DO_DEV_TOOLS=false; DO_PKG_MGRS=false
            DO_SECURITY=false; DO_CLOUD_CLI=false; DO_FONTS=true
            DO_PROJECTOR=true; DO_DESKTOP=false; EXPLICIT_FLAG=true ;;
        --no-casks)    DO_DESKTOP=false ;;
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

# ── Zscaler managed-device cert trust ────────────────────────────────────────
# Runs before any curl/brew operation so managed devices can reach GitHub/brew.
banner "MANAGED DEVICE SETUP"
setup_zscaler_trust

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

# Fix Homebrew share directory permissions to prevent oh-my-zsh compaudit warnings.
# Homebrew sets /opt/homebrew/share group-writable (admin), which OMZ flags as insecure.
if [[ -d /opt/homebrew/share ]]; then
    run_optional "Hardening /opt/homebrew/share permissions" \
        chmod g-w,o-w /opt/homebrew/share
fi

if is_installed "brew"; then
    append_if_missing "$HOME/.zprofile" \
        'command -v brew >/dev/null && eval "$(brew shellenv)"'
fi

# ── Install Go early (needed to build TUI selector) ──────────────────────────
if ! is_installed "go" && is_installed "brew"; then
    run_optional "Installing Go (TUI prerequisite)" brew install go
fi

# ── Show TUI or fallback menu ─────────────────────────────────────────────────
if [[ "$EXPLICIT_FLAG" == "false" ]] && { [[ -t 0 ]] || [[ "$MODE" == "interactive" ]]; }; then
    if build_tui_selector && [[ -x "$TUI_SELECTOR" ]]; then
        run_tui_selector
    else
        show_menu
    fi
fi

info "Supply chain: strict (TLS enforced, hashes verified where available)"

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
        OMZ_TAG="24.9.0"
        info "Cloning Oh My Zsh at tag ${OMZ_TAG} (pinned)"
        if ! git clone --depth 1 --branch "$OMZ_TAG" \
                https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" 2>/dev/null; then
            warn "Tag ${OMZ_TAG} not found in ohmyzsh/ohmyzsh — falling back to install.sh (unpinned)"
            omz_script=""
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
    ZSH_AUTOSUG_TAG="v0.7.1"
    # fast-syntax-highlighting tags: https://github.com/zdharma-continuum/fast-syntax-highlighting/tags
    ZSH_FSH_TAG="v1.55"

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

    # Ensure /opt/homebrew/bin is in PATH for non-login shells (Terminal.app, VS Code, etc.)
    if [[ -d /opt/homebrew/bin ]]; then
        _brew_path_line='[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"'
        append_if_missing "$HOME/.zprofile" "$_brew_path_line"
        append_if_missing "$HOME/.zshrc"    "$_brew_path_line"
        [[ ":$PATH:" != *":/opt/homebrew/bin:"* ]] && \
            export PATH="/opt/homebrew/bin:$PATH" && \
            ok "/opt/homebrew/bin added to current session PATH"
        ok "Homebrew PATH ensured in ~/.zprofile and ~/.zshrc"
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# 3. AI TOOLS
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_AI_TOOLS" == "true" ]]; then
    banner "AI TOOLS"
    if ! is_installed "gemini"; then
        run_optional "Installing Gemini CLI" brew install gemini-cli
        ! is_installed "gemini" && is_installed "npm" && \
            run_optional "Installing Gemini CLI (npm fallback)" \
                npm install -g @google/gemini-cli || true
    else
        skip "Gemini CLI already installed"
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# 4. DEVELOPER TOOLS
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_DEV_TOOLS" == "true" ]]; then
    banner "DEVELOPER TOOLS"
    DEV_PACKAGES=(
        bat binutils btop cbonsai cmatrix exiftool
        fastfetch fontconfig freetype fzf gcc gh git gzip
        harfbuzz hexyl jq lolcat lsd lua lz4 lzo m4 micro ncurses
        nushell speedtest-cli sqlite starship tealdeer tmux
        yazi zoxide zsh-autosuggestions zsh-fast-syntax-highlighting
        # Language runtimes
        go openjdk python@3.11 ruby
    )
    for pkg in "${DEV_PACKAGES[@]}"; do
        if brew list "$pkg" &>/dev/null 2>&1; then
            skip "$pkg"
        else
            run_optional "Installing $pkg" brew install "$pkg" || FAILED_TOOLS+=("$pkg")
        fi
    done
fi

# ────────────────────────────────────────────────────────────────────────────
# 5. PACKAGE MANAGERS
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_PKG_MGRS" == "true" ]]; then
    banner "PACKAGE MANAGERS"

    # Node.js + npm
    if brew list node &>/dev/null 2>&1 || is_installed "node"; then
        skip "node (npm)"
    else
        run_optional "Installing node + npm" brew install node || FAILED_TOOLS+=("node")
    fi

    # yarn
    if is_installed "yarn"; then
        skip "yarn"
    else
        # Prefer brew cask for yarn classic (v1)
        run_optional "Installing yarn" brew install yarn || \
            { is_installed "npm" && \
              run_optional "Installing yarn (npm fallback)" npm install -g yarn; } || \
            FAILED_TOOLS+=("yarn")
    fi

    # pipx + uv (Python package managers)
    for pkg in pipx uv; do
        if brew list "$pkg" &>/dev/null 2>&1 || is_installed "$pkg"; then
            skip "$pkg"
        else
            run_optional "Installing $pkg" brew install "$pkg" || FAILED_TOOLS+=("$pkg")
        fi
    done
    is_installed "pipx" && run_optional "Configuring pipx path" pipx ensurepath

    # Rust / cargo via rustup
    if brew list rustup &>/dev/null 2>&1 || is_installed "rustup"; then
        skip "rustup"
    else
        run_optional "Installing rustup" brew install rustup || FAILED_TOOLS+=("rustup")
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# 6. SECURITY TOOLS
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_SECURITY" == "true" ]]; then
    banner "SECURITY TOOLS"

    # 1Password CLI
    if is_installed "op"; then
        skip "1Password CLI already installed"
    else
        run_optional "Installing 1Password CLI" brew install --cask 1password-cli
        is_installed "op" || warn "1Password CLI (op) not found on PATH after install"
    fi
    mkdir -p "$HOME/.1password"

    SECURITY_PACKAGES=(
        ca-certificates gnutls nmap ngrep openssl@3 tcpdump unbound wireshark yara
    )
    for pkg in "${SECURITY_PACKAGES[@]}"; do
        if brew list "$pkg" &>/dev/null 2>&1; then
            skip "$pkg"
        else
            run_optional "Installing $pkg" brew install "$pkg" || FAILED_TOOLS+=("$pkg")
        fi
    done

    # wtfis via pipx
    is_installed "wtfis" || {
        run_optional "Installing wtfis via pipx" pipx install wtfis
        run_optional "Configuring pipx path"     pipx ensurepath
    }
fi

# ────────────────────────────────────────────────────────────────────────────
# 7. CLOUD / CLI
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_CLOUD_CLI" == "true" ]]; then
    banner "CLOUD / CLI"

    # AWS CLI
    if is_installed "aws"; then
        skip "AWS CLI already installed"
    else
        run_optional "Installing AWS CLI" brew install awscli || FAILED_TOOLS+=("awscli")
    fi

    # rclone
    if brew list rclone &>/dev/null 2>&1 || is_installed "rclone"; then
        skip "rclone"
    else
        run_optional "Installing rclone" brew install rclone || FAILED_TOOLS+=("rclone")
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# 8. DESKTOP APPLICATIONS (Casks)
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_DESKTOP" == "true" ]]; then
    banner "DESKTOP APPLICATIONS"

    _restricted=false
    if is_restricted_device; then
        _restricted=true
        info "Managed device detected — cask installs may require admin approval"
    fi

    if is_app_installed "iTerm"; then
        skip "iTerm2 already installed"
    else
        [[ "$_restricted" == "true" ]] && \
            quip "Restricted device — iTerm2 may need Self Service or manual install"
        run_optional "Installing iTerm2" brew install --cask iterm2
        is_app_installed "iTerm" || warn "iTerm2 not found — install manually or via Self Service"
    fi

    if is_app_installed "Keka"; then
        skip "Keka already installed"
    else
        [[ "$_restricted" == "true" ]] && \
            quip "Restricted device — Keka may need Self Service or manual install"
        run_optional "Installing Keka" brew install --cask keka
        is_app_installed "Keka" || warn "Keka not found — install manually or via Self Service"
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# 9. NERD FONTS
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_FONTS" == "true" ]]; then
    FONT_DIR="$HOME/Library/Fonts"
    NERD_FONTS=(
        Iosevka Hack UbuntuMono JetBrainsMono 3270
        FiraCode CascadiaCode VictorMono Mononoki
        SpaceMono SourceCodePro Meslo GeistMono
    )
    NERD_FONTS_VER="v3.4.0"
    banner "NERD FONTS"
    mkdir -p "$FONT_DIR"
    for _nf in "${NERD_FONTS[@]}"; do
        if find "$FONT_DIR" -maxdepth 1 -iname "*${_nf}*" -print -quit 2>/dev/null | grep -q .; then
            skip "$_nf Nerd Font already installed"
            continue
        fi
        _font_zip="$(mktemp /tmp/font-XXXXXX.zip)"
        _font_extract="$(mktemp -d /tmp/font-extract-XXXXXX)"
        _font_curl_opts=(--proto '=https' --tlsv1.2 -fsSL)
        [[ -n "${CURL_CA_BUNDLE:-}" && -f "${CURL_CA_BUNDLE}" ]] && \
            _font_curl_opts+=(--cacert "$CURL_CA_BUNDLE")
        if curl "${_font_curl_opts[@]}" \
                "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VER}/${_nf}.zip" \
                -o "$_font_zip"; then
            unzip -qo "$_font_zip" -d "$_font_extract"
            find "$_font_extract" -name "*.ttf" -exec cp {} "$FONT_DIR/" \;
            ok "$_nf Nerd Font installed"
        else
            warn "$_nf Nerd Font download failed"
            FAILED_TOOLS+=("font:$_nf")
        fi
        rm -rf "$_font_zip" "$_font_extract"
    done
fi

# ────────────────────────────────────────────────────────────────────────────
# 10. PROJECTOR STACK
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_PROJECTOR" == "true" ]]; then
    banner "PROJECTOR STACK"
    ensure_rust_toolchain

    is_installed "weathr" || run_optional "Installing weathr via cargo" cargo install weathr
    is_installed "trip"   || run_optional "Installing trippy via cargo" cargo install trippy

    banner "PROJECTOR CONFIGURATION"
    mkdir -p "$HOME/.config/projector"
    [[ -f "$HOME/.config/projector/config.json" ]] || \
        cp "$SCRIPT_DIR/projector/config.json.default" "$HOME/.config/projector/config.json"
    [[ -f "$SCRIPT_DIR/projector.py" ]] && chmod +x "$SCRIPT_DIR/projector.py" || true
    ok "Projector configuration deployed"
fi

# ────────────────────────────────────────────────────────────────────────────
# 11. TERMINAL THEME
# ────────────────────────────────────────────────────────────────────────────
banner "TERMINAL THEME"
ITERM_THEME_SRC="$SCRIPT_DIR/macos/Cyberwave.itermcolors"
ITERM_PREFS_DIR="$HOME/Library/Application Support/iTerm2"

if [[ -f "$ITERM_THEME_SRC" ]]; then
    if [[ -d "/Applications/iTerm.app" ]]; then
        mkdir -p "$ITERM_PREFS_DIR"
        _dest="$ITERM_PREFS_DIR/Cyberwave.itermcolors"
        if [[ ! -f "$_dest" ]]; then
            cp "$ITERM_THEME_SRC" "$_dest"
            ok "Cyberwave theme staged — opening iTerm2 to import"
            quip "Preferences → Profiles → Colors → Color Presets… → Import…"
            open "$_dest" 2>/dev/null || warn "Could not auto-open theme; import manually from $_dest"
        else
            skip "Cyberwave iTerm2 theme already staged"
        fi
    else
        warn "iTerm2 not found — theme file is at: $ITERM_THEME_SRC"
        quip "Install iTerm2, then double-click the file above to import Cyberwave"
    fi
else
    warn "Cyberwave theme source not found — run from repo root"
fi

# ────────────────────────────────────────────────────────────────────────────
# 12. TOOL CERT CONFIGURATION (Zscaler managed devices)
# ────────────────────────────────────────────────────────────────────────────
configure_tool_certs

# ────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ────────────────────────────────────────────────────────────────────────────
sc_process_deferred
print_summary
sc_summary
echo -e "${BOLD}${CYAN}>>> mission complete. knives sharp. out.${RESET}"
echo -e "${DIM}    Reminder: restart your shell or run 'source ~/.zshrc' to activate.${RESET}"
