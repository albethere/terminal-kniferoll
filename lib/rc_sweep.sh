#!/usr/bin/env bash
# lib/rc_sweep.sh — RC file Zscaler block sweep utilities
#
# Sourced by install_mac.sh and install_linux.sh.
# Requires: ok(), warn(), info(), skip(), banner() from the calling installer.
#
# Public API:
#   sweep_rc_files          — sweep all existing rc files
#   upsert_rc_zscaler_block — upsert source line in one rc file
#   strip_zscaler_regions   — remove all Zscaler regions (stdout)
#   backup_rc_file          — timestamped backup + rotate to 5 max

# ── Source-line block ─────────────────────────────────────────────────────────
_zscaler_source_block() {
    cat << 'SRCEOF'
# BEGIN terminal-kniferoll zscaler — DO NOT EDIT (managed by installer)
[ -r "$HOME/.config/terminal-kniferoll/zscaler-env.sh" ] && \
    . "$HOME/.config/terminal-kniferoll/zscaler-env.sh"
# END terminal-kniferoll zscaler
SRCEOF
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
    local dir; dir="$(dirname "$rc")"
    local base; base="$(basename "$rc")"
    ls -t "${dir}/${base}.terminal-kniferoll-backup-"* 2>/dev/null | \
        tail -n +6 | while IFS= read -r _old; do rm -f "$_old"; done
    ok "  backup: $backup"
}

# ── AWK state-machine: strip all Zscaler regions, print kept lines ───────────
#
# Algorithm:
#   - A "Zscaler region" starts when a TRIGGER line is seen (known patterns from
#     every past installer version: ZSC_PEM_LINUX=, ZSC_PEM_MAC=, ZSC_PEM=,
#     unset ZSC_PEM, if.*ZSC_PEM, # BEGIN terminal-kniferoll zscaler,
#     for _zsc_p in).
#
#   - One-line lookahead buffer (pending/pending_d): instead of printing each
#     non-trigger line immediately, it is held for one cycle. When the NEXT line
#     is a trigger AND the pending line opened the current depth level
#     (pending_d > 0, e.g. `if [[ "$OSTYPE" == darwin* ]]; then`), the opener
#     is also eaten and entry_depth is set to depth-before-opener so the entire
#     outer if/fi block is consumed. Otherwise pending is flushed (printed).
#
#   - Inside a region, depth is tracked (if/for/while/case push;
#     fi/done/esac/} pop). entry_depth is the depth at which the trigger fired.
#
#   - Region ends when:
#     (a) depth drops BELOW entry_depth — a closing brace/fi that belongs to
#         an OUTER structure. The closing line is emitted (kept).
#     (b) depth == entry_depth AND the current line is not Zscaler-related AND
#         not a structural close AND not elif/else — user content resumes.
#
#   - Blank lines at entry_depth are silently consumed (trailing blank cleanup).
#   - elif/else at entry_depth are eaten (branch of the Zscaler if block).
#   - Multiple regions in one file are all removed in a single pass.
strip_zscaler_regions() {
    local file="$1"
    awk '
    function is_trigger(line) {
        return (line ~ /ZSC_PEM_LINUX[[:space:]]*=/ ||
                line ~ /ZSC_PEM_MAC[[:space:]]*=/ ||
                line ~ /^[[:space:]]*(unset[[:space:]]+)?ZSC_PEM[[:space:]]*=/ ||
                line ~ /^[[:space:]]*unset[[:space:]]+ZSC_PEM[[:space:]]*(#.*)?$/ ||
                line ~ /^[[:space:]]*if[[:space:]].*ZSC_PEM/ ||
                line ~ /# BEGIN terminal-kniferoll zscaler/ ||
                line ~ /^[[:space:]]*for[[:space:]]+_zsc_p[[:space:]]+in/)
    }
    function is_zscaler_content(line) {
        return (line ~ /ZSC_PEM/ ||
                line ~ /CURL_CA_BUNDLE/ ||
                line ~ /SSL_CERT_FILE/ ||
                line ~ /REQUESTS_CA_BUNDLE/ ||
                line ~ /NODE_EXTRA_CA_CERTS/ ||
                line ~ /GIT_SSL_CAINFO/ ||
                line ~ /AWS_CA_BUNDLE/ ||
                line ~ /PIP_CERT/ ||
                line ~ /HOMEBREW_CURLOPT_CACERT/ ||
                line ~ /[Zz]scaler/)
    }
    function is_structural_close(line) {
        return (line ~ /^[[:space:]]*(fi|done|esac)[[:space:]]*(#.*)?$/ ||
                line ~ /^[[:space:]]*\}[[:space:]]*(#.*)?$/)
    }
    function depth_delta(line,    d) {
        d = 0
        if (line ~ /^[[:space:]]*(if|for|while|until)[[:space:]]/) d++
        if (line ~ /^[[:space:]]*case[[:space:]]/) d++
        # Opening brace at end of line (function body open)
        if (line ~ /\{[[:space:]]*(#.*)?$/ && line !~ /\{.*\}/) d++
        if (line ~ /^[[:space:]]*(fi|done|esac)[[:space:]]*(#.*)?$/) d--
        if (line ~ /^[[:space:]]*\}[[:space:]]*(#.*)?$/) d--
        return d
    }
    function is_ctrl_opener(line) {
        # Returns true only for control-flow block openers (if/for/while/until/case),
        # NOT function definitions — so function shells are preserved when their
        # internals contain a Zscaler trigger.
        return (line ~ /^[[:space:]]*(if|for|while|until|case)[[:space:]]/)
    }
    BEGIN { in_region = 0; depth = 0; entry_depth = 0; pending = ""; pending_d = 0 }
    {
        d = depth_delta($0)
        old_depth = depth

        if (!in_region) {
            depth += d
            if (depth < 0) depth = 0
            if (is_trigger($0)) {
                in_region = 1
                # One-line lookahead: if pending was a control-flow opener (if/for/…)
                # that immediately wraps this trigger, eat it and set entry_depth to
                # the depth before the opener. This handles the pattern:
                #   if [[ "$OSTYPE" == darwin* ]]; then
                #       ZSC_PEM_MAC="..."   ← trigger fires here
                # Function definitions are NOT eaten (their closing } is preserved).
                if (is_ctrl_opener(pending) && old_depth > 0) {
                    entry_depth = old_depth - pending_d
                } else {
                    if (pending != "") print pending
                    entry_depth = old_depth
                }
                pending = ""; pending_d = 0
            } else {
                if (pending != "") print pending
                pending = $0; pending_d = d
            }
        } else {
            depth += d
            if (depth < 0) depth = 0

            if (depth < entry_depth) {
                # Closing structure popped us BELOW entry — region ends.
                # The current line (}, fi, done) belongs to outer scope: emit it.
                in_region = 0
                print
            } else if (depth > entry_depth) {
                # Inside deeper structure — eat (part of Zscaler block)
            } else {
                # depth == entry_depth
                if ($0 ~ /^[[:space:]]*$/) {
                    # Blank line — silently consume (trailing blank cleanup)
                } else if (is_zscaler_content($0)) {
                    # Zscaler-related line — eat
                } else if (is_structural_close($0)) {
                    # fi/done/esac/} at entry_depth that closed the Zscaler if/for — eat
                } else if ($0 ~ /^[[:space:]]*elif[[:space:]]/ ||
                           $0 ~ /^[[:space:]]*else([[:space:]]|$)/) {
                    # elif/else continuation of a Zscaler if block — stay in region
                } else {
                    # Non-Zscaler, non-structural at entry_depth — region ends
                    in_region = 0
                    print
                    # Immediately check if this line starts a new region
                    if (is_trigger($0)) {
                        in_region   = 1
                        entry_depth = depth
                    }
                }
            }
        }
    }
    END { if (pending != "" && !in_region) print pending }
    ' "$file"
}

# ── Quick check: does file contain any old Zscaler block? ────────────────────
_has_zscaler_block() {
    grep -Eq \
        'ZSC_PEM_LINUX[[:space:]]*=|ZSC_PEM_MAC[[:space:]]*=|^[[:space:]]*unset[[:space:]]+ZSC_PEM|^[[:space:]]*(export[[:space:]]+)?ZSC_PEM[[:space:]]*=|# BEGIN terminal-kniferoll zscaler|^[[:space:]]*for[[:space:]]+_zsc_p[[:space:]]+in' \
        "$1" 2>/dev/null
}

# ── Diff preview before write ─────────────────────────────────────────────────
_show_sweep_preview() {
    local rc="$1"
    local lines_before lines_after removed_count
    lines_before=$(wc -l < "$rc")
    lines_after=$(strip_zscaler_regions "$rc" | wc -l)
    removed_count=$(( lines_before - lines_after ))
    info "  sweep: $rc"
    [[ $removed_count -gt 0 ]] && \
        info "  - removing ~${removed_count} lines (old Zscaler block)"
    info "  + appending 4 lines (new marker block)"
}

# ── Upsert Zscaler source-line block in one rc file ──────────────────────────
#
# Logic:
#   (A) File has any Zscaler-triggerable content → backup + strip + append
#   (B) File is clean                            → backup + append
#
# On every run, strip_zscaler_regions produces a clean base, then we append
# the canonical source block. This handles: new format, old format, mixed,
# multiple old blocks — all converge to the single clean state.
upsert_rc_zscaler_block() {
    local rc="$1"
    [[ ! -f "$rc" ]] && return 0

    local _blk; _blk="$(mktemp)"; _zscaler_source_block > "$_blk"

    if _has_zscaler_block "$rc"; then
        _show_sweep_preview "$rc"
        backup_rc_file "$rc"
        local _stripped; _stripped="$(mktemp)"; chmod 600 "$_stripped"
        strip_zscaler_regions "$rc" > "$_stripped"
        local _tmp; _tmp="$(mktemp)"; chmod 600 "$_tmp"
        { cat "$_stripped"; echo; cat "$_blk"; } > "$_tmp"
        mv -f "$_tmp" "$rc"
        rm -f "$_stripped"
        ok "$rc: Zscaler block(s) stripped and source block appended"
    else
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
    banner "ZSCALER RC SWEEP"
    local _rc
    for _rc in \
        "$HOME/.zshrc" \
        "$HOME/.zprofile" \
        "$HOME/.bashrc" \
        "$HOME/.bash_profile" \
        "$HOME/.profile"
    do
        [[ -f "$_rc" ]] && upsert_rc_zscaler_block "$_rc"
    done
    unset _rc
}
