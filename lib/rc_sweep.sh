#!/usr/bin/env bash
# lib/rc_sweep.sh — RC file Zscaler block sweep utilities
#
# Sourced by install_mac.sh and install_linux.sh.
# Requires: ok(), warn(), info(), skip(), banner() from the calling installer.
#
# Public API:
#   sweep_rc_files [--dry-run]  — sweep all existing rc files
#   upsert_rc_zscaler_block     — upsert source line in one rc file
#   strip_zscaler_regions       — remove all Zscaler regions (stdout)
#   backup_rc_file              — timestamped backup + rotate to 5 max

# Locate sweep-zscaler.awk relative to this file regardless of cwd.
_rc_sweep_dir() { cd "$(dirname "${BASH_SOURCE[0]}")" && pwd; }

_sweep_awk_path() {
    local d; d="$(_rc_sweep_dir)"
    echo "${d}/../scripts/lib/sweep-zscaler.awk"
}

# ── Source-line block ─────────────────────────────────────────────────────────
_zscaler_source_block() {
    printf '%s\n' \
        '# BEGIN terminal-kniferoll zscaler — DO NOT EDIT (managed by installer)' \
        '[ -r "$HOME/.config/terminal-kniferoll/zscaler-env.sh" ] && \' \
        '    . "$HOME/.config/terminal-kniferoll/zscaler-env.sh"' \
        '# END terminal-kniferoll zscaler'
}

# ── Backup: timestamped copy, keep 5 most recent per file ────────────────────
backup_rc_file() {
    local rc="$1"
    [[ ! -f "$rc" ]] && return 0
    local ts; ts="$(date '+%Y%m%d-%H%M%S')"
    local backup="${rc}.terminal-kniferoll-backup-${ts}"
    cp "$rc" "$backup"
    chmod 600 "$backup"
    # Prune: keep only 5 most recent backups for this rc file
    local dir base
    dir="$(dirname "$rc")"
    base="$(basename "$rc")"
    ls -t "${dir}/${base}.terminal-kniferoll-backup-"* 2>/dev/null | \
        tail -n +6 | while IFS= read -r _old; do rm -f "$_old"; done
    ok "  backup: $backup"
}

# ── AWK state-machine: strip all Zscaler regions, print kept lines ───────────
strip_zscaler_regions() {
    local file="$1"
    local awk_script result
    awk_script="$(_sweep_awk_path)"
    if [[ ! -f "$awk_script" ]]; then
        warn "sweep-zscaler.awk not found at $awk_script — skipping strip"
        cat "$file"
        return 1
    fi
    # Capture output separately; on awk parse error fall back to original file
    if result="$(awk -f "$awk_script" "$file" 2>/tmp/sweep-awk-err$$)"; then
        printf '%s\n' "$result"
    else
        warn "sweep-zscaler.awk error ($file): $(cat /tmp/sweep-awk-err$$ | head -1)"
        rm -f /tmp/sweep-awk-err$$
        cat "$file"
        return 1
    fi
    rm -f /tmp/sweep-awk-err$$
}

# ── Quick check: does file contain any old Zscaler block? ────────────────────
_has_zscaler_block() {
    grep -Eq \
        'ZSC_PEM_LINUX[[:space:]]*=|ZSC_PEM_MAC[[:space:]]*=|^[[:space:]]*unset[[:space:]]+ZSC_PEM|^[[:space:]]*(export[[:space:]]+)?ZSC_PEM[[:space:]]*=|^[[:space:]]*export[[:space:]]+(CURL_CA_BUNDLE|SSL_CERT_FILE|REQUESTS_CA_BUNDLE|NODE_EXTRA_CA_CERTS|GIT_SSL_CAINFO|AWS_CA_BUNDLE|PIP_CERT|HOMEBREW_CURLOPT_CACERT)[[:space:]]*=|# BEGIN terminal-kniferoll zscaler' \
        "$1" 2>/dev/null
}

# ── Diff preview before write ─────────────────────────────────────────────────
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

# ── Upsert Zscaler source-line block in one rc file ──────────────────────────
#
# On every run: strip all Zscaler regions, then append the canonical block.
# This converges new format, old format, mixed, and multiple old blocks to a
# single clean state. Skips files that are already clean (no Zscaler content).
upsert_rc_zscaler_block() {
    local rc="$1" dry="${2:-}"
    [[ ! -f "$rc" ]] && return 0

    local _blk; _blk="$(mktemp)"
    _zscaler_source_block > "$_blk"

    if _has_zscaler_block "$rc"; then
        _show_sweep_preview "$rc" "$dry"
        [[ -n "$dry" ]] && { rm -f "$_blk"; return 0; }
        backup_rc_file "$rc"
        local _stripped; _stripped="$(mktemp)"; chmod 600 "$_stripped"
        strip_zscaler_regions "$rc" > "$_stripped"
        local _tmp; _tmp="$(mktemp)"; chmod 600 "$_tmp"
        # Only add a blank separator if the stripped content is non-empty
        local _stripped_content
        _stripped_content="$(cat "$_stripped")"
        if [[ -n "$_stripped_content" ]]; then
            { printf '%s\n' "$_stripped_content"; echo; cat "$_blk"; } > "$_tmp"
        else
            cat "$_blk" > "$_tmp"
        fi
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

# ── Sweep all existing shell rc files ────────────────────────────────────────
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

# ──────────────────────────────────────────────────────────────────────────────
# DEPRECATED-TOOL RC SWEEP
# ──────────────────────────────────────────────────────────────────────────────
# Tools we no longer install. On every run, sweep their profile entries clean.
#
# Marker convention: any tool that wrote profile lines fenced as
#     # BEGIN terminal-kniferoll <name> — DO NOT EDIT (managed by installer)
#     ...content...
#     # END terminal-kniferoll <name>
# is auto-sweepable when its name is added to KNIFEROLL_DEPRECATED_TOOLS.
# To deprecate a new tool: add the name to the array below AND add a case arm
# to _deprecated_tool_pattern with a regex that matches its raw init line(s).
# ──────────────────────────────────────────────────────────────────────────────

KNIFEROLL_DEPRECATED_TOOLS=(atuin)

# Anchored regex matching the tool's standalone raw init line.
# Anchoring with ^[[:space:]]*<keyword> excludes commented lines (# eval ...).
_deprecated_tool_pattern() {
    case "$1" in
        atuin) printf '%s' '^[[:space:]]*eval[[:space:]].*atuin[[:space:]]+init' ;;
        *)     printf '' ;;
    esac
}

# Legacy back-compat: catches the wrapped form scrubbed by the prior broken sed.
# Anchored to start-of-line (with optional `if` prefix) so comments survive.
_deprecated_tool_legacy_pattern() {
    case "$1" in
        atuin) printf '%s' '^[[:space:]]*(if[[:space:]]+)?command -v atuin.*atuin init' ;;
        *)     printf '' ;;
    esac
}

_sweep_deprecated_tool_in_file() {
    local tool="$1" rc="$2"
    [[ -f "$rc" ]] || return 1
    local raw_re legacy_re begin_re end_re
    raw_re="$(_deprecated_tool_pattern "$tool")"
    legacy_re="$(_deprecated_tool_legacy_pattern "$tool")"
    begin_re="^# BEGIN terminal-kniferoll ${tool}"
    end_re="^# END terminal-kniferoll ${tool}"

    # Idempotency guard — silent no-op if nothing matches.
    if ! grep -Eq "${raw_re}|${legacy_re}|${begin_re}" "$rc" 2>/dev/null; then
        return 1
    fi

    backup_rc_file "$rc"
    local tmp; tmp="$(mktemp)"; chmod 600 "$tmp"
    awk -v B="$begin_re" -v E="$end_re" -v R="$raw_re" -v L="$legacy_re" '
        BEGIN { in_block = 0 }
        {
            if (in_block) { if ($0 ~ E) in_block = 0; next }
            if ($0 ~ B)   { in_block = 1; next }
            if (R != "" && $0 ~ R) next
            if (L != "" && $0 ~ L) next
            print
        }
    ' "$rc" > "$tmp"
    mv -f "$tmp" "$rc"
    info "[~] cleaned: removed orphaned ${tool} entry from ${rc}"
    return 0
}

sweep_deprecated_tools() {
    banner "DEPRECATED-TOOL RC SWEEP"
    local tool rc any=false
    local rc_files=(
        "$HOME/.zshrc"
        "$HOME/.bashrc"
        "$HOME/.zprofile"
        "$HOME/.bash_profile"
        "$HOME/.profile"
    )
    for tool in "${KNIFEROLL_DEPRECATED_TOOLS[@]}"; do
        for rc in "${rc_files[@]}"; do
            if _sweep_deprecated_tool_in_file "$tool" "$rc"; then
                any=true
            fi
        done
    done
    if ! $any; then
        skip "no orphaned deprecated-tool entries found"
    fi
}
