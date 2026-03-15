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

# Optional orchestration stack (only if LCARS_CORE_DIR is set)
if [[ -n "${LCARS_CORE_DIR:-}" ]]; then
    alias aidsocl='bash "$LCARS_CORE_DIR/scripts/lcars_awareness.sh" && lcars_report_awareness'
    alias ship='bash "$LCARS_CORE_DIR/scripts/lcars.sh"'
    alias computer='bash "$LCARS_CORE_DIR/scripts/lcars-console.sh"'
fi
