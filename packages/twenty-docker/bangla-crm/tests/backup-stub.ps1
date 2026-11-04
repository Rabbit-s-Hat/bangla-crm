# Stub test for Invoke-Backup on Windows PowerShell 5.1 (no Docker needed).
# A fake `docker` function answers the size queries and copies, so the test can prove that
# (1) a finished backup is a plain backups\<date-time> folder, (2) a backup that fails halfway leaves
# no folder behind (never a half backup that looks complete), (3) a stale *.partial folder from an
# earlier interrupted run is removed, and (4) the free-space check counts the uploaded files.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\backup-stub.ps1
# ASCII-only on purpose (Windows PowerShell 5.1).

$ErrorActionPreference = 'Stop'
$pkg = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([IO.Path]::GetTempPath()) ('bangla-crm-backup-stub-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
Copy-Item -LiteralPath (Join-Path $pkg 'bangla-crm-common.ps1') -Destination $work
[IO.File]::WriteAllText((Join-Path $work '.env'), "TAG=0.1.0`nPG_DATABASE_USER=postgres`n")
$backups = Join-Path $work 'backups'

$script:FilesKb = '2048'
$script:FailFilesCopy = $false
$script:Calls = New-Object System.Collections.ArrayList

function docker {
    $argv = @($args | ForEach-Object { [string]$_ })
    [void]$script:Calls.Add(($argv -join ' '))
    $global:LASTEXITCODE = 0
    $line = $argv -join ' '
    if ($line -match '^compose ps') { return 'stubcontainer' }
    if ($argv[0] -eq 'inspect') { return 'healthy' }
    if ($line -match '^compose images') { return 'bangla-crm 0.1.0' }
    if ($line -match ' du -sk ') { return ($script:FilesKb + "`t/app/packages/twenty-server/.local-storage") }
    if ($line -match ' psql .*pg_database_size') { return '1048576' }
    if ($argv[0] -eq 'cp') {
        $dest = $argv[2]
        if ($argv[1] -match '\.local-storage$') {
            if ($script:FailFilesCopy) { $global:LASTEXITCODE = 1; return }
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            [IO.File]::WriteAllText((Join-Path $dest 'upload.bin'), 'x')
        } else {
            [IO.File]::WriteAllText($dest, 'PGDMP stub')
        }
        return
    }
}

Set-Location $work
. (Join-Path $work 'bangla-crm-common.ps1')
function Wait-Healthy { }

$failures = 0
function Check([bool]$Ok, [string]$What) {
    if ($Ok) { Write-Host ('  ok   ' + $What) } else { Write-Host ('  FAIL ' + $What) -ForegroundColor Red; $script:failures++ }
}
function Get-BackupDirs { @(Get-ChildItem -LiteralPath $backups -Directory -ErrorAction SilentlyContinue) }

Write-Host 'Scenario 1: successful backup'
Invoke-Backup 6>$null
$dirs = Get-BackupDirs
Check ($dirs.Count -eq 1) 'exactly one backup folder'
Check ($dirs.Count -eq 1 -and $dirs[0].Name -match '^\d{4}-\d{2}-\d{2}_\d{6}$') 'folder is named <date-time> (no .partial)'
Check ($script:BackupDir -eq $dirs[0].FullName) 'BackupDir points at the finished folder'
foreach ($f in @('database.dump', 'files\upload.bin', 'version.txt', 'env.txt')) {
    Check (Test-Path -LiteralPath (Join-Path $dirs[0].FullName $f)) ('contains ' + $f)
}
Check (@($script:Calls | Where-Object { $_ -match ' du -sk ' }).Count -ge 1) 'uploaded files were measured'
Remove-Item -LiteralPath $backups -Recurse -Force

Write-Host 'Scenario 2: copying the uploaded files fails halfway'
$script:FailFilesCopy = $true
$threw = $false
try { Invoke-Backup 6>$null } catch { $threw = $true }
Check $threw 'Invoke-Backup reports the failure'
Check ((Get-BackupDirs).Count -eq 0) 'no backup folder (complete or .partial) is left behind'
$script:FailFilesCopy = $false

Write-Host 'Scenario 3: a stale .partial folder from an interrupted run'
New-Item -ItemType Directory -Force -Path (Join-Path $backups '2026-01-01_000000.partial') | Out-Null
Invoke-Backup 6>$null
$dirs = Get-BackupDirs
Check ($dirs.Count -eq 1 -and $dirs[0].Name -notlike '*.partial') 'stale .partial removed, new backup kept'
Remove-Item -LiteralPath $backups -Recurse -Force

Write-Host 'Scenario 4: uploaded files larger than the free disk space'
$script:FilesKb = '100000000000'   # about 93 TB
$msg = ''
try { Invoke-Backup 6>$null } catch { $msg = [string]$_ }
Check ($msg -like 'Not enough free disk space*') 'free-space check counts the uploaded files'
Check ((Get-BackupDirs).Count -eq 0) 'nothing written when there is no room'

Set-Location $pkg
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
if ($failures -gt 0) { Write-Host "$failures check(s) FAILED" -ForegroundColor Red; exit 1 }
Write-Host 'All backup stub checks passed.'
exit 0
