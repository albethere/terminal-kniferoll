#requires -Version 5.1
<#
.SYNOPSIS
    Terminal Projector - Windows Installer
.DESCRIPTION
    Installs all dependencies for Terminal Projector on Windows.
    Handles: winget, scoop, chocolatey (in priority order), Rust/Cargo,
    Python, and Windows Terminal detection.
.NOTES
    Run as Administrator for full functionality.
    PowerShell 7+ is recommended for best compatibility.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helper Functions ──────────────────────────────────────────────────────────
function Write-OK   { param($m) Write-Host "[OK] $m" -ForegroundColor Green }
function Write-Info { param($m) Write-Host " *   $m" -ForegroundColor Cyan }
function Write-Warn { param($m) Write-Host " !   $m" -ForegroundColor Yellow }
function Write-Die  { param($m) Write-Host "[!!] FATAL: $m" -ForegroundColor Red; exit 1 }

function Test-Command { param($cmd) return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Confirm-Choice {
    param([string]$Prompt, [string]$Default = 'N')
    $choice = Read-Host "$Prompt [y/N]"
    return $choice -match '^[Yy]$'
}

# ── Header ────────────────────────────────────────────────────────────────────
Clear-Host
Write-Host @"
  ╔══════════════════════════════════════════════╗
  ║   Terminal Projector – Windows Installer      ║
  ╚══════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# ── Windows Version Gate ───────────────────────────────────────────────────────
$winVer = [System.Environment]::OSVersion.Version
if ($winVer.Major -lt 10) {
    Write-Die "Windows 10 (1809+) or Windows 11 required. Detected: $($winVer.ToString())"
}
Write-OK "Windows $($winVer.Major).$($winVer.Minor) build $($winVer.Build) detected"

# ── Admin Check ───────────────────────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Warn "Not running as Administrator – some installs may fail or request elevation."
}

# ── ExecutionPolicy Fix ────────────────────────────────────────────────────────
try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Write-OK "ExecutionPolicy set to RemoteSigned for CurrentUser"
} catch {
    Write-Warn "Could not set ExecutionPolicy: $_"
}

# ── Package Manager Detection / Installation ──────────────────────────────────
Write-Info "Detecting package manager..."

$PKG_MANAGER = $null

# Priority 1: winget (ships with Windows 11 and modern Win10)
if (Test-Command 'winget') {
    $PKG_MANAGER = 'winget'
    Write-OK "winget detected (preferred)"
}

# Priority 2: Scoop
elseif (Test-Command 'scoop') {
    $PKG_MANAGER = 'scoop'
    Write-OK "Scoop detected"
}

# Priority 3: Chocolatey
elseif (Test-Command 'choco') {
    $PKG_MANAGER = 'choco'
    Write-OK "Chocolatey detected"
}

# None found – offer to install
else {
    Write-Warn "No supported package manager found (winget / scoop / choco)."
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor Yellow
    Write-Host "  1) Install Scoop (no admin needed, recommended)" -ForegroundColor White
    Write-Host "  2) Install Chocolatey (requires admin)" -ForegroundColor White
    Write-Host "  3) Skip – you will need to install packages manually" -ForegroundColor White
    $pkgChoice = Read-Host "  Choose [1/2/3]"

    switch ($pkgChoice) {
        '1' {
            Write-Info "Installing Scoop..."
            Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
            $env:PATH += ";$env:USERPROFILE\scoop\shims"
            $PKG_MANAGER = 'scoop'
            Write-OK "Scoop installed"
        }
        '2' {
            if (-not $isAdmin) { Write-Die "Chocolatey requires Administrator. Re-run this script as Admin." }
            Write-Info "Installing Chocolatey..."
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
            $PKG_MANAGER = 'choco'
            Write-OK "Chocolatey installed"
        }
        default {
            Write-Warn "Skipping package manager install. Manual installation required."
            $PKG_MANAGER = 'manual'
        }
    }
}

# ── Install helper ─────────────────────────────────────────────────────────────
function Install-Pkg {
    param(
        [string]$Name,
        [string]$WingetId   = '',
        [string]$ScoopName  = '',
        [string]$ChocoName  = '',
        [string]$TestCmd    = $Name
    )

    if (Test-Command $TestCmd) {
        Write-OK "$Name already installed"
        return
    }

    Write-Info "Installing $Name..."

    switch ($PKG_MANAGER) {
        'winget' {
            if ($WingetId)  { winget install --id $WingetId --accept-source-agreements --accept-package-agreements -e --silent }
            elseif ($ScoopName)  { scoop install $ScoopName }
            else { Write-Warn "$Name has no winget ID; skipping. Install manually." }
        }
        'scoop'  {
            if ($ScoopName) { scoop install $ScoopName }
            else            { Write-Warn "$Name not in scoop; skipping. Install manually." }
        }
        'choco'  {
            if ($ChocoName) { choco install $ChocoName -y }
            else            { Write-Warn "$Name not in choco; skipping. Install manually." }
        }
        default  { Write-Warn "Manual mode: please install $Name yourself." }
    }

    # Refresh PATH so newly installed binaries are discoverable
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('PATH', 'User')

    if (Test-Command $TestCmd) {
        Write-OK "$Name installed"
    } else {
        Write-Warn "$Name may not be in PATH yet. Please restart your terminal after this script completes."
    }
}

# ── Python ─────────────────────────────────────────────────────────────────────
Install-Pkg -Name 'Python' -WingetId 'Python.Python.3.12' -ScoopName 'python' -ChocoName 'python3' -TestCmd 'python'

# Verify version
try {
    $pyVer = & python --version 2>&1 | Select-String '\d+\.\d+' | ForEach-Object { $_.Matches[0].Value }
    $pyMajor, $pyMinor = $pyVer -split '\.'
    if ([int]$pyMajor -lt 3 -or ([int]$pyMajor -eq 3 -and [int]$pyMinor -lt 10)) {
        Write-Warn "Python $pyVer found but 3.10+ required. Please update manually."
    } else {
        Write-OK "Python $pyVer is sufficient"
    }
} catch {
    Write-Warn "Could not verify Python version."
}

# ── Rust / Cargo ───────────────────────────────────────────────────────────────
if (Test-Command 'cargo') {
    Write-OK "Rust $(rustc --version 2>$null | Select-String '\d+\.\d+' | ForEach-Object { $_.Matches[0].Value }) already installed"
} else {
    Write-Info "Installing Rust via rustup..."
    $rustupUrl = 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe'
    $rustupExe = "$env:TEMP\rustup-init.exe"
    Invoke-WebRequest -Uri $rustupUrl -OutFile $rustupExe
    & $rustupExe -y --quiet
    Remove-Item $rustupExe
    # Reload PATH
    $env:PATH += ";$env:USERPROFILE\.cargo\bin"
}

# Ensure a default toolchain is set if rustup is present
if (Test-Command 'rustup') {
    $default = & rustup default 2>&1
    if ($null -eq $default -or $default -match "no default toolchain") {
        Write-Info "No default toolchain detected. Setting to stable..."
        & rustup default stable
    }
}
Write-OK "Rust environment verified"

# ── weathr ────────────────────────────────────────────────────────────────────
if (Test-Command 'weathr') {
    Write-OK "weathr already installed"
} else {
    Write-Info "Compiling weathr via Cargo (may take a few minutes)..."
    cargo install weathr
    Write-OK "weathr installed"
}

# ── Scoop extras bucket (for some tools) ──────────────────────────────────────
if ($PKG_MANAGER -eq 'scoop') {
    scoop bucket add extras 2>$null
    scoop bucket add main   2>$null
}

# ── Tool installations ─────────────────────────────────────────────────────────
Install-Pkg -Name 'fastfetch' -WingetId 'Fastfetch-cli.Fastfetch' -ScoopName 'fastfetch' -ChocoName 'fastfetch'
Install-Pkg -Name 'btop'      -WingetId 'aristocratos.btop4win'   -ScoopName 'btop'      -ChocoName 'btop'
Install-Pkg -Name 'lolcat'    -ScoopName 'lolcat'                  -ChocoName 'lolcat'   -TestCmd  'lolcat'

# cmatrix – Windows port
if (Test-Command 'cmatrix') {
    Write-OK "cmatrix already installed"
} else {
    Write-Info "Installing cmatrix..."
    if ($PKG_MANAGER -eq 'scoop')  { scoop install cmatrix }
    elseif ($PKG_MANAGER -eq 'choco') { choco install cmatrix -y }
    elseif ($PKG_MANAGER -eq 'winget') {
        # cmatrix may not be on winget; fallback to scoop install inline
        Write-Warn "cmatrix may not be in winget. Trying scoop..."
        if (-not (Test-Command 'scoop')) {
            Write-Warn "Scoop not available. Install cmatrix manually or via: scoop install cmatrix"
        } else {
            scoop install cmatrix
        }
    }
}

# cbonsai – compile from source on Windows if not available
if (Test-Command 'cbonsai') {
    Write-OK "cbonsai already installed"
} elseif ($PKG_MANAGER -eq 'scoop') {
    Write-Info "Installing cbonsai via scoop..."
    scoop install cbonsai
    Write-OK "cbonsai installed"
} else {
    Write-Warn "cbonsai is not available in winget/choco. Install it via Scoop: scoop install cbonsai"
}

# ── Terminal Check ───────────────────────────────────────────────────
Write-Host ""
Write-Info "Checking terminal emulator..."

function Get-CurrentTerminal {
    if ($env:WT_SESSION)              { return 'windows-terminal' }
    if ($env:TERM_PROGRAM)            { return $env:TERM_PROGRAM }
    if ($env:ConEmuPID)               { return 'conemu' }
    return 'powershell-host'
}

$currentTerm = Get-CurrentTerminal

if ($currentTerm -eq 'windows-terminal') {
    Write-OK "Windows Terminal detected – ideal environment detected"
} else {
    Write-Warn "Terminal detected: $currentTerm"
    Write-Host ""
    Write-Host "  Windows Terminal is the recommended terminal for Terminal Projector." -ForegroundColor Yellow
    Write-Host "  It provides GPU-accelerated rendering and precise ANSI control." -ForegroundColor White
    Write-Host ""

    $installWT = Confirm-Choice "  Install Windows Terminal via winget?"
    if ($installWT) {
        Write-Info "Installing Windows Terminal..."
        if ($PKG_MANAGER -eq 'winget') {
            winget install --id Microsoft.WindowsTerminal --accept-source-agreements --accept-package-agreements -e --silent
            Write-OK "Windows Terminal installed. Launch it and re-run projector.py inside it for best results."
        } else {
            Write-Warn "winget is not available. Please install Windows Terminal from the Microsoft Store."
        }
    } else {
        Write-Host ""
        switch ($currentTerm) {
            'conemu' {
                Write-Warn "ConEmu detected – functional but may have ANSI rendering issues."
                Write-Warn "Consider switching to Windows Terminal."
            }
            'powershell-host' {
                Write-Warn "Raw PowerShell host detected – limited ANSI support."
                Write-Warn "Install Windows Terminal from the Microsoft Store for a better experience."
            }
            default {
                Write-Warn "Terminal '$currentTerm' detected. No specific overrides applied."
            }
        }
    }
}

# ── Windows Terminal Profile (bonus) ───────────────────────────────────────────
if ($currentTerm -eq 'windows-terminal') {
    $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (Test-Path $settingsPath) {
        Write-Info "Windows Terminal settings detected at $settingsPath"
        Write-Warn "Tip: Set 'defaultProfile' to a profile with 'opacity': 85 and 'useAcrylic': true for best visuals."
    }
}

# ── Make projector accessible ──────────────────────────────────────────────────
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectorPath = Join-Path $scriptDir 'projector.py'

if (Test-Path $projectorPath) {
    # Create a small .bat shim so you can double-click or call 'projector' from PATH
    $batPath = Join-Path $scriptDir 'projector.bat'
    @"
@echo off
python "$projectorPath" %*
"@ | Out-File -FilePath $batPath -Encoding ASCII
    Write-OK "Created projector.bat launcher at $batPath"
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "  Installation complete!" -ForegroundColor Green
Write-Host "  Launch with: python projector.py" -ForegroundColor Green
Write-Host "  Config at:   %APPDATA%\projector\config.json" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host ""
Write-Warn "NOTE: Restart your terminal to ensure all PATH changes take effect."
