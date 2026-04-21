#!/usr/bin/awk -f
# scripts/lib/sweep-zscaler.awk
#
# Strips old Zscaler config regions from shell rc files.
# Output: cleaned content (stdout), region metadata (stderr).
# Stderr format: "REGION <start_line> <end_line>"
#
# Design rules (per spec):
#   - Regions are ONLY identified at depth 0. Zscaler variables inside a user
#     function or other control structure are preserved intact (TC3).
#   - Region types:
#       1. Marker-bounded: # BEGIN terminal-kniferoll zscaler … # END …
#       2. Organic: ZSC_PEM_LINUX=, ZSC_PEM_MAC=, ZSC_PEM=, export <known_var>=
#   - Organic regions extend across blank lines (buffered) and control structures
#     that open AND close entirely within the Zscaler context.
#   - Trailing blank lines before the first "other" line are emitted back (kept).
#   - Multiple regions per file are all stripped in a single pass.

# ── Classifiers ──────────────────────────────────────────────────────────────

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
    # Extends (but does not start) an organic region.
    # Zscaler-themed comments after they've been preceded by a trigger.
    return (line ~ /^[[:space:]]*#.*[Zz]scaler/ && !is_marker_begin(line) && !is_marker_end(line))
}

function is_blank(line) {
    return (line ~ /^[[:space:]]*$/)
}

function is_control_open(line) {
    # if/for/while/until/case block openers
    if (line ~ /^[[:space:]]*(if|for|while|until|case)[[:space:]([]/) return 1
    # function name { or function name() {
    if (line ~ /^[[:space:]]*function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[({]/) return 1
    # POSIX-style func() {
    if (line ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*(\{|$)/) return 1
    # bare { at start of line
    if (line ~ /^[[:space:]]*\{[[:space:]]*(#.*)?$/) return 1
    return 0
}

function is_control_close(line) {
    if (line ~ /^[[:space:]]*(fi|esac|done)[[:space:]]*(;[[:space:]]*(#.*)?)?$/) return 1
    if (line ~ /^[[:space:]]*\}[[:space:]]*(#.*)?$/) return 1
    return 0
}

# ── State ────────────────────────────────────────────────────────────────────

BEGIN {
    in_region  = 0   # 1 while inside any Zscaler region
    in_marker  = 0   # 1 when inside a BEGIN/END marker region
    depth      = 0   # nesting depth for control structures
    rstart     = 0   # line number where current region began
    pend_buf   = ""  # buffered blank lines (pending flush decision)
    pend_cnt   = 0   # count of buffered blank lines
}

# ── Main rule ────────────────────────────────────────────────────────────────

{
    line = $0

    # ── NORMAL MODE ──────────────────────────────────────────────────────────
    if (!in_region) {

        # Check for region start BEFORE updating depth (so depth==0 test is
        # relative to the line *before* any opener on this line).
        if (depth == 0) {
            if (is_marker_begin(line)) {
                in_region = 1; in_marker = 1
                rstart = NR; pend_buf = ""; pend_cnt = 0
                next
            }
            if (is_region_trigger(line)) {
                in_region = 1; in_marker = 0
                rstart = NR; pend_buf = ""; pend_cnt = 0
                next
            }
        }

        # Update depth then emit.
        if (is_control_open(line))                    depth++
        else if (is_control_close(line) && depth > 0) depth--
        print line
        next
    }

    # ── MARKER REGION MODE ───────────────────────────────────────────────────
    if (in_marker) {
        if (is_marker_end(line)) {
            print "REGION " rstart " " NR > "/dev/stderr"
            in_region = 0; in_marker = 0
        }
        # Every line inside the marker block (including END itself) is stripped.
        next
    }

    # ── ORGANIC REGION MODE ──────────────────────────────────────────────────

    # Blank lines: buffer — we don't yet know if they're inside the region or
    # trailing whitespace that belongs to the user.
    if (is_blank(line)) {
        pend_buf = pend_buf line "\n"
        pend_cnt++
        next
    }

    # Non-blank line inside organic region.

    if (depth > 0) {
        # We're inside a control structure that was opened inside this region.
        # Track depth, discard buffered blanks, strip this line.
        if (is_control_open(line))                    depth++
        else if (is_control_close(line) && depth > 0) depth--
        pend_buf = ""; pend_cnt = 0
        next
    }

    # depth == 0.

    if (is_region_trigger(line) || is_zsc_extend(line)) {
        # Still squarely in region — discard buffered blanks and continue.
        pend_buf = ""; pend_cnt = 0
        next
    }

    if (is_control_open(line)) {
        # Control structure starts at depth 0 inside the region.
        # The buffered blanks are adjacent to Zscaler content → discard them.
        pend_buf = ""; pend_cnt = 0
        depth++
        next
    }

    # ── "Other" line at depth 0 → end the organic region ────────────────────
    # The region ends at the last actual Zscaler/control line, NOT at the
    # pending blank lines (those belong to the user).
    print "REGION " rstart " " (NR - 1 - pend_cnt) > "/dev/stderr"
    in_region = 0

    # Flush pending blanks back as user content.
    if (pend_cnt > 0) {
        printf "%s", pend_buf
        pend_buf = ""; pend_cnt = 0
    }

    # Check if this "other" line itself opens a new region (handles TC6 where
    # the old organic block ends exactly where the marker block begins).
    if (is_marker_begin(line)) {
        in_region = 1; in_marker = 1
        rstart = NR; pend_buf = ""; pend_cnt = 0
        next
    }
    if (is_region_trigger(line)) {
        in_region = 1; in_marker = 0
        rstart = NR; pend_buf = ""; pend_cnt = 0
        next
    }

    # Regular "other" line — update depth and emit.
    if (is_control_open(line))                    depth++
    else if (is_control_close(line) && depth > 0) depth--
    print line
}

# ── EOF handler ──────────────────────────────────────────────────────────────

END {
    if (in_region) {
        # Region that extended to end-of-file (no trailing "other" line).
        print "REGION " rstart " " NR > "/dev/stderr"
    } else if (pend_cnt > 0) {
        # Trailing blank lines that were buffered but never flushed
        # (shouldn't arise in normal flow, but emit them to be safe).
        printf "%s", pend_buf
    }
}
