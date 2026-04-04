# --- ALIASES ---
# Modernization overrides
if command -v lsd &>/dev/null; then
    alias ls='lsd'
    alias ll='lsd -l'
    alias la='lsd -la'
    alias l='lsd -CF'
    alias lr='lsd -latr'
else
    alias ll='ls -l'
    alias la='ls -la'
    alias l='ls -CF'
    alias lr='ls -latr'
fi

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
