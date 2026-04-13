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
# Standard paths for Linux/WSL and macOS
ZSC_PEM_LINUX="/usr/share/ca-certificates/zscaler.pem"
ZSC_PEM_MAC="/usr/local/share/ca-certificates/zscaler.pem"

if [[ -f "$ZSC_PEM_LINUX" ]]; then
    export ZSC_PEM="$ZSC_PEM_LINUX"
elif [[ -f "$ZSC_PEM_MAC" ]]; then
    export ZSC_PEM="$ZSC_PEM_MAC"
fi

if [[ -n "$ZSC_PEM" ]]; then
    export REQUESTS_CA_BUNDLE="$ZSC_PEM"
    export CURL_CA_BUNDLE="$ZSC_PEM"
    export NODE_EXTRA_CA_CERTS="$ZSC_PEM"
    export SSL_CERT_FILE="$ZSC_PEM"
    export GIT_SSL_CAINFO="$ZSC_PEM"
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

# Welcome message (run early to avoid being blocked by heavy evals)
if [[ -z "$DISABLE_WELCOME" ]] && command -v fastfetch &>/dev/null; then
    if command -v lolcat &>/dev/null; then
        fastfetch --pipe | lolcat -f
    else
        fastfetch
    fi
fi

# Wrapped evals
command -v zoxide &>/dev/null && eval "$(zoxide init zsh --cmd cd)"
