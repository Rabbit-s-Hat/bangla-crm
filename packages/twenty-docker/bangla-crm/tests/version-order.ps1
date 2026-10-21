# Checks Test-VersionOlder from bangla-crm-common.ps1 against tests\version-order.txt.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\version-order.ps1
# ASCII-only on purpose (Windows PowerShell 5.1).
$ErrorActionPreference = 'Stop'
$pkg = Split-Path -Parent $PSScriptRoot
. ([scriptblock]::Create(((Get-Content -LiteralPath (Join-Path $pkg 'bangla-crm-common.ps1') -Raw) -replace '(?m)^Set-Location .*$', '')))
$fails = 0
foreach ($line in Get-Content -LiteralPath (Join-Path $PSScriptRoot 'version-order.txt')) {
    if (-not $line.Trim() -or $line.StartsWith('#')) { continue }
    $a, $b, $want = $line.Split(' ')
    $got = if (Test-VersionOlder $a $b) { 'yes' } else { 'no' }
    if ($got -eq $want) { Write-Host "  ok   $a < $b : $got" } else { Write-Host "  FAIL $a < $b : got $got, want $want" -ForegroundColor Red; $fails++ }
}
if ($fails -gt 0) { Write-Host "$fails check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All version-order checks passed (PowerShell).'
