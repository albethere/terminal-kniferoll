# --- PLUGINS ---
# Load order matters:
#   zsh-autosuggestions  →  must come before fast-syntax-highlighting
#   fast-syntax-highlighting  →  MUST be last plugin (processes already-loaded completions)
plugins=(
    git
    sudo
    extract
    zsh-autosuggestions
    fast-syntax-highlighting
)

# macOS: source brew-managed plugin files (guards against missing paths)
# These complement the OMZ-managed git-cloned versions.
[[ "$OSTYPE" == darwin* ]] && {
    source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh" 2>/dev/null || true
    source "$(brew --prefix)/share/zsh-fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh" 2>/dev/null || true
}
