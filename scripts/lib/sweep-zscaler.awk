# sweep-zscaler.awk — POSIX awk state machine: strip old Zscaler rc blocks
#
# Input:  path to an rc file (pass as awk argument; reads stdin otherwise)
# Output: rc file content with all Zscaler regions removed (stdout)
#
# Region rules
#   - A region is entered when a zscaler-start trigger is seen at depth 0 only.
#   - Depth tracks if/for/while/until/case/brace openers and fi/done/esac/}
#     closers.  Zscaler lines inside user-defined function bodies (depth > 0)
#     are PRESERVED — only top-level regions are swept.
#   - Inside a region all lines are eaten until a non-Zscaler, non-blank,
#     non-structural-close line appears at depth == entry_depth (0).
#   - Multiple regions per file are handled in a single pass.

function is_trigger(line) {
    if (line ~ /ZSC_PEM_LINUX[[:space:]]*=/) return 1
    if (line ~ /ZSC_PEM_MAC[[:space:]]*=/) return 1
    if (line ~ /^[[:space:]]*(export[[:space:]]+)?ZSC_PEM[[:space:]]*=/) return 1
    if (line ~ /^[[:space:]]*unset[[:space:]]+ZSC_PEM/) return 1
    if (line ~ /^[[:space:]]*export[[:space:]]+CURL_CA_BUNDLE[[:space:]]*=/) return 1
    if (line ~ /^[[:space:]]*export[[:space:]]+SSL_CERT_FILE[[:space:]]*=/) return 1
    if (line ~ /^[[:space:]]*export[[:space:]]+REQUESTS_CA_BUNDLE[[:space:]]*=/) return 1
    if (line ~ /^[[:space:]]*export[[:space:]]+NODE_EXTRA_CA_CERTS[[:space:]]*=/) return 1
    if (line ~ /^[[:space:]]*export[[:space:]]+GIT_SSL_CAINFO[[:space:]]*=/) return 1
    if (line ~ /^[[:space:]]*export[[:space:]]+AWS_CA_BUNDLE[[:space:]]*=/) return 1
    if (line ~ /^[[:space:]]*export[[:space:]]+PIP_CERT[[:space:]]*=/) return 1
    if (line ~ /^[[:space:]]*export[[:space:]]+HOMEBREW_CURLOPT_CACERT[[:space:]]*=/) return 1
    if (line ~ /^[[:space:]]*#[[:space:]]*BEGIN terminal-kniferoll zscaler/) return 1
    return 0
}

function is_zscaler_content(line) {
    if (line ~ /ZSC_PEM/) return 1
    if (line ~ /CURL_CA_BUNDLE/) return 1
    if (line ~ /SSL_CERT_FILE/) return 1
    if (line ~ /REQUESTS_CA_BUNDLE/) return 1
    if (line ~ /NODE_EXTRA_CA_CERTS/) return 1
    if (line ~ /GIT_SSL_CAINFO/) return 1
    if (line ~ /AWS_CA_BUNDLE/) return 1
    if (line ~ /PIP_CERT/) return 1
    if (line ~ /HOMEBREW_CURLOPT_CACERT/) return 1
    if (line ~ /[Zz]scaler/) return 1
    return 0
}

function is_structural_close(line) {
    if (line ~ /^[[:space:]]*(fi|done|esac)[[:space:]]*(#.*)?$/) return 1
    if (line ~ /^[[:space:]]*\}[[:space:]]*(#.*)?$/) return 1
    return 0
}

function depth_delta(line,    d) {
    d = 0
    if (line ~ /^[[:space:]]*(if|for|while|until)[[:space:]]/) d++
    if (line ~ /^[[:space:]]*case[[:space:]]/) d++
    if (line ~ /\{[[:space:]]*(#.*)?$/ && line !~ /\{.*\}/) d++
    if (line ~ /^[[:space:]]*(fi|done|esac)[[:space:]]*(#.*)?$/) d--
    if (line ~ /^[[:space:]]*\}[[:space:]]*(#.*)?$/) d--
    return d
}

BEGIN {
    in_region   = 0
    depth       = 0
    entry_depth = 0
}

{
    pre_depth = depth
    d = depth_delta($0)

    if (!in_region) {

        depth += d
        if (depth < 0) depth = 0

        if (pre_depth == 0 && is_trigger($0)) {
            in_region   = 1
            entry_depth = 0
        } else {
            print
        }

    } else {

        if (pre_depth < entry_depth) {
            # Structural close popped below entry — belongs to outer scope
            in_region = 0
            depth += d
            if (depth < 0) depth = 0
            print

        } else if (pre_depth == entry_depth) {

            if ($0 ~ /^[[:space:]]*$/) {
                depth += d
                # blank — consume (trailing-blank cleanup)

            } else if (is_zscaler_content($0)) {
                depth += d
                if (depth < 0) depth = 0
                # Zscaler-related line — eat

            } else if (is_structural_close($0)) {
                depth += d
                if (depth < 0) depth = 0
                # fi/done/esac/} closing a Zscaler control structure — eat

            } else if ($0 ~ /^[[:space:]]*elif[[:space:]]/ || \
                       $0 ~ /^[[:space:]]*else[[:space:]]/ || \
                       $0 ~ /^[[:space:]]*else$/) {
                depth += d
                # elif/else branch of Zscaler if block — stay in region

            } else {
                # Non-Zscaler, non-blank at entry depth — region ends
                in_region = 0
                depth += d
                if (depth < 0) depth = 0
                print
                if (pre_depth == 0 && is_trigger($0)) {
                    in_region   = 1
                    entry_depth = 0
                }
            }

        } else {
            # pre_depth > entry_depth: inside a deeper structure — eat
            depth += d
            if (depth < 0) depth = 0
        }

    }
}
