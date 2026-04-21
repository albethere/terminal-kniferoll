#!/usr/bin/env bash
# scripts/test-sweep.sh — Unit tests for lib/rc_sweep.sh AWK parser
#
# Usage: bash scripts/test-sweep.sh
# Exit 0 if all tests pass; exit 1 if any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Stub helpers required by rc_sweep.sh ─────────────────────────────────────
ok()     { :; }
warn()   { :; }
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

# ── Test 1: Old if/elif/fi block (ZSC_PEM_MAC / ZSC_PEM_LINUX) stripped ──────
echo ""
echo "=== Test 1: old if/elif/fi block stripped ==="
T1="$TMPDIR_TEST/t1.zshrc"
cat > "$T1" << 'EOF'
# some preamble
export EDITOR=vim

if [[ "$OSTYPE" == darwin* ]]; then
    ZSC_PEM_MAC="/Users/Shared/.certificates/zscaler.pem"
    if [[ -s "$ZSC_PEM_MAC" ]]; then
        export ZSC_PEM="$ZSC_PEM_MAC"
    fi
elif [[ "$OSTYPE" == linux* ]]; then
    ZSC_PEM_LINUX="/etc/ssl/certs/zscaler.pem"
    if [[ -s "$ZSC_PEM_LINUX" ]]; then
        export ZSC_PEM="$ZSC_PEM_LINUX"
    fi
fi

if [[ -n "$ZSC_PEM" ]]; then
    export CURL_CA_BUNDLE="$ZSC_PEM"
    export SSL_CERT_FILE="$ZSC_PEM"
    export REQUESTS_CA_BUNDLE="$ZSC_PEM"
    export NODE_EXTRA_CA_CERTS="$ZSC_PEM"
    export GIT_SSL_CAINFO="$ZSC_PEM"
    export AWS_CA_BUNDLE="$ZSC_PEM"
    export PIP_CERT="$ZSC_PEM"
fi

export PATH="$HOME/.local/bin:$PATH"
EOF

strip_zscaler_regions "$T1" > "$TMPDIR_TEST/t1.out"
assert_not_contains "T1: ZSC_PEM_MAC removed"         "$TMPDIR_TEST/t1.out" "ZSC_PEM_MAC"
assert_not_contains "T1: CURL_CA_BUNDLE removed"      "$TMPDIR_TEST/t1.out" "CURL_CA_BUNDLE"
assert_not_contains "T1: orphaned fi removed"         "$TMPDIR_TEST/t1.out" "^fi$"
assert_contains     "T1: EDITOR preserved"            "$TMPDIR_TEST/t1.out" "EDITOR=vim"
assert_contains     "T1: PATH preserved"              "$TMPDIR_TEST/t1.out" 'PATH=.*\.local/bin'

# ── Test 2: Old block wrapped in function (strip internals, leave function) ───
echo ""
echo "=== Test 2: block inside function — strip internals, leave function shell ==="
T2="$TMPDIR_TEST/t2.zshrc"
cat > "$T2" << 'EOF'
setup_zscaler() {
    ZSC_PEM_MAC="/Users/Shared/.certificates/zscaler.pem"
    if [[ -s "$ZSC_PEM_MAC" ]]; then
        export ZSC_PEM="$ZSC_PEM_MAC"
        export CURL_CA_BUNDLE="$ZSC_PEM"
        export SSL_CERT_FILE="$ZSC_PEM"
    fi
}
setup_zscaler

export EDITOR=vim
EOF

strip_zscaler_regions "$T2" > "$TMPDIR_TEST/t2.out"
assert_not_contains "T2: ZSC_PEM_MAC removed"     "$TMPDIR_TEST/t2.out" "ZSC_PEM_MAC"
assert_not_contains "T2: CURL_CA_BUNDLE removed"  "$TMPDIR_TEST/t2.out" "CURL_CA_BUNDLE"
assert_contains     "T2: function name preserved" "$TMPDIR_TEST/t2.out" "setup_zscaler"
assert_contains     "T2: closing } preserved"     "$TMPDIR_TEST/t2.out" "^}$"
assert_contains     "T2: EDITOR preserved"        "$TMPDIR_TEST/t2.out" "EDITOR=vim"

# ── Test 3: Two old blocks in one file — both removed ────────────────────────
echo ""
echo "=== Test 3: two old blocks — both removed ==="
T3="$TMPDIR_TEST/t3.zshrc"
cat > "$T3" << 'EOF'
# first block
ZSC_PEM_MAC="/Users/Shared/.certificates/zscaler.pem"
export CURL_CA_BUNDLE="$ZSC_PEM_MAC"
export SSL_CERT_FILE="$ZSC_PEM_MAC"

export EDITOR=vim

# second block (old BEGIN/END marker)
# BEGIN terminal-kniferoll zscaler — DO NOT EDIT (managed by installer)
[ -r "$HOME/.config/terminal-kniferoll/zscaler-env.sh" ] && \
    . "$HOME/.config/terminal-kniferoll/zscaler-env.sh"
# END terminal-kniferoll zscaler

export PAGER=less
EOF

strip_zscaler_regions "$T3" > "$TMPDIR_TEST/t3.out"
assert_not_contains "T3: ZSC_PEM_MAC removed"         "$TMPDIR_TEST/t3.out" "ZSC_PEM_MAC"
assert_not_contains "T3: CURL_CA_BUNDLE removed"      "$TMPDIR_TEST/t3.out" "CURL_CA_BUNDLE"
assert_not_contains "T3: BEGIN marker removed"        "$TMPDIR_TEST/t3.out" "BEGIN terminal-kniferoll"
assert_not_contains "T3: source line removed"         "$TMPDIR_TEST/t3.out" "zscaler-env.sh"
assert_contains     "T3: EDITOR preserved"            "$TMPDIR_TEST/t3.out" "EDITOR=vim"
assert_contains     "T3: PAGER preserved"             "$TMPDIR_TEST/t3.out" "PAGER=less"

# ── Test 4: Unrelated zscaler comment (no cert setup) — preserved ─────────────
echo ""
echo "=== Test 4: unrelated zscaler comment — preserved ==="
T4="$TMPDIR_TEST/t4.zshrc"
cat > "$T4" << 'EOF'
# This machine is NOT a Zscaler-managed device.
# If it were, zscaler.pem would be at /Users/Shared/.certificates/
export EDITOR=vim
export PAGER=less
EOF

strip_zscaler_regions "$T4" > "$TMPDIR_TEST/t4.out"
assert_contains "T4: zscaler comment preserved" "$TMPDIR_TEST/t4.out" "NOT a Zscaler-managed"
assert_contains "T4: EDITOR preserved"          "$TMPDIR_TEST/t4.out" "EDITOR=vim"
assert_contains "T4: PAGER preserved"           "$TMPDIR_TEST/t4.out" "PAGER=less"

# ── Test 5: Old block + existing marker — idempotent (strip old, keep marker) ─
echo ""
echo "=== Test 5: old block + existing marker → idempotent strip ==="
T5="$TMPDIR_TEST/t5.zshrc"
cat > "$T5" << 'EOF'
export EDITOR=vim

ZSC_PEM_LINUX="/etc/ssl/certs/zscaler.pem"
export CURL_CA_BUNDLE="$ZSC_PEM_LINUX"

# BEGIN terminal-kniferoll zscaler — DO NOT EDIT (managed by installer)
[ -r "$HOME/.config/terminal-kniferoll/zscaler-env.sh" ] && \
    . "$HOME/.config/terminal-kniferoll/zscaler-env.sh"
# END terminal-kniferoll zscaler

export PAGER=less
EOF

strip_zscaler_regions "$T5" > "$TMPDIR_TEST/t5.out"
assert_not_contains "T5: old ZSC_PEM_LINUX removed"  "$TMPDIR_TEST/t5.out" "ZSC_PEM_LINUX"
assert_not_contains "T5: old CURL_CA_BUNDLE removed" "$TMPDIR_TEST/t5.out" "CURL_CA_BUNDLE"
assert_not_contains "T5: old marker removed"         "$TMPDIR_TEST/t5.out" "BEGIN terminal-kniferoll"
assert_not_contains "T5: source line removed"        "$TMPDIR_TEST/t5.out" "zscaler-env.sh"
assert_contains     "T5: EDITOR preserved"           "$TMPDIR_TEST/t5.out" "EDITOR=vim"
assert_contains     "T5: PAGER preserved"            "$TMPDIR_TEST/t5.out" "PAGER=less"

# ── Test 6: User customizations survive untouched ─────────────────────────────
echo ""
echo "=== Test 6: user customizations survive ==="
T6="$TMPDIR_TEST/t6.zshrc"
cat > "$T6" << 'EOF'
# User's custom aliases
alias gst='git status'
alias ll='ls -la'

# BEGIN terminal-kniferoll zscaler — DO NOT EDIT (managed by installer)
[ -r "$HOME/.config/terminal-kniferoll/zscaler-env.sh" ] && \
    . "$HOME/.config/terminal-kniferoll/zscaler-env.sh"
# END terminal-kniferoll zscaler

# User's custom functions
my_func() {
    echo "hello world"
}

export MY_VAR="custom_value"
EOF

strip_zscaler_regions "$T6" > "$TMPDIR_TEST/t6.out"
assert_not_contains "T6: marker block removed"       "$TMPDIR_TEST/t6.out" "BEGIN terminal-kniferoll"
assert_not_contains "T6: source line removed"        "$TMPDIR_TEST/t6.out" "zscaler-env.sh"
assert_contains     "T6: aliases preserved"          "$TMPDIR_TEST/t6.out" "alias gst"
assert_contains     "T6: function preserved"         "$TMPDIR_TEST/t6.out" "my_func"
assert_contains     "T6: custom export preserved"    "$TMPDIR_TEST/t6.out" "MY_VAR"

# ── Test 7: upsert idempotency (block not doubled on re-run) ─────────────────
echo ""
echo "=== Test 7: upsert idempotency — block not doubled on re-run ==="
T7="$TMPDIR_TEST/t7.zshrc"
cat > "$T7" << 'EOF'
export EDITOR=vim
EOF

# First run
upsert_rc_zscaler_block "$T7"
# Second run
upsert_rc_zscaler_block "$T7"
assert_line_count "T7: zscaler-env.sh appears exactly twice (one block)" \
    "$T7" "zscaler-env.sh" 2

# ── Test 8: backup rotation — only 5 most recent kept ────────────────────────
echo ""
echo "=== Test 8: backup rotation — max 5 backups ==="
T8="$TMPDIR_TEST/t8.zshrc"
echo "export EDITOR=vim" > "$T8"
for _i in 1 2 3 4 5 6; do
    sleep 1
    backup_rc_file "$T8"
done
_backup_count=$(ls -1 "$TMPDIR_TEST"/t8.zshrc.terminal-kniferoll-backup-* 2>/dev/null | wc -l | tr -d ' ')
if [[ "$_backup_count" -eq 5 ]]; then
    echo "  PASS: T8: backup rotation: exactly 5 backups remain (got $_backup_count)"
    PASS=$(( PASS + 1 ))
else
    echo "  FAIL: T8: backup rotation: expected 5 backups, got $_backup_count"
    FAIL=$(( FAIL + 1 ))
fi

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
