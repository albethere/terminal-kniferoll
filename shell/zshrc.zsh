# ==============================================================================
# TERMINAL-KNIFEROLL: Defensive Security Engineer Configuration
# ==============================================================================

# --- HOMEBREW (Linux & macOS) ---
if [[ -d "/home/linuxbrew/.linuxbrew" ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# --- PATH & ENVIRONMENT ---
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# --- OH-MY-ZSH ---
export ZSH="$HOME/.oh-my-zsh"
ZSH_DISABLE_COMPFIX="true"
ZSH_THEME="random"
ZSH_THEME_RANDOM_CANDIDATES=(
    "robbyrussell" "agnoster" "junkfood" "tonotdo" "af-magic"
    "fishy" "darkblood" "cypher" "clean" "linuxonly"
    "bureau" "intheloop" "kphoen"
)

# Load Plugins Configuration
[[ -f "$HOME/.shell/plugins.zsh" ]] && source "$HOME/.shell/plugins.zsh"

source "$ZSH/oh-my-zsh.sh"

# --- CUSTOM PLUGINS (macOS brew, loaded after OMZ) ---
# Handled in ~/.shell/plugins.zsh via OSTYPE guard.
# On Linux, OMZ loads zsh-autosuggestions and fast-syntax-highlighting
# from $ZSH_CUSTOM/plugins/ (git-cloned by installer).

# FZF
if command -v fzf &>/dev/null; then
    source <(fzf --zsh)
fi

# --- PYENV ---
export PATH="$HOME/.pyenv/bin:$PATH"
if command -v pyenv &>/dev/null; then
    eval "$(pyenv init --path)"
    eval "$(pyenv init -)"
fi

# --- ZSCALER PROXY CONFIG (CORP DEVICES ONLY) ---
# Detection is platform-aware — macOS paths and Linux paths are kept separate.
#
# macOS (darwin): LM standard path first, then installer bundle, then Zscaler app
#   - /Users/Shared/.certificates/zscaler.pem  ← LM onboarding doc standard
#   - ~/.config/terminal-kniferoll/ca-bundle.pem ← built by installer
#   - /Library/Application Support/Zscaler/…   ← ZIA/ZPA app default
#
# Linux: installer bundle first, then system cert directories
#   - ~/.config/terminal-kniferoll/ca-bundle.pem
#   - /etc/ssl/certs/zscaler.pem
#   - /usr/local/share/ca-certificates/zscaler.pem
#
# If none found, no Zscaler env is set and standard system trust applies.
unset ZSC_PEM
if [[ "$OSTYPE" == darwin* ]]; then
    for _zsc_p in \
        "/Users/Shared/.certificates/zscaler.pem" \
        "$HOME/.config/terminal-kniferoll/ca-bundle.pem" \
        "/Library/Application Support/Zscaler/ZscalerRootCertificate-2048-SHA256.crt"
    do
        [[ -s "$_zsc_p" ]] && { export ZSC_PEM="$_zsc_p"; break; }
    done
else
    for _zsc_p in \
        "$HOME/.config/terminal-kniferoll/ca-bundle.pem" \
        "/etc/ssl/certs/zscaler.pem" \
        "/usr/local/share/ca-certificates/zscaler.pem" \
        "/usr/share/ca-certificates/zscaler.pem"
    do
        [[ -s "$_zsc_p" ]] && { export ZSC_PEM="$_zsc_p"; break; }
    done
fi
unset _zsc_p

if [[ -n "${ZSC_PEM:-}" ]]; then
    export REQUESTS_CA_BUNDLE="$ZSC_PEM"
    export CURL_CA_BUNDLE="$ZSC_PEM"
    export NODE_EXTRA_CA_CERTS="$ZSC_PEM"
    export SSL_CERT_FILE="$ZSC_PEM"
    export GIT_SSL_CAINFO="$ZSC_PEM"
    export AWS_CA_BUNDLE="$ZSC_PEM"
    export PIP_CERT="$ZSC_PEM"
    # HOMEBREW_CURLOPT_CACERT is macOS-only (brew uses this for its internal curl)
    [[ "$OSTYPE" == darwin* ]] && export HOMEBREW_CURLOPT_CACERT="$ZSC_PEM"
fi

# --- WTFIS API KEYS ---
export VT_API_KEY="${PRIVATE_VT_API_KEY:-}"
export PT_API_KEY="${PRIVATE_PT_API_KEY:-}"
export PT_API_USER="${PRIVATE_PT_API_USER:-}"
export IP2WHOIS_API_KEY="${PRIVATE_IP2WHOIS_API_KEY:-}"
export SHODAN_API_KEY="${PRIVATE_SHODAN_API_KEY:-}"
export GREYNOISE_API_KEY="${PRIVATE_GREYNOISE_API_KEY:-}"
export ABUSEIPDB_API_KEY="${PRIVATE_ABUSEIPDB_API_KEY:-}"

# Load Aliases
[[ -f "$HOME/.shell/aliases.zsh" ]] && source "$HOME/.shell/aliases.zsh"

# --- INITIALIZATION ---
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# Welcome message
if [[ -z "${DISABLE_WELCOME:-}" ]] && command -v fastfetch &>/dev/null; then
    if command -v lolcat &>/dev/null; then
        fastfetch --pipe | lolcat -f
    else
        fastfetch
    fi
fi

# Wrapped evals (run after welcome to keep startup responsive)
command -v zoxide &>/dev/null && eval "$(zoxide init zsh --cmd cd)"
