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
if command -v sd &>/dev/null; then alias sed='sd'; fi

# Shell management
alias snzrc='sudo nano ~/.zshrc'
alias szrc='source ~/.zshrc'
alias ff='fastfetch --pipe | lolcat'

# AIDSOCL (AI DevSecOps Cloud Lab)
alias aidsocl='bash $HOME/Projects/lcars-core/scripts/lcars_awareness.sh && lcars_report_awareness'
alias ship='bash $HOME/Projects/lcars-core/scripts/lcars.sh'
alias computer='bash $HOME/Projects/lcars-core/scripts/lcars-console.sh'
