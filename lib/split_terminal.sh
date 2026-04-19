#!/usr/bin/env bash
# =============================================================================
# lib/split_terminal.sh — Split-terminal verbose output UI  (tk-022)
# =============================================================================
#
# Renders a dual-pane install view:
#
#   ┌── left panel (~65%) ──────────────────────┬── right panel (~35%) ────┐
#   │  clean progress output (ok/info/warn/skip) │ ┌─── VERBOSE LOG ──────┐ │
#   │  [✓] Installing nmap                       │ │ Setting up nmap ...  │ │
#   │  [→] Compiling weathr via cargo            │ │ Unpacking cargo ...  │ │
#   │                                            │ │ ...                  │ │
#   └────────────────────────────────────────────┘ └──────────────────────┘ │
#
# Public API (all are no-ops when ST_ENABLED=false):
#   st_init      — initialise split view; call once after the ASCII banner
#   st_log MSG   — append MSG to the verbose log (→ right panel)
#   st_cleanup   — kill background renderer, remove temp log, restore cursor
#
# Graceful fallback:
#   ST_ENABLED stays false when:
#     • stdout is not a TTY (non-interactive / CI / pipe)
#     • terminal width < 100 columns
#     • terminal height < 12 rows
#     • tput is unavailable
# =============================================================================

ST_ENABLED=false
ST_VERBOSE_LOG=""
ST_BG_PID=""
ST_TERM_ROWS=0
ST_TERM_COLS=0
ST_LEFT_W=0
ST_RIGHT_X=0
ST_RIGHT_W=0
ST_RIGHT_INNER_W=0

# ── st_init ───────────────────────────────────────────────────────────────────
# Detect terminal dimensions, draw the right-panel box, and start the
# background tail process.  Safe to call multiple times — second call is a
# no-op if already enabled.
st_init() {
    [[ "$ST_ENABLED" == "true" ]] && return 0   # already initialised
    [[ -t 1 && -t 0 ]] || return 0              # must be an interactive TTY
    command -v tput &>/dev/null || return 0     # need tput for positioning

    ST_TERM_COLS=$(tput cols  2>/dev/null || echo 0)
    ST_TERM_ROWS=$(tput lines 2>/dev/null || echo 0)

    # Minimum size check — needs room for both panels and the box chrome
    (( ST_TERM_COLS >= 100 && ST_TERM_ROWS >= 12 )) || return 0

    ST_ENABLED=true

    # Column layout: left 65%, right 35% (minus 1-col gutter each side)
    ST_LEFT_W=$(( ST_TERM_COLS * 65 / 100 ))
    ST_RIGHT_X=$(( ST_LEFT_W + 1 ))
    ST_RIGHT_W=$(( ST_TERM_COLS - ST_RIGHT_X ))
    ST_RIGHT_INNER_W=$(( ST_RIGHT_W - 2 ))  # width inside the │ borders

    # Secure temp log — all package-manager output is redirected here
    local old_umask; old_umask="$(umask)"
    umask 077
    ST_VERBOSE_LOG="$(mktemp /tmp/kniferoll-verbose-XXXXXX.log)"
    umask "$old_umask"
    chmod 600 "$ST_VERBOSE_LOG"

    _st_draw_box
    _st_start_tail
}

# ── _st_draw_box ──────────────────────────────────────────────────────────────
# Draw the Unicode box for the right panel.  Starts at row 1 so it doesn't
# overwrite the ASCII banner on row 0.
_st_draw_box() {
    local title=" VERBOSE LOG "
    local avail=$(( ST_RIGHT_W - 2 - ${#title} ))
    local dash_l=$(( avail / 2 ))
    local dash_r=$(( avail - dash_l ))
    local dashes_l dashes_r
    dashes_l="$(printf '%*s' $dash_l '' | tr ' ' '─')"
    dashes_r="$(printf '%*s' $dash_r '' | tr ' ' '─')"
    local inner_dashes
    inner_dashes="$(printf '%*s' $(( ST_RIGHT_W - 2 )) '' | tr ' ' '─')"

    # Top border (row 1)
    tput cup 1 $ST_RIGHT_X
    printf '┌%s%s%s┐' "$dashes_l" "$title" "$dashes_r"

    # Side borders + blank interior (rows 2 … ROWS-2)
    local row
    for (( row = 2; row < ST_TERM_ROWS - 1; row++ )); do
        tput cup $row $ST_RIGHT_X
        printf '│%*s│' $ST_RIGHT_INNER_W ''
    done

    # Bottom border
    tput cup $(( ST_TERM_ROWS - 1 )) $ST_RIGHT_X
    printf '└%s┘' "$inner_dashes"

    # Return cursor to left side so normal output continues unperturbed
    tput cup $(( ST_TERM_ROWS - 1 )) 0
}

# ── _st_start_tail ────────────────────────────────────────────────────────────
# Launch a background subshell that tails ST_VERBOSE_LOG and renders each new
# line into the right panel with scrolling and line-wrapping.
_st_start_tail() {
    # Capture panel geometry into locals so the subshell doesn't rely on
    # parent-scope vars (they may change after fork).
    local right_x=$ST_RIGHT_X
    local inner_w=$ST_RIGHT_INNER_W
    local term_rows=$ST_TERM_ROWS
    local start_row=2
    local max_row=$(( term_rows - 2 ))
    local verbose_log="$ST_VERBOSE_LOG"

    (
        local row=$start_row

        while IFS= read -r raw_line; do
            # Scroll: when we've filled the panel, clear and restart from top
            if (( row >= max_row )); then
                local r
                for (( r = start_row; r < max_row; r++ )); do
                    tput cup $r $(( right_x + 1 ))
                    printf '%*s' $inner_w ''
                done
                row=$start_row
            fi

            # Strip ANSI colour codes so the right panel stays readable
            local plain
            plain="$(printf '%s' "$raw_line" \
                | sed 's/\x1b\[[0-9;]*[mKJHfABCDsu]//g')"

            # Truncate to inner panel width
            local truncated="${plain:0:$inner_w}"

            tput cup $row $(( right_x + 1 ))
            printf '%-*s' $inner_w "$truncated"
            (( row++ ))

            # Return cursor to bottom-left of the left panel so normal
            # terminal output from the parent continues at the right place
            tput cup $(( term_rows - 1 )) 0
        done < <(tail -n 0 -f "$verbose_log" 2>/dev/null)
    ) &
    ST_BG_PID=$!
}

# ── st_log ────────────────────────────────────────────────────────────────────
# Append MSG to the verbose log, which the background process picks up.
# Package-manager commands should pipe / redirect their output through here:
#
#   sudo apt-get install ... 2>&1 | tee -a "$ST_VERBOSE_LOG" | grep ...
#   cargo build             2>&1 >> "$ST_VERBOSE_LOG"
#
# Direct string calls are also fine for one-liners:
#
#   st_log "Starting cargo install for weathr..."
st_log() {
    [[ "$ST_ENABLED" == "true" && -n "$ST_VERBOSE_LOG" ]] || return 0
    printf '%s\n' "$*" >> "$ST_VERBOSE_LOG"
}

# ── st_cleanup ────────────────────────────────────────────────────────────────
# Tear down the background renderer, remove the temp log, and move the cursor
# to a clean position below the install output.  Safe to call multiple times.
st_cleanup() {
    [[ "$ST_ENABLED" == "true" ]] || return 0
    ST_ENABLED=false

    if [[ -n "$ST_BG_PID" ]]; then
        kill "$ST_BG_PID" 2>/dev/null || true
        wait "$ST_BG_PID" 2>/dev/null || true
        ST_BG_PID=""
    fi

    [[ -n "$ST_VERBOSE_LOG" ]] && rm -f "$ST_VERBOSE_LOG"
    ST_VERBOSE_LOG=""

    # Move to a clean line so the summary output doesn't overwrite the box
    tput cup $(( ST_TERM_ROWS - 1 )) 0
    echo
}
