#!/usr/bin/env bash
# scripts/test-sweep.sh — 10-TC unit test suite for scripts/lib/sweep-zscaler.*
#
# Usage: bash scripts/test-sweep.sh
# Exit 0 if all tests pass; exit 1 if any fail.
#
# Tests the spec-compliant awk parser + shell wrapper:
#   - scripts/lib/sweep-zscaler.awk  (depth-0-only state machine)
#   - scripts/lib/sweep-zscaler.sh   (wrapper: backup, dry-run, cmp check)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Stub installer helpers required by sweep-zscaler.sh ──────────────────────
ok()     { :; }
warn()   { :; }
info()   { :; }
skip()   { :; }
banner() { :; }

# shellcheck source=scripts/lib/sweep-zscaler.sh
source "$SCRIPT_DIR/scripts/lib/sweep-zscaler.sh"

# ── Test framework ────────────────────────────────────────────────────────────
PASS=0
FAIL=0

assert_contains() {
    local label="$1" file="$2" pattern="$3"
    if grep -Eq "$pattern" "$file"; then
        echo "  PASS: $label"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: $label"
        echo "        pattern not found: $pattern"
        echo "        file content:"
        sed 's/^/          /' "$file"
        FAIL=$(( FAIL + 1 ))
    fi
}

assert_not_contains() {
    local label="$1" file="$2" pattern="$3"
    if ! grep -Eq "$pattern" "$file"; then
        echo "  PASS: $label"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: $label"
        echo "        unexpected pattern still present: $pattern"
        echo "        file content:"
        sed 's/^/          /' "$file"
        FAIL=$(( FAIL + 1 ))
    fi
}

assert_equal() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $label (value=$actual)"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: $label (expected='$expected', got='$actual')"
        FAIL=$(( FAIL + 1 ))
    fi
}

# ── Temp dir ──────────────────────────────────────────────────────────────────
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ── TC1: Old broken block alone → stripped, marker appended ──────────────────
echo ""
echo "=== TC1: old bare-assignment block → stripped, marker appended ==="
T1="$TMPDIR_TEST/tc1.zshrc"
cat > "$T1" << 'EOF'
ZSC_PEM_LINUX="/usr/share/ca-certificates/zscaler.pem"
ZSC_PEM_MAC="/usr/local/share/ca-certificates/zscaler.pem"

if [[ -f "$ZSC_PEM_LINUX" ]]; then
    export ZSC_PEM="$ZSC_PEM_LINUX"
elif [[ -f "$ZSC_PEM_MAC" ]]; then
    export ZSC_PEM="$ZSC_PEM_MAC"
fi

export CURL_CA_BUNDLE="$ZSC_PEM"
export GIT_SSL_CAINFO="$ZSC_PEM"
export SSL_CERT_FILE="$ZSC_PEM"
export REQUESTS_CA_BUNDLE="$ZSC_PEM"
export NODE_EXTRA_CA_CERTS="$ZSC_PEM"
export AWS_CA_BUNDLE="$ZSC_PEM"
export PIP_CERT="$ZSC_PEM"
export HOMEBREW_CURLOPT_CACERT="$ZSC_PEM"
EOF

_sw_upsert_one "$T1" false
assert_not_contains "TC1: ZSC_PEM_LINUX removed"  "$T1" "ZSC_PEM_LINUX"
assert_not_contains "TC1: CURL_CA_BUNDLE removed" "$T1" "CURL_CA_BUNDLE"
assert_not_contains "TC1: orphaned if removed"    "$T1" "^if \[\["
assert_contains     "TC1: marker appended"        "$T1" "BEGIN terminal-kniferoll zscaler"
assert_contains     "TC1: source line present"    "$T1" "zscaler-env\.sh"

# ── TC2: Old block + user aliases below → user content preserved ──────────────
echo ""
echo "=== TC2: old block + user content below → user content preserved ==="
T2="$TMPDIR_TEST/tc2.zshrc"
cat > "$T2" << 'EOF'
export EDITOR=vim

ZSC_PEM_LINUX="/usr/share/ca-certificates/zscaler.pem"
ZSC_PEM_MAC="/usr/local/share/ca-certificates/zscaler.pem"

if [[ -f "$ZSC_PEM_LINUX" ]]; then
    export ZSC_PEM="$ZSC_PEM_LINUX"
elif [[ -f "$ZSC_PEM_MAC" ]]; then
    export ZSC_PEM="$ZSC_PEM_MAC"
fi

export CURL_CA_BUNDLE="$ZSC_PEM"
export SSL_CERT_FILE="$ZSC_PEM"

alias gst='git status'
alias ll='ls -la'
export PATH="$HOME/.local/bin:$PATH"
EOF

_sw_upsert_one "$T2" false
assert_not_contains "TC2: ZSC_PEM_LINUX removed"  "$T2" "ZSC_PEM_LINUX"
assert_not_contains "TC2: CURL_CA_BUNDLE removed" "$T2" "CURL_CA_BUNDLE"
assert_contains     "TC2: EDITOR preserved"       "$T2" "EDITOR=vim"
assert_contains     "TC2: alias gst preserved"    "$T2" "alias gst"
assert_contains     "TC2: PATH preserved"         "$T2" 'PATH=.*\.local/bin'
assert_contains     "TC2: marker appended"        "$T2" "BEGIN terminal-kniferoll zscaler"

# ── TC3: Old block wrapped inside a user function → preserved untouched ───────
echo ""
echo "=== TC3: Zscaler inside user function → full function body preserved ==="
T3="$TMPDIR_TEST/tc3.zshrc"
cat > "$T3" << 'EOF'
export EDITOR=vim

# User wrote this function — must not be touched
setup_corp_certs() {
    ZSC_PEM_MAC="/Users/Shared/.certificates/zscaler.pem"
    if [[ -s "$ZSC_PEM_MAC" ]]; then
        export ZSC_PEM="$ZSC_PEM_MAC"
        export CURL_CA_BUNDLE="$ZSC_PEM"
        export SSL_CERT_FILE="$ZSC_PEM"
    fi
}
setup_corp_certs

export PAGER=less
EOF

_sw_upsert_one "$T3" false
assert_contains "TC3: function name preserved"        "$T3" "setup_corp_certs"
assert_contains "TC3: function body ZSC_PEM intact"  "$T3" "ZSC_PEM_MAC"
assert_contains "TC3: CURL_CA_BUNDLE inside fn kept" "$T3" "CURL_CA_BUNDLE"
assert_contains "TC3: closing } preserved"           "$T3" "^}"
assert_contains "TC3: EDITOR preserved"              "$T3" "EDITOR=vim"
assert_contains "TC3: PAGER preserved"               "$T3" "PAGER=less"
assert_contains "TC3: marker appended"               "$T3" "BEGIN terminal-kniferoll zscaler"

# ── TC4: Two old blocks separated by user content → both removed, user kept ───
echo ""
echo "=== TC4: two old blocks separated by user content → both removed ==="
T4="$TMPDIR_TEST/tc4.zshrc"
cat > "$T4" << 'EOF'
# first old block
ZSC_PEM_MAC="/Users/Shared/.certificates/zscaler.pem"
export CURL_CA_BUNDLE="$ZSC_PEM_MAC"

export EDITOR=vim

# second block (managed marker)
# BEGIN terminal-kniferoll zscaler — DO NOT EDIT (managed by installer)
[ -r "$HOME/.config/terminal-kniferoll/zscaler-env.sh" ] && \
    . "$HOME/.config/terminal-kniferoll/zscaler-env.sh"
# END terminal-kniferoll zscaler

export PAGER=less
EOF

_sw_upsert_one "$T4" false
assert_not_contains "TC4: ZSC_PEM_MAC removed"    "$T4" "ZSC_PEM_MAC"
assert_not_contains "TC4: CURL_CA_BUNDLE removed" "$T4" "CURL_CA_BUNDLE"
_tc4_markers=$(grep -c "BEGIN terminal-kniferoll zscaler" "$T4" || true)
assert_equal        "TC4: exactly one marker"     "1" "$_tc4_markers"
assert_contains     "TC4: EDITOR preserved"       "$T4" "EDITOR=vim"
assert_contains     "TC4: PAGER preserved"        "$T4" "PAGER=less"

# ── TC5: Only marker block present → no change (byte-identical) ───────────────
echo ""
echo "=== TC5: marker-only file → byte-identical, no rewrite, no backup ==="
T5="$TMPDIR_TEST/tc5.zshrc"
_sw_marker_block > "$T5"
cp "$T5" "${T5}.before"

_sw_upsert_one "$T5" false
if cmp -s "${T5}.before" "$T5"; then
    echo "  PASS: TC5: file is byte-identical after re-run"
    PASS=$(( PASS + 1 ))
else
    echo "  FAIL: TC5: file was rewritten when it should have been unchanged"
    FAIL=$(( FAIL + 1 ))
fi
_tc5_baks=$(ls -1 "$TMPDIR_TEST/tc5.zshrc.terminal-kniferoll-backup-"* 2>/dev/null | wc -l | tr -d ' ')
assert_equal "TC5: no backup created" "0" "$_tc5_baks"

# ── TC6: Old block + existing marker → old stripped, single marker remains ────
echo ""
echo "=== TC6: old block + existing marker → both stripped, one marker remains ==="
T6="$TMPDIR_TEST/tc6.zshrc"
cat > "$T6" << 'EOF'
export EDITOR=vim

ZSC_PEM_LINUX="/usr/share/ca-certificates/zscaler.pem"
export CURL_CA_BUNDLE="$ZSC_PEM_LINUX"

# BEGIN terminal-kniferoll zscaler — DO NOT EDIT (managed by installer)
[ -r "$HOME/.config/terminal-kniferoll/zscaler-env.sh" ] && \
    . "$HOME/.config/terminal-kniferoll/zscaler-env.sh"
# END terminal-kniferoll zscaler

export PAGER=less
EOF

_sw_upsert_one "$T6" false
assert_not_contains "TC6: ZSC_PEM_LINUX removed"  "$T6" "ZSC_PEM_LINUX"
assert_not_contains "TC6: CURL_CA_BUNDLE removed" "$T6" "CURL_CA_BUNDLE"
_tc6_markers=$(grep -c "BEGIN terminal-kniferoll zscaler" "$T6" || true)
assert_equal        "TC6: exactly one marker"     "1" "$_tc6_markers"
assert_contains     "TC6: EDITOR preserved"       "$T6" "EDITOR=vim"
assert_contains     "TC6: PAGER preserved"        "$T6" "PAGER=less"

# ── TC7: Unrelated Zscaler comment → preserved ────────────────────────────────
echo ""
echo "=== TC7: unrelated zscaler comment — preserved, no region started ==="
T7="$TMPDIR_TEST/tc7.zshrc"
cat > "$T7" << 'EOF'
# This machine is NOT a zscaler-managed device.
# zscaler.pem would be at /usr/share if it were.
alias ll='ls -la'
export EDITOR=vim
EOF

_sw_upsert_one "$T7" false
assert_contains "TC7: zscaler comment preserved" "$T7" "NOT a zscaler-managed"
assert_contains "TC7: second comment preserved"  "$T7" "zscaler\.pem would be"
assert_contains "TC7: alias preserved"           "$T7" "alias ll"
assert_contains "TC7: EDITOR preserved"          "$T7" "EDITOR=vim"

# ── TC8: Empty file → marker appended only ────────────────────────────────────
echo ""
echo "=== TC8: empty file → marker block appended ==="
T8="$TMPDIR_TEST/tc8.zshrc"
: > "$T8"

_sw_upsert_one "$T8" false
assert_contains     "TC8: marker appended"     "$T8" "BEGIN terminal-kniferoll zscaler"
assert_contains     "TC8: source line present" "$T8" "zscaler-env\.sh"
assert_not_contains "TC8: no ZSC_PEM vars"     "$T8" "^export ZSC_PEM"

# ── TC9: File with only shebang → marker appended after shebang ───────────────
echo ""
echo "=== TC9: shebang-only file → marker appended after shebang ==="
T9="$TMPDIR_TEST/tc9.zsh"
echo "#!/bin/zsh" > "$T9"

_sw_upsert_one "$T9" false
assert_contains "TC9: shebang preserved" "$T9" "^#!/bin/zsh"
assert_contains "TC9: marker appended"   "$T9" "BEGIN terminal-kniferoll zscaler"
_shebang_line=$(grep -n "#!/bin/zsh" "$T9" | cut -d: -f1)
_marker_line=$(grep -n "BEGIN terminal-kniferoll" "$T9" | cut -d: -f1)
if [[ "$_shebang_line" -lt "$_marker_line" ]]; then
    echo "  PASS: TC9: shebang (line $_shebang_line) before marker (line $_marker_line)"
    PASS=$(( PASS + 1 ))
else
    echo "  FAIL: TC9: shebang should be before marker (got shebang=$_shebang_line, marker=$_marker_line)"
    FAIL=$(( FAIL + 1 ))
fi

# ── TC10: Backup rotation — run 6 times, confirm only 5 backups remain ────────
echo ""
echo "=== TC10: backup rotation — 6 runs → exactly 5 backups remain ==="
T10="$TMPDIR_TEST/tc10.zshrc"
for _run in 1 2 3 4 5 6; do
    # Restore an old Zscaler block each run so there's always something to sweep
    cat > "$T10" << 'TCEOF'
ZSC_PEM_LINUX="/usr/share/ca-certificates/zscaler.pem"
export CURL_CA_BUNDLE="$ZSC_PEM_LINUX"
TCEOF
    _sw_upsert_one "$T10" false
    [[ $_run -lt 6 ]] && sleep 1
done
_bak_count=$(ls -1 "$TMPDIR_TEST/tc10.zshrc.terminal-kniferoll-backup-"* 2>/dev/null | wc -l | tr -d ' ')
assert_equal "TC10: exactly 5 backups remain" "5" "$_bak_count"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
echo "─────────────────────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
    echo "All tests passed."
    exit 0
else
    echo "FAILURES detected."
    exit 1
fi
