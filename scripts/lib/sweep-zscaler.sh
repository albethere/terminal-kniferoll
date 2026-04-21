#!/usr/bin/env bash
# scripts/lib/sweep-zscaler.sh
#
# Shell wrapper around scripts/lib/sweep-zscaler.awk.
# Source this from installer scripts; it provides:
#
#   sweep_zscaler_rc_files [--dry-run]
#       Sweep ~/.zshrc, ~/.zprofile, ~/.bashrc, ~/.bash_profile, ~/.profile.
#       --dry-run  Print preview without writing.
#
# Requires: ok(), warn(), info(), skip(), banner() from the calling installer.

_SW_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SW_AWK="$_SW_LIB/sweep-zscaler.awk"

_sw_marker_block() {
    cat << 'SWEOF'
# BEGIN terminal-kniferoll zscaler — DO NOT EDIT (managed by installer)
[ -r "$HOME/.config/terminal-kniferoll/zscaler-env.sh" ] && \
    . "$HOME/.config/terminal-kniferoll/zscaler-env.sh"
# END terminal-kniferoll zscaler
SWEOF
}

# ── Backup: timestamped copy, prune to 5 most recent per file ────────────────
_sw_backup() {
    local rc="$1"
    [[ -f "$rc" ]] || return 0
    local ts; ts="$(date '+%Y%m%d-%H%M%S')"
    local bak="${rc}.terminal-kniferoll-backup-${ts}"
    cp "$rc" "$bak"
    chmod 600 "$bak"
    # Prune: keep only 5 most recent.
    ls -t "${rc}.terminal-kniferoll-backup-"* 2>/dev/null | \
        tail -n +6 | while IFS= read -r _old; do rm -f "$_old"; done
    printf '%s' "$bak"   # return backup path to caller
}

# ── Sweep one rc file ─────────────────────────────────────────────────────────
_sw_upsert_one() {
    local rc="$1" dry_run="${2:-false}"

    [[ -f "$rc" ]] || return 0

    local tmp_clean tmp_regions tmp_final
    tmp_clean="$(mktemp)";   chmod 600 "$tmp_clean"
    tmp_regions="$(mktemp)"; chmod 600 "$tmp_regions"
    tmp_final="$(mktemp)";   chmod 600 "$tmp_final"

    # Run parser: cleaned content → tmp_clean, region metadata → tmp_regions
    awk -f "$_SW_AWK" "$rc" > "$tmp_clean" 2> "$tmp_regions"

    # Build final content: cleaned base + blank separator (only if non-empty) + marker block
    cat "$tmp_clean" > "$tmp_final"
    [[ -s "$tmp_final" ]] && echo >> "$tmp_final"
    _sw_marker_block >> "$tmp_final"
    rm -f "$tmp_clean"

    # Idempotency check: if result is byte-identical to original, skip (TC5).
    if cmp -s "$tmp_final" "$rc"; then
        rm -f "$tmp_regions" "$tmp_final"
        return 0
    fi

    # ── Diff preview ─────────────────────────────────────────────────────────
    echo "sweep: $rc"
    while IFS=' ' read -r _kw _start _end; do
        local cnt=$(( _end - _start + 1 ))
        echo "  - removing ${cnt} lines (Zscaler region at lines ${_start}-${_end})"
    done < "$tmp_regions"
    echo "  + appending 3 lines (marker block)"
    rm -f "$tmp_regions"

    if [[ "$dry_run" == "true" ]]; then
        rm -f "$tmp_final"
        return 0
    fi

    # ── Write ─────────────────────────────────────────────────────────────────
    local bak; bak="$(_sw_backup "$rc")"
    echo "  backup: $bak"
    mv -f "$tmp_final" "$rc"
    ok "  $rc — Zscaler block(s) swept"
}

# ── Public API ────────────────────────────────────────────────────────────────
sweep_zscaler_rc_files() {
    local dry_run=false
    [[ "${1:-}" == "--dry-run" ]] && dry_run=true

    banner "ZSCALER RC SWEEP"

    local _rc
    for _rc in \
        "$HOME/.zshrc" \
        "$HOME/.zprofile" \
        "$HOME/.bashrc" \
        "$HOME/.bash_profile" \
        "$HOME/.profile"
    do
        _sw_upsert_one "$_rc" "$dry_run"
    done
    unset _rc
}
