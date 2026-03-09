#!/usr/bin/env bash
# =============================================================================
# terminal-kniferoll | Antigravity Installer (OS-Agnostic)
# =============================================================================

set -e

# --- Colors ---
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { echo -e "${GREEN}[✔] ${1}${RESET}"; }
info() { echo -e "${CYAN}[*] ${1}${RESET}"; }

INSTALL_DIR="$HOME/.local/opt/antigravity"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"

mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$DESKTOP_DIR"

# --- Determine Tarball Location ---
TARBALL="/home/ctrl/Downloads/Antigravity.tar.gz" # Default for this device

if [ ! -f "$TARBALL" ]; then
    info "Antigravity.tar.gz not found in Downloads. Please ensure it exists."
    # Future: add download logic here if needed
    exit 1
fi

# --- Security Verification ---
# Aligning with ADR-002 Zero-Knowledge/Hardened Node mandate
EXPECTED_HASH="d6d762866a6f43bbdb3ff9e1595d53aa2e896de12be7f35bf57cdaab62b5cd60"
info "Verifying binary integrity..."
ACTUAL_HASH=$(sha256sum "$TARBALL" | awk '{print $1}')

if [ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]; then
    echo -e "\033[0;31m[!] SECURITY ALERT: Checksum mismatch for $TARBALL\033[0m" >&2
    echo -e "\033[0;31m[!] Expected: $EXPECTED_HASH\033[0m" >&2
    echo -e "\033[0;31m[!] Actual:   $ACTUAL_HASH\033[0m" >&2
    echo -e "\033[0;31m[!] Halting installation to prevent potential supply-chain attack.\033[0m" >&2
    exit 1
fi
ok "Binary checksum verified."

# --- Extract ---
info "Extracting Antigravity to $INSTALL_DIR..."
tar -xzf "$TARBALL" -C "$INSTALL_DIR" --strip-components=1

# --- Symlink ---
info "Creating symlink in $BIN_DIR..."
ln -sf "$INSTALL_DIR/antigravity" "$BIN_DIR/antigravity"

# --- Desktop Entry ---
info "Creating desktop entry..."
# Attempt to find the best icon
ICON_PATH=$(find "$INSTALL_DIR" -name "antigravity.png" | head -n 1)

# If not found, use a fallback if possible, but the earlier find should have located it.
if [ -z "$ICON_PATH" ]; then
    ICON_PATH="$INSTALL_DIR/resources/app/out/vs/workbench/contrib/antigravityCustomAppIcon/browser/media/antigravity/antigravity.png"
fi

cat > "$DESKTOP_DIR/antigravity.desktop" <<EOD
[Desktop Entry]
Name=Antigravity
Comment=Google Antigravity Agentic IDE
Exec=$BIN_DIR/antigravity %F
Icon=$ICON_PATH
Type=Application
Categories=Development;IDE;
Terminal=false
StartupNotify=true
MimeType=text/plain;inode/directory;
EOD

ok "Antigravity installed successfully!"
