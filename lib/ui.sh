#!/usr/bin/env bash
# =============================================================================
# lib/ui.sh — Shared UX primitives for terminal-kniferoll installers.
# =============================================================================
#
# Sourced by:  install_mac.sh, install_linux_v2.sh
# Provides:    color palette, _log + LOG_FILE init, status markers
#              (ok/info/warn/skip/err/die), banner, quip, run_optional,
#              download_to_tmp, append_if_missing, ask_yes_no, is_installed,
#              print_summary
#
# Caller contract:
#   - Set FAILED_TOOLS_HINT="…"  (e.g. "brew install <pkg>" / "apt-get install
#     --fix-missing <pkg>") BEFORE calling print_summary. Defaults to a generic
#     message if unset.
#   - Declare FAILED_TOOLS=()  before any install attempt.
#   - Install your own ERR trap. This file does NOT register one — Mac wants a
#     plain warn-on-failure trap, Linux wants one with a benign-command
#     whitelist. Both define `on_error` themselves.
#
# Bash compat: 3.2+ (Mac stays on /bin/bash 3.2). No declare -g, no associative
# arrays, no `${var,,}` lower-casing.
# =============================================================================

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
warn()   { echo -e "${ORANGE}[!]${RESET} $*";                 _log "WARN"  "$*"; }
skip()   { echo -e "${DIM}[~] skip: $*${RESET}";              _log "SKIP"  "$*"; }
err()    { echo -e "${RED}[✗]${RESET} $*";                    _log "ERROR" "$*"; }
die()    { echo -e "${RED}[✗] FATAL: $*${RESET}" >&2;         _log "ERROR" "FATAL: $*"; exit 1; }
# Markers:  [✓] ok  ·  [→] info  ·  [!] warn  ·  [~] skip  ·  [✗] err/die
# Keep these distinct — [~] is RESERVED for the skip marker. A failure that
# the script handles soft (continues, but logs it) goes through warn() and
# uses [!]; a hard failure goes through err()/die() and uses [✗].
banner() { echo -e "\n${BOLD}${CYAN}[ $* ]${RESET}";          _log "INFO"  "=== $* ==="; }
quip()   { echo -e "${DIM}  ⋮ $*${RESET}"; }

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

# ── Mission summary ───────────────────────────────────────────────────────────
# Caller sets FAILED_TOOLS=() and (optionally) FAILED_TOOLS_HINT="…" before
# calling. The hint shows up under "MISSION COMPLETE WITH CASUALTIES" to point
# the user at the correct retry command for their platform.
print_summary() {
    banner "MISSION DEBRIEF"
    if [[ ${#FAILED_TOOLS[@]} -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}  ALL SYSTEMS NOMINAL — zero casualties.${RESET}"
    else
        echo -e "${YELLOW}${BOLD}  MISSION COMPLETE WITH CASUALTIES:${RESET}"
        for t in "${FAILED_TOOLS[@]}"; do echo -e "  ${RED}[✗]${RESET}  $t"; done
        quip "Try: ${FAILED_TOOLS_HINT:-retry the failed install command for your platform}"
    fi
    echo
    echo -e "${DIM}  [→] Log saved to: ${LOG_FILE}${RESET}"
    _log "INFO" "Install complete. Failures: ${#FAILED_TOOLS[@]}"
}
