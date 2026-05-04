# ==============================================================================
# TERMINAL-KNIFEROLL: Defensive Security Engineer Configuration
# ==============================================================================

# --- HOMEBREW ---
# Linuxbrew only on Linux; macOS brew is handled via the brew-shellenv managed block.
if [[ "$(uname)" == "Linux" && -d "/home/linuxbrew/.linuxbrew" ]]; then
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

# FZF -- version-aware init. fzf >= 0.48.0 ships `fzf --zsh` (single-source);
# older builds (Ubuntu 22.04 apt is 0.30.0) emit "unknown option: --zsh" and
# break shell startup. Detect version and fall back to bundled key-bindings/
# completion scripts on older fzf. Linuxbrew is the canonical source on Linux.
if command -v fzf &>/dev/null; then
    _tk_fzf_ver="$(fzf --version 2>/dev/null | awk '{print $1; exit}')"
    if [[ -n "$_tk_fzf_ver" ]] && \
       [[ "$(printf '%s\n0.48.0\n' "$_tk_fzf_ver" | sort -V | head -n1)" == "0.48.0" ]]; then
        source <(fzf --zsh)
    else
        for _tk_fzf_dir in /usr/share/doc/fzf/examples /usr/share/fzf; do
            [[ -r "$_tk_fzf_dir/key-bindings.zsh" ]] && source "$_tk_fzf_dir/key-bindings.zsh"
            [[ -r "$_tk_fzf_dir/completion.zsh"   ]] && source "$_tk_fzf_dir/completion.zsh"
        done
    fi
    unset _tk_fzf_ver _tk_fzf_dir
fi

# --- PYENV ---
export PATH="$HOME/.pyenv/bin:$PATH"
if command -v pyenv &>/dev/null; then
    eval "$(pyenv init --path)"
    eval "$(pyenv init -)"
fi

# --- ZSCALER PROXY CONFIG (CORP DEVICES ONLY) ---
# Detection logic lives in ~/.config/terminal-kniferoll/zscaler-env.sh,
# written fresh on each installer run with OS-specific absolute paths.
# BEGIN terminal-kniferoll zscaler — DO NOT EDIT (managed by installer)
[ -r "$HOME/.config/terminal-kniferoll/zscaler-env.sh" ] && \
    . "$HOME/.config/terminal-kniferoll/zscaler-env.sh"
# END terminal-kniferoll zscaler

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

# --- LOLCRAB ALIAS / FF ALIAS / FASTFETCH GREETER ---
# Three managed marker blocks below. The installer sweeps every POSIX RC file
# (~/.zshrc, ~/.bashrc, ~/.profile, ~/.zprofile, ~/.bash_profile) and upserts
# these in place — DO NOT EDIT inside the BEGIN/END markers.
# BEGIN terminal-kniferoll lolcat-alias — DO NOT EDIT (managed by installer)
if command -v lolcrab >/dev/null 2>&1 && ! command -v lolcat >/dev/null 2>&1; then
    alias lolcat='lolcrab'
fi
# END terminal-kniferoll lolcat-alias

# BEGIN terminal-kniferoll ff-alias — DO NOT EDIT (managed by installer)
if command -v fastfetch >/dev/null 2>&1 && command -v lolcrab >/dev/null 2>&1; then
    alias ff='fastfetch | lolcrab'
elif command -v fastfetch >/dev/null 2>&1; then
    alias ff='fastfetch'
fi
# END terminal-kniferoll ff-alias

# BEGIN terminal-kniferoll fastfetch-greeter — DO NOT EDIT (managed by installer)
if [ -z "${TK_FASTFETCH_GREETED:-}" ] && [ -z "${DISABLE_WELCOME:-}" ] && \
   command -v fastfetch >/dev/null 2>&1; then
    if command -v lolcrab >/dev/null 2>&1; then
        fastfetch | lolcrab
    else
        fastfetch
    fi
    export TK_FASTFETCH_GREETED=1
fi
# END terminal-kniferoll fastfetch-greeter

# Wrapped evals (run after welcome to keep startup responsive)
command -v zoxide &>/dev/null && eval "$(zoxide init zsh --cmd cd)"
