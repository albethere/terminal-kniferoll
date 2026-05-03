#!/usr/bin/env bash
# =============================================================================
# terminal-kniferoll | Linux Installer v2 (Shell + Projector + AI tools)
# =============================================================================
#
# EXPERIMENTAL — UX parity rewrite. The original install_linux.sh remains in
# the repo as a quick-revert reference; install.sh now routes Linux here.
#
# Created:    2026-05-02
# Branch:     feat/linux-ux-parity
# Parity:     Section banners, status markers, ASCII banner, MISSION DEBRIEF,
#             "knives sharp. out." closer, Zscaler manual prompt box, custom-
#             menu category granularity all match install_mac.sh line-for-line.
# Lib:        Sources lib/ui.sh (also consumed by install_mac.sh) for the
#             shared color palette + logging helpers. Touching either script's
#             status markers should be done once in lib/ui.sh.
# Bash:       4+ required. The re-exec preamble below provides a safety net
#             for minimal Pop!_OS / Ubuntu / container environments where the
#             default /bin/sh is dash but a usable bash exists elsewhere on
#             PATH. All real Debian/Ubuntu/Pop!_OS/Arch ship bash 5+.
# Carries forward from install_linux.sh (must not regress):
#   - DEBIAN_FRONTEND + DEBCONF_NONINTERACTIVE_SEEN + NEEDRESTART_*
#   - dpkg lock waiter (_apt_wait_lock, up to 5 min)
#   - Authoritative dpkg-query post-install verification (_apt_verify_installed)
#   - Brew install verification (_brew_install_verified)
#   - Brew update only when stale (>24h) + outdated count surfaced
#   - Robust OS detection via /etc/os-release ID_LIKE chain, WSL2 detect,
#     immutable distro (rpm-ostree / NixOS) refusal
#   - Loud sudo banner up front, fail-clean on non-interactive without sudo,
#     ERR-trap-suppressed background keepalive
#   - Inlined Zscaler RC sweep (subtly different from lib/rc_sweep.sh — keep)
#   - 1Password CLI signed apt repo install with dearmored keyring
#   - GitHub release .deb installer with SHA256 hard-fail (lsd, bat)
#   - Yazi binary install with arch detection
#   - Rust toolchain repair logic (memoized) for stale aarch64 toolchains
#   - lolcrab install via cargo (apt) or AUR helper (pacman)
#   - Atuin + mise eviction (cleanup_removed_tools)
#   - PEP 668 EXTERNALLY-MANAGED detection — skip pip upgrade
#   - All curl calls use --proto '=https' --tlsv1.2
#   - Post-flight verification (dpkg --audit, apt-get check, brew missing)
# =============================================================================

set -Eeuo pipefail

# ── Bash 4+ re-exec preamble (belt-and-suspenders) ────────────────────────────
# Pop!_OS / Ubuntu / Debian / Arch all ship bash 5+; this is insurance for
# the case where /bin/bash on a container or minimal install is too old.
if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    for _candidate in \
        /usr/local/bin/bash \
        /home/linuxbrew/.linuxbrew/bin/bash \
        /opt/homebrew/bin/bash \
        /usr/bin/bash \
        /bin/bash
    do
        if [ -x "$_candidate" ] && \
           "$_candidate" -c '[ "${BASH_VERSINFO[0]}" -ge 4 ]' 2>/dev/null; then
            exec "$_candidate" "$0" "$@"
        fi
    done
    echo "install_linux_v2.sh requires bash 4+; only older bash found." >&2
    exit 1
fi

# ── Non-interactive package manager defaults ──────────────────────────────────
# DEBIAN_FRONTEND alone is not enough: dpkg-reconfigure invoked from postinst
# scripts ignores it unless DEBCONF_NONINTERACTIVE_SEEN is also true. On Ubuntu
# 22.04+ needrestart will additionally prompt about service restarts unless
# explicitly muzzled. Set all three so any apt invocation is genuinely silent
# regardless of which package's postinst is misbehaving.
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export NEEDRESTART_MODE=a       # auto-apply service restarts instead of prompting
export NEEDRESTART_SUSPEND=1    # belt-and-suspenders: skip needrestart entirely

# ── Shared UX primitives ──────────────────────────────────────────────────────
# Color palette, log file init, ok/info/warn/skip/err/die, banner, quip,
# run_optional, download_to_tmp, append_if_missing, ask_yes_no, is_installed,
# print_summary. Identical implementation in install_mac.sh — change once,
# affect both OSes.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ui.sh
source "$SCRIPT_DIR/lib/ui.sh"

# ── Failed tools tracker + retry hint shown by print_summary ──────────────────
FAILED_TOOLS=()
FAILED_TOOLS_HINT="sudo apt-get update && sudo apt-get install --fix-missing <pkg>  (or pacman -S <pkg>)"

# ── ERR trap with benign-command whitelist ────────────────────────────────────
# Suppress non-zero exits we already handle structurally so the trap stays a
# useful diagnostic instead of crying wolf on every presence check. Mac uses
# a simpler trap because its tooling doesn't churn through dpkg presence
# checks the way apt does.
# shellcheck disable=SC2329  # invoked indirectly via ERR trap below
on_error() {
    local cmd="$2"
    case "$cmd" in
        # while-test patterns (sudo keepalive, polling)
        "sudo -n true"*)            return 0 ;;
        # presence checks — non-zero is the "not found" answer, not a failure
        "is_installed "*)           return 0 ;;
        "command -v "*)             return 0 ;;
        "dpkg -s "*|"dpkg-query "*|"dpkg -l "*) return 0 ;;
        "brew list "*)              return 0 ;;
        # grep -q used to scan for matches — non-match is normal
        grep*-q*|grep*-Eq*|grep*-Fq*) return 0 ;;
    esac
    warn "Unexpected failure at line $1: $cmd"
}
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

# ── Write ~/.config/terminal-kniferoll/zscaler-env.sh (Linux) ────────────────
# Installer writes this file fresh on every run with absolute Linux detection
# paths. No $OSTYPE branching at runtime. All env vars derived from $ZSC_PEM.
write_zscaler_env_file() {
    local env_dir="$HOME/.config/terminal-kniferoll"
    local env_file="$env_dir/zscaler-env.sh"
    mkdir -p "$env_dir"
    local _tmp; _tmp="$(mktemp "$env_dir/zscaler-env-XXXXXX.sh")"
    chmod 644 "$_tmp"
    {
        printf '# Auto-generated by terminal-kniferoll installer. DO NOT EDIT.\n'
        printf '# OS: Linux  Generated: %s\n\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        cat << 'ENVEOF'
ZSC_PEM=""
for _p in \
    "$HOME/.config/terminal-kniferoll/ca-bundle.pem" \
    "/etc/ssl/certs/zscaler.pem" \
    "/usr/local/share/ca-certificates/zscaler.pem" \
    "/usr/share/ca-certificates/zscaler.pem"
do
    if [ -s "$_p" ]; then ZSC_PEM="$_p"; break; fi
done
unset _p

if [ -n "$ZSC_PEM" ]; then
    export ZSC_PEM
    export CURL_CA_BUNDLE="$ZSC_PEM"
    export SSL_CERT_FILE="$ZSC_PEM"
    export REQUESTS_CA_BUNDLE="$ZSC_PEM"
    export NODE_EXTRA_CA_CERTS="$ZSC_PEM"
    export GIT_SSL_CAINFO="$ZSC_PEM"
    export AWS_CA_BUNDLE="$ZSC_PEM"
    export PIP_CERT="$ZSC_PEM"
fi
ENVEOF
    } > "$_tmp"
    mv -f "$_tmp" "$env_file"
    ok "~/.config/terminal-kniferoll/zscaler-env.sh written (Linux)"
}

# ── Helper: detect managed-device markers (Linux variant) ────────────────────
# Mac uses `profiles status -type enrollment`; Linux has no MDM API. Best we
# can do is look for the corp-cert breadcrumbs left by Zscaler / IT-managed
# images. Used to print a quip warning the user that some installs may need
# admin approval — same UX role as Mac's is_restricted_device().
is_restricted_device() {
    [[ -f /usr/local/share/ca-certificates/zscaler.pem ]] || \
    [[ -f /usr/local/share/ca-certificates/zscaler.crt ]] || \
    [[ -f /etc/ssl/certs/zscaler.pem ]] || \
    [[ -d /opt/zscaler ]] || \
    command -v zscaler-config &>/dev/null
}

# ── Zscaler splash-page helpers ───────────────────────────────────────────────
#
# Environment variables (all optional):
#   TERMINAL_KNIFEROLL_ZSCALER_AUTO_ACCEPT=1   (default) Try POST auto-accept.
#   TERMINAL_KNIFEROLL_ZSCALER_AUTO_ACCEPT=0   Skip auto-accept; go straight to manual.
#   TERMINAL_KNIFEROLL_ZSCALER_REASON="..."    Override form reason field value.

_splash_log_file="$HOME/.config/terminal-kniferoll/zscaler-splash.log"

_splash_log() {
    mkdir -p "$(dirname "$_splash_log_file")"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$_splash_log_file"
}

# URL-encode a string using python3 (available on modern Linux distros).
_url_encode() { python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))" "$1" 2>/dev/null || printf '%s' "$1"; }

# zscaler_attempt_auto_accept HTML SPLASH_URL COOKIE_JAR
# Parses a Zscaler acknowledgment HTML form, posts the acceptance, returns 0 on success.
zscaler_attempt_auto_accept() {
    local html="$1" splash_url="$2" cookie_jar="$3"

    _splash_log "--- auto-accept attempt: $splash_url"

    # Extract <form action="..."> (first form)
    local form_action
    form_action=$(printf '%s' "$html" | grep -oiE '<form[^>]+>' | head -1 | \
        grep -oiE 'action="[^"]+"' | sed 's/action="//;s/"//')
    if [[ -z "$form_action" ]]; then
        # single-quoted variant
        form_action=$(printf '%s' "$html" | grep -oiE "<form[^>]+>" | head -1 | \
            grep -oiE "action='[^']+'" | sed "s/action='//;s/'//")
    fi
    if [[ -z "$form_action" ]]; then
        _splash_log "no form action found — cannot auto-accept"
        return 1
    fi

    # Resolve relative action URL
    if [[ "$form_action" != http* ]]; then
        local _base; _base="$(printf '%s' "$splash_url" | grep -oE 'https?://[^/]+')"
        [[ "$form_action" == /* ]] && form_action="${_base}${form_action}" \
                                   || form_action="${_base}/${form_action}"
    fi

    # Collect hidden fields  →  name=value& pairs
    local post_data=""
    while IFS= read -r _field; do
        local _n _v
        _n=$(printf '%s' "$_field" | grep -oiE 'name="[^"]+"'  | head -1 | sed 's/name="//;s/"//')
        _v=$(printf '%s' "$_field" | grep -oiE 'value="[^"]*"' | head -1 | sed 's/value="//;s/"//')
        [[ -z "$_n" ]] && continue
        post_data+="$(_url_encode "$_n")=$(_url_encode "$_v")&"
    done < <(printf '%s' "$html" | grep -oiE '<input[^>]+type="hidden"[^>]*>' | head -30)

    # Explicit accept/acknowledge/continue button fields
    local _accept_name _accept_val
    _accept_name=$(printf '%s' "$html" | grep -oiE '<input[^>]+(name="(accept|acknowledge|agree|continue|proceed)")[^>]*>' | head -1 | \
        grep -oiE 'name="[^"]+"' | sed 's/name="//;s/"//')
    if [[ -n "$_accept_name" ]]; then
        _accept_val=$(printf '%s' "$html" | grep -oiE 'name="'"$_accept_name"'"[^>]*>' | head -1 | \
            grep -oiE 'value="[^"]*"' | sed 's/value="//;s/"//')
        post_data+="$(_url_encode "$_accept_name")=$(_url_encode "${_accept_val:-Agree}")&"
    else
        # Generic fallback fields that common Zscaler forms use
        post_data+="accept=Agree&agree=true&acknowledge=1&"
    fi

    # Reason/justification field
    local _reason="${TERMINAL_KNIFEROLL_ZSCALER_REASON:-Developer environment setup}"
    if printf '%s' "$html" | grep -qi 'name="reason"'; then
        post_data+="reason=$(_url_encode "$_reason")&"
    fi
    post_data="${post_data%&}"  # strip trailing &

    _splash_log "form_action: $form_action"
    _splash_log "post_fields: $post_data"

    # POST the form, replay cookies
    local curl_opts=(--proto '=https' --tlsv1.2 --max-time 20 -fsSL
                     -X POST --data "$post_data"
                     -H "Content-Type: application/x-www-form-urlencoded")
    [[ -n "${CURL_CA_BUNDLE:-}" && -f "${CURL_CA_BUNDLE}" ]] && curl_opts+=(--cacert "$CURL_CA_BUNDLE")
    [[ -f "$cookie_jar" ]] && curl_opts+=(-b "$cookie_jar" -c "$cookie_jar")

    local post_resp post_rc=0
    post_resp=$(curl "${curl_opts[@]}" "$form_action" 2>&1) || post_rc=$?

    if [[ "$post_rc" -ne 0 ]]; then
        _splash_log "POST failed (curl exit $post_rc)"
        return 1
    fi

    # Success: response is NOT an HTML splash page
    if ! printf '%s' "$post_resp" | grep -qi "<html\|<!DOCTYPE\|zscaler\|zpa_block\|access denied"; then
        _splash_log "auto-accept: SUCCESS"
        return 0
    fi

    _splash_log "auto-accept: POST returned another HTML page — failed"
    return 1
}

# zscaler_manual_prompt SPLASH_URL
# Shows a user-friendly box, opens the URL in the default browser, waits for Enter.
zscaler_manual_prompt() {
    local splash_url="$1"
    echo
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║  Zscaler requires acknowledgment before this traffic is allowed  ║${RESET}"
    echo -e "${BOLD}${CYAN}╠══════════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${BOLD}${CYAN}║${RESET}                                                                  ${BOLD}${CYAN}║${RESET}"
    echo -e "${BOLD}${CYAN}║${RESET}  Open this URL in your browser and accept:                       ${BOLD}${CYAN}║${RESET}"
    echo -e "${BOLD}${CYAN}║${RESET}  ${YELLOW}${splash_url}${RESET}"
    echo -e "${BOLD}${CYAN}║${RESET}                                                                  ${BOLD}${CYAN}║${RESET}"
    echo -e "${BOLD}${CYAN}║${RESET}  Reason to give (if prompted): \"Developer environment setup\"    ${BOLD}${CYAN}║${RESET}"
    echo -e "${BOLD}${CYAN}║${RESET}                                                                  ${BOLD}${CYAN}║${RESET}"
    echo -e "${BOLD}${CYAN}║${RESET}  After accepting, return to this terminal and press ENTER        ${BOLD}${CYAN}║${RESET}"
    echo -e "${BOLD}${CYAN}║${RESET}  to continue.                                                    ${BOLD}${CYAN}║${RESET}"
    echo -e "${BOLD}${CYAN}║${RESET}                                                                  ${BOLD}${CYAN}║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════╝${RESET}"
    echo
    # Auto-open in default browser on Linux (only in interactive TTY sessions)
    if [[ -t 1 ]]; then
        xdg-open "$splash_url" 2>/dev/null || true
        info "Opened $splash_url in your default browser"
    fi
    echo -en "${CYAN}[→] Press ENTER after accepting in your browser... ${RESET}"
    read -r _
}

# ── TLS preflight check ───────────────────────────────────────────────────────
# Curls a well-known HTTPS endpoint and checks for:
#   - curl exit 60: SSL cert verification failure (Zscaler intercepting, untrusted)
#   - HTML response body: Zscaler/corporate acknowledgment splash page → try auto-accept
# Returns:
#   0  TLS clean — proceed
#   1  SSL cert error or unrecoverable block — caller should invoke setup_zscaler_trust
#   2  Splash page handled (auto-accepted or user manually accepted) — caller should re-run
preflight_zscaler_check() {
    local test_url="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
    local cookie_jar; cookie_jar="$(mktemp /tmp/zscaler-cookies-XXXXXX.txt)"
    local curl_opts=(--proto '=https' --tlsv1.2 --max-time 15 -fsSL
                     -c "$cookie_jar" -w '\n__EFFECTIVE_URL__%{url_effective}')
    [[ -n "${CURL_CA_BUNDLE:-}" && -f "${CURL_CA_BUNDLE}" ]] && \
        curl_opts+=(--cacert "$CURL_CA_BUNDLE")

    local raw exit_code=0
    raw=$(curl "${curl_opts[@]}" "$test_url" 2>&1) || exit_code=$?

    # Split write_out sentinel from body
    local effective_url response
    effective_url=$(printf '%s' "$raw" | grep '__EFFECTIVE_URL__' | sed 's/.*__EFFECTIVE_URL__//')
    response=$(printf '%s' "$raw" | grep -v '__EFFECTIVE_URL__')
    local splash_url="${effective_url:-$test_url}"

    # curl exit 60 = SSL certificate problem — Zscaler not yet trusted
    if [[ "$exit_code" -eq 60 ]]; then
        rm -f "$cookie_jar"
        warn "preflight: TLS certificate error (SSL verification failed)"
        warn "preflight: Zscaler is intercepting HTTPS and the cert is not trusted yet"
        return 1
    fi

    # Any other curl failure (network down, timeout, DNS)
    if [[ "$exit_code" -ne 0 ]]; then
        rm -f "$cookie_jar"
        warn "preflight: curl failed (exit $exit_code) — network may be unavailable"
        return 1
    fi

    # HTML response = Zscaler/corporate acknowledgment splash page
    if printf '%s' "$response" | grep -qi "<html\|<title\|<!DOCTYPE"; then
        warn "preflight: received HTML instead of a shell script"
        warn "preflight: possible Zscaler acknowledgment page at: $splash_url"

        if [[ "${TERMINAL_KNIFEROLL_ZSCALER_AUTO_ACCEPT:-1}" != "0" ]]; then
            info "preflight: attempting automatic Zscaler form acceptance..."
            if zscaler_attempt_auto_accept "$response" "$splash_url" "$cookie_jar"; then
                ok "preflight: auto-accept posted — re-validating TLS..."
                rm -f "$cookie_jar"
                return 2  # signal caller to re-run preflight
            fi
            warn "preflight: auto-accept failed — falling back to manual prompt"
        fi

        rm -f "$cookie_jar"
        zscaler_manual_prompt "$splash_url"
        return 2  # user accepted in browser, caller re-runs preflight
    fi

    rm -f "$cookie_jar"

    # Zscaler block-page body marker (no HTML wrapper)
    if printf '%s' "$response" | grep -qi "zscaler\|zpa_block\|access denied by zscaler"; then
        warn "preflight: Zscaler block-page marker in response body"
        return 1
    fi

    ok "preflight: TLS validated — raw.githubusercontent.com reachable, no interception detected"
    return 0
}

# ── Export all cert env vars for the current session ─────────────────────────
_zscaler_export_env() {
    local bundle="$1"
    export CURL_CA_BUNDLE="$bundle"
    export SSL_CERT_FILE="$bundle"
    export GIT_SSL_CAINFO="$bundle"
    export NODE_EXTRA_CA_CERTS="$bundle"
    export REQUESTS_CA_BUNDLE="$bundle"
    export AWS_CA_BUNDLE="$bundle"
    export PIP_CERT="$bundle"
    export ZSC_PEM="$bundle"
}

# ── Zscaler managed-device cert trust (Linux) ────────────────────────────────
# Call AFTER preflight_zscaler_check returns non-zero.
# Builds a combined CA bundle (system roots + Zscaler) and exports all
# cert env vars so every subsequent curl/git/npm/pip/aws in this session
# inherits them.
#
# Detection order (Linux-only — no macOS paths in this script):
#   1. Previously built combined bundle  (fast path on re-run)
#   2. Known Linux Zscaler cert paths
#
# Flags:
#   --required   Die (exit non-zero) if no cert is found instead of returning 0.
setup_zscaler_trust() {
    local required=false
    [[ "${1:-}" == "--required" ]] && required=true

    local zsc_pem=""
    local bundle_dir="$HOME/.config/terminal-kniferoll"
    local combined_bundle="$bundle_dir/ca-bundle.pem"
    mkdir -p "$bundle_dir"

    # 1. Fast path — prior installer run already built the bundle
    if [[ -s "$combined_bundle" ]]; then
        _zscaler_export_env "$combined_bundle"
        ok "Zscaler trust: using cached CA bundle"
        return 0
    fi

    # 2. Known Linux Zscaler cert paths
    local _candidate
    for _candidate in \
        "/usr/local/share/ca-certificates/zscaler.pem" \
        "/usr/local/share/ca-certificates/zscaler.crt" \
        "/etc/ssl/certs/zscaler.pem" \
        "/usr/share/ca-certificates/zscaler.pem"
    do
        if [[ -s "$_candidate" ]]; then
            zsc_pem="$_candidate"
            info "Zscaler cert found: $zsc_pem"
            break
        fi
    done

    if [[ -z "$zsc_pem" ]]; then
        if [[ "$required" == "true" ]]; then
            err "Zscaler TLS interception detected but no Zscaler root cert was found."
            err ""
            err "Remediation — place the Zscaler root cert at:"
            err "  /usr/local/share/ca-certificates/zscaler.pem"
            err "Then run: sudo update-ca-certificates"
            err "Then re-run: ./install_linux_v2.sh"
            die "Cannot continue without Zscaler root cert on a managed device"
        fi
        skip "No Zscaler cert detected — assuming standard TLS (non-managed device)"
        return 0
    fi

    # Build combined bundle: system roots + Zscaler cert.
    info "Building combined CA bundle for managed-device trust..."
    local _tmp_bundle; _tmp_bundle="$(mktemp "$bundle_dir/ca-bundle-XXXXXX.pem")"
    chmod 644 "$_tmp_bundle"
    {
        if [[ -f /etc/ssl/certs/ca-certificates.crt ]]; then
            cat /etc/ssl/certs/ca-certificates.crt
        elif [[ -f /etc/pki/tls/certs/ca-bundle.crt ]]; then
            cat /etc/pki/tls/certs/ca-bundle.crt
        fi
        cat "$zsc_pem"
    } > "$_tmp_bundle"
    mv -f "$_tmp_bundle" "$combined_bundle"

    _zscaler_export_env "$combined_bundle"
    ok "Zscaler trust configured — $(wc -l < "$combined_bundle") cert lines in bundle"
    quip "curl, git, npm, yarn, pip, aws cli will all trust this bundle in this session"
}

# ── Helper: wait for dpkg/apt lock to clear ──────────────────────────────────
# unattended-upgrades on Pop!_OS / Ubuntu can hold the dpkg lock for 10+ min
# after first boot. Surface that we're waiting (apt-get's own
# DPkg::Lock::Timeout is silent) so the user can tell waiting-on-lock from
# truly-hung. Returns 1 if the lock is still held after `timeout` seconds.
_apt_wait_lock() {
    local timeout="${1:-300}" elapsed=0
    while sudo fuser /var/lib/dpkg/lock-frontend &>/dev/null \
       || sudo fuser /var/lib/dpkg/lock         &>/dev/null \
       || sudo fuser /var/lib/apt/lists/lock    &>/dev/null; do
        if (( elapsed == 0 )); then
            warn "apt/dpkg lock held (likely unattended-upgrades) — waiting up to ${timeout}s..."
        fi
        if (( elapsed >= timeout )); then
            err "apt lock still held after ${timeout}s — try: sudo systemctl stop unattended-upgrades"
            return 1
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 0
}

# ── Helper: verify packages reached the `ii` (installed) state ───────────────
# Authoritative post-install check. apt-get's exit code is informational
# because the grep-pipeline pattern can mis-classify (clean install with
# nothing-to-do exits 0 with no "Setting up" output → grep returns 1).
_apt_verify_installed() {
    local missing=() p
    for p in "$@"; do
        if ! dpkg-query -W -f='${db:Status-Abbrev}' "$p" 2>/dev/null \
                | grep -q '^ii'; then
            missing+=("$p")
        fi
    done
    if (( ${#missing[@]} )); then
        err "post-install verification: not in 'ii' state → ${missing[*]}"
        FAILED_TOOLS+=("${missing[@]}")
        return 1
    fi
    return 0
}

# ── Helper: apt single-package install (skip if present, verify after) ───────
apt_install() {
    local check_bin="$1" pkg="$2" desc="${3:-$2}"
    if is_installed "$check_bin" \
       || dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null | grep -q '^ii'; then
        skip "$desc already installed"; return 0
    fi
    _apt_wait_lock 300 || { FAILED_TOOLS+=("$pkg"); return 1; }
    info "Installing $desc..."
    sudo apt-get -o DPkg::Lock::Timeout=300 install -y --fix-missing -q "$pkg" \
        >>"$LOG_FILE" 2>&1 || true
    if _apt_verify_installed "$pkg"; then
        ok "$desc installed"
    else
        warn "$desc install failed — see $LOG_FILE"
    fi
}

# ── Helper: apt batch install ────────────────────────────────────────────────
apt_batch() {
    local section="$1"; shift
    local to_install=()
    banner "$section"
    for entry in "$@"; do
        local bin="${entry%%:*}" pkg="${entry##*:}"
        if is_installed "$bin" \
           || dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null | grep -q '^ii'; then
            skip "$pkg"
        else
            to_install+=("$pkg")
        fi
    done
    if [[ ${#to_install[@]} -eq 0 ]]; then
        quip "Nothing new here — pantry stocked."; return 0
    fi
    _apt_wait_lock 300 || { FAILED_TOOLS+=("${to_install[@]}"); return 1; }
    info "Installing: ${to_install[*]}"
    local rc=0
    if [[ "${ST_ENABLED:-false}" == "true" && -n "${ST_VERBOSE_LOG:-}" ]]; then
        sudo apt-get -o DPkg::Lock::Timeout=300 install -y --fix-missing \
            "${to_install[@]}" 2>&1 | tee -a "$ST_VERBOSE_LOG" >>"$LOG_FILE" \
            || rc=$?
    else
        sudo apt-get -o DPkg::Lock::Timeout=300 install -y --fix-missing -q \
            "${to_install[@]}" >>"$LOG_FILE" 2>&1 || rc=$?
    fi
    if (( rc != 0 )); then
        warn "$section — apt-get exited ${rc}; verifying which packages landed..."
    fi
    # dpkg-query is authoritative — apt's exit code is informational only.
    if _apt_verify_installed "${to_install[@]}"; then
        ok "$section — all ${#to_install[@]} package(s) verified ii"
    else
        warn "$section — partial install (see FAILED_TOOLS in summary)"
    fi
}

# ── Helper: nmap install with debconf pre-seeding (tk-021) ───────────────────
# DEBIAN_FRONTEND=noninteractive (set globally) handles the "is this a hang or
# not" question. The preseed below is OPINIONATED: we explicitly set
# wireshark-common/install-setuid=false rather than accept the package default,
# so non-root users on this machine cannot capture raw packets via dumpcap.
# This is a security choice, not a hang-prevention.
_nmap_safe_install() {
    if is_installed "nmap" \
       || dpkg-query -W -f='${db:Status-Abbrev}' nmap 2>/dev/null | grep -q '^ii'; then
        skip "nmap already installed"; return 0
    fi
    info "Pre-seeding wireshark-common/install-setuid=false (security choice)..."
    echo 'wireshark-common wireshark-common/install-setuid boolean false' | \
        sudo debconf-set-selections 2>/dev/null || true
    _apt_wait_lock 300 || { FAILED_TOOLS+=("nmap"); return 1; }
    info "Installing nmap (timeout 120s, no recommended extras)..."
    timeout 120 sudo apt-get -o DPkg::Lock::Timeout=300 install -y \
        --fix-missing -q --no-install-recommends nmap >>"$LOG_FILE" 2>&1 || true
    _apt_verify_installed nmap && ok "nmap installed"
}

# ── Helper: cargo install (skip if present) ──────────────────────────────────
cargo_install() {
    local check_bin="$1" crate="$2" name="${3:-$2}"
    if is_installed "$check_bin"; then skip "$name already installed"; return 0; fi
    if ! is_installed "cargo"; then
        warn "cargo not found — skipping $name"; FAILED_TOOLS+=("${name}(cargo)"); return 0
    fi
    if [[ "${_RUST_TOOLCHAIN_BROKEN:-0}" == "1" ]]; then
        warn "Rust toolchain unusable — skipping $name"; FAILED_TOOLS+=("${name}(rust-broken)"); return 0
    fi
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env" || true
    info "Compiling $name via cargo..."
    read -ra _crates <<< "$crate"
    if cargo install "${_crates[@]}"; then ok "$name compiled and ready"
    else warn "cargo install failed for $name"; FAILED_TOOLS+=("${name}(cargo)"); fi
}

# ── Helper: install lolcrab (rainbow CLI) — cascade ──────────────────────────
# Cascade order:
#   1. AUR (lolcrab-bin → lolcrab) on Arch when an AUR helper is available.
#   2. cargo install lolcrab (crates.io, hash-verified). Linuxbrew has no
#      lolcrab formula; apt does not package it.
#
# The lolcat → lolcrab backwards-compat alias is added by the rainbow-block
# sweep at the end of this script. Failure is non-fatal — the fastfetch
# greeter falls through to plain (non-rainbow) fastfetch.
install_lolcrab() {
    if is_installed "lolcrab"; then skip "lolcrab already installed"; return 0; fi

    # Path 1: AUR (Arch only)
    if [[ "$PKG_MGR" == "pacman" ]] && [[ -n "${AUR_HELPER:-}" ]] && \
       command -v "$AUR_HELPER" &>/dev/null; then
        local _pkg
        for _pkg in lolcrab-bin lolcrab; do
            if "$AUR_HELPER" -Si "$_pkg" &>/dev/null; then
                run_optional "Installing $_pkg ($AUR_HELPER)" \
                    "$AUR_HELPER" -S --noconfirm "$_pkg"
                is_installed "lolcrab" && return 0
                break
            fi
        done
    fi

    # Path 2: cargo (works on apt + pacman; crates.io hash-verified)
    ensure_rust_toolchain
    cargo_install "lolcrab" "lolcrab" "lolcrab (rainbow output)"
    is_installed "lolcrab" && return 0

    warn "lolcrab install failed — fastfetch greeter will fall through to plain output"
    FAILED_TOOLS+=("lolcrab")
    return 0
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

# ── Helper: install yazi from GitHub binary release ──────────────────────────
install_yazi_binary() {
    if is_installed "yazi"; then skip "yazi already installed"; return 0; fi
    local arch triple
    arch="$(uname -m)"
    case "$arch" in
        x86_64)  triple="x86_64-unknown-linux-gnu" ;;
        aarch64) triple="aarch64-unknown-linux-gnu" ;;
        *)       warn "yazi: unsupported arch $arch — skipping"; return 0 ;;
    esac
    info "Installing yazi from GitHub binary release..."
    local curl_args=(-fsSL --proto '=https' --tlsv1.2)
    [[ -n "${GITHUB_TOKEN:-}" && "${GITHUB_TOKEN}" =~ ^[A-Za-z0-9_-]+$ ]] && \
        curl_args+=(-H "Authorization: token ${GITHUB_TOKEN}")
    local url
    url=$(curl "${curl_args[@]}" "https://api.github.com/repos/sxyazi/yazi/releases/latest" \
        | grep browser_download_url \
        | grep "${triple}\.zip" \
        | head -1 | cut -d'"' -f4 || true)
    if [[ -z "$url" ]]; then
        warn "yazi: no binary release found for $triple — skipping"
        FAILED_TOOLS+=("yazi(github)"); return 0
    fi
    local tmp_zip tmp_dir
    tmp_zip="$(mktemp /tmp/yazi-XXXXXX.zip)"
    tmp_dir="$(mktemp -d /tmp/yazi-XXXXXX)"
    if curl "${curl_args[@]}" -o "$tmp_zip" "$url" && unzip -qo "$tmp_zip" -d "$tmp_dir"; then
        local bin_dir="$HOME/.local/bin"
        mkdir -p "$bin_dir"
        # Release zip contains a subdirectory; find the binaries
        find "$tmp_dir" -maxdepth 2 -type f \( -name "yazi" -o -name "ya" \) \
            -exec install -m 0755 {} "$bin_dir/" \;
        ok "yazi installed to $bin_dir"
    else
        warn "yazi: download or unzip failed — skipping"
        FAILED_TOOLS+=("yazi(github)")
    fi
    rm -rf "$tmp_zip" "$tmp_dir"
}

# ── Feature: ensure Rust toolchain ───────────────────────────────────────────
# On aarch64 (Raspberry Pi 4) we have seen `cargo` already on PATH (from a
# prior partial rustup or apt) while ~/.rustup has a default-toolchain pointer
# but no manifest on disk — every `cargo install` then fails with
# "Missing manifest in toolchain 'stable-aarch64-unknown-linux-gnu'".
# `rustup default stable` alone is not enough to repair this: it sets the
# pointer and *should* trigger a download, but if the download fails or the
# toolchain dir already exists in a partial state, rustup leaves it as-is.
# `rustup toolchain install stable` is the canonical idempotent operation
# that re-fetches the manifest and binaries.
#
# Caveat: on Debian/Ubuntu, `apt install rustup` ships a *stub* at
# /usr/bin/rustup that prints "rustup is not installed" and exits 1 until
# `rustup-init` has run.  We detect that and treat the stub as "no rustup
# present" so we bootstrap real rustup instead of trying to drive the stub.
_rustup_works() {
    is_installed "rustup" || return 1
    # Real rustup: `rustup --version` exits 0 and prints "rustup x.y.z (...)".
    # Debian stub: exits 1 and prints "rustup is not installed at ...".
    rustup --version &>/dev/null
}
ensure_rust_toolchain() {
    # Memoize: this function may be invoked from both DO_DEV_TOOLS (nushell)
    # and DO_PROJECTOR (weathr/trippy). Avoid the duplicate manifest fetch.
    [[ "${_RUST_TOOLCHAIN_CHECKED:-0}" == "1" ]] && return 0

    # Track whether we actually attempted rustup-driven repair this run.
    # The final rustc -vV sanity check should only flag the toolchain as
    # broken if we tried to repair it — otherwise an apt-only rustc/cargo
    # box that was working fine would be falsely marked broken.
    local _attempted_repair=0

    # 1. Bootstrap rustup if neither cargo nor a real rustup is present.
    #    (apt's rustup stub does NOT count as rustup here.)
    if ! is_installed "cargo" && ! _rustup_works; then
        local rustup_script
        rustup_script="$(download_to_tmp "https://sh.rustup.rs" "rustup-init-XXXXXX.sh")"
        run_optional "Installing Rust via rustup" \
            bash "$rustup_script" -y --quiet \
                --default-toolchain stable --profile minimal --no-modify-path
        rm -f "$rustup_script"
        [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env" || true
        _attempted_repair=1
    fi
    # 2. If a real rustup is present, force-install the stable toolchain
    #    manifest.  Skip when only the apt stub is on PATH — driving the
    #    stub would always fail and would falsely poison the broken flag.
    if _rustup_works; then
        run_optional "Ensuring stable toolchain manifest (rustup toolchain install stable)" \
            rustup toolchain install stable --profile minimal --no-self-update
        run_optional "Setting rustup default to stable" \
            rustup default stable
        [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env" || true
        _attempted_repair=1
    fi
    # 3. Final sanity check.  Only set the broken flag if we actually tried
    #    to repair via rustup; an apt-only rustc/cargo box that never went
    #    through rustup is none of our business.  Local (no export) — only
    #    this script reads it; subprocesses don't need to know.
    if (( _attempted_repair )) && is_installed "cargo" && ! rustc -vV &>/dev/null; then
        warn "Rust toolchain is broken (rustc -vV failed) — cargo installs will be skipped"
        warn "  remediation: run 'rustup toolchain install stable' manually, then re-run installer"
        _RUST_TOOLCHAIN_BROKEN=1
    fi
    _RUST_TOOLCHAIN_CHECKED=1
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
        gpg --dearmor < "$key_asc" > "$key_gpg"
        $SUDO install -m 0644 "$key_gpg" /usr/share/keyrings/1password-archive-keyring.gpg
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

# ── Helper: brew update only if cache is stale (>24h) ────────────────────────
# `brew update` on a stale install can take 5+ minutes with no output. Skip
# when the homebrew-core tap was fetched within the last 24h, otherwise stream
# brew's own progress lines so the user can tell running from hung.
_brew_update_if_stale() {
    local repo
    repo="$(brew --repository 2>/dev/null)" || return 0
    local fetch_head="$repo/.git/FETCH_HEAD"
    local age_hours=999
    if [[ -f "$fetch_head" ]]; then
        local mtime now
        # `stat -c` is GNU; macOS uses `stat -f` but this is the Linux installer.
        mtime="$(stat -c %Y "$fetch_head" 2>/dev/null || echo 0)"
        now="$(date +%s)"
        age_hours=$(( (now - mtime) / 3600 ))
    fi
    if (( age_hours < 24 )); then
        skip "Homebrew update — tap fetched ${age_hours}h ago (< 24h, skipping)"
        return 0
    fi
    info "Updating Homebrew (last fetch ${age_hours}h ago — can take several minutes)..."
    if brew update 2>&1 | tee -a "$LOG_FILE"; then
        ok "Homebrew updated"
    else
        warn "brew update returned non-zero — continuing"
    fi
}

# ── Helper: surface brew outdated count without auto-upgrading ───────────────
_brew_outdated_report() {
    local count
    count="$(brew outdated --quiet 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]; then
        warn "Homebrew: ${count} formula(e) outdated — run \`brew upgrade\` if you want them updated"
        warn "         (this installer does not auto-upgrade existing formulae)"
    fi
}

# ── Helper: install a list of bin:formula pairs via brew ─────────────────────
# Splits out from apt_batch for tools that are NOT reliably in Debian/Ubuntu
# apt repos (cbonsai isn't in apt at all; starship/zoxide are only in 22.04+
# universe). Also fails loud if brew isn't on PATH instead of silently
# poisoning the install run — `apt-get install A B C` is atomic, so one
# missing package cascades and breaks every other tool in the batch.
brew_extras_install() {
    local section="$1"; shift
    banner "$section"
    if ! command -v brew &>/dev/null; then
        # install_homebrew_and_gemini eval'd shellenv earlier — if brew still
        # isn't reachable, surface the install path that should have worked
        # rather than failing silently.
        err "brew not in PATH — these tools cannot be installed: $*"
        err "expected brew at /home/linuxbrew/.linuxbrew/bin/brew or \$HOME/.linuxbrew/bin/brew"
        local entry
        for entry in "$@"; do
            FAILED_TOOLS+=("${entry%%:*}(no-brew)")
        done
        return 1
    fi
    local entry bin formula
    for entry in "$@"; do
        bin="${entry%%:*}"; formula="${entry##*:}"
        if is_installed "$bin"; then
            skip "$bin already installed"
        else
            _brew_install_verified "$formula" || true
        fi
    done
}

# ── Helper: brew install with post-install verification ──────────────────────
# `brew install` can return 0 on partial failure (network glitches mid-fetch,
# postinstall script failures, etc.). Verify the formula actually appears in
# `brew list` before declaring success.
_brew_install_verified() {
    local formula="$1"
    if brew list --formula -1 2>/dev/null | grep -qx "$formula"; then
        skip "$formula already installed (brew)"
        return 0
    fi
    info "Installing $formula via Homebrew..."
    if brew install "$formula" >>"$LOG_FILE" 2>&1; then
        if brew list --formula -1 2>/dev/null | grep -qx "$formula"; then
            ok "$formula installed (verified in brew list)"
            return 0
        fi
        warn "$formula: brew exited 0 but formula not in \`brew list\`"
    else
        warn "$formula: brew install failed — see $LOG_FILE"
    fi
    FAILED_TOOLS+=("${formula}(brew)")
    return 1
}

# ── Feature: Homebrew bootstrap ──────────────────────────────────────────────
# Installs Linuxbrew if not present, evals shellenv into the current run, and
# upserts the marker block into rc files. AI Tools (Gemini) is now its own
# section; this function is "make brew available" only.
ensure_homebrew() {
    local brew_bin=""
    if is_installed "brew"; then
        brew_bin="$(command -v brew)"; skip "Homebrew already installed"
    else
        if [[ "$PKG_MGR" == "apt" ]]; then
            if command -v gcc &>/dev/null || dpkg -s build-essential &>/dev/null 2>&1; then
                skip "gcc / build-essential already installed"
            else
                run_optional "Installing Homebrew build prerequisites" \
                    bash -c "$SUDO apt-get install -y -qq build-essential procps curl file git"
            fi
        fi
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
        # Upsert brew shellenv block into rc files using the marker-based sweep.
        # Replaces older bare eval "$(brew shellenv)" lines from previous installs.
        sweep_brew_shellenv_files "" _brew_shellenv_block_linux
        _brew_update_if_stale
        is_installed "gcc" || _brew_install_verified gcc
        _brew_outdated_report
        return 0
    fi
    warn "Homebrew unavailable — skipping Homebrew-based installs"
    return 1
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
    if ! [ -t 0 ]; then
        # Non-interactive: must be pre-authenticated or running as root
        if ! sudo -n true 2>/dev/null; then
            die "non-interactive run but sudo not pre-authenticated; run \`sudo -v\` first or rerun with a TTY"
        fi
        ok "sudo — pre-authenticated (non-interactive)"
    else
        banner "SUDO REQUIRED"
        echo -e "${YELLOW}${BOLD}  [!] This installer needs sudo. Enter your password when prompted.${RESET}"
        echo -e "${DIM}      (credential cached for the rest of the run)${RESET}"
        if ! sudo -v; then die "sudo authentication failed"; fi
        ok "sudo — cleared"
    fi
    # set -E (errtrace, inherited from `set -Eeuo pipefail` at top) propagates
    # the ERR trap into this backgrounded subshell. Clear it explicitly so
    # signal-interrupted `sleep` calls during dpkg postinst don't trip a
    # spurious "Unexpected failure at line N: sleep 50" warning.
    (
        trap - ERR
        set +Ee
        while sudo -n true 2>/dev/null; do
            sleep 50 || break
            kill -0 "$$" 2>/dev/null || break
        done
    ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "${SUDO_KEEPALIVE_PID:-}" 2>/dev/null; true' EXIT
}

# print_summary — provided by lib/ui.sh, parameterised via FAILED_TOOLS_HINT.

# ── Help text ─────────────────────────────────────────────────────────────────
show_help() {
    echo "Usage: install_linux_v2.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --shell          Install shell environment only (skip projector + tools)"
    echo "  --projector      Install projector tools only (skip shell + tools)"
    echo "  --interactive    Force interactive menu"
    echo "  --help           Show this help message and exit"
    echo ""
    echo "Default: shows install menu (TTY) or full install (non-TTY)."
}

# ── Install menus ─────────────────────────────────────────────────────────────
# Mac-aligned 8-category granularity. No DO_DESKTOP — Linux has no cask
# concept and iTerm2/Keka aren't packaged for apt. AI Tools (Gemini CLI) is
# its own toggle so users on locked-down corp boxes can opt out cleanly.
show_custom_menu() {
    echo -e "\n${BOLD}${CYAN}[ CUSTOM — select tool groups ]${RESET}\n"
    ask_yes_no "  Shell environment (Zsh, Oh My Zsh, plugins, configs)?" \
        && DO_SHELL=true || DO_SHELL=false
    ask_yes_no "  AI Tools (Gemini CLI)?" \
        && DO_AI_TOOLS=true || DO_AI_TOOLS=false
    ask_yes_no "  Developer Tools (bat, fzf, jq, ripgrep, micro, tmux, btop...)?" \
        && DO_DEV_TOOLS=true || DO_DEV_TOOLS=false
    ask_yes_no "  Package Managers (npm, pipx, uv, rustup)?" \
        && DO_PKG_MGRS=true || DO_PKG_MGRS=false
    ask_yes_no "  Security Tools (1Password, nmap, openssl, yara, wtfis, wireshark)?" \
        && DO_SECURITY=true || DO_SECURITY=false
    ask_yes_no "  Cloud / CLI (rclone)?" \
        && DO_CLOUD_CLI=true || DO_CLOUD_CLI=false
    ask_yes_no "  Nerd Fonts?" \
        && DO_FONTS=true || DO_FONTS=false
    ask_yes_no "  Projector stack (weathr, trippy, terminal animation)?" \
        && DO_PROJECTOR=true || DO_PROJECTOR=false
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
           DO_PROJECTOR=false ;;
        3) DO_SHELL=false; DO_AI_TOOLS=false; DO_DEV_TOOLS=false; DO_PKG_MGRS=false
           DO_SECURITY=false; DO_CLOUD_CLI=false; DO_FONTS=true
           DO_PROJECTOR=true ;;
        4) show_custom_menu ;;
        *) warn "Invalid choice — defaulting to full install" ;;
    esac
}

# ── Flag parsing ──────────────────────────────────────────────────────────────
# All categories default to true (install everything) — same as Mac.
DO_SHELL=true
DO_AI_TOOLS=true
DO_DEV_TOOLS=true
DO_PKG_MGRS=true
DO_SECURITY=true
DO_CLOUD_CLI=true
DO_FONTS=true
DO_PROJECTOR=true

EXPLICIT_FLAG=false
MODE="${MODE:-batch}"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --shell)
            DO_SHELL=true; DO_AI_TOOLS=false; DO_DEV_TOOLS=false; DO_PKG_MGRS=false
            DO_SECURITY=false; DO_CLOUD_CLI=false; DO_FONTS=false
            DO_PROJECTOR=false; EXPLICIT_FLAG=true ;;
        --projector)
            DO_SHELL=false; DO_AI_TOOLS=false; DO_DEV_TOOLS=false; DO_PKG_MGRS=false
            DO_SECURITY=false; DO_CLOUD_CLI=false; DO_FONTS=true
            DO_PROJECTOR=true; EXPLICIT_FLAG=true ;;
        --interactive) MODE=interactive ;;
        --help)        show_help; exit 0 ;;
        *) err "Unknown parameter: $1"; show_help; exit 1 ;;
    esac
    shift
done

# ── OS detection ──────────────────────────────────────────────────────────────
# Parse /etc/os-release (freedesktop.org standard), then resolve package
# manager via the ID_LIKE chain — not just `command -v` — so derivatives like
# Pop!_OS, Linux Mint, elementary, Kali, Zorin, Manjaro, EndeavourOS, CachyOS
# all attribute to the right family. Detect WSL2 and immutable filesystems
# (rpm-ostree, NixOS) up front and refuse cleanly rather than half-working.
DISTRO_ID=""
DISTRO_LIKE=""
DISTRO_NAME=""
DISTRO_VERSION=""
DISTRO_CODENAME=""
DISTRO_FAMILY=""
KERNEL_VARIANT=""
IS_WSL=false
IS_IMMUTABLE=false

if [[ -r /etc/os-release ]]; then
    # Sourcing /etc/os-release is the documented usage — it's a key=value file
    # that exports ID, ID_LIKE, NAME, VERSION_ID, VERSION_CODENAME, etc.
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-}"
    DISTRO_LIKE="${ID_LIKE:-}"
    DISTRO_NAME="${PRETTY_NAME:-${NAME:-}}"
    DISTRO_VERSION="${VERSION_ID:-}"
    DISTRO_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
fi

# WSL2 detection — Microsoft kernel signature in /proc/sys/kernel/osrelease,
# or WSL_DISTRO_NAME env var set when launched via wsl.exe.
if [[ -n "${WSL_DISTRO_NAME:-}" ]] || \
   ( [[ -r /proc/sys/kernel/osrelease ]] && \
       grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null ); then
    IS_WSL=true
fi

# Immutable filesystem detection — Homebrew, apt-installed binaries that write
# to /usr will fail or do the wrong thing. Refuse rather than half-work.
if [[ -d /sysroot/ostree ]] || command -v rpm-ostree &>/dev/null; then
    IS_IMMUTABLE=true
    KERNEL_VARIANT="rpm-ostree (Fedora Silverblue/Kinoite/uBlue)"
elif [[ -e /etc/NIXOS ]] || [[ -d /nix/store && ! -w /usr/local ]]; then
    IS_IMMUTABLE=true
    KERNEL_VARIANT="NixOS"
fi

# Surface kernel oddities for diagnostics (non-fatal, just informational).
[[ "$DISTRO_ID" == "pop" ]] && KERNEL_VARIANT="${KERNEL_VARIANT:-System76 kernel (Pop!_OS)}"

if "$IS_IMMUTABLE"; then
    die "Unsupported environment: ${KERNEL_VARIANT}. /usr is read-only on this system; this installer expects a mutable filesystem. Use a toolbox/distrobox container or run on a traditional distro."
fi

# ── Resolve package manager + family via ID_LIKE chain ────────────────────────
# Helper: returns 0 if DISTRO_ID == family OR family appears in ID_LIKE.
_distro_in_family() {
    local family="$1"
    [[ "$DISTRO_ID" == "$family" ]] && return 0
    case " $DISTRO_LIKE " in
        *" $family "*) return 0 ;;
    esac
    return 1
}

if command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
    if _distro_in_family "ubuntu"; then DISTRO_FAMILY="ubuntu"
    elif _distro_in_family "debian"; then DISTRO_FAMILY="debian"
    else DISTRO_FAMILY="debian"; fi    # apt-get implies Debian-family
elif command -v pacman &>/dev/null; then
    PKG_MGR="pacman"
    DISTRO_FAMILY="arch"
    if command -v yay &>/dev/null; then AUR_HELPER="yay"
    elif command -v paru &>/dev/null; then AUR_HELPER="paru"
    else AUR_HELPER=""; fi
elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
    die "Detected ${DISTRO_NAME:-Fedora/RHEL family} (dnf/yum). This installer supports Debian/Ubuntu (apt) and Arch (pacman) families only."
elif command -v zypper &>/dev/null; then
    die "Detected ${DISTRO_NAME:-openSUSE} (zypper). This installer supports Debian/Ubuntu (apt) and Arch (pacman) families only."
elif command -v apk &>/dev/null; then
    die "Detected ${DISTRO_NAME:-Alpine} (apk/musl). This installer's Homebrew step requires glibc; run inside a Debian/Ubuntu container instead."
else
    die "Unsupported Linux distribution — no apt-get/pacman/dnf/zypper/apk. /etc/os-release: ${DISTRO_NAME:-<missing>}"
fi

# ── Single info line capturing the full operating context ────────────────────
_distro_label="${DISTRO_NAME:-Linux}"
[[ -n "$DISTRO_VERSION"  ]] && _distro_label+=" ${DISTRO_VERSION}"
[[ -n "$DISTRO_CODENAME" ]] && _distro_label+=" (${DISTRO_CODENAME})"
"$IS_WSL"                    && _distro_label+=" — WSL2"
[[ -n "$KERNEL_VARIANT"  ]] && _distro_label+=" — ${KERNEL_VARIANT}"
info "Detected ${_distro_label}"
info "Package manager: ${PKG_MGR} | Family: ${DISTRO_FAMILY}${AUR_HELPER:+ | AUR helper: ${AUR_HELPER}}"
unset _distro_label

SUDO=""
if [[ "$EUID" -ne 0 ]]; then
    command -v sudo &>/dev/null || die "sudo not installed and not root"
    SUDO="sudo"
fi

ARCH="$(dpkg --print-architecture 2>/dev/null || echo "amd64")"

# ── Supply chain guard ────────────────────────────────────────────────────────
# shellcheck source=lib/supply_chain_guard.sh
source "$SCRIPT_DIR/lib/supply_chain_guard.sh"

# ── RC file sweep utilities (inlined) ────────────────────────────────────────
# These mirror the inline copies in install_mac.sh / install_linux.sh. Subtle
# differences from lib/rc_sweep.sh (different awk strategy) — keep inlined
# until a future refactor consolidates them.

_zscaler_source_block() {
    printf '%s\n' \
        '# BEGIN terminal-kniferoll zscaler — DO NOT EDIT (managed by installer)' \
        '[ -r "$HOME/.config/terminal-kniferoll/zscaler-env.sh" ] && \' \
        '    . "$HOME/.config/terminal-kniferoll/zscaler-env.sh"' \
        '# END terminal-kniferoll zscaler'
}

backup_rc_file() {
    local rc="$1"
    [[ ! -f "$rc" ]] && return 0
    local ts; ts="$(date '+%Y%m%d-%H%M%S')"
    local backup="${rc}.terminal-kniferoll-backup-${ts}"
    cp "$rc" "$backup"
    chmod 600 "$backup"
    local dir base
    dir="$(dirname "$rc")"
    base="$(basename "$rc")"
    ls -t "${dir}/${base}.terminal-kniferoll-backup-"* 2>/dev/null | \
        tail -n +6 | while IFS= read -r _old; do rm -f "$_old"; done
    ok "  backup: $backup"
}

strip_zscaler_regions() {
    local file="$1"
    local result
    if result="$(awk '
function is_region_trigger(line) {
    if (line ~ /^[[:space:]]*(ZSC_PEM_LINUX|ZSC_PEM_MAC|ZSC_PEM)[[:space:]]*=/) return 1
    if (line ~ /^[[:space:]]*export[[:space:]]+(ZSC_PEM|CURL_CA_BUNDLE|GIT_SSL_CAINFO|SSL_CERT_FILE|REQUESTS_CA_BUNDLE|NODE_EXTRA_CA_CERTS|AWS_CA_BUNDLE|PIP_CERT|HOMEBREW_CURLOPT_CACERT)[[:space:]]*=/) return 1
    return 0
}
function is_marker_begin(line) {
    return (line ~ /^[[:space:]]*#[[:space:]]*BEGIN[[:space:]]+terminal-kniferoll[[:space:]]+zscaler/)
}
function is_marker_end(line) {
    return (line ~ /^[[:space:]]*#[[:space:]]*END[[:space:]]+terminal-kniferoll[[:space:]]+zscaler/)
}
function is_zsc_extend(line) {
    return (line ~ /^[[:space:]]*#.*[Zz]scaler/ && !is_marker_begin(line) && !is_marker_end(line))
}
function is_blank(line) { return (line ~ /^[[:space:]]*$/) }
function is_control_open(line) {
    if (line ~ /^[[:space:]]*(if|for|while|until|case)[[:space:]([]/) return 1
    if (line ~ /^[[:space:]]*function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[({]/) return 1
    if (line ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*(\{|$)/) return 1
    if (line ~ /^[[:space:]]*\{[[:space:]]*(#.*)?$/) return 1
    return 0
}
function is_control_close(line) {
    if (line ~ /^[[:space:]]*(fi|esac|done)[[:space:]]*(;[[:space:]]*(#.*)?)?$/) return 1
    if (line ~ /^[[:space:]]*\}[[:space:]]*(#.*)?$/) return 1
    return 0
}
BEGIN { in_region=0; in_marker=0; depth=0; rstart=0; pend_buf=""; pend_cnt=0 }
{
    line = $0
    if (!in_region) {
        if (depth == 0) {
            if (is_marker_begin(line)) {
                in_region=1; in_marker=1; rstart=NR; pend_buf=""; pend_cnt=0; next
            }
            if (is_region_trigger(line)) {
                in_region=1; in_marker=0; rstart=NR; pend_buf=""; pend_cnt=0; next
            }
        }
        if (is_control_open(line)) depth++
        else if (is_control_close(line) && depth > 0) depth--
        print line; next
    }
    if (in_marker) {
        if (is_marker_end(line)) {
            print "REGION " rstart " " NR > "/dev/stderr"
            in_region=0; in_marker=0
        }
        next
    }
    if (is_blank(line)) { pend_buf = pend_buf line "\n"; pend_cnt++; next }
    if (depth > 0) {
        if (is_control_open(line)) depth++
        else if (is_control_close(line) && depth > 0) depth--
        pend_buf=""; pend_cnt=0; next
    }
    if (is_region_trigger(line) || is_zsc_extend(line)) { pend_buf=""; pend_cnt=0; next }
    if (is_control_open(line)) { pend_buf=""; pend_cnt=0; depth++; next }
    print "REGION " rstart " " (NR - 1 - pend_cnt) > "/dev/stderr"
    in_region=0
    if (pend_cnt > 0) { printf "%s", pend_buf; pend_buf=""; pend_cnt=0 }
    if (is_marker_begin(line)) {
        in_region=1; in_marker=1; rstart=NR; pend_buf=""; pend_cnt=0; next
    }
    if (is_region_trigger(line)) {
        in_region=1; in_marker=0; rstart=NR; pend_buf=""; pend_cnt=0; next
    }
    if (is_control_open(line)) depth++
    else if (is_control_close(line) && depth > 0) depth--
    print line
}
END {
    if (in_region) {
        print "REGION " rstart " " NR > "/dev/stderr"
    } else if (pend_cnt > 0) {
        printf "%s", pend_buf
    }
}
' "$file" 2>/tmp/sweep-awk-err$$)"; then
        printf '%s\n' "$result"
    else
        warn "sweep-zscaler (inline) error ($file): $(head -1 /tmp/sweep-awk-err$$)"
        rm -f /tmp/sweep-awk-err$$
        cat "$file"
        return 1
    fi
    rm -f /tmp/sweep-awk-err$$
}

_has_zscaler_block() {
    grep -Eq \
        'ZSC_PEM_LINUX[[:space:]]*=|ZSC_PEM_MAC[[:space:]]*=|^[[:space:]]*unset[[:space:]]+ZSC_PEM|^[[:space:]]*(export[[:space:]]+)?ZSC_PEM[[:space:]]*=|^[[:space:]]*export[[:space:]]+(CURL_CA_BUNDLE|SSL_CERT_FILE|REQUESTS_CA_BUNDLE|NODE_EXTRA_CA_CERTS|GIT_SSL_CAINFO|AWS_CA_BUNDLE|PIP_CERT|HOMEBREW_CURLOPT_CACERT)[[:space:]]*=|# BEGIN terminal-kniferoll zscaler' \
        "$1" 2>/dev/null
}

_show_sweep_preview() {
    local rc="$1" dry="${2:-}"
    local lines_before lines_after removed_count
    lines_before=$(wc -l < "$rc")
    lines_after=$(strip_zscaler_regions "$rc" | wc -l)
    removed_count=$(( lines_before - lines_after ))
    if [[ -n "$dry" ]]; then
        info "  [dry-run] sweep: $rc"
    else
        info "  sweep: $rc"
    fi
    [[ $removed_count -gt 0 ]] && \
        info "  - removing ~${removed_count} lines (old Zscaler block)"
    info "  + appending 4 lines (new marker block)"
}

upsert_rc_zscaler_block() {
    local rc="$1" dry="${2:-}"
    [[ ! -f "$rc" ]] && return 0
    local _blk; _blk="$(mktemp)"
    _zscaler_source_block > "$_blk"
    if _has_zscaler_block "$rc"; then
        _show_sweep_preview "$rc" "$dry"
        [[ -n "$dry" ]] && { rm -f "$_blk"; return 0; }
        local _stripped; _stripped="$(mktemp)"; chmod 600 "$_stripped"
        strip_zscaler_regions "$rc" > "$_stripped"
        local _tmp; _tmp="$(mktemp)"; chmod 600 "$_tmp"
        local _stripped_content
        _stripped_content="$(cat "$_stripped")"
        if [[ -n "$_stripped_content" ]]; then
            { printf '%s\n' "$_stripped_content"; echo; cat "$_blk"; } > "$_tmp"
        else
            cat "$_blk" > "$_tmp"
        fi
        if cmp -s "$_tmp" "$rc"; then
            rm -f "$_stripped" "$_tmp" "$_blk"
            ok "$rc: Zscaler block already canonical — no backup needed"
            return 0
        fi
        backup_rc_file "$rc"
        mv -f "$_tmp" "$rc"
        rm -f "$_stripped"
        ok "$rc: Zscaler block(s) swept, source block appended"
    else
        [[ -n "$dry" ]] && {
            info "  [dry-run] $rc: no Zscaler block found — would append marker"
            rm -f "$_blk"; return 0
        }
        backup_rc_file "$rc"
        local _tmp; _tmp="$(mktemp)"; chmod 600 "$_tmp"
        { cat "$rc"; echo; cat "$_blk"; } > "$_tmp"
        mv -f "$_tmp" "$rc"
        ok "$rc: Zscaler source block appended"
    fi
    rm -f "$_blk"
}

sweep_rc_files() {
    local dry=""
    [[ "${1:-}" == "--dry-run" ]] && dry="1"
    banner "ZSCALER RC SWEEP${dry:+ (DRY RUN)}"
    local _rc
    for _rc in \
        "$HOME/.zshrc" \
        "$HOME/.zprofile" \
        "$HOME/.bashrc" \
        "$HOME/.bash_profile" \
        "$HOME/.profile"
    do
        [[ -f "$_rc" ]] && upsert_rc_zscaler_block "$_rc" "$dry"
    done
    unset _rc
}

_brew_shellenv_block() {
    cat << 'BSEOF'
# BEGIN terminal-kniferoll brew-shellenv — DO NOT EDIT (managed by installer)
if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi
# END terminal-kniferoll brew-shellenv
BSEOF
}

_brew_shellenv_block_linux() {
    cat << 'BSEOF'
# BEGIN terminal-kniferoll brew-shellenv — DO NOT EDIT (managed by installer)
if [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -x "$HOME/.linuxbrew/bin/brew" ]]; then
    eval "$($HOME/.linuxbrew/bin/brew shellenv)"
fi
# END terminal-kniferoll brew-shellenv
BSEOF
}

_strip_brew_shellenv_regions() {
    local file="$1"
    awk '
        /# BEGIN terminal-kniferoll brew-shellenv/ { skip=1; next }
        /# END terminal-kniferoll brew-shellenv/   { skip=0; next }
        skip                                        { next }
        /eval[[:space:]]+"?\$\(.*brew shellenv/    { next }
        { print }
    ' "$file"
}

_has_brew_shellenv_block() {
    grep -Eq \
        'eval[[:space:]]+"?\$\(.*brew[[:space:]]+shellenv|# BEGIN terminal-kniferoll brew-shellenv' \
        "$1" 2>/dev/null
}

upsert_brew_shellenv_block() {
    local rc="$1" dry="${2:-}" block_fn="${3:-_brew_shellenv_block}"
    [[ ! -f "$rc" ]] && return 0
    local _blk; _blk="$(mktemp)"; chmod 600 "$_blk"
    "$block_fn" > "$_blk"
    local _clean; _clean="$(mktemp)"; chmod 600 "$_clean"
    local _final; _final="$(mktemp)"; chmod 600 "$_final"
    _strip_brew_shellenv_regions "$rc" > "$_clean"
    local _clean_content
    _clean_content="$(cat "$_clean")"
    rm -f "$_clean"
    if [[ -n "$_clean_content" ]]; then
        { printf '%s\n' "$_clean_content"; echo; cat "$_blk"; } > "$_final"
    else
        cat "$_blk" > "$_final"
    fi
    rm -f "$_blk"
    if cmp -s "$_final" "$rc"; then
        rm -f "$_final"
        return 0
    fi
    if [[ -n "$dry" ]]; then
        info "  [dry-run] sweep (brew-shellenv): $rc"
        rm -f "$_final"
        return 0
    fi
    backup_rc_file "$rc"
    mv -f "$_final" "$rc"
    ok "$rc: brew-shellenv block upserted"
}

sweep_brew_shellenv_files() {
    local dry="" block_fn="${2:-_brew_shellenv_block}"
    [[ "${1:-}" == "--dry-run" ]] && dry="1"
    banner "BREW SHELLENV RC SWEEP${dry:+ (DRY RUN)}"
    local _rc
    for _rc in \
        "$HOME/.zshrc" \
        "$HOME/.zprofile" \
        "$HOME/.bashrc" \
        "$HOME/.bash_profile" \
        "$HOME/.profile"
    do
        [[ -f "$_rc" ]] && upsert_brew_shellenv_block "$_rc" "$dry" "$block_fn"
    done
    unset _rc
}

# ── Rainbow / fastfetch managed marker blocks ────────────────────────────────
# Three blocks — lolcat→lolcrab alias, ff alias, fastfetch greeter — emitted
# into every POSIX RC file so bash users get them too. Order: aliases first,
# greeter last (so the greeter's body uses lolcrab directly without going
# through the alias).

_lolcat_alias_block() {
    cat << 'BLKEOF'
# BEGIN terminal-kniferoll lolcat-alias — DO NOT EDIT (managed by installer)
if command -v lolcrab >/dev/null 2>&1 && ! command -v lolcat >/dev/null 2>&1; then
    alias lolcat='lolcrab'
fi
# END terminal-kniferoll lolcat-alias
BLKEOF
}

_ff_alias_block() {
    cat << 'BLKEOF'
# BEGIN terminal-kniferoll ff-alias — DO NOT EDIT (managed by installer)
if command -v fastfetch >/dev/null 2>&1 && command -v lolcrab >/dev/null 2>&1; then
    alias ff='fastfetch | lolcrab'
elif command -v fastfetch >/dev/null 2>&1; then
    alias ff='fastfetch'
fi
# END terminal-kniferoll ff-alias
BLKEOF
}

_fastfetch_greeter_block() {
    cat << 'BLKEOF'
# BEGIN terminal-kniferoll fastfetch-greeter — DO NOT EDIT (managed by installer)
if [ -z "${TK_FASTFETCH_GREETED:-}" ] && [ -z "${DISABLE_WELCOME:-}" ] && \
   command -v fastfetch >/dev/null 2>&1; then
    if command -v lolcrab >/dev/null 2>&1; then
        fastfetch | lolcrab
    else
        fastfetch
    fi
    export TK_FASTFETCH_GREETED=1
fi
# END terminal-kniferoll fastfetch-greeter
BLKEOF
}

# Generic per-marker stripper. Strips a single BEGIN/END terminal-kniferoll
# <marker> block from the file.
_strip_marker_block() {
    local file="$1" marker="$2"
    awk -v m="$marker" '
        $0 ~ ("^# BEGIN terminal-kniferoll " m "( |$)") { skip=1; next }
        $0 ~ ("^# END terminal-kniferoll " m "( |$)")   { skip=0; next }
        skip                                              { next }
        { print }
    ' "$file"
}

# Generic upsert: rc, dry, block-emitter fn, marker-name.
upsert_marker_block() {
    local rc="$1" dry="$2" block_fn="$3" marker="$4"
    [[ ! -f "$rc" ]] && return 0
    local _blk; _blk="$(mktemp)"; chmod 600 "$_blk"
    "$block_fn" > "$_blk"
    local _clean; _clean="$(mktemp)"; chmod 600 "$_clean"
    local _final; _final="$(mktemp)"; chmod 600 "$_final"
    _strip_marker_block "$rc" "$marker" > "$_clean"
    local _clean_content
    _clean_content="$(cat "$_clean")"
    rm -f "$_clean"
    if [[ -n "$_clean_content" ]]; then
        { printf '%s\n' "$_clean_content"; echo; cat "$_blk"; } > "$_final"
    else
        cat "$_blk" > "$_final"
    fi
    rm -f "$_blk"
    if cmp -s "$_final" "$rc"; then
        rm -f "$_final"
        return 0
    fi
    if [[ -n "$dry" ]]; then
        info "  [dry-run] sweep ($marker): $rc"
        rm -f "$_final"
        return 0
    fi
    backup_rc_file "$rc"
    mv -f "$_final" "$rc"
    ok "$rc: $marker block upserted"
}

# Sweep all POSIX RC files for the rainbow / fastfetch trio.
sweep_rainbow_blocks() {
    local dry=""
    [[ "${1:-}" == "--dry-run" ]] && dry="1"
    banner "FASTFETCH/LOLCRAB RC SWEEP${dry:+ (DRY RUN)}"
    local _rc
    for _rc in \
        "$HOME/.zshrc" \
        "$HOME/.zprofile" \
        "$HOME/.bashrc" \
        "$HOME/.bash_profile" \
        "$HOME/.profile"
    do
        if [[ -f "$_rc" ]]; then
            upsert_marker_block "$_rc" "$dry" "_lolcat_alias_block"      "lolcat-alias"
            upsert_marker_block "$_rc" "$dry" "_ff_alias_block"          "ff-alias"
            upsert_marker_block "$_rc" "$dry" "_fastfetch_greeter_block" "fastfetch-greeter"
        fi
    done
    unset _rc
}

# ── Split-terminal UI (tk-022) ────────────────────────────────────────────────
# Bash + tput + background tail. NOT tmux. Falls back silently when terminal
# is too narrow / non-interactive.
# shellcheck source=lib/split_terminal.sh
source "$SCRIPT_DIR/lib/split_terminal.sh"

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

# ── Show install menu ─────────────────────────────────────────────────────────
if [[ "$EXPLICIT_FLAG" == "false" ]] && { [[ -t 0 ]] || [[ "$MODE" == "interactive" ]]; }; then
    show_menu
fi

# ── sudo keepalive (non-root only) — FIRST interactive step ───────────────────
# Prompt for sudo before any UI is drawn so the password prompt is the first
# user-visible interaction, not a surprise mid-run hidden behind a banner or
# the split-terminal box.
[[ "$EUID" -ne 0 ]] && check_sudo

# ── Initialise split-terminal UI (tk-022) ────────────────────────────────────
# Draws right-panel box and starts background verbose renderer.
# Falls back silently if terminal is too narrow or non-interactive.
st_init

info "Supply chain: strict (TLS enforced, hashes verified where available)"

# Surface managed-device status near the top so the user can connect cask /
# proxy / cert messages later in the run to "yeah, I'm on a corp box."
if is_restricted_device; then
    quip "Managed device detected — some installs may require admin approval"
fi

# ── TLS preflight + Zscaler trust (hard gate) ────────────────────────────────
# Proceeding with a broken TLS stack would silently corrupt every download.
# preflight_zscaler_check exit codes:
#   0 — clean, proceed
#   1 — SSL cert error → run setup_zscaler_trust --required
#   2 — HTML splash page handled (auto-accept or manual) → re-run preflight
banner "TLS PREFLIGHT"
_preflight_rc=0
preflight_zscaler_check || _preflight_rc=$?

if [[ "$_preflight_rc" -eq 2 ]]; then
    # Splash page was accepted (auto or manual) — re-validate once
    info "Re-validating TLS after Zscaler acknowledgment..."
    _preflight_rc=0
    preflight_zscaler_check || _preflight_rc=$?
    if [[ "$_preflight_rc" -ne 0 ]]; then
        die "TLS still blocked after Zscaler acceptance — check $LOG_FILE"
    fi
fi

if [[ "$_preflight_rc" -eq 1 ]]; then
    banner "MANAGED DEVICE SETUP — REQUIRED"
    info "TLS interception detected — configuring Zscaler cert trust before proceeding"
    setup_zscaler_trust --required

    info "Re-validating TLS after trust setup..."
    _preflight_rc=0
    preflight_zscaler_check || _preflight_rc=$?
    if [[ "$_preflight_rc" -ne 0 ]]; then
        err "TLS validation failed even after Zscaler cert trust was configured."
        err ""
        err "Possible causes:"
        err "  - The Zscaler cert bundle is incomplete or expired"
        err "  - A different corporate proxy is intercepting (not Zscaler)"
        err "  - Network connectivity issue (VPN not connected?)"
        err ""
        err "Log: $LOG_FILE"
        die "TLS still broken after trust setup — aborting install"
    fi
    ok "TLS re-validated — all subsequent curl/git installs will use the Zscaler CA bundle"
else
    # Opportunistic cert detection: wire up env vars for tool configuration
    # even on non-managed devices that happen to have a Zscaler cert present.
    setup_zscaler_trust
fi

# ── Evict tools removed from this project ─────────────────────────────────────
banner "HOUSEKEEPING — EVICTING REMOVED TOOLS"
cleanup_removed_tools

# ────────────────────────────────────────────────────────────────────────────
# 1. CORE PREREQUISITES (always — every category needs these)
# ────────────────────────────────────────────────────────────────────────────
banner "CORE PREREQUISITES"
if [[ "$PKG_MGR" == "apt" ]]; then
    run_optional "Refreshing apt package list" \
        bash -c "$SUDO apt-get update -qq"
    run_optional "Installing core prerequisites" \
        bash -c "$SUDO apt-get install -y -qq ca-certificates curl gnupg unzip fontconfig"
    if [[ -f "/usr/local/share/ca-certificates/zscaler.pem" ]] || \
       [[ -f "/usr/local/share/ca-certificates/zscaler.crt" ]]; then
        run_optional "Updating system CA bundle (Zscaler cert detected)" \
            bash -c "$SUDO update-ca-certificates"
    fi
else
    run_optional "Refreshing pacman database" \
        bash -c "$SUDO pacman -Sy --noconfirm"
    run_optional "Installing core prerequisites" \
        bash -c "$SUDO pacman -S --noconfirm ca-certificates curl gnupg unzip fontconfig"
fi

# Bring up Linuxbrew once, here, so AI Tools / Dev Tools can use it without
# each section reinventing the bootstrap. Skip on shell-only or projector-only
# runs that don't touch brew-backed packages — saves ~3 min on minimal installs.
if [[ "$DO_AI_TOOLS" == "true" || "$DO_DEV_TOOLS" == "true" ]]; then
    ensure_homebrew || true
else
    skip "Homebrew bootstrap (no brew-backed categories selected)"
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
        # Pinned to a specific release tag instead of piping master/install.sh.
        # GIT_SSL_CAINFO is already exported (set in _zscaler_export_env above) so
        # this clone trusts the Zscaler CA on managed devices.
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
    if [[ ! -f "$HOME/.zshrc" ]]; then
        cp "$SCRIPT_DIR/shell/zshrc.zsh" "$HOME/.zshrc"
        ok "~/.zshrc deployed (fresh install)"
    fi
    cp "$SCRIPT_DIR/shell/aliases.zsh" "$HOME/.shell/aliases.zsh"
    cp "$SCRIPT_DIR/shell/plugins.zsh" "$HOME/.shell/plugins.zsh"
    ok "Shell configurations deployed"
fi

# ────────────────────────────────────────────────────────────────────────────
# 3. AI TOOLS
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_AI_TOOLS" == "true" ]]; then
    banner "AI TOOLS"
    if is_installed "gemini"; then
        skip "Gemini CLI already installed"
    elif is_installed "brew"; then
        _brew_install_verified gemini-cli || true
        ! is_installed "gemini" && is_installed "npm" && \
            run_optional "Installing Gemini CLI (npm fallback)" \
                npm install -g @google/gemini-cli || true
    elif is_installed "npm"; then
        run_optional "Installing Gemini CLI (npm — brew unavailable)" \
            npm install -g @google/gemini-cli || true
    else
        warn "Gemini CLI: neither brew nor npm available — skipping"
        FAILED_TOOLS+=("gemini-cli")
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# 4. DEVELOPER TOOLS
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_DEV_TOOLS" == "true" ]]; then
    if [[ "$PKG_MGR" == "apt" ]]; then
        apt_batch "DEVELOPER UTILITIES" \
            "jq:jq" "fzf:fzf" "rg:ripgrep" "micro:micro" \
            "sqlite3:sqlite3" "lua5.4:lua5.4" "m4:m4" "lz4:lz4" \
            "exiftool:libimage-exiftool-perl" "git:git" \
            "curl:curl" "gzip:gzip" "tmux:tmux" "btop:btop" \
            "hexyl:hexyl"

        apt_batch "BUILD AND CRYPTO" \
            "openssl:openssl" "binutils:binutils" "fc-cache:fontconfig" \
            "ca-certificates:ca-certificates" "libssl-dev:libssl-dev"

        apt_batch "LANGUAGE RUNTIMES" \
            "python3:python3" "pip3:python3-pip" "ruby:ruby" \
            "node:nodejs" "go:golang"

        # SHELL EXTRAS is split into apt (reliably-in-apt) and brew
        # (needs-brew) batches. The previous combined batch was poisoned by
        # starship/zoxide/cbonsai (not in older Ubuntu/Pop!_OS apt) — when
        # any one of those fails to locate, `apt-get install` errors out
        # atomically and installs NONE of the others, including cmatrix and
        # fastfetch which DO exist in apt.
        # speedtest-cli intentionally dropped — Chef's policy: deprecated
        # upstream, supply chain risk. Replacement (if any) handled by a
        # separate task, not this file.
        apt_batch "SHELL EXTRAS (apt)" \
            "unzip:unzip" "fastfetch:fastfetch" "cmatrix:cmatrix"
        brew_extras_install "SHELL EXTRAS (brew)" \
            "zoxide:zoxide" "starship:starship" "cbonsai:cbonsai"

        if ! is_installed "nu"; then
            ensure_rust_toolchain    # repair toolchain before this cargo path too
            if is_installed "cargo"; then
                cargo_install "nu" "nu" "nushell"
            else
                warn "nushell not in apt and no cargo — skipping"
            fi
        fi
        install_yazi_binary

        banner "GITHUB RELEASE INSTALLS"
        install_github_deb "lsd" "lsd-rs/lsd"  "_${ARCH}\\.deb" "lsd"
        install_github_deb "bat" "sharkdp/bat" "_${ARCH}\\.deb" "bat"
    else
        # Arch/CachyOS via pacman — single batch is safe (atomic install
        # behavior is the same but every package below is in the official
        # repos, so no atomic-failure cascade risk).
        banner "DEVELOPER TOOLS (pacman)"
        PACMAN_DEV_PACKAGES=(
            binutils btop perl-image-exiftool fastfetch fzf git go gzip hexyl jq openssl lua
            lz4 m4 micro ncurses nodejs python python-pip ripgrep ruby
            sqlite tealdeer tmux nushell yazi lsd bat zoxide starship cmatrix
        )
        for pkg in "${PACMAN_DEV_PACKAGES[@]}"; do
            pacman -Qi "$pkg" &>/dev/null && skip "$pkg" && continue
            run_optional "Installing $pkg" bash -c "$SUDO pacman -S --noconfirm '$pkg'"
        done
        if ! is_installed "cbonsai" && [[ -n "${AUR_HELPER:-}" ]]; then
            run_optional "Installing cbonsai (AUR)" "$AUR_HELPER" -S --noconfirm cbonsai
        fi
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# 5. PACKAGE MANAGERS
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_PKG_MGRS" == "true" ]]; then
    banner "PACKAGE MANAGERS"

    if [[ "$PKG_MGR" == "apt" ]]; then
        apt_batch "PYTHON AND PACKAGE MANAGEMENT" \
            "pipx:pipx" "python3:python3-venv"

        # uv: safe install only (no custom-domain script). astral.sh/uv/install.sh
        # was HIGH risk — removed. uv comes via pipx on apt.
        is_installed "uv" || {
            run_optional "Installing uv via pipx" pipx install uv
            run_optional "Configuring pipx path" pipx ensurepath
        }
    else
        is_installed "uv" || \
            run_optional "Installing uv (pacman)" bash -c "$SUDO pacman -S --noconfirm uv"
    fi

    is_installed "pipx" && run_optional "Configuring pipx path" pipx ensurepath

    # Rustup — bootstrap the toolchain. ensure_rust_toolchain is memoized so
    # this won't double-fetch if Dev Tools (nushell) already triggered it.
    ensure_rust_toolchain
fi

# ────────────────────────────────────────────────────────────────────────────
# 6. SECURITY TOOLS
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_SECURITY" == "true" ]]; then
    banner "SECURITY TOOLS"

    if is_restricted_device; then
        quip "Managed device — 1Password / Wireshark may need IT/MDM approval"
    fi

    install_1password_cli

    if [[ "$PKG_MGR" == "apt" ]]; then
        # nmap handled separately — wireshark dep requires debconf pre-seeding (tk-021)
        _nmap_safe_install
        apt_batch "SECURITY TOOLING" \
            "tcpdump:tcpdump" "ngrep:ngrep" \
            "tshark:wireshark" "yara:yara" "unbound:unbound" \
            "certtool:gnutls-bin"
    else
        banner "SECURITY TOOLING (pacman)"
        PACMAN_SEC_PACKAGES=(
            nmap tcpdump ngrep wireshark-cli yara unbound gnutls
        )
        for pkg in "${PACMAN_SEC_PACKAGES[@]}"; do
            pacman -Qi "$pkg" &>/dev/null && skip "$pkg" && continue
            run_optional "Installing $pkg" bash -c "$SUDO pacman -S --noconfirm '$pkg'"
        done
    fi

    # wtfis via pipx (works on both apt and pacman once pipx is present)
    if is_installed "wtfis"; then
        skip "wtfis already installed"
    elif is_installed "pipx"; then
        run_optional "Installing wtfis via pipx" pipx install wtfis
        run_optional "Configuring pipx path"     pipx ensurepath
    else
        warn "wtfis: pipx not available — skipping (re-run with DO_PKG_MGRS=true)"
        FAILED_TOOLS+=("wtfis(no-pipx)")
    fi

    # pip upgrade + TLS smoke test
    # 'local' is only valid inside a function; use plain assignment here.
    _py3="$(command -v python3 || true)"
    if [[ -n "$_py3" ]]; then
        # PEP 668 (Debian 11+, Homebrew Python): pip upgrade is managed by the
        # system package manager.  Detect the EXTERNALLY-MANAGED sentinel and
        # skip rather than using --break-system-packages.
        _py3_stdlib="$("$_py3" -c 'import sysconfig; print(sysconfig.get_path("stdlib"))' 2>/dev/null || true)"
        if [[ -n "$_py3_stdlib" && -f "$_py3_stdlib/EXTERNALLY-MANAGED" ]]; then
            skip "pip upgrade — Python is externally-managed (PEP 668); package manager owns pip"
        else
            run_optional "Upgrading pip" "$_py3" -m pip install --upgrade pip
        fi
        run_optional "Python TLS smoke test (ssl.create_default_context)" \
            "$_py3" -c "import ssl; ssl.create_default_context().load_default_certs(); print('SSL OK')"
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# 7. CLOUD / CLI
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_CLOUD_CLI" == "true" ]]; then
    banner "CLOUD / CLI"

    # rclone via apt or pacman
    if is_installed "rclone"; then
        skip "rclone already installed"
    elif [[ "$PKG_MGR" == "apt" ]]; then
        apt_install "rclone" "rclone" "rclone"
    else
        run_optional "Installing rclone (pacman)" bash -c "$SUDO pacman -S --noconfirm rclone"
    fi

    # awscli via apt or pacman (no AWS CLI v2 in apt; v1 is fine for most uses;
    # users wanting v2 can install from AWS bundle separately).
    if is_installed "aws"; then
        skip "AWS CLI already installed"
    elif [[ "$PKG_MGR" == "apt" ]]; then
        apt_install "aws" "awscli" "AWS CLI (v1 from apt)"
    else
        run_optional "Installing AWS CLI (pacman)" bash -c "$SUDO pacman -S --noconfirm aws-cli"
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# 8. NERD FONTS
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_FONTS" == "true" ]]; then
    FONT_DIR="$HOME/.local/share/fonts"
    NERD_FONTS=(
        Iosevka IosevkaTerm Hack UbuntuMono JetBrainsMono 3270
        FiraCode CascadiaCode VictorMono Mononoki
        SpaceMono SourceCodePro Meslo GeistMono
    )
    # Pinned release — update NERD_FONTS_VER here to upgrade all fonts at once
    NERD_FONTS_VER="v3.4.0"
    _fonts_installed=0
    banner "NERD FONTS"
    mkdir -p "$FONT_DIR"
    for _nf in "${NERD_FONTS[@]}"; do
        if fc-list 2>/dev/null | grep -qi "$_nf"; then
            skip "$_nf Nerd Font already installed"
            continue
        fi
        _font_zip="$(mktemp /tmp/font-XXXXXX.zip)"
        if curl --proto '=https' --tlsv1.2 -fsSL \
                ${CURL_CA_BUNDLE:+--cacert "$CURL_CA_BUNDLE"} \
                "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VER}/${_nf}.zip" \
                -o "$_font_zip"; then
            mkdir -p "$FONT_DIR/$_nf"
            unzip -qo "$_font_zip" -d "$FONT_DIR/$_nf"
            ok "$_nf Nerd Font installed"
            (( ++_fonts_installed ))
        else
            warn "$_nf Nerd Font download failed"
            FAILED_TOOLS+=("font:$_nf")
        fi
        rm -f "$_font_zip"
    done
    if [[ $_fonts_installed -gt 0 ]]; then
        run_optional "Refreshing font cache" fc-cache -f
    fi
fi

# ────────────────────────────────────────────────────────────────────────────
# 9. PROJECTOR STACK
# ────────────────────────────────────────────────────────────────────────────
if [[ "$DO_PROJECTOR" == "true" ]]; then
    banner "PROJECTOR STACK"
    ensure_rust_toolchain
    cargo_install "weathr" "weathr"  "weathr (weather CLI)"
    cargo_install "trip"   "trippy"  "trippy (network pulse)"

    # lolcrab — Rust port of lolcat, single static binary, drop-in CLI.
    # Installed here (not in Dev Tools) because it depends on Rust toolchain
    # which the projector stack already brings up. The lolcat → lolcrab alias
    # + fastfetch greeter are upserted in the rainbow-block sweep at the end
    # of this script regardless of whether lolcrab actually installed.
    install_lolcrab

    banner "PROJECTOR CONFIGURATION"
    mkdir -p "$HOME/.config/projector"
    [[ -f "$HOME/.config/projector/config.json" ]] || \
        cp "$SCRIPT_DIR/projector/config.json.default" "$HOME/.config/projector/config.json"
    [[ -f "$SCRIPT_DIR/projector.py" ]] && chmod +x "$SCRIPT_DIR/projector.py" || true
    ok "Projector configuration deployed"
fi

# ────────────────────────────────────────────────────────────────────────────
# 10. ZSCALER ENV FILE + RC SWEEP (every invocation, any mode)
# ────────────────────────────────────────────────────────────────────────────
write_zscaler_env_file
sweep_rc_files

# ────────────────────────────────────────────────────────────────────────────
# 10b. FASTFETCH/LOLCRAB RC SWEEP (every invocation, any mode)
# Idempotent: rewrites the three managed blocks (lolcat-alias, ff-alias,
# fastfetch-greeter) in every POSIX RC file. Block bodies runtime-check
# command -v lolcrab/fastfetch so they no-op when the tools are missing.
# ────────────────────────────────────────────────────────────────────────────
sweep_rainbow_blocks

# ────────────────────────────────────────────────────────────────────────────
# 11. BREW SHELLENV RC SWEEP (idempotent; re-run in case brew was just installed)
# ────────────────────────────────────────────────────────────────────────────
if is_installed "brew" || [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]] || \
   [[ -x "$HOME/.linuxbrew/bin/brew" ]]; then
    sweep_brew_shellenv_files "" _brew_shellenv_block_linux
fi

# ── POST-FLIGHT VERIFICATION ─────────────────────────────────────────────────
# Diagnostic, not gating — per-step verification owns FAILED_TOOLS already.
# This pass surfaces broken state across the whole system so the user knows.
_postflight_verify() {
    banner "POST-FLIGHT VERIFICATION"
    if [[ "$PKG_MGR" == "apt" ]]; then
        local audit_out check_out
        audit_out="$(dpkg --audit 2>&1 | head -20 || true)"
        if [[ -n "$audit_out" ]]; then
            warn "dpkg --audit reports half-configured packages:"
            echo "$audit_out" | sed 's/^/    /'
        else
            ok "dpkg --audit: no half-configured packages"
        fi
        check_out="$(sudo apt-get -o DPkg::Lock::Timeout=60 check 2>&1 | tail -5 || true)"
        if echo "$check_out" | grep -qE 'broken|Unmet|E:'; then
            warn "apt-get check found broken dependencies:"
            echo "$check_out" | sed 's/^/    /'
        else
            ok "apt-get check: no broken dependencies"
        fi
    fi
    if is_installed "brew"; then
        local missing_out
        missing_out="$(brew missing 2>&1 | head -10 || true)"
        if [[ -n "$missing_out" ]]; then
            warn "brew missing reports gaps:"
            echo "$missing_out" | sed 's/^/    /'
        else
            ok "brew missing: no missing dependencies"
        fi
    fi
}

trap - ERR  # per-step verification owns FAILED_TOOLS — no more ERR trap needed
_postflight_verify
st_cleanup  # tear down split-terminal UI before printing summary (tk-022)
sc_process_deferred
print_summary
sc_summary

# ── Brew login-shell verification ─────────────────────────────────────────────
_brew_login_path="$(
    /bin/zsh  -l -c 'command -v brew' 2>/dev/null || \
    /bin/bash -l -c 'command -v brew' 2>/dev/null || true
)"
if [[ -n "$_brew_login_path" ]]; then
    ok "brew verification: findable from a clean login shell (${_brew_login_path})"
elif is_installed "brew" || [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    warn "brew is installed but NOT findable from a clean login shell"
    warn "Add to ~/.bashrc / ~/.zshrc manually:"
    warn '  if [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then'
    warn '      eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
    warn '  fi'
fi

echo -e "${BOLD}${CYAN}>>> mission complete. knives sharp. out.${RESET}"
echo -e "${DIM}    Reminder: run 'chsh -s \$(which zsh)' to set Zsh as default shell.${RESET}"
echo -e "${DIM}    Reminder: source ~/.cargo/env or restart your shell for Rust tools.${RESET}"
exit 0
