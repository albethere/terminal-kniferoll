#!/usr/bin/env bash
# =============================================================================
# terminal-kniferoll | Supply Chain Guard
# =============================================================================
# Provides interactive risk controls for third-party package installation.
# Sourced by install_linux.sh and install_mac.sh.
#
# USAGE (from installer scripts):
#   source "$SCRIPT_DIR/lib/supply_chain_guard.sh"
#   sc_set_risk_tolerance          # prompt user once (interactive only)
#   sc_install NAME RISK DESC SAFE_FN RISKY_FN GITHUB_URL SOURCE_URL
#   sc_process_deferred            # review deferred packages at end
#   sc_summary                     # print skipped/deferred list
#
# ENVIRONMENT VARIABLES:
#   SC_RISK_TOLERANCE    — preset policy: 1=strict 2=balanced 3=permissive 4=manual
#                          Unset or 0 = prompt interactively (TTY only)
#   SC_ALLOW_RISKY=1     — shorthand for SC_RISK_TOLERANCE=3 (CI escape hatch)
# =============================================================================

# ── Internal state ─────────────────────────────────────────────────────────────
SC_DEFERRED=()
SC_SKIPPED=()
SC_RISK_TOLERANCE="${SC_RISK_TOLERANCE:-0}"

# ── Apply env shorthand ────────────────────────────────────────────────────────
[[ "${SC_ALLOW_RISKY:-0}" == "1" ]] && SC_RISK_TOLERANCE=3

# ── Non-interactive default: strict (safe methods only) ───────────────────────
# In CI/batch mode (no TTY), default to Strict unless overridden by env.
if [[ "$SC_RISK_TOLERANCE" == "0" ]] && [[ ! -t 0 ]]; then
    SC_RISK_TOLERANCE=1
fi

# ── Risk tolerance prompt ──────────────────────────────────────────────────────
# Call once at the start of an interactive install session.
# No-op if tolerance is already set or no TTY.
sc_set_risk_tolerance() {
    [[ "$SC_RISK_TOLERANCE" != "0" ]] && return 0
    [[ ! -t 0 ]] && { SC_RISK_TOLERANCE=1; return 0; }

    echo
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║  ⌁  SUPPLY CHAIN SECURITY POLICY            ║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${RESET}"
    echo
    echo -e "  This installer fetches packages from external sources."
    echo -e "  Some use ${RED}custom-domain curl|bash scripts${RESET} with no checksum verification."
    echo
    echo -e "  Select your risk policy for this session:\n"
    echo -e "  ${CYAN}[1]${RESET} ${BOLD}Strict${RESET}      — Package managers only (apt/brew/cargo)."
    echo -e "       ${DIM}Skips all custom-domain curl|bash scripts. Safest option.${RESET}"
    echo
    echo -e "  ${CYAN}[2]${RESET} ${BOLD}Balanced${RESET}    — Prefer safe methods; prompt on HIGH-risk packages."
    echo -e "       ${DIM}MEDIUM-risk installs proceed; HIGH-risk triggers a prompt.${RESET}"
    echo
    echo -e "  ${CYAN}[3]${RESET} ${BOLD}Permissive${RESET}  — Use original install methods. TLS enforced throughout."
    echo -e "       ${DIM}Fastest. Mirrors the pre-guard behavior. Matches SC_ALLOW_RISKY=1.${RESET}"
    echo
    echo -e "  ${CYAN}[4]${RESET} ${BOLD}Manual${RESET}      — Ask me about every risky package individually."
    echo -e "       ${DIM}Full control. Includes inspect/OSINT options per package.${RESET}"
    echo
    echo -en "${CYAN}  Policy [1-4, default=2]: ${RESET}"
    read -r _sc_tol
    case "$_sc_tol" in
        1) SC_RISK_TOLERANCE=1
           ok "Supply chain policy: Strict — no curl|bash scripts" ;;
        3) SC_RISK_TOLERANCE=3
           ok "Supply chain policy: Permissive — TLS-enforced, original methods" ;;
        4) SC_RISK_TOLERANCE=4
           ok "Supply chain policy: Manual — prompting per package" ;;
        *) SC_RISK_TOLERANCE=2
           ok "Supply chain policy: Balanced — safe-first, prompt on HIGH risk" ;;
    esac
    echo
}

# ── Core install dispatcher ────────────────────────────────────────────────────
# sc_install NAME RISK DESC SAFE_FN RISKY_FN GITHUB_URL SOURCE_URL
#
#   NAME        — binary name (used with is_installed check)
#   RISK        — low | medium | high
#   DESC        — human-readable description of the risk
#   SAFE_FN     — bash function name: safe install path (pkg mgr / cargo)
#   RISKY_FN    — bash function name: original install path (curl|bash etc.)
#   GITHUB_URL  — upstream source repo for OSINT/inspection
#   SOURCE_URL  — the actual download URL (shown in inspect mode)
sc_install() {
    local name="$1" risk="$2" desc="$3"
    local safe_fn="$4" risky_fn="$5"
    local github_url="${6:-}" source_url="${7:-}"

    # Skip if already installed
    if is_installed "$name"; then
        skip "$name already installed"
        return 0
    fi

    case "$SC_RISK_TOLERANCE" in
        1) # Strict: safe path only
            info "[strict] Installing $name via safe method"
            "$safe_fn" ;;

        2) # Balanced: safe for HIGH, original for MEDIUM/LOW
            if [[ "$risk" == "high" ]]; then
                warn "[balanced] HIGH-risk package — using safe method for $name"
                "$safe_fn"
            else
                "$risky_fn"
            fi ;;

        3) # Permissive: always use original method
            "$risky_fn" ;;

        4) # Manual: always prompt
            _sc_prompt "$name" "$risk" "$desc" "$safe_fn" "$risky_fn" \
                "$github_url" "$source_url" ;;
    esac
}

# ── Interactive per-package prompt ─────────────────────────────────────────────
_sc_prompt() {
    local name="$1" risk="$2" desc="$3"
    local safe_fn="$4" risky_fn="$5"
    local github_url="$6" source_url="$7"
    local risk_label risk_color

    case "$risk" in
        high)   risk_label="HIGH";   risk_color="${RED}" ;;
        medium) risk_label="MEDIUM"; risk_color="${YELLOW}" ;;
        low)    risk_label="LOW";    risk_color="${GREEN}" ;;
        *)      risk_label="UNKNOWN"; risk_color="${STEEL}" ;;
    esac

    echo
    echo -e "${BOLD}${CYAN}┌─ SUPPLY CHAIN DECISION: $name ─────────────────────${RESET}"
    echo -e "${BOLD}${CYAN}│${RESET} Risk: ${risk_color}${BOLD}$risk_label${RESET}"
    echo -e "${BOLD}${CYAN}│${RESET} $desc"
    [[ -n "$github_url" ]] && \
        echo -e "${BOLD}${CYAN}│${RESET} ${DIM}GitHub: $github_url${RESET}"
    echo -e "${BOLD}${CYAN}└──────────────────────────────────────────────────${RESET}"
    echo
    echo -e "  ${CYAN}[1]${RESET} Safe install    — use package manager or cargo"
    echo -e "  ${CYAN}[2]${RESET} Original method — ${risk_color}${risk_label}${RESET} risk (curl|bash or script)"
    echo -e "  ${CYAN}[3]${RESET} Skip            — install $name manually later"
    echo -e "  ${CYAN}[4]${RESET} Defer           — remind me at end of install"
    [[ -n "$source_url" ]] && \
        echo -e "  ${CYAN}[5]${RESET} Inspect / OSINT — show verification options"
    echo
    echo -en "${CYAN}  Decision [1-4${source_url:+/5}]: ${RESET}"
    read -r _sc_dec

    case "$_sc_dec" in
        1) "$safe_fn" ;;
        2) "$risky_fn" ;;
        3) SC_SKIPPED+=("$name")
           warn "Skipped: $name — install manually: $github_url" ;;
        4) SC_DEFERRED+=("$name|$desc|$safe_fn|$risky_fn|$github_url|$source_url")
           warn "Deferred: $name (will review before summary)" ;;
        5) [[ -n "$source_url" ]] && {
               _sc_inspect "$name" "$source_url" "$github_url" "$safe_fn"
               _sc_prompt "$name" "$risk" "$desc" "$safe_fn" "$risky_fn" \
                   "$github_url" "$source_url"
           } ;;
        *) SC_SKIPPED+=("$name")
           warn "No selection — skipping $name" ;;
    esac
}

# ── OSINT / inspection display ─────────────────────────────────────────────────
_sc_inspect() {
    local name="$1" source_url="$2" github_url="$3" safe_fn="$4"
    local tmp_inspect

    echo
    echo -e "${BOLD}${YELLOW}┌─ INSPECT: $name ─────────────────────────────────────${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET} Source URL  : ${CYAN}$source_url${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET} GitHub repo : ${CYAN}$github_url${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET} ${BOLD}Verification commands:${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET}   ${DIM}# Inspect script contents:${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET}   ${CYAN}curl --proto '=https' --tlsv1.2 -fsSL '$source_url' | less${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET}   ${DIM}# Compute SHA256 of install script:${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET}   ${CYAN}curl --proto '=https' --tlsv1.2 -fsSL '$source_url' | sha256sum${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET}   ${DIM}# Check HTTP headers (server, cert, redirects):${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET}   ${CYAN}curl --proto '=https' --tlsv1.2 -sI '$source_url' | head -20${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET}   ${DIM}# Check TLS certificate:${RESET}"

    local host
    host="$(echo "$source_url" | sed 's|https://||;s|/.*||')"
    echo -e "${BOLD}${YELLOW}│${RESET}   ${CYAN}echo | openssl s_client -connect '$host:443' 2>/dev/null | openssl x509 -noout -issuer -subject -dates${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET}"

    # Live SHA256 of the script
    echo -e "${BOLD}${YELLOW}│${RESET} ${BOLD}Live SHA256 (fetching now...):${RESET}"
    local actual_hash
    if actual_hash=$(curl --proto '=https' --tlsv1.2 -fsSL --max-time 10 "$source_url" 2>/dev/null \
            | sha256sum | awk '{print $1}'); then
        echo -e "${BOLD}${YELLOW}│${RESET}   ${GREEN}$actual_hash${RESET}"
        echo -e "${BOLD}${YELLOW}│${RESET}   ${DIM}Record this hash. If it changes on re-run, the script was modified.${RESET}"
        _log "INFO" "sc_inspect: $name SHA256=$actual_hash from $source_url"
    else
        echo -e "${BOLD}${YELLOW}│${RESET}   ${RED}Could not fetch script for hashing.${RESET}"
    fi
    echo -e "${BOLD}${YELLOW}│${RESET}"
    echo -e "${BOLD}${YELLOW}│${RESET} ${BOLD}Safe alternative:${RESET} call '${safe_fn}' (package manager / cargo)"
    echo -e "${BOLD}${YELLOW}└──────────────────────────────────────────────────────${RESET}"
    echo

    ask_yes_no "Open script in less for manual review?" && {
        tmp_inspect="$(download_to_tmp "$source_url" "${name}-inspect-XXXXXX.sh")"
        "${PAGER:-less}" "$tmp_inspect" || true
        rm -f "$tmp_inspect"
    } || true
}

# ── Process deferred packages ──────────────────────────────────────────────────
# Call this before print_summary to give the user one last chance.
sc_process_deferred() {
    [[ ${#SC_DEFERRED[@]} -eq 0 ]] && return 0

    banner "DEFERRED PACKAGE REVIEW"
    echo -e "  ${YELLOW}${#SC_DEFERRED[@]} package(s) were deferred. Review now:${RESET}\n"

    local saved_tolerance="$SC_RISK_TOLERANCE"
    SC_RISK_TOLERANCE=4  # Force manual prompt for each

    for entry in "${SC_DEFERRED[@]}"; do
        local name="${entry%%|*}"
        local rest="${entry#*|}"
        local ddesc="${rest%%|*}"; rest="${rest#*|}"
        local sfn="${rest%%|*}"; rest="${rest#*|}"
        local rfn="${rest%%|*}"; rest="${rest#*|}"
        local gurl="${rest%%|*}"
        local surl="${rest#*|}"

        if is_installed "$name"; then
            ok "$name already installed (deferred, now present)"
            continue
        fi

        _sc_prompt "$name" "deferred" "$ddesc" "$sfn" "$rfn" "$gurl" "$surl"
    done

    SC_RISK_TOLERANCE="$saved_tolerance"
    SC_DEFERRED=()
}

# ── Supply chain summary ───────────────────────────────────────────────────────
# Call this inside or after print_summary.
sc_summary() {
    local has_output=false

    if [[ ${#SC_SKIPPED[@]} -gt 0 ]]; then
        has_output=true
        echo -e "\n${BOLD}${YELLOW}  SUPPLY CHAIN — SKIPPED PACKAGES:${RESET}"
        for s in "${SC_SKIPPED[@]}"; do
            echo -e "    ${YELLOW}[⊘]${RESET} $s"
        done
        echo -e "  ${DIM}Install these manually or re-run with SC_RISK_TOLERANCE=3 to allow risky methods.${RESET}"
    fi

    if [[ ${#SC_DEFERRED[@]} -gt 0 ]]; then
        has_output=true
        echo -e "\n${BOLD}${YELLOW}  SUPPLY CHAIN — STILL DEFERRED:${RESET}"
        for entry in "${SC_DEFERRED[@]}"; do
            local name="${entry%%|*}"
            echo -e "    ${YELLOW}[⊙]${RESET} $name"
        done
    fi

    "$has_output" && echo || true
}
