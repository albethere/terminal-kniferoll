#requires -Version 5.1
<#
.SYNOPSIS
    terminal-kniferoll | Windows Installer
.DESCRIPTION
    Installs all dependencies for terminal-kniferoll on Windows.
    Uses winget as primary package manager with chocolatey fallback.
.PARAMETER Interactive
    Prompt before each major section instead of installing everything.
.PARAMETER Help
    Show this help message and exit.
.NOTES
    Run as Administrator for full functionality.
    PowerShell 7+ recommended for best compatibility.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Interactive,
    [switch]$Shell,
    [switch]$Projector,
    [Alias('h')]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ── Colors / Logging ─────────────────────────────────────────────────────────

function Write-OK   { param([string]$m) Write-Host "[OK] $m" -ForegroundColor Green }
function Write-Info { param([string]$m) Write-Host " *  $m" -ForegroundColor Cyan }
function Write-Warn { param([string]$m) Write-Host " !  $m" -ForegroundColor Yellow }
function Write-Die  { param([string]$m) Write-Host "[!!] FATAL: $m" -ForegroundColor Red; exit 1 }

function Test-Cmd {
    param([string]$Name)
    [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Ask-YesNo {
    param([string]$Prompt)
    if (-not $script:Interactive) { return $true }
    $choice = Read-Host "[?] $Prompt [Y/n]"
    return ($choice -eq '' -or $choice -match '^[Yy]$')
}

function Invoke-Step {
    param(
        [string]$Description,
        [scriptblock]$Action
    )
    Write-Info $Description
    try {
        & $Action
        Write-OK $Description
    } catch {
        Write-Warn "$Description failed: $($_.Exception.Message)"
    }
}

function Refresh-Path {
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    if (Test-Path "$env:USERPROFILE\.cargo\bin") {
        $env:PATH += ";$env:USERPROFILE\.cargo\bin"
    }
}

# ── Help ─────────────────────────────────────────────────────────────────────

if ($Help) {
    Write-Host @"
Usage: install_windows.ps1 [-Interactive] [-Shell] [-Projector] [-Help] [-WhatIf]

Options:
  -Interactive   Prompt before each section instead of installing everything
  -Shell         Install only shell experience (skip projector stack)
  -Projector     Install only projector stack (skip shell experience)
  -Help          Show this help message and exit
  -WhatIf        Preview what would happen without making changes

Sections installed:
  Core       git, python, golang, nodejs
  Shell      PowerShell modules (PSReadLine, Terminal-Icons, oh-my-posh), profile
  Security   1Password CLI, shared payload tools (fzf, ripgrep, jq, etc.)
  Projector  Rust toolchain, cargo tools (bat, lsd, sd, weathr), fonts, config

Without -Interactive, all sections are installed (batch mode).
"@
    exit 0
}

# ── Banner ───────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '  ================================================================' -ForegroundColor Magenta
Write-Host '    T E R M I N A L   K N I F E R O L L' -ForegroundColor Cyan
Write-Host '  ================================================================' -ForegroundColor Magenta
Write-Host '  Windows Installer' -ForegroundColor Cyan
Write-Host ''

# ── Windows Version Gate ─────────────────────────────────────────────────────

$winVer = [System.Environment]::OSVersion.Version
if ($winVer.Major -lt 10) {
    Write-Die "Windows 10+ required. Detected: $($winVer.ToString())"
}
Write-OK "Windows $($winVer.Major).$($winVer.Minor) build $($winVer.Build)"

# ── Admin Check ──────────────────────────────────────────────────────────────

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Warn 'Not running as Administrator - some installs may request elevation.'
    Write-Warn 'winget/choco may silently hang waiting for UAC. Consider re-running as Administrator.'
}

# ── ExecutionPolicy ──────────────────────────────────────────────────────────

try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
    Write-OK 'ExecutionPolicy: RemoteSigned (CurrentUser)'
} catch {
    Write-Warn "Could not set ExecutionPolicy: $_"
}

# ── Package Manager Detection ────────────────────────────────────────────────

Write-Info 'Detecting package manager...'

$PKG = $null

if (Test-Cmd 'winget') {
    $PKG = 'winget'
    Write-OK 'winget detected (primary)'
} elseif (Test-Cmd 'choco') {
    $PKG = 'choco'
    Write-OK 'Chocolatey detected (fallback)'
} else {
    Write-Warn 'No package manager found (winget / choco).'
    Write-Warn 'winget ships with Windows 10/11 via App Installer from the Microsoft Store.'
    $PKG = 'manual'
}

# ── Install Helper ───────────────────────────────────────────────────────────

function Install-Pkg {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Name,
        [string]$WingetId  = '',
        [string]$ChocoName = '',
        [string]$TestCmd   = $Name
    )

    if (Test-Cmd $TestCmd) {
        Write-OK "$Name already installed"
        return
    }

    if (-not $PSCmdlet.ShouldProcess($Name, 'Install')) { return }

    Write-Info "Installing $Name..."
    $installed = $false

    if ($script:PKG -eq 'winget' -and $WingetId) {
        try {
            & winget install --id $WingetId --accept-source-agreements --accept-package-agreements -e --silent 2>&1 | Out-Null
            $installed = $true
        } catch {
            Write-Warn "winget failed for $Name; trying choco fallback..."
        }
    }

    if (-not $installed -and $ChocoName -and (Test-Cmd 'choco')) {
        try {
            & choco install $ChocoName -y 2>&1 | Out-Null
            $installed = $true
        } catch {
            Write-Warn "choco also failed for $Name."
        }
    }

    if (-not $installed -and $script:PKG -eq 'manual') {
        Write-Warn "Manual mode: install $Name yourself."
        return
    }

    Refresh-Path

    if (Test-Cmd $TestCmd) {
        Write-OK "$Name installed"
    } else {
        Write-Warn "$Name may not be in PATH yet. Restart your terminal after this script."
    }
}

# ── Interactive Questions ────────────────────────────────────────────────────

# -Shell means skip projector; -Projector means skip shell; neither means both
$INSTALL_SHELL     = -not $Projector -or $Shell
$INSTALL_PROJECTOR = -not $Shell     -or $Projector

$DO_CORE      = Ask-YesNo 'Install core prerequisites (git, python, golang, nodejs)?'
$DO_SHELL     = $INSTALL_SHELL     -and (Ask-YesNo 'Install shell experience (PSReadLine, Terminal-Icons, oh-my-posh)?')
$DO_SECURITY  = Ask-YesNo 'Install security/developer tools (1Password CLI, shared payload)?'
$DO_PROJECTOR = $INSTALL_PROJECTOR -and (Ask-YesNo 'Install projector stack (Rust, cargo tools, fonts)?')

# ══════════════════════════════════════════════════════════════════════════════
# 1. CORE PREREQUISITES
# ══════════════════════════════════════════════════════════════════════════════

if ($DO_CORE) {
    Write-Host ''
    Write-Info '── Core Prerequisites ──'

    Install-Pkg -Name 'Git'      -WingetId 'Git.Git'            -ChocoName 'git'        -TestCmd 'git'
    Install-Pkg -Name 'Python'   -WingetId 'Python.Python.3.12' -ChocoName 'python3'    -TestCmd 'python'
    Install-Pkg -Name 'Go'       -WingetId 'GoLang.Go'          -ChocoName 'golang'     -TestCmd 'go'
    Install-Pkg -Name 'Node.js'  -WingetId 'OpenJS.NodeJS.LTS'  -ChocoName 'nodejs-lts' -TestCmd 'node'

    if (Test-Cmd 'python') {
        try {
            $pyVer = & python --version 2>&1
            if ($pyVer -match '(\d+)\.(\d+)') {
                $maj = [int]$Matches[1]; $min = [int]$Matches[2]
                if ($maj -lt 3 -or ($maj -eq 3 -and $min -lt 10)) {
                    Write-Warn "Python $($Matches[0]) found but 3.10+ recommended."
                } else {
                    Write-OK "Python $($Matches[0]) verified"
                }
            }
        } catch { Write-Warn 'Could not verify Python version.' }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# 2. SHELL EXPERIENCE
# ══════════════════════════════════════════════════════════════════════════════

if ($DO_SHELL) {
    Write-Host ''
    Write-Info '── Shell Experience ──'

    # NuGet provider (required for Install-Module)
    Invoke-Step 'Ensuring NuGet package provider' {
        $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nuget -or $nuget.Version -lt [version]'2.8.5.201') {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
            $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
            if (-not $nuget) {
                throw 'NuGet provider installation failed - Install-Module may not work'
            }
        }
    }

    # PSReadLine
    Invoke-Step 'Installing/updating PSReadLine' {
        Install-Module -Name PSReadLine -Scope CurrentUser -Force -SkipPublisherCheck -ErrorAction Stop
    }

    # Terminal-Icons
    if (Get-Module -ListAvailable -Name Terminal-Icons) {
        Write-OK 'Terminal-Icons already installed'
    } else {
        Invoke-Step 'Installing Terminal-Icons' {
            Install-Module -Name Terminal-Icons -Scope CurrentUser -Force -ErrorAction Stop
        }
    }

    # oh-my-posh
    if (Test-Cmd 'oh-my-posh') {
        Write-OK 'oh-my-posh already installed'
    } else {
        Install-Pkg -Name 'oh-my-posh' -WingetId 'JanDeDobbeleer.OhMyPosh' -ChocoName 'oh-my-posh' -TestCmd 'oh-my-posh'
    }

    # Windows Terminal
    if ($env:WT_SESSION) {
        Write-OK 'Windows Terminal detected'
    } else {
        Write-Warn 'Windows Terminal recommended for best experience.'
        Install-Pkg -Name 'Windows Terminal' -WingetId 'Microsoft.WindowsTerminal' -ChocoName 'microsoft-windows-terminal' -TestCmd 'wt'
    }

    # PowerShell profile
    $profileDir = Split-Path -Parent $PROFILE
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    $profileBlock = @'

# ── terminal-kniferoll ──
if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons
}
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh | Invoke-Expression
}
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}
# ── end terminal-kniferoll ──
'@

    if (Test-Path $PROFILE) {
        $existing = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
        if ($existing -and $existing.Contains('terminal-kniferoll')) {
            Write-OK 'PowerShell profile already configured'
        } else {
            Add-Content -Path $PROFILE -Value $profileBlock
            Write-OK "PowerShell profile updated: $PROFILE"
        }
    } else {
        Set-Content -Path $PROFILE -Value $profileBlock.TrimStart()
        Write-OK "PowerShell profile created: $PROFILE"
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# 3. SECURITY / DEVELOPER TOOLS
# ══════════════════════════════════════════════════════════════════════════════

if ($DO_SECURITY) {
    Write-Host ''
    Write-Info '── Security / Developer Tools ──'

    # 1Password CLI
    Install-Pkg -Name '1Password CLI' -WingetId 'AgileBits.1Password.CLI' -ChocoName '1password-cli' -TestCmd 'op'

    # Shared payload tools with Windows builds
    Install-Pkg -Name 'fzf'       -WingetId 'junegunn.fzf'            -ChocoName 'fzf'       -TestCmd 'fzf'
    Install-Pkg -Name 'ripgrep'   -WingetId 'BurntSushi.ripgrep.MSVC' -ChocoName 'ripgrep'   -TestCmd 'rg'
    Install-Pkg -Name 'jq'        -WingetId 'jqlang.jq'               -ChocoName 'jq'        -TestCmd 'jq'
    Install-Pkg -Name 'fastfetch' -WingetId 'Fastfetch-cli.Fastfetch' -ChocoName 'fastfetch' -TestCmd 'fastfetch'
    Install-Pkg -Name 'btop'      -WingetId 'aristocratos.btop4win'   -ChocoName 'btop'      -TestCmd 'btop'
    Install-Pkg -Name 'hexyl'     -WingetId 'sharkdp.hexyl'           -ChocoName 'hexyl'     -TestCmd 'hexyl'
    Install-Pkg -Name 'starship'  -WingetId 'Starship.Starship'       -ChocoName 'starship'  -TestCmd 'starship'
    Install-Pkg -Name 'zoxide'    -WingetId 'ajeetdsouza.zoxide'      -ChocoName 'zoxide'    -TestCmd 'zoxide'
    Install-Pkg -Name 'tealdeer'  -WingetId 'dbrgn.tealdeer'          -ChocoName 'tealdeer'  -TestCmd 'tldr'
    Install-Pkg -Name 'micro'     -WingetId 'zyedidia.micro'          -ChocoName 'micro'     -TestCmd 'micro'
    Install-Pkg -Name 'sqlite'    -WingetId 'SQLite.SQLite'           -ChocoName 'sqlite'    -TestCmd 'sqlite3'
    Install-Pkg -Name 'nmap'      -WingetId 'Insecure.Nmap'           -ChocoName 'nmap'      -TestCmd 'nmap'
    Install-Pkg -Name 'rclone'    -WingetId 'Rclone.Rclone'           -ChocoName 'rclone'    -TestCmd 'rclone'
    Install-Pkg -Name 'mise'      -WingetId 'jdx.mise'                -ChocoName 'mise'      -TestCmd 'mise'

    # pipx + wtfis (requires Python)
    if (Test-Cmd 'python') {
        if (-not (Test-Cmd 'pipx')) {
            Invoke-Step 'Installing pipx' { & python -m pip install --user pipx 2>&1 | Out-Null }
            Refresh-Path
        }
        if ((Test-Cmd 'pipx') -and -not (Test-Cmd 'wtfis')) {
            Invoke-Step 'Installing wtfis via pipx' {
                & pipx install wtfis 2>&1 | Out-Null
                & pipx ensurepath 2>&1 | Out-Null
            }
        }
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# 4. PROJECTOR STACK
# ══════════════════════════════════════════════════════════════════════════════

if ($DO_PROJECTOR) {
    Write-Host ''
    Write-Info '── Projector Stack ──'

    # Rust / Cargo
    if (Test-Cmd 'cargo') {
        Write-OK 'Rust/Cargo already installed'
    } else {
        Install-Pkg -Name 'Rust (rustup)' -WingetId 'Rustlang.Rustup' -ChocoName 'rustup.install' -TestCmd 'rustup'
        if (Test-Cmd 'rustup') {
            Invoke-Step 'Setting default Rust toolchain to stable' {
                & rustup default stable 2>&1 | Out-Null
            }
            $env:PATH += ";$env:USERPROFILE\.cargo\bin"
            Refresh-Path
        }
    }

    # Verify toolchain health
    if (Test-Cmd 'rustup') {
        $healthy = $false
        try {
            $toolchainOut = & rustup show active-toolchain 2>&1
            if ($LASTEXITCODE -eq 0) { $healthy = $true }
        } catch {
            Write-Warn "Could not verify Rust toolchain: $($_.Exception.Message)"
        }
        if (-not $healthy) {
            Invoke-Step 'Repairing Rust toolchain' { & rustup default stable 2>&1 | Out-Null }
        }
    }

    # Cargo tools
    if (Test-Cmd 'cargo') {
        $cargoTools = @(
            @{ Name = 'bat';      Crate = 'bat';      Cmd = 'bat' }
            @{ Name = 'lsd';      Crate = 'lsd';      Cmd = 'lsd' }
            @{ Name = 'sd';       Crate = 'sd';       Cmd = 'sd' }
            @{ Name = 'nu';       Crate = 'nu';       Cmd = 'nu' }
            @{ Name = 'yazi-fm';  Crate = 'yazi-fm';  Cmd = 'yazi' }
            @{ Name = 'yazi-cli'; Crate = 'yazi-cli'; Cmd = 'ya' }
            @{ Name = 'atuin';    Crate = 'atuin';    Cmd = 'atuin' }
            @{ Name = 'weathr';   Crate = 'weathr';   Cmd = 'weathr' }
            @{ Name = 'trippy';   Crate = 'trippy';   Cmd = 'trip' }
        )
        foreach ($t in $cargoTools) {
            if (Test-Cmd $t.Cmd) {
                Write-OK "$($t.Name) already installed"
            } else {
                Invoke-Step "Installing $($t.Name) via cargo (may take a few minutes)" {
                    & cargo install $t.Crate 2>&1 | Out-Null
                }
            }
        }
    } else {
        Write-Warn 'Cargo not available - skipping cargo tool installs.'
    }

    # JetBrainsMono Nerd Font
    $fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    $fontInstalled = $false
    if (Test-Path $fontDir) {
        $fontInstalled = @(Get-ChildItem $fontDir -Filter '*JetBrainsMono*' -ErrorAction SilentlyContinue).Count -gt 0
    }
    if (-not $fontInstalled) {
        Invoke-Step 'Installing JetBrainsMono Nerd Font' {
            $fontZip = Join-Path $env:USERPROFILE 'JetBrainsMono.zip'
            $fontExtract = Join-Path $env:USERPROFILE 'JetBrainsMono_nf'
            Invoke-WebRequest -Uri 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip' -OutFile $fontZip -UseBasicParsing -ErrorAction Stop
            if (-not (Test-Path $fontZip) -or (Get-Item $fontZip).Length -lt 1024) {
                throw "Font download failed or file is too small ($(if (Test-Path $fontZip) { (Get-Item $fontZip).Length } else { 0 }) bytes)"
            }
            Expand-Archive -Path $fontZip -DestinationPath $fontExtract -Force
            $shell = New-Object -ComObject Shell.Application
            $fontsFolder = $shell.Namespace(0x14)
            Get-ChildItem $fontExtract -Filter '*.ttf' | ForEach-Object {
                $fontsFolder.CopyHere($_.FullName, 0x14)
            }
            Remove-Item $fontZip -Force -ErrorAction SilentlyContinue
            Remove-Item $fontExtract -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-OK 'JetBrainsMono Nerd Font already installed'
    }

    # Projector config
    $SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
    $configDir = Join-Path $env:APPDATA 'projector'
    $configFile = Join-Path $configDir 'config.json'
    $defaultCfg = Join-Path $SCRIPT_DIR 'projector\config.json.default'

    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    if (-not (Test-Path $configFile) -and (Test-Path $defaultCfg)) {
        Copy-Item $defaultCfg $configFile
        Write-OK "Projector config deployed to $configFile"
    } elseif (Test-Path $configFile) {
        Write-OK 'Projector config already exists'
    }

    # projector.bat shim
    $projectorPy = Join-Path $SCRIPT_DIR 'projector.py'
    if (Test-Path $projectorPy) {
        $batContent = "@echo off`r`npython `"$projectorPy`" %*"
        Set-Content -Path (Join-Path $SCRIPT_DIR 'projector.bat') -Value $batContent -Encoding ASCII
        Write-OK 'Created projector.bat launcher'
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host '  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor Green
Write-Host '  Installation complete!' -ForegroundColor Green
Write-Host "  Launch with: python projector.py" -ForegroundColor Green
Write-Host "  Config at:   $env:APPDATA\projector\config.json" -ForegroundColor Green
Write-Host '  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━' -ForegroundColor Green
Write-Host ''
Write-Warn 'Restart your terminal to ensure all PATH changes take effect.'
