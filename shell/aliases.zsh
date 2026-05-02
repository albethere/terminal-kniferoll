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
if command -v ss &>/dev/null; then alias ports='ss -tulanp'; fi

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
# trippy installs as 'trip' (cargo crate name vs binary name mismatch)
if command -v trip &>/dev/null; then alias trippy='trip'; fi

# Shell management
alias snzrc='sudo nano ~/.zshrc'
alias szrc='source ~/.zshrc'
# `ff` alias lives in the managed `ff-alias` marker block in ~/.zshrc / ~/.bashrc
# (installer-upserted). See shell/zshrc.zsh and the installer sweep.

# --- System update across every package manager present ---
# `up` detects each package manager on PATH and runs its update flow.
# Backward-compat aliases: `abu` (was apt+brew) and `bru` (was brew) both call up.
up() {
    local rc=0 step
    step() { print -P "%F{75}==> $*%f"; "$@" || rc=$?; }

    # System package managers
    if command -v apt &>/dev/null; then
        step sudo apt update
        step sudo apt full-upgrade -y
        step sudo apt autoremove -y
    fi
    # AUR helpers build packages in a subshell that inherits PATH. If linuxbrew
    # is ahead of /usr/bin, PKGBUILDs resolving `python3`/`pkg-config`/etc hit
    # brew's copies and fail (e.g. evdi-dkms needs system pybind11 + Python.h).
    # Strip linuxbrew from PATH for the AUR step only.
    local _aur_path="${PATH//:\/home\/linuxbrew\/.linuxbrew\/sbin/}"
    _aur_path="${_aur_path//:\/home\/linuxbrew\/.linuxbrew\/bin/}"
    _aur_path="${_aur_path//\/home\/linuxbrew\/.linuxbrew\/sbin:/}"
    _aur_path="${_aur_path//\/home\/linuxbrew\/.linuxbrew\/bin:/}"
    if command -v paru &>/dev/null; then
        step env PATH="$_aur_path" paru -Syu --noconfirm
    elif command -v yay &>/dev/null; then
        step env PATH="$_aur_path" yay -Syu --noconfirm
    elif command -v pacman &>/dev/null; then
        step sudo pacman -Syu --noconfirm
    fi
    if command -v dnf &>/dev/null; then
        step sudo dnf upgrade --refresh -y
    fi
    if command -v zypper &>/dev/null; then
        step sudo zypper refresh
        step sudo zypper update -y
    fi
    if command -v apk &>/dev/null; then
        step sudo apk update
        step sudo apk upgrade
    fi

    # User-space package managers
    if command -v brew &>/dev/null; then
        step brew update
        step brew upgrade
        step brew cleanup
    fi
    if command -v flatpak &>/dev/null; then
        step flatpak update -y
    fi
    if command -v snap &>/dev/null; then
        step sudo snap refresh
    fi

    # macOS system updates
    if [[ "$(uname -s)" == "Darwin" ]] && command -v softwareupdate &>/dev/null; then
        step softwareupdate -i -a
    fi

    unfunction step 2>/dev/null
    return $rc
}
alias abu='up'
alias bru='up'
