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
# Detection order (macOS → Linux fallback):
#   1. Installer-built combined bundle  (installer writes this on managed devices)
#   2. Zscaler app default path         (ZIA/ZPA client installs cert here on macOS)
#   3. Linux/manually placed PEM        (/etc/ssl/certs or /usr/share/ca-certificates)
#
# If none found, no Zscaler env is set and standard system trust applies.
_ZSC_BUNDLE="$HOME/.config/terminal-kniferoll/ca-bundle.pem"
_ZSC_APP_CERT="/Library/Application Support/Zscaler/ZscalerRootCertificate-2048-SHA256.crt"
_ZSC_LINUX_1="/etc/ssl/certs/zscaler.pem"
_ZSC_LINUX_2="/usr/share/ca-certificates/zscaler.pem"

if [[ -s "$_ZSC_BUNDLE" ]]; then
    export ZSC_PEM="$_ZSC_BUNDLE"
elif [[ -f "$_ZSC_APP_CERT" ]]; then
    export ZSC_PEM="$_ZSC_APP_CERT"
elif [[ -f "$_ZSC_LINUX_1" ]]; then
    export ZSC_PEM="$_ZSC_LINUX_1"
elif [[ -f "$_ZSC_LINUX_2" ]]; then
    export ZSC_PEM="$_ZSC_LINUX_2"
fi
unset _ZSC_BUNDLE _ZSC_APP_CERT _ZSC_LINUX_1 _ZSC_LINUX_2

if [[ -n "${ZSC_PEM:-}" ]]; then
    export REQUESTS_CA_BUNDLE="$ZSC_PEM"
    export CURL_CA_BUNDLE="$ZSC_PEM"
    export NODE_EXTRA_CA_CERTS="$ZSC_PEM"
    export SSL_CERT_FILE="$ZSC_PEM"
    export GIT_SSL_CAINFO="$ZSC_PEM"
    export AWS_CA_BUNDLE="$ZSC_PEM"
    export PIP_CERT="$ZSC_PEM"
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
