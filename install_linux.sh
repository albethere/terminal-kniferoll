#!/usr/bin/env bash
# =============================================================================
# terminal-kniferoll | Linux Installer (Shell + Projector)
# =============================================================================
#
# Supply chain controls: lib/supply_chain_guard.sh is sourced below.
# Set SC_RISK_TOLERANCE=1..4 in environment to bypass the interactive prompt.
# Set SC_ALLOW_RISKY=1 to match pre-guard (permissive) behavior in automation.
# =============================================================================

set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

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

# ── Helper: apt single-package install (skip if present) ─────────────────────
apt_install() {
    local check_bin="$1" pkg="$2" desc="${3:-$2}"
    if is_installed "$check_bin"; then skip "$desc already installed"; return 0; fi
    info "Installing $desc..."
    if sudo apt-get install -y --fix-missing -q "$pkg" 2>&1 | tail -3; then
        ok "$desc installed"
    else
        warn "$desc install failed — logged"
        FAILED_TOOLS+=("$pkg")
    fi
}

# ── Helper: apt batch install ────────────────────────────────────────────────
apt_batch() {
    local section="$1"; shift
    local to_install=()
    banner "$section"
    for entry in "$@"; do
        local bin="${entry%%:*}" pkg="${entry##*:}"
        if is_installed "$bin" || dpkg -s "$pkg" &>/dev/null 2>&1; then
            skip "$pkg"
        else
            to_install+=("$pkg")
        fi
    done
    if [[ ${#to_install[@]} -eq 0 ]]; then
        quip "Nothing new here — pantry stocked."; return 0
    fi
    info "Installing: ${to_install[*]}"
    if sudo apt-get install -y --fix-missing -q "${to_install[@]}" 2>&1 | \
        grep -E '(Setting up|already installed|[Ee]rror|E:)'; then
        ok "$section — complete"
    else
        warn "Partial failure in $section — check log"
        for pkg in "${to_install[@]}"; do FAILED_TOOLS+=("$pkg"); done
    fi
}

# ── Helper: cargo install (skip if present) ──────────────────────────────────
cargo_install() {
    local check_bin="$1" crate="$2" name="${3:-$2}"
    if is_installed "$check_bin"; then skip "$name already installed"; return 0; fi
    if ! is_installed "cargo"; then
        warn "cargo not found — skipping $name"; FAILED_TOOLS+=("${name}(cargo)"); return 0
    fi
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env" || true
    info "Compiling $name via cargo..."
    if cargo install "$crate"; then ok "$name compiled and ready"
    else warn "cargo install failed for $name"; FAILED_TOOLS+=("${name}(cargo)"); fi
}

# ── Helper: install .deb from GitHub releases (arch-aware, with SHA256 verify) ─
install_github_deb() {
    local check_bin="$1" repo="$2" pattern="$3" name="$4"
    if is_installed "$check_bin"; then skip "$name already installed"; return 0; fi
    [[ "$PKG_MGR" == "apt" ]] || return 0
    info "Installing $name from GitHub releases..."
    local curl_args=(--proto '=https' --tlsv1.2 -fsSL)
    [[ -n "${GITHUB_TOKEN:-}" && "${GITHUB_TOKEN}" =~ ^[A-Za-z0-9_-]+$ ]] && \
        curl_args+=(-H "Authorization: token ${GITHUB_TOKEN}")

    # Fetch release JSON once — reuse for both .deb and checksum lookups
    local release_json
    release_json=$(curl "${curl_args[@]}" \
        "https://api.github.com/repos/${repo}/releases/latest")

    # Try native arch first, then any match
    local url=""
    url=$(echo "$release_json" | grep browser_download_url \
        | grep -E "$pattern" | grep -v musl | head -1 | cut -d'"' -f4 || true)
    [[ -z "$url" ]] && \
        url=$(echo "$release_json" | grep browser_download_url \
            | grep -E "$pattern" | head -1 | cut -d'"' -f4 || true)
    if [[ -z "$url" ]]; then
        warn "No release .deb found for $name matching $pattern"
        FAILED_TOOLS+=("${name}(github)"); return 0
    fi

    local filename; filename="$(basename "$url")"

    # Locate checksum asset: prefer per-file <filename>.sha256sum or .sha256 (bat-style),
    # fall back to combined sha256sums/SHA256SUMS/checksums.txt (lsd-style).
    local sha_url="" sha_combined_url=""
    sha_url=$(echo "$release_json" | grep browser_download_url \
        | grep -Ei "${filename}\\.sha256(sum)?\b" | head -1 | cut -d'"' -f4 || true)
    [[ -z "$sha_url" ]] && \
        sha_combined_url=$(echo "$release_json" | grep browser_download_url \
            | grep -Ei '"[^"]*/(sha256sums?|checksums?)(\.txt)?\"' \
            | head -1 | cut -d'"' -f4 || true)

    # Download .deb
    local tmp_deb; tmp_deb="$(mktemp "/tmp/${name}-XXXXXX.deb")"
    if ! curl "${curl_args[@]}" -o "$tmp_deb" "$url"; then
        warn "Download failed for $name"; FAILED_TOOLS+=("${name}(github)")
        rm -f "$tmp_deb"; return 0
    fi

    # Verify SHA256 — hard-fail on mismatch, soft-warn if no checksum asset found
    local verified=false
    local tmp_sha actual expected
    if [[ -n "$sha_url" ]]; then
        tmp_sha="$(mktemp "/tmp/${name}-sha256-XXXXXX.txt")"
        if curl "${curl_args[@]}" -o "$tmp_sha" "$sha_url" && [[ -s "$tmp_sha" ]]; then
            expected=$(awk '{print $1}' "$tmp_sha" | head -1)
            actual=$(sha256sum "$tmp_deb" | awk '{print $1}')
            rm -f "$tmp_sha"
            if [[ "$expected" == "$actual" ]]; then
                ok "$name SHA256 verified (${actual:0:16}…)"
                verified=true
            else
                warn "SHA256 MISMATCH for $name — refusing to install"
                warn "  expected: $expected"
                warn "  actual:   $actual"
                FAILED_TOOLS+=("${name}(sha256-mismatch)")
                rm -f "$tmp_deb"; return 0
            fi
        else
            rm -f "$tmp_sha"
            warn "$name: SHA256 file download failed — proceeding without verification"
        fi
    elif [[ -n "$sha_combined_url" ]]; then
        tmp_sha="$(mktemp "/tmp/${name}-sha256sums-XXXXXX.txt")"
        if curl "${curl_args[@]}" -o "$tmp_sha" "$sha_combined_url" && [[ -s "$tmp_sha" ]]; then
            expected=$(grep -F "$filename" "$tmp_sha" | awk '{print $1}' | head -1)
            rm -f "$tmp_sha"
            if [[ -n "$expected" ]]; then
                actual=$(sha256sum "$tmp_deb" | awk '{print $1}')
                if [[ "$expected" == "$actual" ]]; then
                    ok "$name SHA256 verified (${actual:0:16}…)"
                    verified=true
                else
                    warn "SHA256 MISMATCH for $name — refusing to install"
                    warn "  expected: $expected"
                    warn "  actual:   $actual"
                    FAILED_TOOLS+=("${name}(sha256-mismatch)")
                    rm -f "$tmp_deb"; return 0
                fi
            else
                warn "$name: entry not found in combined SHA file — proceeding without verification"
            fi
        else
            rm -f "$tmp_sha"
            warn "$name: SHA256 sums file download failed — proceeding without verification"
        fi
    else
        warn "$name: no SHA256 asset found in release — proceeding without verification"
    fi
    [[ "$verified" == "false" ]] && _log "WARN" "$name installed without SHA256 verification"

    sudo dpkg -i "$tmp_deb" || sudo apt-get install -f -y -q || true
    ok "$name installed from GitHub"
    rm -f "$tmp_deb"
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

# ── Feature: 1Password CLI ────────────────────────────────────────────────────
install_1password_cli() {
    if is_installed "op"; then skip "1Password CLI already installed"; return 0; fi
    if [[ "$PKG_MGR" == "apt" ]]; then
        local key_asc key_gpg old_umask
        old_umask="$(umask)"
        umask 077
        key_asc="$(mktemp /tmp/1password-key-XXXXXX.asc)"
        key_gpg="$(mktemp /tmp/1password-key-XXXXXX.gpg)"
        umask "$old_umask"
        chmod 600 "$key_asc" "$key_gpg"
        if ! curl --proto '=https' --tlsv1.2 -fsSL \
            "https://downloads.1password.com/linux/keys/1password.asc" -o "$key_asc" \
            || [[ ! -s "$key_asc" ]]; then
            warn "1Password signing key download failed — skipping"
            rm -f "$key_asc" "$key_gpg"; return 0
        fi
        run_optional "Installing 1Password prerequisites" \
            bash -c "$SUDO apt-get install -y -qq curl gnupg ca-certificates"
        $SUDO install -d -m 0755 /usr/share/keyrings
        gpg --dearmor < "$key_asc" | $SUDO install -m 0644 /dev/stdin \
            /usr/share/keyrings/1password-archive-keyring.gpg
        rm -f "$key_asc" "$key_gpg"
        local arch; arch="$(dpkg --print-architecture)"
        echo "deb [arch=${arch} signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] \
https://downloads.1password.com/linux/debian/${arch} stable main" | \
            $SUDO tee /etc/apt/sources.list.d/1password.list >/dev/null
        run_optional "Refreshing apt after 1Password repo" bash -c "$SUDO apt-get update -qq"
        run_optional "Installing 1Password CLI" bash -c "$SUDO apt-get install -y 1password-cli"
    elif [[ "$PKG_MGR" == "pacman" ]]; then
        run_optional "Installing 1Password CLI (pacman)" \
            bash -c "$SUDO pacman -S --noconfirm 1password-cli"
    fi
    mkdir -p "$HOME/.1password"
    run_optional "Setting .1password ownership" \
        bash -c "$SUDO chown -R '$USER':'$USER' '$HOME/.1password'"
}

# ── Feature: Homebrew + Gemini CLI ───────────────────────────────────────────
install_homebrew_and_gemini() {
    local brew_bin=""
    if is_installed "brew"; then
        brew_bin="$(command -v brew)"; skip "Homebrew already installed"
    else
        [[ "$PKG_MGR" == "apt" ]] && \
            run_optional "Installing Homebrew build prerequisites" \
                bash -c "$SUDO apt-get install -y -qq build-essential procps curl file git"
        local brew_script
        brew_script="$(download_to_tmp \
            "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" \
            "homebrew-install-XXXXXX.sh")"
        run_optional "Installing Homebrew" env NONINTERACTIVE=1 /bin/bash "$brew_script"
        rm -f "$brew_script"
        [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]] && \
            brew_bin="/home/linuxbrew/.linuxbrew/bin/brew" || true
        [[ -z "$brew_bin" && -x "$HOME/.linuxbrew/bin/brew" ]] && \
            brew_bin="$HOME/.linuxbrew/bin/brew" || true
    fi
    [[ -z "$brew_bin" ]] && is_installed "brew" && brew_bin="$(command -v brew)"
    if [[ -n "$brew_bin" ]]; then
        eval "$("$brew_bin" shellenv)"
        append_if_missing "$HOME/.zshrc" \
            'command -v brew >/dev/null && eval "$(brew shellenv)"'
        append_if_missing "$HOME/.bashrc" \
            'command -v brew >/dev/null && eval "$(brew shellenv)"'
        run_optional "Updating Homebrew" brew update
        run_optional "Installing gcc via Homebrew" brew install gcc
        if ! is_installed "gemini"; then
            run_optional "Installing Gemini CLI (Homebrew)" brew install gemini-cli
            ! is_installed "gemini" && is_installed "npm" && \
                run_optional "Installing Gemini CLI (npm fallback)" \
                    npm install -g @google/gemini-cli || true
        else
            skip "Gemini CLI already installed"
        fi
    else
        warn "Homebrew unavailable — skipping Homebrew-based installs"
    fi
}

# ── Cleanup: tools explicitly removed from this project ──────────────────────
# Run on every install to evict previously-installed tools we've cut.
# All checks are guarded — safe on fresh machines.
cleanup_removed_tools() {
    local did_work=false

    # ── atuin — removed 2026-04-05: HIGH supply chain risk (custom-domain curl|bash),
    #   no value-add over built-in zsh history on a hardened deployment.
    if is_installed "atuin" || [[ -f "$HOME/.cargo/bin/atuin" ]] || \
       [[ -d "$HOME/.atuin" ]]; then
        did_work=true
        warn "atuin found — evicting (cut: supply chain risk)"
        if is_installed "cargo" && \
           cargo install --list 2>/dev/null | grep -q "^atuin "; then
            run_optional "Removing atuin (cargo uninstall)" cargo uninstall atuin
        fi
        rm -f "$HOME/.cargo/bin/atuin" 2>/dev/null || true
        [[ -d "$HOME/.atuin" ]] && \
            run_optional "Removing ~/.atuin data dir" rm -rf "$HOME/.atuin"
        # Scrub atuin init from deployed zshrc
        if [[ -f "$HOME/.zshrc" ]]; then
            sed -i '/command -v atuin.*atuin init zsh/d' "$HOME/.zshrc" 2>/dev/null || true
            ok "atuin init removed from ~/.zshrc"
        fi
        if [[ "$PKG_MGR" == "pacman" ]]; then
            pacman -Qi atuin &>/dev/null 2>&1 && \
                run_optional "Removing atuin (pacman)" \
                    bash -c "$SUDO pacman -R --noconfirm atuin" || true
        fi
        ok "atuin — evicted"
    fi

    # ── mise — removed 2026-04-05: HIGH supply chain risk (custom-domain curl|bash)
    #   on apt systems; no safe binary channel. Use native pyenv/nvm/system packages.
    if is_installed "mise" || [[ -f "$HOME/.local/bin/mise" ]] || \
       [[ -f "$HOME/.cargo/bin/mise" ]]; then
        did_work=true
        warn "mise found — evicting (cut: supply chain risk)"
        if is_installed "cargo" && \
           cargo install --list 2>/dev/null | grep -q "^mise "; then
            run_optional "Removing mise (cargo uninstall)" cargo uninstall mise
        fi
        rm -f "$HOME/.local/bin/mise" "$HOME/.cargo/bin/mise" 2>/dev/null || true
        [[ -d "$HOME/.local/share/mise" ]] && \
            run_optional "Removing ~/.local/share/mise data dir" \
                rm -rf "$HOME/.local/share/mise"
        if [[ "$PKG_MGR" == "pacman" ]]; then
            pacman -Qi mise &>/dev/null 2>&1 && \
                run_optional "Removing mise (pacman)" \
                    bash -c "$SUDO pacman -R --noconfirm mise" || true
        fi
        ok "mise — evicted"
    fi

    "$did_work" || skip "No removed tools found — clean slate"
}

# ── Feature: sudo keepalive ───────────────────────────────────────────────────
check_sudo() {
    quip "Checking sudo access..."
    if ! sudo -v 2>/dev/null; then die "sudo authentication failed"; fi
    ok "sudo — cleared"
    ( while true; do sudo -n true; sleep 50; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "${SUDO_KEEPALIVE_PID:-}" 2>/dev/null; true' EXIT
}

# ── Mission summary ───────────────────────────────────────────────────────────
print_summary() {
    banner "MISSION DEBRIEF"
    if [[ ${#FAILED_TOOLS[@]} -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}  ALL SYSTEMS NOMINAL — zero casualties.${RESET}"
    else
        echo -e "${YELLOW}${BOLD}  MISSION COMPLETE WITH CASUALTIES:${RESET}"
        for t in "${FAILED_TOOLS[@]}"; do echo -e "  ${RED}[✗]${RESET}  $t"; done
        quip "Try: sudo apt-get update && sudo apt-get install --fix-missing <pkg>"
    fi
    echo
    echo -e "${DIM}  [→] Log saved to: ${LOG_FILE}${RESET}"
    _log "INFO" "Install complete. Failures: ${#FAILED_TOOLS[@]}"
}

# ── Help text ─────────────────────────────────────────────────────────────────
show_help() {
    echo "Usage: install_linux.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --shell          Install shell environment only (zsh, oh-my-zsh, dotfiles)"
    echo "  --projector      Install projector tools only (Rust, cargo tools, fonts)"
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
    ask_yes_no "  Core security & developer tools (nmap, ripgrep, fzf...)?" \
        && DO_SECURITY=true || DO_SECURITY=false
    ask_yes_no "  Projector stack (Rust, weathr, JetBrains font, config)?" \
        && INSTALL_PROJECTOR=true || INSTALL_PROJECTOR=false
    ask_yes_no "  Homebrew + Gemini CLI?" \
        && DO_BREW=true || DO_BREW=false
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
DO_BREW=true

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

# ── OS detection ──────────────────────────────────────────────────────────────
if command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
    info "Detected Debian/Ubuntu-based system"
elif command -v pacman &>/dev/null; then
    PKG_MGR="pacman"
    info "Detected Arch/CachyOS-based system"
    if command -v yay &>/dev/null; then AUR_HELPER="yay"
    elif command -v paru &>/dev/null; then AUR_HELPER="paru"
    else AUR_HELPER=""; fi
else
    die "Unsupported Linux distribution — no apt-get or pacman found"
fi

SUDO=""
if [[ "$EUID" -ne 0 ]]; then
    command -v sudo &>/dev/null || die "sudo not installed and not root"
    SUDO="sudo"
fi

ARCH="$(dpkg --print-architecture 2>/dev/null || echo "amd64")"
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

# ── Show menu or use defaults ─────────────────────────────────────────────────
if [[ "$EXPLICIT_FLAG" == "false" ]] && { [[ -t 0 ]] || [[ "$MODE" == "interactive" ]]; }; then
    show_menu
fi

# ── Resolve deployment flags ──────────────────────────────────────────────────
DO_CORE=true
DO_SHELL="$INSTALL_SHELL"
DO_PROJECTOR="$INSTALL_PROJECTOR"

# ── Supply chain risk policy (interactive TTY only; no-op in batch/CI) ────────
sc_set_risk_tolerance

# ── sudo keepalive (non-root only) ────────────────────────────────────────────
[[ "$EUID" -ne 0 ]] && check_sudo

# ── Evict tools removed from this project ─────────────────────────────────────
banner "HOUSEKEEPING — EVICTING REMOVED TOOLS"
cleanup_removed_tools

# ────────────────────────────────────────────────────────────────────────────
# 1. CORE PREREQUISITES
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_CORE" == "true" ]]; then
    banner "CORE PREREQUISITES"
    if [[ "$PKG_MGR" == "apt" ]]; then
        run_optional "Refreshing apt package list" \
            bash -c "$SUDO apt-get update -qq"
        run_optional "Installing core prerequisites" \
            bash -c "$SUDO apt-get install -y -qq ca-certificates curl gnupg unzip fontconfig"
    else
        run_optional "Refreshing pacman database" \
            bash -c "$SUDO pacman -Sy --noconfirm"
        run_optional "Installing core prerequisites" \
            bash -c "$SUDO pacman -S --noconfirm ca-certificates curl gnupg unzip fontconfig"
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# 2. SHELL ENVIRONMENT
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_SHELL" == "true" ]]; then
    banner "SHELL ENVIRONMENT"
    if [[ "$PKG_MGR" == "apt" ]]; then
        apt_install "zsh" "zsh" "Zsh shell"
    else
        is_installed "zsh" || \
            run_optional "Installing zsh (pacman)" bash -c "$SUDO pacman -S --noconfirm zsh"
    fi

    run_optional "Setting default shell to zsh" \
        bash -c "$SUDO chsh -s '$(command -v zsh)' '$USER'"

    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        omz_script="$(download_to_tmp \
            "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" \
            "ohmyzsh-install-XXXXXX.sh")"
        RUNZSH=no CHSH=no run_optional "Installing Oh My Zsh" bash "$omz_script" --unattended
        rm -f "$omz_script"
    else
        skip "Oh My Zsh already installed"
    fi

    ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    mkdir -p "$ZSH_CUSTOM/plugins"

    [[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] || \
        run_optional "Installing zsh-autosuggestions plugin" \
            git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
                "$ZSH_CUSTOM/plugins/zsh-autosuggestions"

    # fast-syntax-highlighting MUST be last plugin loaded
    [[ -d "$ZSH_CUSTOM/plugins/fast-syntax-highlighting" ]] || \
        run_optional "Installing fast-syntax-highlighting plugin" \
            git clone --depth=1 https://github.com/zdharma-continuum/fast-syntax-highlighting \
                "$ZSH_CUSTOM/plugins/fast-syntax-highlighting"

    banner "DEPLOYING SHELL CONFIGS"
    mkdir -p "$HOME/.shell"
    cp "$SCRIPT_DIR/shell/zshrc.zsh"   "$HOME/.zshrc"
    cp "$SCRIPT_DIR/shell/aliases.zsh" "$HOME/.shell/aliases.zsh"
    cp "$SCRIPT_DIR/shell/plugins.zsh" "$HOME/.shell/plugins.zsh"
    ok "Shell configurations deployed"
fi

# ── uv: safe install only (no custom-domain script) ──────────────────────────
# astral.sh/uv/install.sh was HIGH risk — removed. uv is available via pipx
# on apt systems and natively in pacman. The risky curl|bash path is gone.
_install_uv_safe() {
    if [[ "$PKG_MGR" == "pacman" ]]; then
        is_installed "uv" && { skip "uv already installed"; return 0; }
        run_optional "Installing uv (pacman)" bash -c "$SUDO pacman -S --noconfirm uv"
    else
        is_installed "uv" && { skip "uv already installed"; return 0; }
        run_optional "Installing uv via pipx" pipx install uv
        run_optional "Configuring pipx path" pipx ensurepath
    fi
}

# ────────────────────────────────────────────────────────────────────────────
# 3. SECURITY / DEVELOPER TOOLS
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_SECURITY" == "true" ]]; then
    install_1password_cli
    [[ "${DO_BREW:-true}" == "true" ]] && install_homebrew_and_gemini

    if [[ "$PKG_MGR" == "apt" ]]; then
        apt_batch "SECURITY TOOLING" \
            "nmap:nmap" "tcpdump:tcpdump" "ngrep:ngrep" \
            "tshark:wireshark" "yara:yara" "unbound:unbound" \
            "certtool:gnutls-bin" "hexyl:hexyl"

        apt_batch "DEVELOPER UTILITIES" \
            "jq:jq" "fzf:fzf" "rg:ripgrep" "micro:micro" \
            "sqlite3:sqlite3" "lua5.4:lua5.4" "m4:m4" "lz4:lz4" \
            "exiftool:libimage-exiftool-perl" "git:git" \
            "curl:curl" "gzip:gzip" "tmux:tmux" "btop:btop"

        apt_batch "BUILD AND CRYPTO" \
            "openssl:openssl" "python3:python3" "pip3:python3-pip" \
            "ruby:ruby" "binutils:binutils" "fc-cache:fontconfig" \
            "ca-certificates:ca-certificates" "libssl-dev:libssl-dev" \
            "node:nodejs" "go:golang"

        apt_batch "PYTHON AND PACKAGE MANAGEMENT" \
            "pipx:pipx" "python3:python3-venv"

        apt_batch "SHELL EXTRAS" \
            "rclone:rclone" "speedtest-cli:speedtest-cli" "unzip:unzip" \
            "fastfetch:fastfetch" "zoxide:zoxide" "starship:starship" \
            "cmatrix:cmatrix" "cbonsai:cbonsai"

        # Tools requiring non-apt installation methods
        # uv — safe install only (astral.sh custom-domain script removed)
        _install_uv_safe

        if ! is_installed "nu"; then
            is_installed "cargo" && cargo_install "nu" "nu" "nushell" || \
                warn "nushell not in apt and no cargo — skipping"
        fi
        if ! is_installed "yazi"; then
            is_installed "cargo" && cargo_install "yazi" "yazi-fm yazi-cli" "yazi" || \
                warn "yazi not in apt and no cargo — skipping"
        fi
        # mise and atuin are not installed — removed 2026-04-05 (supply chain risk)
        # Use native pyenv/nvm for runtime version management; zsh built-in history for atuin
    else
        # Arch/CachyOS via pacman
        PACMAN_PACKAGES=(
            binutils btop exiftool fastfetch fzf git gnutls go gzip hexyl jq openssl lua
            lz4 m4 micro ncurses ngrep nmap nodejs python-pipx python python-pip rclone
            ripgrep ruby rustup speedtest-cli sqlite tcpdump tealdeer tmux unbound uv
            wireshark-cli yara zsh-autosuggestions cmatrix nushell yazi
            zoxide starship
            # mise and atuin removed 2026-04-05 — supply chain risk
        )
        for pkg in "${PACMAN_PACKAGES[@]}"; do
            pacman -Qi "$pkg" &>/dev/null && skip "$pkg" && continue
            run_optional "Installing $pkg" bash -c "$SUDO pacman -S --noconfirm '$pkg'"
        done
        if ! is_installed "cbonsai" && [[ -n "${AUR_HELPER:-}" ]]; then
            run_optional "Installing cbonsai (AUR)" "$AUR_HELPER" -S --noconfirm cbonsai
        fi
    fi

    banner "GITHUB RELEASE INSTALLS"
    install_github_deb "lsd" "lsd-rs/lsd"    "_${ARCH}\\.deb" "lsd"
    install_github_deb "bat" "sharkdp/bat"   "_${ARCH}\\.deb" "bat"
    is_installed "wtfis" || {
        run_optional "Installing wtfis via pipx" pipx install wtfis
        run_optional "Configuring pipx path"     pipx ensurepath
    }
    is_installed "lolcat" || \
        run_optional "Installing lolcat via gem" bash -c "$SUDO gem install lolcat"
fi

# ────────────────────────────────────────────────────────────────────────────
# 4. PROJECTOR STACK
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_PROJECTOR" == "true" ]]; then
    banner "PROJECTOR STACK"
    ensure_rust_toolchain
    cargo_install "weathr" "weathr"  "weathr (weather CLI)"
    cargo_install "trip"   "trippy"  "trippy (network pulse)"

    FONT_DIR="$HOME/.local/share/fonts"
    if ! fc-list 2>/dev/null | grep -qi "JetBrainsMono"; then
        banner "JETBRAINSMONO NERD FONT"
        mkdir -p "$FONT_DIR/JetBrainsMono"
        font_zip="$(mktemp /tmp/font-XXXXXX.zip)"
        # Pinned to v3.4.0 — update version here when upgrading
        run_optional "Downloading JetBrainsMono Nerd Font" \
            curl --proto '=https' --tlsv1.2 -fsSL \
                "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip" \
                -o "$font_zip"
        run_optional "Extracting font" unzip -q "$font_zip" -d "$FONT_DIR/JetBrainsMono"
        run_optional "Refreshing font cache" fc-cache -f
        rm -f "$font_zip"
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
echo -e "${DIM}    Reminder: run 'chsh -s \$(which zsh)' to set Zsh as default shell.${RESET}"
echo -e "${DIM}    Reminder: source ~/.cargo/env or restart your shell for Rust tools.${RESET}"
