# Stub test for Invoke-Restore on Windows PowerShell 5.1 (no Docker needed).
# A fake `docker` function records every argv and stdin and simulates the Postgres database list, so the
# test can prove that (1) no SQL travels as a native argument (PS 5.1 strips inner double quotes there),
# (2) the live database is never dropped before the restored one has replaced it, and (3) a failed swap
# leaves the live database untouched.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\restore-stub.ps1
# ASCII-only on purpose (Windows PowerShell 5.1).

$ErrorActionPreference = 'Stop'
$pkg = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([IO.Path]::GetTempPath()) ('bangla-crm-restore-stub-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
Copy-Item -LiteralPath (Join-Path $pkg 'bangla-crm-common.ps1') -Destination $work
[IO.File]::WriteAllText((Join-Path $work '.env'), "TAG=0.1.0`nPG_DATABASE_USER=postgres`n")
$backup = Join-Path $work 'backups\2026-01-01_000000'
New-Item -ItemType Directory -Path $backup | Out-Null
[IO.File]::WriteAllText((Join-Path $backup 'database.dump'), 'PGDMP stub')

$script:Calls = New-Object System.Collections.ArrayList
$script:Dbs = New-Object System.Collections.ArrayList
$script:FailSwap = $false

function docker {
    $argv = @($args | ForEach-Object { [string]$_ })
    $stdin = (@($input) -join "`n")
    [void]$script:Calls.Add([pscustomobject]@{ Argv = $argv; Stdin = $stdin })
    $global:LASTEXITCODE = 0
    $line = $argv -join ' '
    if ($line -match '^compose ps') { return 'stubcontainer' }
    if ($argv[0] -eq 'inspect') { return 'healthy' }
    $tool = if ($argv.Count -gt 4) { $argv[4] } else { '' }
    if ($tool -eq 'createdb') { [void]$script:Dbs.Add($argv[-1]); return }
    if ($tool -eq 'dropdb') { $script:Dbs.Remove($argv[-1]); return }
    if ($tool -eq 'psql') {
        if ($stdin -match 'BEGIN;' -and $script:FailSwap) { $global:LASTEXITCODE = 3; return }
        if ($stdin -match 'SELECT datname') {
            return @($script:Dbs | Where-Object { $stdin.Contains("'" + $_ + "'") })
        }
        foreach ($m in [regex]::Matches($stdin, 'ALTER DATABASE "([^"]+)" RENAME TO "([^"]+)";')) {
            $i = $script:Dbs.IndexOf($m.Groups[1].Value)
            if ($i -lt 0) { $global:LASTEXITCODE = 3; return }
            $script:Dbs[$i] = $m.Groups[2].Value
        }
        return
    }
}

. (Join-Path $work 'bangla-crm-common.ps1')
function Wait-Healthy { }   # the stub containers are always healthy; skip the polling loop

$failures = 0
function Check([bool]$Ok, [string]$What) {
    if ($Ok) { Write-Host ('  ok   ' + $What) } else { Write-Host ('  FAIL ' + $What) -ForegroundColor Red; $script:failures++ }
}

function Reset-Stub([bool]$FailSwap) {
    $script:Calls.Clear(); $script:Dbs.Clear(); [void]$script:Dbs.Add('postgres'); [void]$script:Dbs.Add('default')
    $script:FailSwap = $FailSwap
}

Write-Host 'Scenario 1: successful restore (database name "default", a reserved word)'
Reset-Stub $false
Invoke-Restore $backup -Yes 6>$null
$quoted = @($script:Calls | Where-Object { ($_.Argv -join ' ').Contains('"') })
Check ($quoted.Count -eq 0) 'no docker argument contains a double quote'
$cArgs = @($script:Calls | Where-Object { $_.Argv -contains '-c' })
Check ($cArgs.Count -eq 0) 'psql is never given SQL with -c'
Check (@($script:Calls | Where-Object { $_.Stdin -match 'ALTER DATABASE "default" RENAME TO "default_old";' }).Count -eq 1) 'swap SQL quotes "default" and goes via stdin'
$liveDrop = @($script:Calls | Where-Object { $_.Argv -contains 'dropdb' -and $_.Argv[-1] -eq 'default' })
Check ($liveDrop.Count -eq 0) 'the live database is never dropped by name'
Check ((($script:Dbs | Sort-Object) -join ',') -eq 'default,postgres') 'end state: default (restored) + postgres; _old and _restore gone'

Write-Host 'Scenario 2: the swap transaction fails'
Reset-Stub $true
$err = ''
try { Invoke-Restore $backup -Yes 6>$null } catch { $err = $_.Exception.Message }
Check ($err -match 'NOT changed') 'restore reports that current data was not changed'
Check ($script:Dbs -contains 'default') 'live database still exists'
Check ($script:Dbs -contains 'default_restore') 'restored copy kept for inspection'

Set-Location -LiteralPath $pkg   # bangla-crm-common.ps1 moved into the temp folder
Remove-Item -LiteralPath $work -Recurse -Force
if ($failures -gt 0) { Write-Host "$failures check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All restore stub checks passed.'
