# ==============================================================================
# terminal-kniferoll | PowerShell Profile
# Windows equivalent of shell/zshrc.zsh — dot-sourced from $PROFILE.CurrentUserAllHosts
# by install_windows.ps1.
# ==============================================================================
# Guard: no-op on non-Windows. Use $null check so this works on PS 5.1 where
# $IsWindows doesn't exist (PS 5.1 only runs on Windows, so the guard is a no-op).
if ($null -ne $IsWindows -and -not $IsWindows) { return }

# ── ZSCALER PROXY CONFIG (CORP / MANAGED DEVICES ONLY) ───────────────────────
#
# Detection order (mirrors install_mac.sh logic adapted for Windows):
#   1. Previously built CA bundle (installer-cached, fast path on re-run):
#        $env:USERPROFILE\.config\terminal-kniferoll\ca-bundle.pem
#   2. PDF-prescribed LM standard paths (LM Zscaler Developer Onboarding, Dec 2025):
#        C:\Users\<user>\.certificates\zscaler.pem  /  .crt copy
#   3. $env:USERPROFILE\.certificates\... (user-level, equiv. to above)
#   4. ProgramData Zscaler paths (ZIA/ZPA client defaults)
#
# If none found: no Zscaler env is set; standard system trust applies.
# HOMEBREW_CURLOPT_CACERT is intentionally excluded — macOS-only env var.
$_zscCandidates = @(
    "$env:USERPROFILE\.config\terminal-kniferoll\ca-bundle.pem",
    "C:\Users\$env:UserName\.certificates\zscaler.pem",
    "C:\Users\$env:UserName\.certificates\zscaler.crt",
    "$env:USERPROFILE\.certificates\zscaler.pem",
    "$env:USERPROFILE\.certificates\zscaler.crt",
    'C:\ProgramData\Zscaler\ZscalerRootCertificate-2048-SHA256.crt',
    'C:\ProgramData\Zscaler\ZscalerRootCertificate.pem',
    'C:\ProgramData\Zscaler\ZscalerRootCertificate.crt'
)
$_zscPem = $null
foreach ($_p in $_zscCandidates) {
    if (Test-Path $_p) {
        $_fi = Get-Item $_p -ErrorAction SilentlyContinue
        if ($_fi -and $_fi.Length -gt 0) { $_zscPem = $_p; break }
    }
}
if ($_zscPem) {
    $env:CURL_CA_BUNDLE      = $_zscPem
    $env:AWS_CA_BUNDLE       = $_zscPem
    $env:PIP_CERT            = $_zscPem
    $env:NODE_EXTRA_CA_CERTS = $_zscPem
    $env:REQUESTS_CA_BUNDLE  = $_zscPem
    $env:SSL_CERT_FILE       = $_zscPem
    $env:GIT_SSL_CAINFO      = $_zscPem
    # HOMEBREW_CURLOPT_CACERT intentionally NOT set — macOS-only
}
Remove-Variable _zscCandidates, _zscPem, _p, _fi -ErrorAction SilentlyContinue

# ── Oh My Posh ────────────────────────────────────────────────────────────────
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    $_ompTheme = "$env:POSH_THEMES_PATH\jandedobbeleer.omp.json"
    if (-not (Test-Path $_ompTheme)) { $_ompTheme = 'jandedobbeleer' }
    oh-my-posh init pwsh --config $_ompTheme | Invoke-Expression
    Remove-Variable _ompTheme -ErrorAction SilentlyContinue
}

# ── PSReadLine (autosuggestions + syntax highlighting) ────────────────────────
if (Get-Module -ListAvailable PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
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
if (Get-Module -ListAvailable Terminal-Icons) { Import-Module Terminal-Icons }

# ── posh-git ──────────────────────────────────────────────────────────────────
if (Get-Module -ListAvailable posh-git) { Import-Module posh-git }

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

if (Get-Command lsd -ErrorAction SilentlyContinue) {
    function ls  { lsd @args }
    function l   { lsd -l @args }
    function la  { lsd -la @args }
    function ll  { lsd -lA @args }
    function lr  { lsd -latr @args }
    function lt  { lsd --tree @args }
} else {
    function l  { Get-ChildItem @args }
    function la { Get-ChildItem -Force @args }
    function ll { Get-ChildItem -Force @args | Format-List }
}

if (Get-Command bat -ErrorAction SilentlyContinue) {
    function cat { bat @args }
}

if (Get-Command nvim -ErrorAction SilentlyContinue) {
    Set-Alias vim  nvim
    Set-Alias vi   nvim
    Set-Alias nano nvim
}

function myip  { (Invoke-WebRequest -Uri 'https://icanhazip.com' -UseBasicParsing).Content.Trim() }
function reload { . $PROFILE; Write-Host 'Profile reloaded.' -ForegroundColor Cyan }
# `ff` lives in the managed `ff-alias` marker block in $PROFILE (installer-managed).

function ..   { Set-Location .. }
function ...  { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

function gs  { git status }
function ga  { git add @args }
function gc  { git commit @args }
function gp  { git push }
function gl  { git --no-pager log --oneline -10 }
function gd  { git --no-pager diff }
function gb  { git branch @args }
function gco { git checkout @args }
function gpl { git pull }

if (Get-Command rg -ErrorAction SilentlyContinue) {
    Set-Alias grep rg -Force -ErrorAction SilentlyContinue
}

# ── up: cross-package-manager updater (matches Unix `up` alias) ───────────────
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
        scoop update '*'
        scoop cleanup '*'
    }
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host '==> choco upgrade all' -ForegroundColor Cyan
        choco upgrade all -y
    }
    Write-Host '==> Update-Module (PSGallery, CurrentUser)' -ForegroundColor Cyan
    Update-Module -Scope CurrentUser -Force -ErrorAction Continue
}
Set-Alias abu up -Force -ErrorAction SilentlyContinue
Set-Alias bru up -Force -ErrorAction SilentlyContinue

# ── Private API keys (from environment, never hardcoded) ──────────────────────
if ($env:PRIVATE_VT_API_KEY)        { $env:VT_API_KEY        = $env:PRIVATE_VT_API_KEY }
if ($env:PRIVATE_PT_API_KEY)        { $env:PT_API_KEY        = $env:PRIVATE_PT_API_KEY }
if ($env:PRIVATE_PT_API_USER)       { $env:PT_API_USER       = $env:PRIVATE_PT_API_USER }
if ($env:PRIVATE_IP2WHOIS_API_KEY)  { $env:IP2WHOIS_API_KEY  = $env:PRIVATE_IP2WHOIS_API_KEY }
if ($env:PRIVATE_SHODAN_API_KEY)    { $env:SHODAN_API_KEY    = $env:PRIVATE_SHODAN_API_KEY }
if ($env:PRIVATE_GREYNOISE_API_KEY) { $env:GREYNOISE_API_KEY = $env:PRIVATE_GREYNOISE_API_KEY }
if ($env:PRIVATE_ABUSEIPDB_API_KEY) { $env:ABUSEIPDB_API_KEY = $env:PRIVATE_ABUSEIPDB_API_KEY }

# ── lolcat alias / ff alias / fastfetch greeter (managed marker blocks) ──────
# Three managed blocks below. install_windows.ps1's profile generator emits
# the same blocks into $PROFILE files; this is the in-repo source of truth.

# BEGIN terminal-kniferoll lolcat-alias -- DO NOT EDIT (managed by installer)
if ((Get-Command lolcrab -ErrorAction SilentlyContinue) -and `
    -not (Get-Command lolcat -ErrorAction SilentlyContinue)) {
    Set-Alias -Name lolcat -Value lolcrab -Scope Global
}
# END terminal-kniferoll lolcat-alias

# BEGIN terminal-kniferoll ff-alias -- DO NOT EDIT (managed by installer)
if ((Get-Command fastfetch -ErrorAction SilentlyContinue) -and `
    (Get-Command lolcrab -ErrorAction SilentlyContinue)) {
    function ff { fastfetch | lolcrab }
} elseif (Get-Command fastfetch -ErrorAction SilentlyContinue) {
    function ff { fastfetch }
}
# END terminal-kniferoll ff-alias

# BEGIN terminal-kniferoll fastfetch-greeter -- DO NOT EDIT (managed by installer)
function Test-TKAnsiSupported {
    if ($env:WT_SESSION) { return $true }
    if ($Host.UI.SupportsVirtualTerminal) { return $true }
    if ($PSVersionTable.PSVersion.Major -ge 7) { return $true }
    return $false
}
if (-not $env:TK_FASTFETCH_GREETED -and -not $env:DISABLE_WELCOME -and `
    (Get-Command fastfetch -ErrorAction SilentlyContinue) -and `
    (Test-TKAnsiSupported)) {
    if (Get-Command lolcrab -ErrorAction SilentlyContinue) {
        fastfetch | lolcrab
    } else {
        fastfetch
    }
    $env:TK_FASTFETCH_GREETED = '1'
}
Remove-Item Function:Test-TKAnsiSupported -ErrorAction SilentlyContinue
# END terminal-kniferoll fastfetch-greeter
