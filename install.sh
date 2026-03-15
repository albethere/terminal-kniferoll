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

# --- PSYCHIC BOOTSTRAPPER ---
echo -e "\n${C_BLUE}Initializing Psychic Bootstrapper...${C_RESET}"

# 1. Optional environment awareness (set LCARS_CORE_DIR or leave unset for standalone use)
AWARENESS_SCRIPT=""
if [[ -n "${LCARS_CORE_DIR:-}" && -f "$LCARS_CORE_DIR/scripts/lcars_awareness.sh" ]]; then
    AWARENESS_SCRIPT="$LCARS_CORE_DIR/scripts/lcars_awareness.sh"
elif [[ -f "$SCRIPT_DIR/../lcars-core/scripts/lcars_awareness.sh" ]]; then
    AWARENESS_SCRIPT="$(cd "$SCRIPT_DIR/../lcars-core/scripts" && pwd)/lcars_awareness.sh"
elif [[ -f "$HOME/Projects/lcars-core/scripts/lcars_awareness.sh" ]]; then
    AWARENESS_SCRIPT="$HOME/Projects/lcars-core/scripts/lcars_awareness.sh"
fi
if [[ -n "$AWARENESS_SCRIPT" ]]; then
    source "$AWARENESS_SCRIPT"
    lcars_report_awareness 2>/dev/null || true
else
    echo -e "\033[1;33m[*] Standalone mode. Set LCARS_CORE_DIR to enable optional awareness.\033[0m"
fi

# 2. Dual-Mode Prompt
MODE="passive"
INTERACTIVE_FLAG="--passive"

if [[ -t 0 ]]; then
    echo -e "\n${C_ORANGE}Select Installation Mode:${C_RESET}"
    echo -e "  [1] Interactive (Conversational tool selection)"
    echo -e "  [2] Passive     (Automated sync & configuration)"
    read -p "Selection [1/2] (Default: 2): " -r mode_choice

    if [[ "$mode_choice" == "1" ]]; then
        MODE="interactive"
        INTERACTIVE_FLAG="--interactive"
    fi
else
    echo -e "\n\033[1;33m[*] Non-interactive environment detected. Defaulting to Passive Mode.\033[0m"
fi

if [[ "$MODE" == "passive" ]]; then
    echo -e "\n[*] Passive Mode: Initiating Psychic SCM Sync..."
    if command -v git &>/dev/null; then
        (cd "$SCRIPT_DIR" && git pull --rebase || echo -e "\033[1;33m[!] git pull failed, continuing anyway.\033[0m")
    fi
fi
echo ""

case "$OS_TYPE" in
    Linux)
        echo -e "[*] Detected Linux environment. Delegating to install_linux.sh..."
        bash "$SCRIPT_DIR/install_linux.sh" "$INTERACTIVE_FLAG" "$@"
        ;;
    Darwin)
        echo -e "[*] Detected macOS environment. Delegating to install_mac.sh..."
        bash "$SCRIPT_DIR/install_mac.sh" "$INTERACTIVE_FLAG" "$@"
        ;;
    *)
        if [[ -n "$WSL_DISTRO_NAME" ]]; then
            echo -e "[*] Detected WSL environment. Delegating to install_linux.sh..."
            bash "$SCRIPT_DIR/install_linux.sh" "$INTERACTIVE_FLAG" "$@"
        else
            echo -e "[!] Unsupported OS: $OS_TYPE. Attempting Windows PowerShell if applicable..."
            # Implementation for Windows handover if needed
        fi
        ;;
esac
