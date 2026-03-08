# --- PLUGINS ---
plugins=(git sudo extract)

# Only add plugins if not using Homebrew versions
if [[ ! -d "/home/linuxbrew/.linuxbrew/opt/zsh-fast-syntax-highlighting" ]]; then
    plugins+=(zsh-autosuggestions zsh-fast-syntax-highlighting)
fi
