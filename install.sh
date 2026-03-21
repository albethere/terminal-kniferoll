#!/usr/bin/env bash
# =============================================================================
# terminal-kniferoll | Universal Entrypoint
# Standardized environment bootstrapper (Shell + Projector)
# =============================================================================

set -e

# --- ANSI Colors ---
C_ORANGE="\033[38;5;214m"
C_BLUE="\033[38;5;75m"
C_PURPLE="\033[38;5;135m"
C_RESET="\033[0m"

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
    *)
        if [[ -n "$WSL_DISTRO_NAME" ]]; then
            echo -e "[*] Detected WSL environment. Delegating to install_linux.sh..."
            bash "$SCRIPT_DIR/install_linux.sh" "$@"
        else
            echo -e "[!] Unsupported OS: $OS_TYPE. Attempting Windows PowerShell if applicable..."
            # Implementation for Windows handover if needed
        fi
        ;;
esac
