#Requires -Version 5.1
<#
.SYNOPSIS
    terminal-kniferoll | Windows Installer
.DESCRIPTION
    Installs the full terminal-kniferoll stack on Windows.
    Uses winget (primary) → Scoop (secondary) → Chocolatey (tertiary).
    Deploys a PowerShell profile with Oh My Posh, PSReadLine, Terminal-Icons,
    zoxide, fzf, posh-git, and shell aliases matching the Unix side.
.PARAMETER Full
    Install everything: Shell + Projector (default when no flag given).
.PARAMETER Shell
    Install shell experience only (Oh My Posh, PS modules, profile, aliases).
.PARAMETER Projector
    Install projector tools only (fastfetch, cmatrix, Python).
.PARAMETER Custom
    Interactively choose which groups to install.
.PARAMETER Help
    Show this help message and exit.
.EXAMPLE
    .\install_windows.ps1
    .\install_windows.ps1 -Shell
    .\install_windows.ps1 -Projector
    .\install_windows.ps1 -Custom
    .\install_windows.ps1 -Full
.NOTES
    Run from a standard (non-elevated) PowerShell session when possible.
    Some winget operations may prompt for UAC elevation automatically.
    PowerShell 5.1+ required; PowerShell 7+ recommended.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Full,
    [switch]$Shell,
    [switch]$Projector,
    [switch]$Custom,
    [Alias('h')]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ══════════════════════════════════════════════════════════════════════════════
# LOGGING
# ══════════════════════════════════════════════════════════════════════════════

$LogDir  = "$env:USERPROFILE\.terminal-kniferoll\logs"
$LogFile = "$LogDir\install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Log {
    param(
        [ValidateSet('INFO','OK','WARN','ERROR')][string]$Level,
        [string]$Message
    )
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line  = "[$stamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Write-OK   { param([string]$m) Write-Host "[`u{2713}] $m" -ForegroundColor Green;  Write-Log OK   $m }
function Write-Info { param([string]$m) Write-Host "[*] $m"        -ForegroundColor Cyan;   Write-Log INFO $m }
function Write-Warn { param([string]$m) Write-Host "[~] $m"        -ForegroundColor Yellow; Write-Log WARN $m }
function Write-Err  { param([string]$m) Write-Host "[x] $m"        -ForegroundColor Red;    Write-Log ERROR $m }
function Write-Die  { param([string]$m) Write-Err "FATAL: $m"; exit 1 }

function Write-Section {
    param([string]$Title)
    $bar = '─' * 66
    Write-Host ''
    Write-Host "  $bar" -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "  $bar" -ForegroundColor DarkCyan
    Write-Log INFO "=== $Title ==="
}

# ══════════════════════════════════════════════════════════════════════════════
# HELP
# ══════════════════════════════════════════════════════════════════════════════

if ($Help) {
    Write-Host @'

  terminal-kniferoll  |  Windows Installer

  USAGE
      .\install_windows.ps1 [OPTIONS]

  OPTIONS
      (none)        Interactive menu — pick from 4 grouped choices
      -Full         Install everything (Shell + Projector)
      -Shell        Shell experience only (Oh My Posh, PS profile, aliases)
      -Projector    Projector tools only (fastfetch, cmatrix, Python)
      -Custom       Choose individual tool groups interactively
      -Help         Show this help and exit

  INSTALL GROUPS
      [1] Full        Shell environment + Terminal projector  (recommended)
      [2] Shell only  PowerShell profile + Oh My Posh + plugins + aliases
      [3] Projector   Terminal animation suite (fastfetch, cmatrix, Python)
      [4] Custom      Choose individual tool groups

  PACKAGE MANAGER PRIORITY
      1. winget   (built-in Windows 10 1809+)
      2. Scoop    (user-space, no elevation)
      3. Chocolatey (tertiary fallback)

  LOG FILE
      %USERPROFILE%\.terminal-kniferoll\logs\install_<timestamp>.log

'@
    exit 0
}

# ══════════════════════════════════════════════════════════════════════════════
# BANNER
# ══════════════════════════════════════════════════════════════════════════════

Write-Host ''
Write-Host '  ╔══════════════════════════════════════════════════════════════╗' -ForegroundColor DarkMagenta
Write-Host '  ║   T E R M I N A L   K N I F E R O L L                      ║' -ForegroundColor Cyan
Write-Host '  ║   Windows Installer  //  winget + Scoop + PS modules        ║' -ForegroundColor DarkCyan
Write-Host '  ╚══════════════════════════════════════════════════════════════╝' -ForegroundColor DarkMagenta
Write-Host ''
Write-Host "  Log → $LogFile" -ForegroundColor DarkGray
Write-Host ''

# ══════════════════════════════════════════════════════════════════════════════
# ENVIRONMENT CHECKS
# ══════════════════════════════════════════════════════════════════════════════

# PowerShell version gate (redundant with #Requires but gives a clear message)
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Die "PowerShell 5.1 or newer is required. Current: $($PSVersionTable.PSVersion)"
}
Write-Info "PowerShell $($PSVersionTable.PSVersion) detected"

# Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if ($isAdmin) {
    Write-Info "Running as Administrator"
} else {
    Write-Warn "Not running as Administrator — winget and module installs may prompt for UAC"
}

# WSL detection
$wslPresent = Test-Path "$env:SystemRoot\system32\wsl.exe"
if ($wslPresent) {
    Write-Info "WSL detected — tip: run install_linux.sh inside WSL for a full Zsh/Oh-My-Zsh environment"
}

# ══════════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

function Test-Cmd {
    param([string]$Name)
    [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Refresh-EnvPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $userPath    = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    $env:PATH    = "$machinePath;$userPath"
    $extraPaths  = @(
        "$env:USERPROFILE\.cargo\bin",
        "$env:USERPROFILE\scoop\shims",
        "$env:USERPROFILE\AppData\Local\Programs\oh-my-posh\bin"
    )
    foreach ($p in $extraPaths) {
        if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) {
            $env:PATH += ";$p"
        }
    }
}

function Invoke-Optional {
    param(
        [string]$Description,
        [scriptblock]$Action
    )
    Write-Info $Description
    try {
        & $Action
        Write-OK $Description
        return $true
    } catch {
        Write-Warn "$Description — $($_.Exception.Message)"
        return $false
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# PACKAGE MANAGER BOOTSTRAP
# ══════════════════════════════════════════════════════════════════════════════

function Initialize-PackageManagers {
    Write-Section "Package Manager Bootstrap"

    # ── winget ──
    if (Test-Cmd winget) {
        Write-OK "winget available — $(winget --version 2>$null)"
    } else {
        Write-Warn "winget not found. Install 'App Installer' from the Microsoft Store, or upgrade to Windows 10 1809+."
    }

    # ── Scoop ──
    if (Test-Cmd scoop) {
        Write-OK "Scoop already installed"
    } else {
        Invoke-Optional "Installing Scoop (user-space)" {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Invoke-RestMethod get.scoop.sh | Invoke-Expression
            Refresh-EnvPath
        }
    }

    # Scoop extras bucket (has many tools)
    if (Test-Cmd scoop) {
        $buckets = scoop bucket list 2>$null
        if ($buckets -notmatch 'extras') {
            Invoke-Optional "Adding Scoop extras bucket" { scoop bucket add extras }
        }
        if ($buckets -notmatch 'nerd-fonts') {
            Invoke-Optional "Adding Scoop nerd-fonts bucket" { scoop bucket add nerd-fonts }
        }
    }

    # ── Chocolatey ──
    if (Test-Cmd choco) {
        Write-OK "Chocolatey already installed"
    } else {
        Invoke-Optional "Installing Chocolatey" {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
            Refresh-EnvPath
        }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# WINGET INSTALL HELPER
# ══════════════════════════════════════════════════════════════════════════════

function Install-Winget {
    param(
        [string]$Id,
        [string]$DisplayName,
        [string]$CheckCmd = ''
    )
    if ($CheckCmd -and (Test-Cmd $CheckCmd)) {
        Write-OK "$DisplayName already installed"
        return
    }
    if (-not (Test-Cmd winget)) {
        Write-Warn "winget not available — skipping $DisplayName"
        return
    }
    Invoke-Optional "Installing $DisplayName via winget" {
        winget install --id $Id --silent --accept-package-agreements --accept-source-agreements --no-upgrade 2>&1 | Out-Null
        Refresh-EnvPath
    }
}

function Install-Scoop {
    param(
        [string]$Package,
        [string]$DisplayName = '',
        [string]$CheckCmd = ''
    )
    if ($DisplayName -eq '') { $DisplayName = $Package }
    if ($CheckCmd -and (Test-Cmd $CheckCmd)) {
        Write-OK "$DisplayName already installed"
        return
    }
    if (-not (Test-Cmd scoop)) {
        Write-Warn "Scoop not available — skipping $DisplayName"
        return
    }
    Invoke-Optional "Installing $DisplayName via Scoop" {
        scoop install $Package 2>&1 | Out-Null
        Refresh-EnvPath
    }
}

function Install-PsModule {
    param(
        [string]$Name,
        [switch]$Force,
        [switch]$AllowClobber
    )
    if (Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue) {
        Write-OK "PS module $Name already installed"
        return
    }
    $args = @{ Name = $Name; Scope = 'CurrentUser'; ErrorAction = 'Stop' }
    if ($Force)       { $args['Force'] = $true }
    if ($AllowClobber){ $args['AllowClobber'] = $true }
    Invoke-Optional "Installing PowerShell module $Name" {
        Install-Module @args
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# SHELL INSTALL
# ══════════════════════════════════════════════════════════════════════════════

function Install-ShellExperience {
    Write-Section "Shell Experience"

    # ── Core CLI tools ──
    Install-Winget  'Git.Git'                    'Git'       'git'
    Install-Winget  'JanDeDobbeleer.OhMyPosh'    'Oh My Posh' 'oh-my-posh'
    Install-Winget  'junegunn.fzf'               'fzf'       'fzf'
    Install-Winget  'ajeetdsouza.zoxide'         'zoxide'    'zoxide'
    Install-Winget  'sharkdp.bat'                'bat'       'bat'
    Install-Winget  'BurntSushi.ripgrep.MSVC'    'ripgrep'   'rg'
    Install-Winget  'Neovim.Neovim'              'Neovim'    'nvim'
    Install-Scoop   'lsd'                        'lsd'       'lsd'
    Install-Scoop   'btop'                       'btop'      'btop'

    # ── Nerd Fonts ──
    $NerdFonts = @(
        'Iosevka', 'Hack', 'UbuntuMono', 'JetBrainsMono', '3270',
        'FiraCode', 'CascadiaCode', 'VictorMono', 'Mononoki',
        'SpaceMono', 'SourceCodePro', 'Meslo', 'GeistMono'
    )
    if (Test-Cmd oh-my-posh) {
        foreach ($nf in $NerdFonts) {
            Invoke-Optional "Installing $nf Nerd Font" {
                oh-my-posh font install $nf 2>&1 | Out-Null
            }
        }
    } elseif (Test-Cmd scoop) {
        foreach ($nf in $NerdFonts) {
            Install-Scoop "${nf}-NF" "$nf Nerd Font"
        }
    }

    # ── PowerShell Modules ──
    Write-Section "PowerShell Modules"

    # Ensure NuGet provider is available (required for Install-Module)
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Invoke-Optional "Installing NuGet package provider" {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        }
    }

    # Trust PSGallery silently
    $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if ($psGallery -and $psGallery.InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }

    Install-PsModule 'posh-git'         -AllowClobber
    Install-PsModule 'PSReadLine'       -Force -AllowClobber
    Install-PsModule 'Terminal-Icons'   -Force
    Install-PsModule 'PSFzf'            -Force

    # ── Deploy PowerShell Profile ──
    Deploy-PSProfile

    # ── Deploy Windows Terminal Settings ──
    Deploy-WTSettings
}

# ══════════════════════════════════════════════════════════════════════════════
# POWERSHELL PROFILE DEPLOYMENT
# ══════════════════════════════════════════════════════════════════════════════

function Deploy-PSProfile {
    Write-Section "PowerShell Profile"

    $profileDir = Split-Path $PROFILE -Parent
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    }

    # Back up existing profile
    if (Test-Path $PROFILE) {
        $backup = "$PROFILE.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $PROFILE $backup -Force
        Write-Info "Existing profile backed up → $backup"
    }

    $profileContent = @'
# ==============================================================================
# terminal-kniferoll | PowerShell Profile
# Generated by install_windows.ps1
# ==============================================================================

# ── Oh My Posh ────────────────────────────────────────────────────────────────
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    $ompTheme = "$env:POSH_THEMES_PATH\jandedobbeleer.omp.json"
    if (-not (Test-Path $ompTheme)) {
        $ompTheme = "jandedobbeleer"
    }
    oh-my-posh init pwsh --config $ompTheme | Invoke-Expression
}

# ── PSReadLine (autosuggestions + syntax highlighting) ────────────────────────
if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineOption -Colors @{
        Command   = 'Cyan'
        Parameter = 'DarkCyan'
        String    = 'Green'
        Keyword   = 'Magenta'
        Comment   = 'DarkGray'
        Error     = 'Red'
    }
}

# ── Terminal-Icons ────────────────────────────────────────────────────────────
if (Get-Module -ListAvailable Terminal-Icons) {
    Import-Module Terminal-Icons
}

# ── posh-git ──────────────────────────────────────────────────────────────────
if (Get-Module -ListAvailable posh-git) {
    Import-Module posh-git
}

# ── zoxide ────────────────────────────────────────────────────────────────────
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# ── fzf / PSFzf ───────────────────────────────────────────────────────────────
if ((Get-Command fzf -ErrorAction SilentlyContinue) -and (Get-Module -ListAvailable PSFzf)) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}

# ── Aliases & Functions ───────────────────────────────────────────────────────

# ls replacements
if (Get-Command lsd -ErrorAction SilentlyContinue) {
    function ls  { lsd $args }
    function l   { lsd -l $args }
    function la  { lsd -la $args }
    function ll  { lsd -lA $args }
    function lr  { lsd -latr $args }
    function lt  { lsd --tree $args }
} else {
    function l  { Get-ChildItem $args }
    function la { Get-ChildItem -Force $args }
    function ll { Get-ChildItem -Force $args | Format-List }
}

# cat replacement
if (Get-Command bat -ErrorAction SilentlyContinue) {
    function cat { bat $args }
}

# Editor
if (Get-Command nvim -ErrorAction SilentlyContinue) {
    Set-Alias vim  nvim
    Set-Alias vi   nvim
    Set-Alias nano nvim
}

# Networking
function myip  { (Invoke-WebRequest -Uri 'https://icanhazip.com' -UseBasicParsing).Content.Trim() }

# Shell management
function reload { . $PROFILE; Write-Host "Profile reloaded." -ForegroundColor Cyan }
function ff     {
    if (Get-Command fastfetch -ErrorAction SilentlyContinue) { fastfetch }
    else { Write-Host "fastfetch not installed." -ForegroundColor Yellow }
}

# Navigation
function ..   { Set-Location .. }
function ...  { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

# Git shortcuts
function gs { git status }
function ga { git add $args }
function gc { git commit $args }
function gp { git push }
function gl { git --no-pager log --oneline -10 }
function gd { git --no-pager diff }
function gb { git branch $args }
function gco { git checkout $args }
function gpl { git pull }

# Grep
if (Get-Command rg -ErrorAction SilentlyContinue) {
    Set-Alias grep rg
}

# ── PRIVATE API Keys (loaded from environment, never hardcoded) ───────────────
# Set these in your user environment or a secrets manager:
#   $env:PRIVATE_VT_API_KEY, $env:PRIVATE_PT_API_KEY, etc.
if ($env:PRIVATE_VT_API_KEY)       { $env:VT_API_KEY        = $env:PRIVATE_VT_API_KEY }
if ($env:PRIVATE_PT_API_KEY)       { $env:PT_API_KEY        = $env:PRIVATE_PT_API_KEY }
if ($env:PRIVATE_PT_API_USER)      { $env:PT_API_USER       = $env:PRIVATE_PT_API_USER }
if ($env:PRIVATE_IP2WHOIS_API_KEY) { $env:IP2WHOIS_API_KEY  = $env:PRIVATE_IP2WHOIS_API_KEY }
if ($env:PRIVATE_SHODAN_API_KEY)   { $env:SHODAN_API_KEY    = $env:PRIVATE_SHODAN_API_KEY }
if ($env:PRIVATE_GREYNOISE_API_KEY){ $env:GREYNOISE_API_KEY = $env:PRIVATE_GREYNOISE_API_KEY }
if ($env:PRIVATE_ABUSEIPDB_API_KEY){ $env:ABUSEIPDB_API_KEY = $env:PRIVATE_ABUSEIPDB_API_KEY }

# ── Welcome ───────────────────────────────────────────────────────────────────
if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
    fastfetch
}
'@

    try {
        Set-Content -Path $PROFILE -Value $profileContent -Encoding UTF8 -Force
        Write-OK "PowerShell profile deployed → $PROFILE"
    } catch {
        Write-Warn "Could not write profile: $($_.Exception.Message)"
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# WINDOWS TERMINAL SETTINGS DEPLOYMENT
# ══════════════════════════════════════════════════════════════════════════════

function Deploy-WTSettings {
    Write-Section "Windows Terminal Settings"

    $scriptDir = Split-Path $MyInvocation.PSCommandPath -Parent
    $sourceSettings = Join-Path $scriptDir 'windows\settings.json'

    if (-not (Test-Path $sourceSettings)) {
        Write-Warn "windows\settings.json not found in repo — skipping WT deployment"
        return
    }

    # Locate Windows Terminal LocalState directory
    $wtPaths = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState"
    )
    $wtDir = $null
    foreach ($p in $wtPaths) {
        if (Test-Path $p) { $wtDir = $p; break }
    }

    if (-not $wtDir) {
        Write-Warn "Windows Terminal LocalState directory not found — is Windows Terminal installed?"
        return
    }

    $targetSettings = Join-Path $wtDir 'settings.json'

    # Back up existing settings
    if (Test-Path $targetSettings) {
        $backup = "$targetSettings.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $targetSettings $backup -Force
        Write-Info "Existing WT settings backed up → $backup"
    }

    try {
        Copy-Item $sourceSettings $targetSettings -Force
        Write-OK "Windows Terminal settings deployed (Cyberwave color scheme)"
    } catch {
        Write-Warn "Could not deploy WT settings: $($_.Exception.Message)"
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# PROJECTOR INSTALL
# ══════════════════════════════════════════════════════════════════════════════

function Install-Projector {
    Write-Section "Projector Stack"

    Install-Winget 'fastfetch-cli.fastfetch' 'fastfetch' 'fastfetch'
    Install-Winget 'Python.Python.3.12'      'Python 3.12' 'python'
    Install-Scoop  'cmatrix'                 'cmatrix'   'cmatrix'

    # cbonsai: no native Windows build available
    Write-Warn "cbonsai — no native Windows binary; run inside WSL if desired"

    # Run projector.py if available
    $scriptDir   = Split-Path $MyInvocation.PSCommandPath -Parent
    $projectorPy = Join-Path $scriptDir 'projector.py'
    if ((Test-Path $projectorPy) -and (Test-Cmd python)) {
        Write-Info "Launching projector.py…"
        try {
            & python $projectorPy
        } catch {
            Write-Warn "projector.py failed: $($_.Exception.Message)"
        }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# INSTALL MODE SELECTION
# ══════════════════════════════════════════════════════════════════════════════

$doShell     = $false
$doProjector = $false

if ($Full -or (-not $Shell -and -not $Projector -and -not $Custom -and -not $Full)) {
    # Default (no flags) → show interactive menu
    if (-not $Full) {
        Write-Host ''
        Write-Host '  Select install mode:' -ForegroundColor White
        Write-Host ''
        Write-Host '    [1]  Full        Shell environment + Terminal projector  (recommended)' -ForegroundColor Cyan
        Write-Host '    [2]  Shell only  PowerShell profile + Oh My Posh + plugins + aliases' -ForegroundColor Cyan
        Write-Host '    [3]  Projector   Terminal animation suite (fastfetch, cmatrix, Python)' -ForegroundColor Cyan
        Write-Host '    [4]  Custom      Choose individual tool groups' -ForegroundColor Cyan
        Write-Host ''
        $choice = Read-Host '  Enter choice [1-4] (default: 1)'
        if ($choice -eq '') { $choice = '1' }

        switch ($choice) {
            '1' { $doShell = $true; $doProjector = $true }
            '2' { $doShell = $true }
            '3' { $doProjector = $true }
            '4' {
                $ans = Read-Host '  Install Shell experience? [Y/n]'
                if ($ans -eq '' -or $ans -match '^[Yy]') { $doShell = $true }
                $ans = Read-Host '  Install Projector stack? [Y/n]'
                if ($ans -eq '' -or $ans -match '^[Yy]') { $doProjector = $true }
            }
            default { Write-Warn "Unknown choice '$choice' — defaulting to Full"; $doShell = $true; $doProjector = $true }
        }
    } else {
        # -Full flag
        $doShell     = $true
        $doProjector = $true
    }
} else {
    if ($Shell)     { $doShell = $true }
    if ($Projector) { $doProjector = $true }
    if ($Custom) {
        $ans = Read-Host '  Install Shell experience? [Y/n]'
        if ($ans -eq '' -or $ans -match '^[Yy]') { $doShell = $true }
        $ans = Read-Host '  Install Projector stack? [Y/n]'
        if ($ans -eq '' -or $ans -match '^[Yy]') { $doProjector = $true }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# EXECUTE
# ══════════════════════════════════════════════════════════════════════════════

Initialize-PackageManagers

if ($doShell)     { Install-ShellExperience }
if ($doProjector) { Install-Projector }

# ══════════════════════════════════════════════════════════════════════════════
# DONE
# ══════════════════════════════════════════════════════════════════════════════

Write-Host ''
Write-Host '  ╔══════════════════════════════════════════════════════════════╗' -ForegroundColor DarkGreen
Write-Host '  ║   [✓]  Installation complete!                               ║' -ForegroundColor Green
Write-Host '  ╚══════════════════════════════════════════════════════════════╝' -ForegroundColor DarkGreen
Write-Host ''
if ($doShell) {
    Write-Host '  Next steps:' -ForegroundColor White
    Write-Host '    1. Restart your terminal (or run: . $PROFILE)' -ForegroundColor DarkCyan
    Write-Host '    2. Set your Windows Terminal font to "CaskaydiaCove Nerd Font"' -ForegroundColor DarkCyan
    Write-Host '    3. Enjoy your new shell  ¯\_(ツ)_/¯' -ForegroundColor DarkCyan
}
if ($wslPresent -and -not $doShell) {
    Write-Host '  WSL tip: run install_linux.sh inside WSL for a full Zsh environment' -ForegroundColor DarkYellow
}
Write-Host ''
Write-Host "  Full log: $LogFile" -ForegroundColor DarkGray
Write-Host ''
