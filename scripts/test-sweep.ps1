#Requires -Version 5.1
<#
.SYNOPSIS
    Unit tests for the Windows Zscaler profile sweep (install_windows.ps1).
.DESCRIPTION
    Sources Strip-ZscalerRegionsPS and Upsert-ProfileZscalerBlock from
    install_windows.ps1 then runs a suite of test cases matching the Unix
    TC1–TC10 semantics.

    Exit 0 — all tests pass.
    Exit 1 — one or more failures.
.EXAMPLE
    pwsh -NoProfile -File scripts\test-sweep.ps1
    powershell -NoProfile -File scripts\test-sweep.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ── Locate installer ──────────────────────────────────────────────────────────
$RepoRoot   = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
$InstallerPath = Join-Path $RepoRoot 'install_windows.ps1'
if (-not (Test-Path $InstallerPath)) {
    Write-Error "install_windows.ps1 not found at: $InstallerPath"
    exit 1
}

# Dot-source only the sweep functions (not the main execution block).
# install_windows.ps1 has its execution block protected by CmdletBinding +
# param() — the functions are defined at parse time when dot-sourced in a
# child scope. We stub any missing helpers below.
function Write-Info { param([string]$m) }
function Write-Warn { param([string]$m) }
function Write-OK   { param([string]$m) }
function Write-Log  { param([string]$l, [string]$m) }
function Write-Section { param([string]$t) }

# Suppress execution guard by setting all switch params
$Script:SkipMainBlock = $true
try {
    # Parse-only: extract just the function definitions we need
    $src = Get-Content $InstallerPath -Raw
    $funcNames = @('Strip-ZscalerRegionsPS', 'Upsert-ProfileZscalerBlock',
                   'Invoke-ZscalerProfileSweep')
    foreach ($fn in $funcNames) {
        # Regex: capture the function block (single brace depth)
        $pattern = "(?ms)^function\s+${fn}\s*\{(.+?)^\}"
        if ($src -match $pattern) {
            $block = "function ${fn} {$($Matches[1])}"
            Invoke-Expression $block
        }
    }
} catch {
    Write-Warning "Could not parse installer functions: $_"
}

# Verify we have the functions
foreach ($fn in @('Strip-ZscalerRegionsPS', 'Upsert-ProfileZscalerBlock')) {
    if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) {
        Write-Error "Function $fn not available — cannot run tests."
        exit 1
    }
}

# ── Test framework ────────────────────────────────────────────────────────────
$Script:Pass = 0
$Script:Fail = 0

function Assert-Contains {
    param([string]$Label, [string]$FilePath, [string]$Pattern)
    $content = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
    if ($content -match $Pattern) {
        Write-Host "  PASS: $Label" -ForegroundColor Green
        $Script:Pass++
    } else {
        Write-Host "  FAIL: $Label" -ForegroundColor Red
        Write-Host "        expected pattern: $Pattern"
        Write-Host "        file content:`n$(Get-Content $FilePath -Raw | ForEach-Object { "          $_" })"
        $Script:Fail++
    }
}

function Assert-NotContains {
    param([string]$Label, [string]$FilePath, [string]$Pattern)
    $content = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
    if ($content -notmatch $Pattern) {
        Write-Host "  PASS: $Label" -ForegroundColor Green
        $Script:Pass++
    } else {
        Write-Host "  FAIL: $Label" -ForegroundColor Red
        Write-Host "        unexpected pattern still present: $Pattern"
        $Script:Fail++
    }
}

function Assert-CountEquals {
    param([string]$Label, [string]$FilePath, [string]$Pattern, [int]$Expected)
    $content = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
    $matches = ([regex]::Matches($content, $Pattern)).Count
    if ($matches -eq $Expected) {
        Write-Host "  PASS: $Label (count=$matches)" -ForegroundColor Green
        $Script:Pass++
    } else {
        Write-Host "  FAIL: $Label (expected $Expected, got $matches)" -ForegroundColor Red
        $Script:Fail++
    }
}

# ── Temp dir ──────────────────────────────────────────────────────────────────
$TmpDir = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path ($_.FullName + '_sweep_test') }

try {

# ══════════════════════════════════════════════════════════════════════════════
# TC1 — old block alone → stripped, marker appended
# ══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== TC1: old PS block alone → stripped, marker appended ===" -ForegroundColor Cyan
$f1 = Join-Path $TmpDir 'tc1_profile.ps1'
Set-Content $f1 @'
$ZSC_PEM_WIN = "$env:USERPROFILE\.certificates\zscaler.pem"
$ZSC_PEM = $null
if (Test-Path $ZSC_PEM_WIN) { $ZSC_PEM = $ZSC_PEM_WIN }
if ($ZSC_PEM) {
    $env:CURL_CA_BUNDLE = $ZSC_PEM
    $env:SSL_CERT_FILE  = $ZSC_PEM
    $env:GIT_SSL_CAINFO = $ZSC_PEM
}
'@ -Encoding UTF8
Upsert-ProfileZscalerBlock -ProfilePath $f1
Assert-NotContains "TC1: ZSC_PEM_WIN removed"         $f1 '\$ZSC_PEM_WIN\s*='
Assert-NotContains "TC1: raw CURL_CA_BUNDLE removed"   $f1 'env:CURL_CA_BUNDLE\s*=\s*\$ZSC_PEM'
Assert-Contains    "TC1: marker appended"              $f1 'BEGIN terminal-kniferoll zscaler'
Assert-Contains    "TC1: source line present"          $f1 'zscaler-env\.ps1'

# ══════════════════════════════════════════════════════════════════════════════
# TC2 — old block + user content below → user preserved
# ══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== TC2: old block + user content below → user preserved ===" -ForegroundColor Cyan
$f2 = Join-Path $TmpDir 'tc2_profile.ps1'
Set-Content $f2 @'
$ZSC_PEM_WIN = "$env:USERPROFILE\.certificates\zscaler.pem"
$env:CURL_CA_BUNDLE = $ZSC_PEM_WIN

Set-Alias ll Get-ChildItem
$env:EDITOR = 'nvim'
'@ -Encoding UTF8
Upsert-ProfileZscalerBlock -ProfilePath $f2
Assert-NotContains "TC2: ZSC_PEM_WIN removed"         $f2 '\$ZSC_PEM_WIN\s*='
Assert-Contains    "TC2: Set-Alias preserved"         $f2 'Set-Alias ll'
Assert-Contains    "TC2: EDITOR preserved"            $f2 'EDITOR.*nvim'
Assert-Contains    "TC2: marker appended"             $f2 'BEGIN terminal-kniferoll zscaler'

# ══════════════════════════════════════════════════════════════════════════════
# TC3 — only marker → marker exactly once after re-run
# ══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== TC3: only marker → idempotent (marker exactly once) ===" -ForegroundColor Cyan
$f3 = Join-Path $TmpDir 'tc3_profile.ps1'
Set-Content $f3 @'
# BEGIN terminal-kniferoll zscaler -- DO NOT EDIT (managed by installer)
$__zkEnv = "$env:USERPROFILE\.config\terminal-kniferoll\zscaler-env.ps1"
if (Test-Path $__zkEnv) { . $__zkEnv }
Remove-Variable __zkEnv -ErrorAction SilentlyContinue
# END terminal-kniferoll zscaler
'@ -Encoding UTF8
Upsert-ProfileZscalerBlock -ProfilePath $f3
Assert-Contains    "TC3: marker present"              $f3 'BEGIN terminal-kniferoll zscaler'
Assert-CountEquals "TC3: BEGIN exactly once"          $f3 'BEGIN terminal-kniferoll zscaler' 1
Assert-CountEquals "TC3: END exactly once"            $f3 'END terminal-kniferoll zscaler' 1

# ══════════════════════════════════════════════════════════════════════════════
# TC4 — old block + existing marker → old stripped, single clean marker
# ══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== TC4: old block + existing marker → single clean marker ===" -ForegroundColor Cyan
$f4 = Join-Path $TmpDir 'tc4_profile.ps1'
Set-Content $f4 @'
$env:EDITOR = 'nvim'

$ZSC_PEM_WIN = "$env:USERPROFILE\.certificates\zscaler.pem"
$env:CURL_CA_BUNDLE = $ZSC_PEM_WIN

# BEGIN terminal-kniferoll zscaler -- DO NOT EDIT (managed by installer)
$__zkEnv = "$env:USERPROFILE\.config\terminal-kniferoll\zscaler-env.ps1"
if (Test-Path $__zkEnv) { . $__zkEnv }
Remove-Variable __zkEnv -ErrorAction SilentlyContinue
# END terminal-kniferoll zscaler

$env:PAGER = 'less'
'@ -Encoding UTF8
Upsert-ProfileZscalerBlock -ProfilePath $f4
Assert-NotContains "TC4: ZSC_PEM_WIN removed"         $f4 '\$ZSC_PEM_WIN\s*='
Assert-Contains    "TC4: EDITOR preserved"            $f4 'EDITOR.*nvim'
Assert-Contains    "TC4: PAGER preserved"             $f4 'PAGER.*less'
Assert-CountEquals "TC4: BEGIN exactly once"          $f4 'BEGIN terminal-kniferoll zscaler' 1

# ══════════════════════════════════════════════════════════════════════════════
# TC5 — empty profile → marker only
# ══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== TC5: empty profile → marker only ===" -ForegroundColor Cyan
$f5 = Join-Path $TmpDir 'tc5_profile.ps1'
Set-Content $f5 '' -Encoding UTF8
Upsert-ProfileZscalerBlock -ProfilePath $f5
Assert-Contains    "TC5: marker present"              $f5 'BEGIN terminal-kniferoll zscaler'
Assert-Contains    "TC5: source line present"         $f5 'zscaler-env\.ps1'
Assert-CountEquals "TC5: BEGIN exactly once"          $f5 'BEGIN terminal-kniferoll zscaler' 1

# ══════════════════════════════════════════════════════════════════════════════
# TC6 — backup rotation: 6 calls → 5 backups retained
# ══════════════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== TC6: backup rotation — 6 calls, 5 backups retained ===" -ForegroundColor Cyan
$f6 = Join-Path $TmpDir 'tc6_profile.ps1'
Set-Content $f6 '$env:EDITOR = "nvim"' -Encoding UTF8
for ($i = 1; $i -le 6; $i++) {
    Upsert-ProfileZscalerBlock -ProfilePath $f6
    Start-Sleep -Milliseconds 1100
}
$backupCount = (Get-ChildItem "$f6.terminal-kniferoll-backup-*" -ErrorAction SilentlyContinue).Count
if ($backupCount -eq 5) {
    Write-Host "  PASS: TC6: backup rotation — 5 backups remain (got $backupCount)" -ForegroundColor Green
    $Script:Pass++
} else {
    Write-Host "  FAIL: TC6: backup rotation — expected 5, got $backupCount" -ForegroundColor Red
    $Script:Fail++
}

} finally {
    Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "─────────────────────────────────────────────"
Write-Host "Results: $($Script:Pass) passed, $($Script:Fail) failed"
Write-Host "─────────────────────────────────────────────"
if ($Script:Fail -eq 0) {
    Write-Host "All $($Script:Pass) tests passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "$($Script:Fail) test(s) FAILED." -ForegroundColor Red
    exit 1
}
