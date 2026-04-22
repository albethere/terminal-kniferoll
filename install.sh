#!/usr/bin/env bash
# =============================================================================
# terminal-kniferoll | Universal Entrypoint
# Standardized environment bootstrapper (Shell + Projector)
# =============================================================================

set -euo pipefail

# --- ANSI Colors ---
C_ORANGE="\033[38;5;214m"
C_BLUE="\033[38;5;75m"
C_PURPLE="\033[38;5;135m"
C_RESET="\033[0m"

# --- Help ---
show_help() {
    echo "Usage: ./install.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --shell          Install shell environment only (zsh, oh-my-zsh, dotfiles)"
    echo "  --projector      Install projector tools only (Rust, cargo tools, fonts)"
    echo "  --interactive    Force interactive menu"
    echo "  --help           Show this help message and exit"
    echo ""
    echo "With no options: shows a 4-choice install menu (TTY) or full install (non-TTY)."
}

for arg in "$@"; do
    if [[ "$arg" == "--help" ]]; then
        show_help
        exit 0
    fi
done

echo -e "${C_PURPLE}================================================================${C_RESET}"
echo -e "${C_ORANGE}  ■■■■■■■  ${C_BLUE}T E R M I N A L   K N I F E R O L L${C_RESET}"
echo -e "${C_PURPLE}================================================================${C_RESET}"

OS_TYPE="$(uname -s 2>/dev/null || echo 'Unknown')"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$OS_TYPE" in
    Linux)
        echo -e "[*] Detected Linux environment. Delegating to install_linux.sh..."
        bash "$SCRIPT_DIR/install_linux.sh" "$@"
        ;;
    Darwin)
        echo -e "[*] Detected macOS environment. Delegating to install_mac.sh..."
        bash "$SCRIPT_DIR/install_mac.sh" "$@"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        # NOTE: install.sh requires Git Bash / MSYS2 on Windows (uname must exist).
        # From native PowerShell, run install_windows.ps1 directly instead.
        echo -e "[*] Detected Windows (Git Bash/MSYS2). Delegating to install_windows.ps1..."
        powershell.exe -ExecutionPolicy Bypass -File "$SCRIPT_DIR/install_windows.ps1" "$@"
        ;;
    *)
        echo -e "[!] Unsupported OS: $OS_TYPE"
        exit 1
        ;;
esac
