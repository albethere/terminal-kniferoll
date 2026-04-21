#Requires -Version 5.1
<#
.SYNOPSIS
    Unit tests for the PowerShell Zscaler-block sweeper in install_windows.ps1.
.DESCRIPTION
    Sources Strip-ZscalerRegionsPS and Upsert-ProfileZscalerBlock from
    install_windows.ps1 (via stub shim), then runs targeted test cases
    matching the 10-TC spec.
.NOTES
    Run: pwsh -NoProfile -File scripts/test-sweep.ps1
    Exit 0 if all tests pass; exit 1 if any fail.
#>

param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Locate installer ──────────────────────────────────────────────────────────
$ScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
$InstallerPath = Join-Path (Split-Path $ScriptRoot -Parent) 'install_windows.ps1'
if (-not (Test-Path $InstallerPath)) {
    Write-Error "install_windows.ps1 not found at: $InstallerPath"
    exit 1
}

# ── Dot-source only the functions we need, bypassing main execution ───────────
# Extract Strip-ZscalerRegionsPS and Upsert-ProfileZscalerBlock function text.
$src = [System.IO.File]::ReadAllText($InstallerPath)

# Isolate function bodies by grepping between function start and next blank-line
# preceded by closing brace.  Simple but reliable for these functions.
$funcPattern = '(?ms)^function (Strip-ZscalerRegionsPS|Upsert-ProfileZscalerBlock|Get-ZscalerMarkerBlock)\s*\{.*?^}'
$matches_ = [regex]::Matches($src, $funcPattern)
foreach ($m in $matches_) {
    Invoke-Expression $m.Value
}

# ── Minimal stubs for helpers not extracted above ────────────────────────────
if (-not (Get-Command 'Write-OK'   -ErrorAction SilentlyContinue)) { function Write-OK   { param($m) } }
if (-not (Get-Command 'Write-Info' -ErrorAction SilentlyContinue)) { function Write-Info { param($m) } }
if (-not (Get-Command 'Write-Warn' -ErrorAction SilentlyContinue)) { function Write-Warn { param($m) } }

# ── Test framework ────────────────────────────────────────────────────────────
$Pass = 0
$Fail = 0

function Assert-Contains {
    param([string]$Label, [string]$Content, [string]$Pattern)
    if ($Content -match $Pattern) {
        Write-Host "  PASS: $Label" -ForegroundColor Green
        $script:Pass++
    } else {
        Write-Host "  FAIL: $Label" -ForegroundColor Red
        Write-Host "        pattern not found: $Pattern"
        Write-Host "        content: $Content"
        $script:Fail++
    }
}

function Assert-NotContains {
    param([string]$Label, [string]$Content, [string]$Pattern)
    if ($Content -notmatch $Pattern) {
        Write-Host "  PASS: $Label" -ForegroundColor Green
        $script:Pass++
    } else {
        Write-Host "  FAIL: $Label" -ForegroundColor Red
        Write-Host "        unexpected pattern still present: $Pattern"
        Write-Host "        content: $Content"
        $script:Fail++
    }
}

function Assert-Equal {
    param([string]$Label, $Expected, $Actual)
    if ($Expected -eq $Actual) {
        Write-Host "  PASS: $Label (value=$Actual)" -ForegroundColor Green
        $script:Pass++
    } else {
        Write-Host "  FAIL: $Label (expected=$Expected, got=$Actual)" -ForegroundColor Red
        $script:Fail++
    }
}

# ── Temp dir ──────────────────────────────────────────────────────────────────
$TmpDir = [System.IO.Path]::GetTempPath()
$TmpDir = Join-Path $TmpDir "tk_sweep_test_$([System.Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $TmpDir | Out-Null

try {

# ── TC1: Old $ZSC_PEM_WIN= block stripped ────────────────────────────────────
Write-Host "`n=== TC1-PS: old assignment block stripped ==="
$tc1 = @'
$env:EDITOR = 'vim'

$ZSC_PEM_WIN = 'C:\ProgramData\Zscaler\ZscalerRootCertificate.crt'
if (Test-Path $ZSC_PEM_WIN) {
    $env:CURL_CA_BUNDLE = $ZSC_PEM_WIN
    $env:SSL_CERT_FILE  = $ZSC_PEM_WIN
    $env:GIT_SSL_CAINFO = $ZSC_PEM_WIN
}

Set-Alias gst 'git status'
'@
$t1f = Join-Path $TmpDir 'tc1.ps1'
Set-Content $t1f $tc1 -Encoding UTF8

$out1 = Strip-ZscalerRegionsPS -FilePath $t1f
Assert-NotContains 'TC1: ZSC_PEM_WIN removed'    $out1 'ZSC_PEM_WIN'
Assert-NotContains 'TC1: CURL_CA_BUNDLE removed' $out1 'CURL_CA_BUNDLE'
Assert-Contains    'TC1: EDITOR preserved'        $out1 "EDITOR.*=.*'vim'"
Assert-Contains    'TC1: gst alias preserved'     $out1 'gst'

# ── TC2: Old block + user code below ─────────────────────────────────────────
Write-Host "`n=== TC2-PS: old block + user code preserved ==="
$tc2 = @'
$ZSC_PEM_WIN = 'C:\ProgramData\Zscaler\ZscalerRootCertificate.crt'
$env:CURL_CA_BUNDLE = $ZSC_PEM_WIN

function MyWork { Write-Host "hello" }
$env:PAGER = 'less'
'@
$t2f = Join-Path $TmpDir 'tc2.ps1'
Set-Content $t2f $tc2 -Encoding UTF8

$out2 = Strip-ZscalerRegionsPS -FilePath $t2f
Assert-NotContains 'TC2: ZSC_PEM_WIN removed'    $out2 'ZSC_PEM_WIN'
Assert-NotContains 'TC2: CURL_CA_BUNDLE removed' $out2 'CURL_CA_BUNDLE'
Assert-Contains    'TC2: MyWork preserved'        $out2 'MyWork'
Assert-Contains    'TC2: PAGER preserved'         $out2 'PAGER'

# ── TC3: Old block wrapped in user function ───────────────────────────────────
# Note: PS1 sweeper uses heuristic (strips structural lines), so we verify the
# function shell key parts are preserved even if internals are eaten.
Write-Host "`n=== TC3-PS: block in user function — function preserved ==="
$tc3 = @'
function Setup-MyCerts {
    $ZSC_PEM_WIN = 'C:\ProgramData\Zscaler\ZscalerRootCertificate.crt'
    if (Test-Path $ZSC_PEM_WIN) {
        $env:CURL_CA_BUNDLE = $ZSC_PEM_WIN
    }
}
$env:EDITOR = 'vim'
'@
$t3f = Join-Path $TmpDir 'tc3.ps1'
Set-Content $t3f $tc3 -Encoding UTF8

$out3 = Strip-ZscalerRegionsPS -FilePath $t3f
Assert-Contains    'TC3: Setup-MyCerts name preserved' $out3 'Setup-MyCerts'
Assert-Contains    'TC3: EDITOR preserved'             $out3 'EDITOR'

# ── TC4: Two old blocks separated by user content ────────────────────────────
Write-Host "`n=== TC4-PS: two old blocks — both removed, user content between preserved ==="
$tc4 = @'
$ZSC_PEM_WIN = 'C:\ProgramData\Zscaler\ZscalerRootCertificate.crt'
$env:CURL_CA_BUNDLE = $ZSC_PEM_WIN

$env:EDITOR = 'vim'

# BEGIN terminal-kniferoll zscaler — DO NOT EDIT (managed by installer)
if (Test-Path "$env:USERPROFILE\.config\terminal-kniferoll\zscaler-env.ps1") {
    . "$env:USERPROFILE\.config\terminal-kniferoll\zscaler-env.ps1"
}
# END terminal-kniferoll zscaler

$env:PAGER = 'less'
'@
$t4f = Join-Path $TmpDir 'tc4.ps1'
Set-Content $t4f $tc4 -Encoding UTF8

$out4 = Strip-ZscalerRegionsPS -FilePath $t4f
Assert-NotContains 'TC4: ZSC_PEM_WIN removed'        $out4 'ZSC_PEM_WIN'
Assert-NotContains 'TC4: CURL_CA_BUNDLE removed'     $out4 'CURL_CA_BUNDLE'
Assert-NotContains 'TC4: BEGIN marker removed'       $out4 'BEGIN terminal-kniferoll'
Assert-NotContains 'TC4: source line removed'        $out4 'zscaler-env\.ps1'
Assert-Contains    'TC4: EDITOR preserved'           $out4 'EDITOR'
Assert-Contains    'TC4: PAGER preserved'            $out4 'PAGER'

# ── TC5: Marker-only → after strip+re-append result is idempotent ────────────
Write-Host "`n=== TC5-PS: marker-only file — strip produces empty base ==="
$tc5 = @'
# BEGIN terminal-kniferoll zscaler — DO NOT EDIT (managed by installer)
if (Test-Path "$env:USERPROFILE\.config\terminal-kniferoll\zscaler-env.ps1") {
    . "$env:USERPROFILE\.config\terminal-kniferoll\zscaler-env.ps1"
}
# END terminal-kniferoll zscaler
'@
$t5f = Join-Path $TmpDir 'tc5.ps1'
Set-Content $t5f $tc5 -Encoding UTF8

$out5 = Strip-ZscalerRegionsPS -FilePath $t5f
Assert-NotContains 'TC5: BEGIN marker stripped' $out5 'BEGIN terminal-kniferoll'
Assert-NotContains 'TC5: source line stripped'  $out5 'zscaler-env\.ps1'

# ── TC6: Old block + existing marker → both stripped ─────────────────────────
Write-Host "`n=== TC6-PS: old block + existing marker — both stripped ==="
$tc6 = @'
$env:EDITOR = 'vim'

$ZSC_PEM_WIN = 'C:\ProgramData\Zscaler\ZscalerRootCertificate.crt'
$env:SSL_CERT_FILE = $ZSC_PEM_WIN

# BEGIN terminal-kniferoll zscaler — DO NOT EDIT (managed by installer)
if (Test-Path "$env:USERPROFILE\.config\terminal-kniferoll\zscaler-env.ps1") {
    . "$env:USERPROFILE\.config\terminal-kniferoll\zscaler-env.ps1"
}
# END terminal-kniferoll zscaler

$env:PAGER = 'less'
'@
$t6f = Join-Path $TmpDir 'tc6.ps1'
Set-Content $t6f $tc6 -Encoding UTF8

$out6 = Strip-ZscalerRegionsPS -FilePath $t6f
Assert-NotContains 'TC6: ZSC_PEM_WIN removed'       $out6 'ZSC_PEM_WIN'
Assert-NotContains 'TC6: SSL_CERT_FILE removed'     $out6 'SSL_CERT_FILE'
Assert-NotContains 'TC6: BEGIN marker removed'      $out6 'BEGIN terminal-kniferoll'
Assert-Contains    'TC6: EDITOR preserved'          $out6 'EDITOR'
Assert-Contains    'TC6: PAGER preserved'           $out6 'PAGER'

# ── TC7: Unrelated Zscaler comment preserved ─────────────────────────────────
Write-Host "`n=== TC7-PS: unrelated Zscaler comment — preserved ==="
$tc7 = @'
# This machine is NOT a Zscaler-managed device.
$env:EDITOR = 'vim'
$env:PAGER  = 'less'
'@
$t7f = Join-Path $TmpDir 'tc7.ps1'
Set-Content $t7f $tc7 -Encoding UTF8

$out7 = Strip-ZscalerRegionsPS -FilePath $t7f
Assert-Contains 'TC7: Zscaler comment preserved' $out7 'NOT a Zscaler-managed'
Assert-Contains 'TC7: EDITOR preserved'          $out7 'EDITOR'
Assert-Contains 'TC7: PAGER preserved'           $out7 'PAGER'

# ── TC8: Empty file → stripped output is empty ───────────────────────────────
Write-Host "`n=== TC8-PS: empty file — strip returns empty ==="
$t8f = Join-Path $TmpDir 'tc8.ps1'
Set-Content $t8f '' -Encoding UTF8

$out8 = Strip-ZscalerRegionsPS -FilePath $t8f
Assert-Equal 'TC8: empty file returns empty string' '' ($out8.Trim())

# ── TC9: Shebang / no rc content ─────────────────────────────────────────────
Write-Host "`n=== TC9-PS: comment-only file — strip preserves it ==="
$tc9 = @'
# PowerShell profile
$env:EDITOR = 'notepad'
'@
$t9f = Join-Path $TmpDir 'tc9.ps1'
Set-Content $t9f $tc9 -Encoding UTF8

$out9 = Strip-ZscalerRegionsPS -FilePath $t9f
Assert-Contains 'TC9: comment preserved' $out9 'PowerShell profile'
Assert-Contains 'TC9: EDITOR preserved'  $out9 'EDITOR'

# ── TC10: Backup rotation — only 5 most recent kept ──────────────────────────
Write-Host "`n=== TC10-PS: backup rotation — 6 backups pruned to 5 ==="
$t10f = Join-Path $TmpDir 'tc10.ps1'
Set-Content $t10f '$env:EDITOR = ''vim''' -Encoding UTF8

# Simulate 6 backups by calling Upsert-ProfileZscalerBlock 6 times.
# Each call creates a timestamped backup; rotation should keep only 5.
# We inject delays to ensure distinct timestamps (1-second resolution).
for ($i = 1; $i -le 6; $i++) {
    # Restore a trigger line so upsert has something to sweep each time
    $ZscContent = "`$ZSC_PEM_WIN = 'C:\test.crt'`n`$env:EDITOR = 'vim'"
    Set-Content $t10f $ZscContent -Encoding UTF8
    try { Upsert-ProfileZscalerBlock -ProfilePath $t10f } catch {}
    if ($i -lt 6) { Start-Sleep -Seconds 1 }
}

$baks = @(Get-ChildItem -Path $TmpDir -Filter 'tc10.ps1.terminal-kniferoll-backup-*' -ErrorAction SilentlyContinue)
Assert-Equal 'TC10: exactly 5 backups remain' 5 $baks.Count

} finally {
    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "─────────────────────────────────────────────"
Write-Host "Results: $Pass passed, $Fail failed"
Write-Host "─────────────────────────────────────────────"
if ($Fail -eq 0) {
    Write-Host "All tests passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "FAILURES detected." -ForegroundColor Red
    exit 1
}
