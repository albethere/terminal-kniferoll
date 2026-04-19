#Requires -Version 5.1
<#
.SYNOPSIS
    terminal-kniferoll | Windows Installer

.DESCRIPTION
    Installs the full terminal-kniferoll stack on Windows.

    Supply chain ladder (most-trusted first):
        winget    -> Microsoft-curated, hash-verified, signed manifests
        Scoop     -> user-space, no admin, manifest SHA256 verification
        PSGallery -> Microsoft-backed PowerShell module registry
        cargo     -> crates.io with package hash verification
        Choco     -> tertiary fallback only (admin)

    Deploys a PowerShell profile with Oh My Posh, PSReadLine, Terminal-Icons,
    zoxide, fzf, posh-git, gsudo, and shell aliases matching the Unix side.
    Merges (does not overwrite) the Cyberwave color scheme into Windows
    Terminal settings.json. Optionally installs Claude Code, Gemini CLI, and
    GitHub Copilot CLI as part of the AI tools group.

    Bootstraps gum (charmbracelet) for cyberwave-themed prompts/banners and
    spawns a side terminal window with a live, color-coded install log.

.PARAMETER Full
    Install everything: Shell + Projector + AI tools (default when no flag given).
.PARAMETER Shell
    Install shell experience only.
.PARAMETER Projector
    Install projector tools only (fastfetch, cmatrix, Python).
.PARAMETER AI
    Install AI CLIs only (Claude Code, Gemini CLI, gh copilot).
.PARAMETER Custom
    Interactively choose which groups to install.
.PARAMETER SkipPwshUpgrade
    Do not auto-install PowerShell 7 even when running on 5.1.
.PARAMETER NoRelaunch
    Do not relaunch in pwsh after installing PS 7. Stay in current session.
.PARAMETER NoLogViewer
    Do not spawn the side log-viewer window.
.PARAMETER Help
    Show this help message and exit.

.EXAMPLE
    .\install_windows.ps1
    .\install_windows.ps1 -Shell
    .\install_windows.ps1 -Projector
    .\install_windows.ps1 -AI
    .\install_windows.ps1 -Custom
    .\install_windows.ps1 -Full

.NOTES
    Run from a standard (non-elevated) PowerShell session when possible.
    The script self-elevates ONLY for Chocolatey install (if missing) and lets
    winget UAC-prompt for any package that needs machine-wide write.
    PowerShell 5.1+ required; 7.6+ recommended (auto-installed if missing).

    ASCII-only by deliberate design. PowerShell 5.1 reads .ps1 files as the
    Windows ANSI codepage (cp1252) when no UTF-8 BOM is present, which
    mojibakes any multi-byte UTF-8 chars and breaks the parser. Keeping this
    file pure ASCII makes it parse correctly under both 5.1 and 7+ in any
    locale, with or without BOM.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Full,
    [switch]$Shell,
    [switch]$Projector,
    [switch]$AI,
    [switch]$Custom,
    [switch]$SkipPwshUpgrade,
    [switch]$NoRelaunch,
    [switch]$NoLogViewer,
    [Alias('h')]
    [switch]$Help
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'

# Force TLS 1.2+ for any direct .NET web calls we make in this script.
try {
    [System.Net.ServicePointManager]::SecurityProtocol =
        [System.Net.ServicePointManager]::SecurityProtocol -bor `
        [System.Net.SecurityProtocolType]::Tls12
} catch { }

# =============================================================================
# CYBERWAVE PALETTE  (matches windows/settings.json color scheme)
# =============================================================================

$Script:CW = @{
    Bg          = '#0B0221'
    Fg          = '#D4C5F9'
    Pink        = '#FF2A6D'
    Cyan        = '#05D9E8'
    Yellow      = '#FEDE5D'
    Purple      = '#BD93F9'
    Magenta     = '#FF6AC1'
    BrightCyan  = '#0FF0FC'
    BrightGreen = '#0FF0FC'
    BrightWhite = '#F8F8F2'
    Dim         = '#7B2D8B'
}

# =============================================================================
# LOGGING
# =============================================================================

$Script:LogDir  = "$env:USERPROFILE\.terminal-kniferoll\logs"
$Script:LogFile = "$LogDir\install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$Script:FailedTools = New-Object System.Collections.Generic.List[string]

function Write-Log {
    param(
        [ValidateSet('INFO','OK','WARN','ERROR')][string]$Level,
        [string]$Message
    )
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line  = "[$stamp] [$Level] $Message"
    Add-Content -Path $Script:LogFile -Value $line -Encoding UTF8
}

function Write-OK   { param([string]$m) Write-Host "[+] $m" -ForegroundColor Green;  Write-Log OK    $m }
function Write-Info { param([string]$m) Write-Host "[*] $m" -ForegroundColor Cyan;   Write-Log INFO  $m }
function Write-Warn { param([string]$m) Write-Host "[!] $m" -ForegroundColor Yellow; Write-Log WARN  $m }
function Write-Err  { param([string]$m) Write-Host "[x] $m" -ForegroundColor Red;    Write-Log ERROR $m }
function Write-Die  { param([string]$m) Write-Err "FATAL: $m"; exit 1 }

function Write-Section {
    param([string]$Title)
    if (Test-Cmd gum) {
        Show-GumSection $Title
        Write-Log INFO "=== $Title ==="
        return
    }
    $bar = ('-' * 66)
    Write-Host ''
    Write-Host "  $bar" -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "  $bar" -ForegroundColor DarkCyan
    Write-Log INFO "=== $Title ==="
}

# =============================================================================
# GUM HELPERS  (cyberwave-themed; safe to call before gum is installed)
# =============================================================================

function Test-Cmd {
    param([string]$Name)
    [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Show-GumBanner {
    param(
        [string]$Title    = 'TERMINAL  KNIFEROLL',
        [string]$Subtitle = 'Windows Installer  //  winget + Scoop + PSGallery + cargo'
    )
    if (Test-Cmd gum) {
        $payload = "$Title`n$Subtitle"
        & gum style `
            --border 'double' `
            --border-foreground $Script:CW.Pink `
            --foreground $Script:CW.Cyan `
            --padding '1 6' `
            --margin '1 2' `
            --align 'center' `
            $payload
        return
    }
    Write-Host ''
    Write-Host '  +==============================================================+' -ForegroundColor DarkMagenta
    Write-Host '  |   T E R M I N A L   K N I F E R O L L                        |' -ForegroundColor Cyan
    Write-Host '  |   Windows Installer   //   winget + Scoop + PSGallery        |' -ForegroundColor DarkCyan
    Write-Host '  +==============================================================+' -ForegroundColor DarkMagenta
    Write-Host ''
}

function Show-GumSection {
    param([string]$Title)
    if (-not (Test-Cmd gum)) {
        Write-Host ''
        Write-Host "  -- $Title --" -ForegroundColor Cyan
        Write-Host ''
        return
    }
    & gum style `
        --border 'normal' `
        --border-foreground $Script:CW.Purple `
        --foreground $Script:CW.BrightCyan `
        --padding '0 3' `
        --margin '1 2' `
        $Title
}

function Show-GumKV {
    param([string]$Key, [string]$Value, [string]$Color = $null)
    if (-not $Color) { $Color = $Script:CW.Cyan }
    if (Test-Cmd gum) {
        $line = "  {0,-22} {1}" -f "$Key`:", $Value
        & gum style --foreground $Color $line
    } else {
        Write-Host ("  {0,-22} {1}" -f "$Key`:", $Value) -ForegroundColor Cyan
    }
}

function Read-GumChoice {
    param(
        [string]$Header,
        [string[]]$Options
    )
    if (-not (Test-Cmd gum)) { return $null }
    try {
        $sel = & gum choose `
            --header $Header `
            --cursor.foreground $Script:CW.Pink `
            --selected.foreground $Script:CW.BrightCyan `
            --header.foreground $Script:CW.Yellow `
            $Options
        return $sel
    } catch {
        return $null
    }
}

function Read-GumConfirm {
    param([string]$Prompt)
    if (-not (Test-Cmd gum)) { return $null }
    & gum confirm $Prompt `
        --selected.background $Script:CW.Pink `
        --selected.foreground $Script:CW.BrightWhite
    return ($LASTEXITCODE -eq 0)
}

# =============================================================================
# HELP
# =============================================================================

if ($Help) {
    Write-Host @'

  terminal-kniferoll  |  Windows Installer

  USAGE
      .\install_windows.ps1 [OPTIONS]

  OPTIONS
      (none)             Interactive menu (5 choices)
      -Full              Install everything (Shell + Projector + AI)
      -Shell             Shell experience only
      -Projector         Projector tools only
      -AI                AI CLIs only (Claude Code, Gemini CLI, gh copilot)
      -Custom            Choose individual tool groups interactively
      -SkipPwshUpgrade   Do not auto-install PowerShell 7
      -NoRelaunch        Do not relaunch in pwsh after PS 7 install
      -NoLogViewer       Do not spawn the side log-viewer window
      -Help              Show this help and exit

  INSTALL GROUPS
      [1] Full        Shell environment + Terminal projector + AI CLIs (recommended)
      [2] Shell only  PowerShell profile + Oh My Posh + plugins + aliases
      [3] Projector   Terminal animation suite (fastfetch, cmatrix, Python)
      [4] AI tools    Claude Code, Gemini CLI, gh copilot
      [5] Custom      Choose individual tool groups

  SUPPLY CHAIN LADDER
      1. winget       (primary;   Microsoft-signed manifests)
      2. Scoop        (secondary; user-space, no admin)
      3. PSGallery    (PowerShell modules)
      4. cargo        (Rust tools; crates.io hash-verified)
      5. Chocolatey   (last resort; admin required)

  LOG FILE
      %USERPROFILE%\.terminal-kniferoll\logs\install_<timestamp>.log

'@
    exit 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Update-EnvPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $userPath    = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    $env:PATH    = "$machinePath;$userPath"

    $extraPaths = @(
        "$env:USERPROFILE\.cargo\bin",
        "$env:USERPROFILE\scoop\shims",
        "$env:USERPROFILE\AppData\Local\Programs\oh-my-posh\bin",
        "$env:USERPROFILE\AppData\Local\Programs\Anthropic Claude\bin",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps",
        "$env:LOCALAPPDATA\Programs\Anthropic Claude\bin",
        "$env:ProgramFiles\PowerShell\7",
        "$env:ProgramFiles\nodejs",
        "$env:ProgramData\chocolatey\bin"
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
        $output = & $Action 2>&1
        if ($output) {
            foreach ($line in $output) {
                $text = "$line"
                if ($text) { Write-Log INFO ("  > $text") }
            }
        }
        Write-OK $Description
        return $true
    } catch {
        Write-Warn "$Description -- $($_.Exception.Message)"
        $Script:FailedTools.Add($Description) | Out-Null
        return $false
    }
}

function Invoke-Elevated {
    <#
    Spawn a new elevated PowerShell window, run the given script as a string,
    wait for it to finish, then refresh PATH in the current session.
    Used only for Chocolatey install (which writes HKLM + ProgramData).
    #>
    param(
        [Parameter(Mandatory)][string]$Command,
        [string]$Reason = 'Operation requires Administrator'
    )

    if (Test-IsAdmin) {
        Write-Info "Already elevated -- running inline"
        Invoke-Expression $Command
        return $true
    }

    Write-Info "$Reason -- requesting UAC"
    $tempScript = Join-Path $env:TEMP "tk-elevated-$([guid]::NewGuid().Guid).ps1"
    Set-Content -Path $tempScript -Value $Command -Encoding UTF8 -Force

    try {
        $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru `
            -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', $tempScript)
        Update-EnvPath
        return ($proc.ExitCode -eq 0)
    } catch {
        Write-Warn "Elevation cancelled or failed: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# RESUME / RELAUNCH SUPPORT
#
# When this script installs PowerShell 7 from a PS 5.1 session, we want to
# continue in pwsh so the rest of the install runs on a modern shell that
# already has the new PATH baked in. We do this by spawning a new pwsh window
# with the install mode flag set and exiting the current PS 5.1 session.
# =============================================================================

$Script:Resumed = ($env:KNIFEROLL_RESUMED -eq '1')
if ($Script:Resumed) {
    Write-Info "Resumed in PowerShell $($PSVersionTable.PSVersion) (relaunched after upgrade)"
    Remove-Item Env:KNIFEROLL_RESUMED -ErrorAction SilentlyContinue
}

function Restart-InPwsh {
    param([string]$Mode)

    if ($NoRelaunch) {
        Write-Info "-NoRelaunch given; staying in current PowerShell session"
        return $false
    }

    Update-EnvPath
    if (-not (Test-Cmd pwsh)) {
        Write-Warn "pwsh not on PATH yet; cannot relaunch"
        return $false
    }

    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }
    if (-not $scriptPath -or -not (Test-Path $scriptPath)) {
        Write-Warn "Cannot determine script path; not relaunching"
        return $false
    }

    $env:KNIFEROLL_RESUMED = '1'

    $relayArgs = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $scriptPath
    )
    if ($Mode) { $relayArgs += "-$Mode" }
    if ($NoLogViewer) { $relayArgs += '-NoLogViewer' }

    Write-OK "Continuing in a fresh PowerShell 7 window..."
    try {
        # Try Windows Terminal in a new window first (matches the side log
        # viewer aesthetic). Fall back to plain pwsh.exe.
        if (Test-Cmd wt) {
            $wtArgs = @(
                '-w', 'new', 'new-tab',
                '--title', 'terminal-kniferoll  //  install',
                '--colorScheme', 'Cyberwave',
                'pwsh.exe'
            ) + $relayArgs
            Start-Process -FilePath 'wt.exe' -ArgumentList $wtArgs | Out-Null
        } else {
            Start-Process -FilePath 'pwsh.exe' -ArgumentList $relayArgs | Out-Null
        }
    } catch {
        Write-Warn "Could not start pwsh.exe: $($_.Exception.Message)"
        Remove-Item Env:KNIFEROLL_RESUMED -ErrorAction SilentlyContinue
        return $false
    }

    Write-Info "This PowerShell 5.1 session will exit. Watch the new window."
    Start-Sleep -Seconds 2
    exit 0
}

# =============================================================================
# BANNER  (ASCII fallback; gum banner shown again after gum installs)
# =============================================================================

Show-GumBanner
Write-Host "  Log -> $Script:LogFile" -ForegroundColor DarkGray
Write-Host ''

# =============================================================================
# ENVIRONMENT CHECKS
# =============================================================================

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Die "PowerShell 5.1 or newer is required. Current: $($PSVersionTable.PSVersion)"
}
Write-Info "PowerShell $($PSVersionTable.PSVersion) detected"

$Script:IsAdmin = Test-IsAdmin
if ($Script:IsAdmin) {
    Write-Info "Running as Administrator"
} else {
    Write-Info "Running as standard user (will request UAC only when needed)"
}

# WSL detection (informational, not a gate)
$Script:WslPresent = Test-Path "$env:SystemRoot\system32\wsl.exe"
if ($Script:WslPresent) {
    Write-Info "WSL detected -- tip: run install_linux.sh inside WSL for a full Zsh environment"
}

# =============================================================================
# PREREQUISITE GATES
#
# Hard requirements (fail-fast):
#   - PowerShell 5.1+        (already gated above)
#   - winget                 (App Installer; preinstalled on Win10 1809+)
#   - Git                    (the user already has this -- they cloned the repo;
#                             we still verify and give a clear error if missing)
#
# Soft requirements (auto-install):
#   - curl                   (preinstalled Win10 1803+; install via winget if missing)
#   - PowerShell 7           (install via winget if running on 5.1, then relaunch)
# =============================================================================

function Test-Prerequisites {
    Write-Section "Prerequisite Checks"

    # ---- Git (hard requirement) --------------------------------------------
    if (Test-Cmd git) {
        $gitVer = (git --version 2>$null)
        Write-OK "Git present -- $gitVer"
    } else {
        Write-Err "Git is required but not on PATH."
        Write-Host ''
        Write-Host '  Install Git for Windows from one of:' -ForegroundColor White
        Write-Host '    - https://git-scm.com/download/win        (official installer)' -ForegroundColor DarkCyan
        Write-Host '    - winget install --id Git.Git --source winget' -ForegroundColor DarkCyan
        Write-Host '  Then re-run this script.' -ForegroundColor White
        Write-Host ''
        Write-Die "Git missing -- aborting before any installs"
    }

    # ---- winget (hard requirement) -----------------------------------------
    if (Test-Cmd winget) {
        $wgVer = (winget --version 2>$null)
        Write-OK "winget present -- $wgVer"
    } else {
        Write-Err "winget (App Installer) is required but not on PATH."
        Write-Host ''
        Write-Host '  winget ships in App Installer (Microsoft Store package).' -ForegroundColor White
        Write-Host '  Install from: https://apps.microsoft.com/detail/9NBLGGH4NNS1' -ForegroundColor DarkCyan
        Write-Host '  Or upgrade to Windows 10 1809+ / Windows 11.' -ForegroundColor DarkCyan
        Write-Host ''
        Write-Die "winget missing -- aborting before any installs"
    }

    # ---- curl (soft; auto-install via winget) ------------------------------
    if (Test-Cmd curl) {
        Write-OK "curl present"
    } else {
        Write-Warn "curl missing -- installing via winget (cURL.cURL)"
        Invoke-Optional "Installing curl via winget" {
            winget install --id cURL.cURL --source winget --silent `
                --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        }
        Update-EnvPath
        if (Test-Cmd curl) { Write-OK "curl installed" }
        else               { Write-Warn "curl still missing -- continuing anyway" }
    }

    # ---- PowerShell 7 (soft; auto-install + relaunch) ----------------------
    Install-PowerShell7
}

function Install-PowerShell7 {
    if ($SkipPwshUpgrade) {
        Write-Info "-SkipPwshUpgrade set -- not touching PowerShell version"
        return
    }

    $current = [Version]$PSVersionTable.PSVersion.ToString()
    $minimum = [Version]'7.6.0'

    if ($current -ge $minimum) {
        Write-OK "PowerShell $current already meets >= $minimum -- skipping upgrade"
        return
    }

    Write-Info "PowerShell $current detected; installing latest PowerShell 7 via winget"

    # Microsoft.PowerShell installs machine-wide; winget handles its own UAC
    # prompt when needed. We do NOT need to self-elevate the parent here.
    $installed = Invoke-Optional "Installing Microsoft.PowerShell (winget)" {
        winget install --id Microsoft.PowerShell --source winget --silent `
            --accept-package-agreements --accept-source-agreements `
            --scope machine 2>&1 | Out-Null
    }

    Update-EnvPath

    if (Test-Cmd pwsh) {
        Write-OK "pwsh on PATH -- relaunching to continue with PowerShell 7"

        $mode = $null
        if     ($Full)      { $mode = 'Full' }
        elseif ($Shell)     { $mode = 'Shell' }
        elseif ($Projector) { $mode = 'Projector' }
        elseif ($AI)        { $mode = 'AI' }
        elseif ($Custom)    { $mode = 'Custom' }
        else                { $mode = 'Full' }

        Restart-InPwsh -Mode $mode
        # If Restart-InPwsh returns at all, it means relaunch was suppressed
        # or failed -- continue in the current PS 5.1 session.
    } elseif ($installed) {
        Write-Warn "PowerShell 7 installed but pwsh not yet on PATH -- continuing in PS 5.1"
        Write-Info "After this script finishes, open a new terminal and PowerShell 7 will be available"
    } else {
        Write-Warn "PowerShell 7 install did not complete -- continuing in PS 5.1"
    }
}

# =============================================================================
# PACKAGE MANAGER BOOTSTRAP (Scoop + Choco + gum)
# =============================================================================

function Initialize-PackageManagers {
    Write-Section "Package Manager Bootstrap"

    # winget already validated as a prereq.
    Write-OK "winget   ready"

    # ---- Scoop (user-space, no admin) --------------------------------------
    if (Test-Cmd scoop) {
        Write-OK "Scoop    already installed"
    } else {
        Invoke-Optional "Installing Scoop (user-space, no admin required)" {
            try {
                Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            } catch { }
            Invoke-RestMethod -Uri 'https://get.scoop.sh' -UseBasicParsing | Invoke-Expression
            Update-EnvPath
        }
    }

    # Add useful Scoop buckets
    if (Test-Cmd scoop) {
        $buckets = @(scoop bucket list 2>$null | Out-String)
        if ($buckets -notmatch 'extras') {
            Invoke-Optional "Adding Scoop 'extras' bucket"   { scoop bucket add extras 2>&1 | Out-Null }
        }
        if ($buckets -notmatch 'nerd-fonts') {
            Invoke-Optional "Adding Scoop 'nerd-fonts' bucket" { scoop bucket add nerd-fonts 2>&1 | Out-Null }
        }
    }

    # ---- Chocolatey (tertiary fallback; install via UAC self-elevate) ------
    if (Test-Cmd choco) {
        Write-OK "Choco    already installed"
    } else {
        Write-Info "Chocolatey not detected -- installing via elevated PowerShell"
        $chocoCmd = @"
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = `
    [System.Net.ServicePointManager]::SecurityProtocol -bor `
    [System.Net.SecurityProtocolType]::Tls12
try {
    Invoke-RestMethod -UseBasicParsing -Uri 'https://community.chocolatey.org/install.ps1' |
        Invoke-Expression
} catch {
    Write-Host "Chocolatey install failed: $(`$_.Exception.Message)" -ForegroundColor Red
    exit 1
}
exit 0
"@
        $ok = Invoke-Elevated -Command $chocoCmd -Reason 'Chocolatey install needs Administrator'
        Update-EnvPath
        if (Test-Cmd choco) {
            Write-OK "Chocolatey installed"
        } else {
            if ($ok) {
                Write-Warn "Chocolatey reported success but is not on PATH yet (open a new shell to use it)"
            } else {
                Write-Warn "Chocolatey not installed -- continuing without it (winget + Scoop cover everything we need)"
            }
        }
    }

    # ---- gum (charmbracelet) for cyberwave UI ------------------------------
    Install-Gum
}

function Install-Gum {
    if (Test-Cmd gum) {
        Write-OK "gum      already installed"
        return
    }

    Write-Info "Installing gum (charmbracelet) for cyberwave UI"

    # Try winget first
    Invoke-Optional "Installing gum via winget (charmbracelet.gum)" {
        winget install --id charmbracelet.gum --source winget --silent `
            --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    } | Out-Null
    Update-EnvPath

    # Fall back to Scoop
    if (-not (Test-Cmd gum) -and (Test-Cmd scoop)) {
        Invoke-Optional "Installing gum via Scoop" {
            scoop install gum 2>&1 | Out-Null
        } | Out-Null
        Update-EnvPath
    }

    # Last resort: Chocolatey
    if (-not (Test-Cmd gum) -and (Test-Cmd choco)) {
        Invoke-Optional "Installing gum via Chocolatey" {
            choco install gum -y --no-progress 2>&1 | Out-Null
        } | Out-Null
        Update-EnvPath
    }

    if (Test-Cmd gum) {
        Write-OK "gum installed -- engaging cyberwave UI"
        # Re-show the banner now that we have gum
        Show-GumBanner
    } else {
        Write-Warn "gum could not be installed -- using ASCII fallback UI"
    }
}

# =============================================================================
# LIVE LOG VIEWER (separate terminal window, bordered)
# =============================================================================

function Start-LogViewerWindow {
    if ($NoLogViewer) {
        Write-Info "-NoLogViewer set -- skipping side log window"
        return
    }

    $logPath = $Script:LogFile
    if (-not (Test-Path $logPath)) {
        # Create the file so Get-Content -Wait has something to grab.
        New-Item -ItemType File -Force -Path $logPath | Out-Null
    }

    # The viewer script lives in $env:TEMP and tails the log forever.
    $cwBorder  = $Script:CW.Pink
    $cwHeading = $Script:CW.Cyan
    $cwAccent  = $Script:CW.Yellow

    $tailScript = @"
`$ErrorActionPreference = 'Continue'
`$Host.UI.RawUI.WindowTitle = 'terminal-kniferoll  //  live install log'

function Show-Header {
    if (Get-Command gum -ErrorAction SilentlyContinue) {
        & gum style ``
            --border 'double' ``
            --border-foreground '$cwBorder' ``
            --foreground '$cwHeading' ``
            --padding '1 6' ``
            --margin '1 2' ``
            --align 'center' ``
            "TERMINAL  KNIFEROLL`nLive Install Log  //  Cyberwave"
        & gum style --foreground '$cwAccent' "  Tailing: '$logPath'"
        Write-Host ''
    } else {
        Write-Host ''
        Write-Host '  +==============================================================+' -ForegroundColor Magenta
        Write-Host '  |          TERMINAL KNIFEROLL  //  live install log            |' -ForegroundColor Cyan
        Write-Host '  +==============================================================+' -ForegroundColor Magenta
        Write-Host "  Tailing: '$logPath'" -ForegroundColor Yellow
        Write-Host ''
    }
}

Show-Header

# Wait for the file to exist (parent may still be initializing)
`$start = Get-Date
while (-not (Test-Path '$logPath')) {
    if ((Get-Date) - `$start -gt [TimeSpan]::FromSeconds(30)) {
        Write-Host '  Log file did not appear within 30 seconds. Exiting.' -ForegroundColor Red
        exit 1
    }
    Start-Sleep -Milliseconds 200
}

Get-Content -Path '$logPath' -Wait | ForEach-Object {
    `$line = `$_
    if (`$null -eq `$line) { return }
    `$text = "`$line"
    if (`$text -match '\[ERROR\]')    { Write-Host `$text -ForegroundColor Red }
    elseif (`$text -match '\[WARN\]') { Write-Host `$text -ForegroundColor Yellow }
    elseif (`$text -match '\[OK\]')   { Write-Host `$text -ForegroundColor Green }
    elseif (`$text -match '\[INFO\]') { Write-Host `$text -ForegroundColor Cyan }
    else                                { Write-Host `$text -ForegroundColor Gray }
    if (`$text -match '=== INSTALL COMPLETE ===') {
        Write-Host ''
        if (Get-Command gum -ErrorAction SilentlyContinue) {
            & gum style ``
                --border 'double' ``
                --border-foreground '$cwBorder' ``
                --foreground '$cwHeading' ``
                --padding '1 6' ``
                --margin '1 2' ``
                --align 'center' ``
                'INSTALL COMPLETE  //  knives sharp.'
        }
        Write-Host '  Press any key to close this window...' -ForegroundColor DarkGray
        `$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit 0
    }
}
"@

    $tempScript = Join-Path $env:TEMP "tk-logviewer-$([guid]::NewGuid().Guid).ps1"
    Set-Content -Path $tempScript -Value $tailScript -Encoding UTF8 -Force

    try {
        # Prefer Windows Terminal in a NEW window with the Cyberwave color scheme.
        if (Test-Cmd wt) {
            $shellExe = if (Test-Cmd pwsh) { 'pwsh.exe' } else { 'powershell.exe' }
            $wtArgs = @(
                '-w', 'new', 'new-tab',
                '--title', 'terminal-kniferoll  //  live log',
                '--colorScheme', 'Cyberwave',
                $shellExe, '-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', $tempScript
            )
            Start-Process -FilePath 'wt.exe' -ArgumentList $wtArgs -ErrorAction Stop | Out-Null
            Write-OK "Live log viewer opened in new Windows Terminal window"
        } else {
            $shellExe = if (Test-Cmd pwsh) { 'pwsh.exe' } else { 'powershell.exe' }
            Start-Process -FilePath $shellExe -ArgumentList @(
                '-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', $tempScript
            ) -ErrorAction Stop | Out-Null
            Write-OK "Live log viewer opened in new $shellExe window"
        }
    } catch {
        Write-Warn "Could not open live log viewer: $($_.Exception.Message)"
    }
}

# =============================================================================
# INSTALL HELPERS
# =============================================================================

function Install-Winget {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$DisplayName,
        [string]$CheckCmd = '',
        [string]$Source = 'winget'
    )
    if ($CheckCmd -and (Test-Cmd $CheckCmd)) {
        Write-OK "$DisplayName already installed"
        return
    }
    if (-not (Test-Cmd winget)) {
        Write-Warn "winget not available -- skipping $DisplayName"
        return
    }
    Invoke-Optional "Installing $DisplayName via winget" {
        winget install --id $Id --source $Source --silent `
            --accept-package-agreements --accept-source-agreements `
            --no-upgrade 2>&1 | Out-Null
        Update-EnvPath
    } | Out-Null
}

function Install-Scoop {
    param(
        [Parameter(Mandatory)][string]$Package,
        [string]$DisplayName = '',
        [string]$CheckCmd = ''
    )
    if (-not $DisplayName) { $DisplayName = $Package }
    if ($CheckCmd -and (Test-Cmd $CheckCmd)) {
        Write-OK "$DisplayName already installed"
        return
    }
    if (-not (Test-Cmd scoop)) {
        Write-Warn "Scoop not available -- skipping $DisplayName"
        return
    }
    Invoke-Optional "Installing $DisplayName via Scoop" {
        scoop install $Package 2>&1 | Out-Null
        Update-EnvPath
    } | Out-Null
}

function Install-Cargo {
    param(
        [Parameter(Mandatory)][string]$Crate,
        [string]$DisplayName = '',
        [string]$CheckCmd = ''
    )
    if (-not $DisplayName) { $DisplayName = $Crate }
    if ($CheckCmd -and (Test-Cmd $CheckCmd)) {
        Write-OK "$DisplayName already installed"
        return
    }
    if (-not (Test-Cmd cargo)) {
        Write-Warn "cargo not available -- skipping $DisplayName"
        return
    }
    Invoke-Optional "Installing $DisplayName via cargo" {
        cargo install $Crate 2>&1 | Out-Null
        Update-EnvPath
    } | Out-Null
}

function Install-PsModule {
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Force,
        [switch]$AllowClobber
    )
    if (Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue) {
        Write-OK "PS module $Name already installed"
        return
    }
    $installArgs = @{
        Name        = $Name
        Scope       = 'CurrentUser'
        Repository  = 'PSGallery'
        ErrorAction = 'Stop'
    }
    if ($Force)        { $installArgs['Force']        = $true }
    if ($AllowClobber) { $installArgs['AllowClobber'] = $true }

    Invoke-Optional "Installing PowerShell module $Name" {
        Install-Module @installArgs
    } | Out-Null
}

# =============================================================================
# SHELL EXPERIENCE
# =============================================================================

function Install-ShellExperience {
    Write-Section "Shell Experience"

    # ---- Core CLI tools (winget primary) -----------------------------------
    Install-Winget 'JanDeDobbeleer.OhMyPosh'    'Oh My Posh'  'oh-my-posh'
    Install-Winget 'junegunn.fzf'               'fzf'         'fzf'
    Install-Winget 'ajeetdsouza.zoxide'         'zoxide'      'zoxide'
    Install-Winget 'sharkdp.bat'                'bat'         'bat'
    Install-Winget 'BurntSushi.ripgrep.MSVC'    'ripgrep'     'rg'
    Install-Winget 'Neovim.Neovim'              'Neovim'      'nvim'
    Install-Winget 'gerardog.gsudo'             'gsudo'       'gsudo'
    Install-Winget 'GitHub.cli'                 'GitHub CLI'  'gh'
    Install-Winget 'jqlang.jq'                  'jq'          'jq'
    Install-Winget 'astral-sh.uv'               'uv (Python)' 'uv'
    Install-Winget 'starship.starship'          'starship'    'starship'
    Install-Winget 'OpenJS.NodeJS.LTS'          'Node.js LTS' 'node'

    # ---- Tools easier to get from Scoop ------------------------------------
    Install-Scoop 'lsd'   'lsd'   'lsd'
    Install-Scoop 'btop'  'btop'  'btop'

    # ---- Windows Terminal (install if missing) -----------------------------
    Install-Winget 'Microsoft.WindowsTerminal' 'Windows Terminal' 'wt'

    # ---- Nerd Fonts via Oh My Posh -----------------------------------------
    if (Test-Cmd oh-my-posh) {
        Write-Section "Nerd Fonts (via oh-my-posh)"
        $nerdFonts = @(
            'CascadiaCode','Meslo','JetBrainsMono','FiraCode','Hack',
            'UbuntuMono','SourceCodePro','VictorMono','Mononoki','GeistMono'
        )
        foreach ($nf in $nerdFonts) {
            Invoke-Optional "Installing $nf Nerd Font" {
                oh-my-posh font install $nf 2>&1 | Out-Null
            } | Out-Null
        }
    }

    # ---- PowerShell modules (PSGallery) ------------------------------------
    Write-Section "PowerShell Modules (PSGallery)"

    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Invoke-Optional "Installing NuGet package provider" {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 `
                -Force -Scope CurrentUser | Out-Null
        } | Out-Null
    }

    $psGallery = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
    if ($psGallery -and $psGallery.InstallationPolicy -ne 'Trusted') {
        try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted } catch { }
    }

    Install-PsModule 'PSReadLine'     -Force -AllowClobber
    Install-PsModule 'Terminal-Icons' -Force
    Install-PsModule 'PSFzf'          -Force
    Install-PsModule 'posh-git'       -AllowClobber

    # ---- Profile + Windows Terminal scheme ---------------------------------
    Deploy-PSProfile
    Deploy-WTScheme
}

# =============================================================================
# AI TOOLS  (Claude Code, Gemini CLI, GitHub Copilot CLI)
# =============================================================================

function Install-AITools {
    Write-Section "AI Tooling"

    # ---- Claude Code (official Anthropic installer) ------------------------
    # Distribution channel: irm https://claude.ai/install.ps1 | iex
    # This is a download-then-execute pattern. Risk: MEDIUM (TLS 1.2+ enforced
    # globally; official Anthropic domain). We install non-interactively.
    if (Test-Cmd claude) {
        Write-OK "Claude Code already installed"
    } else {
        Invoke-Optional "Installing Claude Code (claude.ai/install.ps1)" {
            # TLS 1.2+ is already set at the top of this script.
            $installer = Invoke-RestMethod -UseBasicParsing -Uri 'https://claude.ai/install.ps1'
            if (-not $installer) { throw "Empty installer body from claude.ai" }
            Invoke-Expression $installer
            Update-EnvPath
        } | Out-Null
    }

    # ---- Gemini CLI (npm global install via Node) --------------------------
    if (Test-Cmd gemini) {
        Write-OK "Gemini CLI already installed"
    } else {
        if (Test-Cmd npm) {
            Invoke-Optional "Installing @google/gemini-cli (npm global)" {
                npm install -g '@google/gemini-cli' 2>&1 | Out-Null
                Update-EnvPath
            } | Out-Null
        } else {
            Write-Warn "Node.js / npm not on PATH yet -- Gemini CLI skipped (run 'up' or reopen the shell, then re-run with -AI)"
        }
    }

    # ---- GitHub Copilot CLI (gh extension) ---------------------------------
    if (Test-Cmd gh) {
        $installed = $false
        try {
            $extList = & gh extension list 2>$null | Out-String
            if ($extList -match 'github/gh-copilot') { $installed = $true }
        } catch { }

        if ($installed) {
            Write-OK "gh copilot extension already installed"
        } else {
            Invoke-Optional "Installing gh copilot extension (github/gh-copilot)" {
                gh extension install github/gh-copilot 2>&1 | Out-Null
            } | Out-Null
        }
    } else {
        Write-Warn "GitHub CLI (gh) not on PATH -- gh copilot skipped"
    }
}

# =============================================================================
# POWERSHELL PROFILE DEPLOYMENT
#
# We deploy to BOTH:
#   - $PROFILE for whichever pwsh/powershell is running this script
#   - The PowerShell 7 profile path (if different from current $PROFILE)
# so the user gets the new shell experience whether they launch 5.1 or 7.
# =============================================================================

function Deploy-PSProfile {
    Write-Section "PowerShell Profile"

    $profileTargets = New-Object System.Collections.Generic.List[string]
    if ($PROFILE) { $profileTargets.Add($PROFILE) | Out-Null }

    $pwsh7Profile = Join-Path $env:USERPROFILE 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
    if ($pwsh7Profile -and ($profileTargets -notcontains $pwsh7Profile)) {
        $profileTargets.Add($pwsh7Profile) | Out-Null
    }

    $ps5Profile = Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
    if ($ps5Profile -and ($profileTargets -notcontains $ps5Profile)) {
        $profileTargets.Add($ps5Profile) | Out-Null
    }

    $profileContent = Get-ProfileContent

    foreach ($target in $profileTargets) {
        try {
            $dir = Split-Path $target -Parent
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Force -Path $dir | Out-Null
            }
            if (Test-Path $target) {
                $backup = "$target.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                Copy-Item $target $backup -Force
                Write-Info "Backed up existing profile -> $backup"
            }
            # IMPORTANT: write profile with UTF-8 BOM so PS 5.1 reads it correctly.
            $bom  = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllText($target, $profileContent, $bom)
            Write-OK "Profile deployed -> $target"
        } catch {
            Write-Warn "Could not write profile $target -- $($_.Exception.Message)"
        }
    }
}

function Get-ProfileContent {
    # NOTE: This profile content uses the kitchen/blade flavor of the Unix
    # scripts (see docs/FLAVOR.md). ASCII-safe in case the user opens it in a
    # legacy editor.
    return @'
# =============================================================================
# terminal-kniferoll | PowerShell Profile
# Generated by install_windows.ps1
# =============================================================================

# ---- Oh My Posh -------------------------------------------------------------
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    $ompTheme = $null
    if ($env:POSH_THEMES_PATH) {
        $candidate = Join-Path $env:POSH_THEMES_PATH 'jandedobbeleer.omp.json'
        if (Test-Path $candidate) { $ompTheme = $candidate }
    }
    if ($ompTheme) {
        oh-my-posh init pwsh --config $ompTheme | Invoke-Expression
    } else {
        oh-my-posh init pwsh | Invoke-Expression
    }
}

# ---- PSReadLine (autosuggest + history search + colors) ---------------------
if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction SilentlyContinue
    Set-PSReadLineOption -PredictionViewStyle ListView      -ErrorAction SilentlyContinue
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineKeyHandler -Key Tab        -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow    -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow  -Function HistorySearchForward
    Set-PSReadLineOption -Colors @{
        Command   = 'Cyan'
        Parameter = 'DarkCyan'
        String    = 'Green'
        Keyword   = 'Magenta'
        Comment   = 'DarkGray'
        Error     = 'Red'
    }
}

# ---- Terminal-Icons ---------------------------------------------------------
if (Get-Module -ListAvailable Terminal-Icons) { Import-Module Terminal-Icons }

# ---- posh-git ---------------------------------------------------------------
if (Get-Module -ListAvailable posh-git) { Import-Module posh-git }

# ---- zoxide -----------------------------------------------------------------
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# ---- fzf / PSFzf ------------------------------------------------------------
if ((Get-Command fzf -ErrorAction SilentlyContinue) -and (Get-Module -ListAvailable PSFzf)) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}

# ---- Aliases & Functions (parity with shell/aliases.zsh) --------------------

# ls strategy: lsd preferred (icons, color, git status)
if (Get-Command lsd -ErrorAction SilentlyContinue) {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    function ls  { lsd $args }
    function l   { lsd -l $args }
    function la  { lsd -la $args }
    function ll  { lsd -lA $args }
    function lt  { lsd --tree $args }
    function lr  { lsd -latr $args }
    function lsp { Get-ChildItem -Force $args }
} else {
    function l   { Get-ChildItem $args }
    function la  { Get-ChildItem -Force $args }
    function ll  { Get-ChildItem -Force $args | Format-List }
}

# cat replacement
if (Get-Command bat -ErrorAction SilentlyContinue) {
    Remove-Item Alias:cat -Force -ErrorAction SilentlyContinue
    function cat { bat $args }
}

# Editors
if (Get-Command nvim -ErrorAction SilentlyContinue) {
    Set-Alias vim  nvim
    Set-Alias vi   nvim
    Set-Alias nano nvim
}

# Networking
function myip { (Invoke-WebRequest -Uri 'https://icanhazip.com' -UseBasicParsing).Content.Trim() }

# Shell management
function reload { . $PROFILE; Write-Host 'Profile reloaded.' -ForegroundColor Cyan }
function ff {
    if (Get-Command fastfetch -ErrorAction SilentlyContinue) { fastfetch }
    else { Write-Host 'fastfetch not installed.' -ForegroundColor Yellow }
}

# Navigation
function ..   { Set-Location .. }
function ...  { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

# Git shortcuts (parity with Unix aliases)
function gs  { git status }
function ga  { git add $args }
function gc  { git commit $args }
function gp  { git push }
function gl  { git --no-pager log --oneline -10 }
function gd  { git --no-pager diff }
function gb  { git branch $args }
function gco { git checkout $args }
function gpl { git pull }

# grep replacement
if (Get-Command rg -ErrorAction SilentlyContinue) { Set-Alias grep rg }

# ---- System update across every package manager present --------------------
# `up` mirrors the Unix `up` function.
function up {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host '==> winget source update' -ForegroundColor Cyan
        winget source update
        Write-Host '==> winget upgrade --all' -ForegroundColor Cyan
        winget upgrade --all --accept-source-agreements --accept-package-agreements --include-unknown --silent
    }
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host '==> scoop update' -ForegroundColor Cyan
        scoop update
        Write-Host '==> scoop update *' -ForegroundColor Cyan
        scoop update *
        Write-Host '==> scoop cleanup *' -ForegroundColor Cyan
        scoop cleanup *
    }
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host '==> choco upgrade all' -ForegroundColor Cyan
        if (Get-Command gsudo -ErrorAction SilentlyContinue) {
            gsudo choco upgrade all -y
        } else {
            choco upgrade all -y
        }
    }
    if (Get-Command Update-Module -ErrorAction SilentlyContinue) {
        Write-Host '==> Update-Module (PSGallery, CurrentUser scope)' -ForegroundColor Cyan
        Update-Module -Scope CurrentUser -Force -ErrorAction Continue
    }
}
Set-Alias abu up
Set-Alias bru up

# ---- PRIVATE API keys (loaded from environment, never hardcoded) ------------
if ($env:PRIVATE_VT_API_KEY)        { $env:VT_API_KEY        = $env:PRIVATE_VT_API_KEY }
if ($env:PRIVATE_PT_API_KEY)        { $env:PT_API_KEY        = $env:PRIVATE_PT_API_KEY }
if ($env:PRIVATE_PT_API_USER)       { $env:PT_API_USER       = $env:PRIVATE_PT_API_USER }
if ($env:PRIVATE_IP2WHOIS_API_KEY)  { $env:IP2WHOIS_API_KEY  = $env:PRIVATE_IP2WHOIS_API_KEY }
if ($env:PRIVATE_SHODAN_API_KEY)    { $env:SHODAN_API_KEY    = $env:PRIVATE_SHODAN_API_KEY }
if ($env:PRIVATE_GREYNOISE_API_KEY) { $env:GREYNOISE_API_KEY = $env:PRIVATE_GREYNOISE_API_KEY }
if ($env:PRIVATE_ABUSEIPDB_API_KEY) { $env:ABUSEIPDB_API_KEY = $env:PRIVATE_ABUSEIPDB_API_KEY }

# ---- Welcome ----------------------------------------------------------------
if (Get-Command fastfetch -ErrorAction SilentlyContinue) { fastfetch }
'@
}

# =============================================================================
# WINDOWS TERMINAL COLOR SCHEME (MERGE, NOT OVERWRITE)
#
# Reads the Cyberwave color scheme out of windows/settings.json in this repo,
# merges it into the user's existing Windows Terminal settings.json, sets
# profiles.defaults.colorScheme = 'Cyberwave'. Never replaces the user's full
# settings (which would wipe their profiles, keybindings, etc).
# =============================================================================

function Deploy-WTScheme {
    Write-Section "Windows Terminal Color Scheme"

    $sourceFile = Join-Path $PSScriptRoot 'windows\settings.json'
    if (-not (Test-Path $sourceFile)) {
        Write-Warn "windows/settings.json not found in repo -- skipping color scheme"
        return
    }

    $cyberwave = $null
    try {
        $sourceJson = Get-Content $sourceFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($sourceJson.PSObject.Properties['schemes']) {
            $cyberwave = $sourceJson.schemes | Where-Object { $_.name -eq 'Cyberwave' } | Select-Object -First 1
        }
    } catch {
        Write-Warn "Could not parse repo settings.json -- $($_.Exception.Message)"
        return
    }

    if (-not $cyberwave) {
        Write-Warn "Cyberwave scheme not found in repo settings.json"
        return
    }

    $wtDirs = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState"
    )

    $deployed = 0
    foreach ($wtDir in $wtDirs) {
        if (-not (Test-Path $wtDir)) { continue }

        $target = Join-Path $wtDir 'settings.json'

        try {
            $targetJson = $null
            if (Test-Path $target) {
                $backup = "$target.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                Copy-Item $target $backup -Force
                Write-Info "Backed up existing WT settings -> $backup"
                $raw = Get-Content $target -Raw -Encoding UTF8
                if ($raw) { $targetJson = $raw | ConvertFrom-Json }
            }
            if (-not $targetJson) {
                $targetJson = [pscustomobject]@{
                    schemes  = @()
                    profiles = [pscustomobject]@{ defaults = [pscustomobject]@{} }
                }
            }

            # Ensure schemes exists and is an array
            if (-not $targetJson.PSObject.Properties['schemes']) {
                $targetJson | Add-Member -NotePropertyName schemes -NotePropertyValue @() -Force
            }
            $existingSchemes = @()
            if ($targetJson.schemes) {
                $existingSchemes = @($targetJson.schemes | Where-Object { $_.name -ne 'Cyberwave' })
            }
            $targetJson.schemes = @($existingSchemes + $cyberwave)

            # Ensure profiles.defaults exists
            if (-not $targetJson.PSObject.Properties['profiles']) {
                $targetJson | Add-Member -NotePropertyName profiles `
                    -NotePropertyValue ([pscustomobject]@{ defaults = [pscustomobject]@{} }) -Force
            }
            if (-not $targetJson.profiles.PSObject.Properties['defaults']) {
                $targetJson.profiles | Add-Member -NotePropertyName defaults `
                    -NotePropertyValue ([pscustomobject]@{}) -Force
            }

            # Set colorScheme on defaults (preserve everything else)
            if ($targetJson.profiles.defaults.PSObject.Properties['colorScheme']) {
                $targetJson.profiles.defaults.colorScheme = 'Cyberwave'
            } else {
                $targetJson.profiles.defaults | Add-Member -NotePropertyName colorScheme `
                    -NotePropertyValue 'Cyberwave' -Force
            }

            $json = $targetJson | ConvertTo-Json -Depth 32
            # Write WITHOUT BOM (Windows Terminal expects plain UTF-8)
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($target, $json, $utf8NoBom)
            $leaf = Split-Path $wtDir -Leaf
            Write-OK "Cyberwave scheme merged into $leaf"
            $deployed++
        } catch {
            Write-Warn "Could not merge WT settings at $wtDir -- $($_.Exception.Message)"
        }
    }

    if ($deployed -eq 0) {
        Write-Warn "Windows Terminal not installed (LocalState not found). Run again after installing Windows Terminal."
    }
}

# =============================================================================
# PROJECTOR INSTALL
# =============================================================================

function Install-Projector {
    Write-Section "Projector Stack"

    Install-Winget 'Fastfetch-cli.Fastfetch' 'fastfetch'    'fastfetch'
    Install-Winget 'Python.Python.3.12'      'Python 3.12'  'python'
    Install-Scoop  'cmatrix'                 'cmatrix'      'cmatrix'

    # cbonsai has no native Windows binary
    Write-Warn "cbonsai -- no native Windows binary; run inside WSL if desired"

    $projectorPy = Join-Path $PSScriptRoot 'projector.py'
    if ((Test-Path $projectorPy) -and (Test-Cmd python)) {
        Write-Info "projector.py present at $projectorPy -- launch with: python `"$projectorPy`""
    }
}

# =============================================================================
# MODE SELECTION
# =============================================================================

$Script:DoShell     = $false
$Script:DoProjector = $false
$Script:DoAI        = $false

function Resolve-InstallMode {
    if ($Full) {
        $Script:DoShell = $true; $Script:DoProjector = $true; $Script:DoAI = $true; return
    }
    if ($Shell -or $Projector -or $AI) {
        if ($Shell)     { $Script:DoShell     = $true }
        if ($Projector) { $Script:DoProjector = $true }
        if ($AI)        { $Script:DoAI        = $true }
        return
    }
    if ($Custom) {
        Resolve-Custom
        return
    }
    if ($Script:Resumed) {
        # Belt-and-suspenders: if relaunched without a mode flag, default to Full.
        $Script:DoShell = $true; $Script:DoProjector = $true; $Script:DoAI = $true
        return
    }

    # Try the gum picker first; fall back to plain Read-Host menu.
    if (Test-Cmd gum) {
        $opts = @(
            '[1] Full        Shell + Projector + AI tools (recommended)',
            '[2] Shell only  PowerShell profile + Oh My Posh + plugins + aliases',
            '[3] Projector   Terminal animation suite (fastfetch, cmatrix, Python)',
            '[4] AI tools    Claude Code, Gemini CLI, gh copilot',
            '[5] Custom      Choose individual tool groups'
        )
        $sel = Read-GumChoice -Header 'Select install mode' -Options $opts
        if ($sel) {
            switch -Regex ($sel) {
                '^\[1\]' { $Script:DoShell = $true; $Script:DoProjector = $true; $Script:DoAI = $true; return }
                '^\[2\]' { $Script:DoShell = $true; return }
                '^\[3\]' { $Script:DoProjector = $true; return }
                '^\[4\]' { $Script:DoAI = $true; return }
                '^\[5\]' { Resolve-Custom; return }
            }
        }
    }

    # ASCII fallback menu
    Write-Host ''
    Write-Host '  Select install mode:' -ForegroundColor White
    Write-Host ''
    Write-Host '    [1]  Full        Shell + Projector + AI tools (recommended)' -ForegroundColor Cyan
    Write-Host '    [2]  Shell only  PowerShell profile + Oh My Posh + plugins + aliases' -ForegroundColor Cyan
    Write-Host '    [3]  Projector   Terminal animation suite (fastfetch, cmatrix, Python)' -ForegroundColor Cyan
    Write-Host '    [4]  AI tools    Claude Code, Gemini CLI, gh copilot' -ForegroundColor Cyan
    Write-Host '    [5]  Custom      Choose individual tool groups' -ForegroundColor Cyan
    Write-Host ''
    $choice = Read-Host '  Enter choice [1-5] (default: 1)'
    if ($choice -eq '') { $choice = '1' }
    switch ($choice) {
        '1' { $Script:DoShell = $true; $Script:DoProjector = $true; $Script:DoAI = $true }
        '2' { $Script:DoShell = $true }
        '3' { $Script:DoProjector = $true }
        '4' { $Script:DoAI = $true }
        '5' { Resolve-Custom }
        default {
            Write-Warn "Unknown choice '$choice' -- defaulting to Full"
            $Script:DoShell = $true; $Script:DoProjector = $true; $Script:DoAI = $true
        }
    }
}

function Resolve-Custom {
    $ans = Read-Host '  Install Shell experience? [Y/n]'
    if ($ans -eq '' -or $ans -match '^[Yy]') { $Script:DoShell = $true }
    $ans = Read-Host '  Install Projector stack? [Y/n]'
    if ($ans -eq '' -or $ans -match '^[Yy]') { $Script:DoProjector = $true }
    $ans = Read-Host '  Install AI tools (Claude Code, Gemini CLI)? [Y/n]'
    if ($ans -eq '' -or $ans -match '^[Yy]') { $Script:DoAI = $true }
}

# =============================================================================
# EXECUTE
# =============================================================================

Test-Prerequisites          # gates + auto-install PS 7 + (possibly) relaunch
Initialize-PackageManagers  # Scoop + Choco + gum
Start-LogViewerWindow       # spawn the cyberwave-bordered live log window
Resolve-InstallMode         # gum-based picker (now available)

if ($Script:DoShell)     { Install-ShellExperience }
if ($Script:DoProjector) { Install-Projector }
if ($Script:DoAI)        { Install-AITools }

# =============================================================================
# DONE
# =============================================================================

Write-Log INFO "=== INSTALL COMPLETE ==="

if (Test-Cmd gum) {
    Write-Host ''
    & gum style `
        --border 'double' `
        --border-foreground $Script:CW.Pink `
        --foreground $Script:CW.BrightCyan `
        --padding '1 6' `
        --margin '1 2' `
        --align 'center' `
        "[+]  Installation complete  --  knives sharp."
} else {
    Write-Host ''
    Write-Host '  +==============================================================+' -ForegroundColor DarkGreen
    Write-Host '  |   [+]  Installation complete -- knives sharp.                |' -ForegroundColor Green
    Write-Host '  +==============================================================+' -ForegroundColor DarkGreen
    Write-Host ''
}

if ($Script:FailedTools.Count -gt 0) {
    Write-Host '  Some tools did not install cleanly:' -ForegroundColor Yellow
    foreach ($f in $Script:FailedTools) {
        Write-Host "    - $f" -ForegroundColor DarkYellow
    }
    Write-Host ''
}

if ($Script:DoShell) {
    Write-Host '  Next steps:' -ForegroundColor White
    Write-Host '    1. Restart your terminal (or run: . $PROFILE)' -ForegroundColor DarkCyan
    Write-Host '    2. Set Windows Terminal font to a Nerd Font (e.g. CaskaydiaCove NF)' -ForegroundColor DarkCyan
    Write-Host '    3. Enjoy your new shell.' -ForegroundColor DarkCyan
}
if ($Script:WslPresent -and -not $Script:DoShell) {
    Write-Host '  WSL tip: run install_linux.sh inside WSL for the full Zsh experience' -ForegroundColor DarkYellow
}

Write-Host ''
Write-Host "  Full log: $Script:LogFile" -ForegroundColor DarkGray
Write-Host ''
