# --- ALIASES ---

# ls strategy: lsd preferred over plain ls aliases.
# lsd provides icons, color, git-status, and tree view.
# Requires: brew install lsd (macOS) / apt install lsd (Linux)
# Escape hatch: use \ls or lsp for POSIX ls.
alias ls='lsd'
alias l='lsd -l'
alias la='lsd -la'
alias lt='lsd --tree'
alias ll='lsd -lA'
alias lsp='\ls -la'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Safety
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'

# Editors
alias vim='nvim'
alias vi='nvim'

# Network
alias myip='curl -s https://icanhazip.com'
alias ports='ss -tulanp'

# Git shortcuts
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git --no-pager log --oneline -10'
alias gd='git --no-pager diff'

# Disk
alias df='df -h'
alias du='du -sh'

# Process
alias psa='ps aux'
alias psg='ps aux | grep'

# Reload
alias reload='source ~/.zshrc'
alias zshrc='${EDITOR:-nvim} ~/.zshrc'

# Modern replacements (guarded so missing tools don't break the shell)
if command -v bat &>/dev/null; then alias cat='bat'; fi
if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then alias cat='batcat'; fi
if command -v sd &>/dev/null; then alias subs='sd'; fi

# Shell management
alias snzrc='sudo nano ~/.zshrc'
alias szrc='source ~/.zshrc'
if command -v fastfetch &>/dev/null && command -v lolcat &>/dev/null; then
    alias ff='fastfetch --pipe | lolcat'
elif command -v fastfetch &>/dev/null; then
    alias ff='fastfetch'
fi
