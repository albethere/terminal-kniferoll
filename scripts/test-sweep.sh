#!/usr/bin/env bash
# scripts/test-sweep.sh — Unit tests for scripts/lib/sweep-zscaler.awk + lib/rc_sweep.sh
#
# Usage: bash scripts/test-sweep.sh
# Exit 0 if all tests pass; exit 1 if any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Stub helpers required by rc_sweep.sh ─────────────────────────────────────
ok()     { :; }
warn()   { echo "WARN: $*" >&2; }
info()   { :; }
skip()   { :; }
banner() { :; }

# shellcheck source=lib/rc_sweep.sh
source "$SCRIPT_DIR/lib/rc_sweep.sh"

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
        echo "        expected pattern: $pattern"
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

assert_line_count() {
    local label="$1" file="$2" pattern="$3" expected="$4"
    local got
    got=$(grep -Ec "$pattern" "$file" || true)
    if [[ "$got" -eq "$expected" ]]; then
        echo "  PASS: $label (count=$got)"
        PASS=$(( PASS + 1 ))
    else
        echo "  FAIL: $label (expected $expected, got $got)"
        echo "        file content:"
        sed 's/^/          /' "$file"
        FAIL=$(( FAIL + 1 ))
    fi
}

# ── Temp dir for test fixtures ────────────────────────────────────────────────
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# ═════════════════════════════════════════════════════════════════════════════
# TC1 — old block alone → stripped, marker appended
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC1: old block alone → stripped, marker appended ==="
TC1="$TMPDIR_TEST/tc1.zshrc"
cat > "$TC1" << 'EOF'
ZSC_PEM_LINUX="/usr/share/ca-certificates/zscaler.pem"
ZSC_PEM_MAC="/usr/local/share/ca-certificates/zscaler.pem"
if [[ -f "$ZSC_PEM_LINUX" ]]; then export ZSC_PEM="$ZSC_PEM_LINUX"
elif [[ -f "$ZSC_PEM_MAC" ]]; then export ZSC_PEM="$ZSC_PEM_MAC"
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
upsert_rc_zscaler_block "$TC1"
assert_not_contains "TC1: ZSC_PEM_LINUX removed"          "$TC1" "ZSC_PEM_LINUX"
assert_not_contains "TC1: ZSC_PEM_MAC removed"            "$TC1" "ZSC_PEM_MAC"
assert_not_contains "TC1: CURL_CA_BUNDLE raw removed"     "$TC1" 'CURL_CA_BUNDLE="\$ZSC_PEM"'
assert_contains     "TC1: marker appended"                "$TC1" "BEGIN terminal-kniferoll zscaler"
assert_contains     "TC1: source line present"            "$TC1" "zscaler-env\.sh"

# ═════════════════════════════════════════════════════════════════════════════
# TC2 — old block + user aliases/exports below → user preserved
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC2: old block + user aliases/exports below → user preserved ==="
TC2="$TMPDIR_TEST/tc2.zshrc"
cat > "$TC2" << 'EOF'
ZSC_PEM_LINUX="/usr/share/ca-certificates/zscaler.pem"
export CURL_CA_BUNDLE="$ZSC_PEM_LINUX"
export SSL_CERT_FILE="$ZSC_PEM_LINUX"

alias gst='git status'
alias ll='ls -la'
export EDITOR=vim
export PAGER=less
EOF
upsert_rc_zscaler_block "$TC2"
assert_not_contains "TC2: ZSC_PEM_LINUX removed"     "$TC2" "ZSC_PEM_LINUX"
assert_not_contains "TC2: CURL_CA_BUNDLE raw removed" "$TC2" 'CURL_CA_BUNDLE="\$ZSC_PEM'
assert_contains     "TC2: alias gst preserved"        "$TC2" "alias gst"
assert_contains     "TC2: alias ll preserved"         "$TC2" "alias ll"
assert_contains     "TC2: EDITOR preserved"           "$TC2" "EDITOR=vim"
assert_contains     "TC2: PAGER preserved"            "$TC2" "PAGER=less"
assert_contains     "TC2: marker appended"            "$TC2" "BEGIN terminal-kniferoll zscaler"

# ═════════════════════════════════════════════════════════════════════════════
# TC3 — old block inside user function → preserved untouched
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC3: old block inside user function → preserved untouched ==="
TC3="$TMPDIR_TEST/tc3.zshrc"
cat > "$TC3" << 'EOF'
# User-defined corp proxy setup — called explicitly
corp_proxy_setup() {
    ZSC_PEM_LINUX="/etc/ssl/certs/zscaler.pem"
    if [[ -f "$ZSC_PEM_LINUX" ]]; then
        export ZSC_PEM="$ZSC_PEM_LINUX"
        export CURL_CA_BUNDLE="$ZSC_PEM"
        export SSL_CERT_FILE="$ZSC_PEM"
    fi
}
export EDITOR=vim
EOF
upsert_rc_zscaler_block "$TC3"
assert_contains     "TC3: function name preserved"        "$TC3" "corp_proxy_setup"
assert_contains     "TC3: ZSC_PEM_LINUX preserved"        "$TC3" "ZSC_PEM_LINUX"
assert_contains     "TC3: CURL_CA_BUNDLE inside preserved" "$TC3" "CURL_CA_BUNDLE"
assert_contains     "TC3: closing brace preserved"        "$TC3" "^}"
assert_contains     "TC3: EDITOR preserved"               "$TC3" "EDITOR=vim"
assert_contains     "TC3: marker appended"                "$TC3" "BEGIN terminal-kniferoll zscaler"

# ═════════════════════════════════════════════════════════════════════════════
# TC4 — two old blocks separated by user content → both removed, middle preserved
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC4: two old blocks + user middle → both stripped, middle preserved ==="
TC4="$TMPDIR_TEST/tc4.zshrc"
cat > "$TC4" << 'EOF'
ZSC_PEM_LINUX="/usr/share/ca-certificates/zscaler.pem"
export CURL_CA_BUNDLE="$ZSC_PEM_LINUX"

export EDITOR=vim
alias ll='ls -la'

ZSC_PEM_MAC="/usr/local/share/ca-certificates/zscaler.pem"
export SSL_CERT_FILE="$ZSC_PEM_MAC"
export REQUESTS_CA_BUNDLE="$ZSC_PEM_MAC"

export PAGER=less
EOF
upsert_rc_zscaler_block "$TC4"
assert_not_contains "TC4: ZSC_PEM_LINUX removed"      "$TC4" "ZSC_PEM_LINUX"
assert_not_contains "TC4: ZSC_PEM_MAC removed"        "$TC4" "ZSC_PEM_MAC"
assert_not_contains "TC4: CURL_CA_BUNDLE raw removed"  "$TC4" 'CURL_CA_BUNDLE="\$ZSC_PEM'
assert_not_contains "TC4: SSL_CERT_FILE raw removed"   "$TC4" 'SSL_CERT_FILE="\$ZSC_PEM'
assert_contains     "TC4: EDITOR preserved"            "$TC4" "EDITOR=vim"
assert_contains     "TC4: alias preserved"             "$TC4" "alias ll"
assert_contains     "TC4: PAGER preserved"             "$TC4" "PAGER=less"
assert_contains     "TC4: marker appended"             "$TC4" "BEGIN terminal-kniferoll zscaler"

# ═════════════════════════════════════════════════════════════════════════════
# TC5 — only marker present → byte-identical (marker exactly once, no old blocks)
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC5: only marker present → marker exactly once ==="
TC5="$TMPDIR_TEST/tc5.zshrc"
cat > "$TC5" << 'EOF'
# BEGIN terminal-kniferoll zscaler — DO NOT EDIT (managed by installer)
[ -r "$HOME/.config/terminal-kniferoll/zscaler-env.sh" ] && \
    . "$HOME/.config/terminal-kniferoll/zscaler-env.sh"
# END terminal-kniferoll zscaler
EOF
upsert_rc_zscaler_block "$TC5"
assert_contains     "TC5: marker present after re-run"         "$TC5" "BEGIN terminal-kniferoll zscaler"
assert_line_count   "TC5: BEGIN marker appears exactly once"   "$TC5" "BEGIN terminal-kniferoll zscaler" 1
assert_line_count   "TC5: END marker appears exactly once"     "$TC5" "END terminal-kniferoll zscaler" 1
assert_not_contains "TC5: no raw ZSC_PEM_LINUX"               "$TC5" "ZSC_PEM_LINUX"

# ═════════════════════════════════════════════════════════════════════════════
# TC6 — old block + marker together → old stripped, marker kept/rewritten
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC6: old block + existing marker → old stripped, single clean marker ==="
TC6="$TMPDIR_TEST/tc6.zshrc"
cat > "$TC6" << 'EOF'
export EDITOR=vim

ZSC_PEM_LINUX="/usr/share/ca-certificates/zscaler.pem"
export CURL_CA_BUNDLE="$ZSC_PEM_LINUX"

# BEGIN terminal-kniferoll zscaler — DO NOT EDIT (managed by installer)
[ -r "$HOME/.config/terminal-kniferoll/zscaler-env.sh" ] && \
    . "$HOME/.config/terminal-kniferoll/zscaler-env.sh"
# END terminal-kniferoll zscaler

export PAGER=less
EOF
upsert_rc_zscaler_block "$TC6"
assert_not_contains "TC6: ZSC_PEM_LINUX removed"      "$TC6" "ZSC_PEM_LINUX"
assert_not_contains "TC6: raw CURL_CA_BUNDLE removed"  "$TC6" 'CURL_CA_BUNDLE="\$ZSC_PEM'
assert_contains     "TC6: EDITOR preserved"            "$TC6" "EDITOR=vim"
assert_contains     "TC6: PAGER preserved"             "$TC6" "PAGER=less"
assert_line_count   "TC6: BEGIN marker exactly once"   "$TC6" "BEGIN terminal-kniferoll zscaler" 1

# ═════════════════════════════════════════════════════════════════════════════
# TC7 — comment mentioning zscaler unrelated to exports → preserved
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC7: unrelated Zscaler comment (no cert exports) → preserved ==="
TC7="$TMPDIR_TEST/tc7.zshrc"
cat > "$TC7" << 'EOF'
# This machine is NOT a Zscaler-managed device.
# If it were, zscaler.pem would be at /Users/Shared/.certificates/
export EDITOR=vim
export PAGER=less
EOF
upsert_rc_zscaler_block "$TC7"
assert_contains "TC7: Zscaler comment preserved"       "$TC7" "NOT a Zscaler-managed"
assert_contains "TC7: second comment preserved"        "$TC7" "zscaler\.pem would be"
assert_contains "TC7: EDITOR preserved"                "$TC7" "EDITOR=vim"
assert_contains "TC7: PAGER preserved"                 "$TC7" "PAGER=less"
assert_contains "TC7: marker appended"                 "$TC7" "BEGIN terminal-kniferoll zscaler"

# ═════════════════════════════════════════════════════════════════════════════
# TC8 — empty file → marker only
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC8: empty file → marker only ==="
TC8="$TMPDIR_TEST/tc8.zshrc"
touch "$TC8"
upsert_rc_zscaler_block "$TC8"
assert_contains   "TC8: marker present"          "$TC8" "BEGIN terminal-kniferoll zscaler"
assert_contains   "TC8: source line present"     "$TC8" "zscaler-env\.sh"
assert_line_count "TC8: BEGIN exactly once"      "$TC8" "BEGIN terminal-kniferoll zscaler" 1

# ═════════════════════════════════════════════════════════════════════════════
# TC9 — shebang only → marker appended after shebang
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC9: shebang only → marker after shebang ==="
TC9="$TMPDIR_TEST/tc9.zshrc"
printf '#!/usr/bin/env zsh\n' > "$TC9"
upsert_rc_zscaler_block "$TC9"
assert_contains "TC9: shebang preserved"       "$TC9" "^#!/usr/bin/env zsh"
assert_contains "TC9: marker appended"         "$TC9" "BEGIN terminal-kniferoll zscaler"
# Shebang must come before marker
shebang_line=$(grep -n "#!/usr/bin/env zsh" "$TC9" | head -1 | cut -d: -f1)
marker_line=$(grep -n "BEGIN terminal-kniferoll zscaler" "$TC9" | head -1 | cut -d: -f1)
if [[ -n "$shebang_line" && -n "$marker_line" && "$shebang_line" -lt "$marker_line" ]]; then
    echo "  PASS: TC9: shebang before marker (line $shebang_line < $marker_line)"
    PASS=$(( PASS + 1 ))
else
    echo "  FAIL: TC9: shebang not before marker (shebang=$shebang_line marker=$marker_line)"
    FAIL=$(( FAIL + 1 ))
fi

# ═════════════════════════════════════════════════════════════════════════════
# TC10 — backup rotation: 6 runs → exactly 5 backups retained
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "=== TC10: backup rotation — 6 runs, 5 backups retained ==="
TC10="$TMPDIR_TEST/tc10.zshrc"
echo "export EDITOR=vim" > "$TC10"
for _i in 1 2 3 4 5 6; do
    backup_rc_file "$TC10"
    sleep 1
done
_backup_count=$(ls -1 "$TMPDIR_TEST"/tc10.zshrc.terminal-kniferoll-backup-* 2>/dev/null | wc -l | tr -d ' ')
if [[ "$_backup_count" -eq 5 ]]; then
    echo "  PASS: TC10: backup rotation: exactly 5 backups remain (got $_backup_count)"
    PASS=$(( PASS + 1 ))
else
    echo "  FAIL: TC10: backup rotation: expected 5 backups, got $_backup_count"
    ls -1 "$TMPDIR_TEST"/tc10.zshrc.terminal-kniferoll-backup-* 2>/dev/null | sed 's/^/    /'
    FAIL=$(( FAIL + 1 ))
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
echo "─────────────────────────────────────────────"
if [[ $FAIL -eq 0 ]]; then
    echo "All $PASS tests passed."
    exit 0
else
    echo "$FAIL test(s) FAILED."
    exit 1
fi
