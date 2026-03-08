# ==============================================================================
# TERMINAL-KNIFEROLL: Defensive Security Engineer Configuration
# ==============================================================================

# --- PATH & ENVIRONMENT ---
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"

# --- LINUXBREW ---
if [[ -d "/home/linuxbrew/.linuxbrew" ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

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

source $ZSH/oh-my-zsh.sh

# --- CUSTOM PLUGINS (Homebrew or Manual) ---
if [[ -d "/home/linuxbrew/.linuxbrew/opt/zsh-fast-syntax-highlighting" ]]; then
    source /home/linuxbrew/.linuxbrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    source /home/linuxbrew/.linuxbrew/opt/zsh-fast-syntax-highlighting/share/zsh-fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh
fi

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
if [[ -f "/usr/share/ca-certificates/zscaler.pem" ]]; then
    export REQUESTS_CA_BUNDLE=/usr/share/ca-certificates/zscaler.pem
    export CURL_CA_BUNDLE=/usr/share/ca-certificates/zscaler.pem
    export NODE_EXTRA_CA_CERTS=/usr/share/ca-certificates/zscaler.pem
    export SSL_CERT_FILE=/usr/share/ca-certificates/zscaler.pem
fi

# --- WTFIS API KEYS ---
export VT_API_KEY="${PRIVATE_VT_API_KEY:-redacted}"
export PT_API_KEY="${PRIVATE_PT_API_KEY:-redacted}"
export PT_API_USER="${PRIVATE_PT_API_USER:-redactedd}"
export IP2WHOIS_API_KEY="${PRIVATE_IP2WHOIS_API_KEY:-redacted}"
export SHODAN_API_KEY="${PRIVATE_SHODAN_API_KEY:-redacted}"
export GREYNOISE_API_KEY="${PRIVATE_GREYNOISE_API_KEY:-redacted}"
export ABUSEIPDB_API_KEY="${PRIVATE_ABUSEIPDB_API_KEY:-redacted}"

# Load Aliases
[[ -f "$HOME/.shell/aliases.zsh" ]] && source "$HOME/.shell/aliases.zsh"

# --- INITIALIZATION ---
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# Wrapped evals
command -v zoxide &>/dev/null && eval "$(zoxide init zsh --cmd cd)"
command -v atuin &>/dev/null && eval "$(atuin init zsh)"

# Welcome message
if command -v fastfetch &>/dev/null; then
    if command -v lolcat &>/dev/null; then
        fastfetch --pipe | lolcat
    else
        fastfetch
    fi
fi
