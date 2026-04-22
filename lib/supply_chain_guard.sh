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
# Always runs in strict mode: package managers only, no curl|bash scripts.
# =============================================================================

# ── Internal state ─────────────────────────────────────────────────────────────
SC_DEFERRED=()
SC_SKIPPED=()
SC_RISK_TOLERANCE=1  # Always strict: package managers only

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

    # Strict: safe path only (package managers / cargo)
    info "[strict] Installing $name via safe method"
    "$safe_fn"
}

# ── Process deferred packages ──────────────────────────────────────────────────
# No-op in strict mode: SC_RISK_TOLERANCE=1 means sc_install always calls the
# safe function directly — SC_DEFERRED is never populated. Stub kept so call
# sites in installers don't need to be patched.
sc_process_deferred() {
    [[ ${#SC_DEFERRED[@]} -eq 0 ]] && return 0
    # Should not be reached in normal operation; drain silently.
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
