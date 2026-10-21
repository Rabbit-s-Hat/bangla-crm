# Stub test for Invoke-Update on Windows PowerShell 5.1 (no Docker needed).
# A fake `docker` function simulates local image tags, so the test can prove that update downloads BEFORE
# it backs up and switches, refuses downgrades, never offers an older release, and on a failed start
# points the "latest" tag back at the previous image before restoring the backup.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File tests\update-stub.ps1
# ASCII-only on purpose (Windows PowerShell 5.1).

$ErrorActionPreference = 'Stop'
$pkg = Split-Path -Parent $PSScriptRoot
$work = Join-Path ([IO.Path]::GetTempPath()) ('bangla-crm-update-stub-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
Copy-Item -LiteralPath (Join-Path $pkg 'bangla-crm-common.ps1') -Destination $work
. (Join-Path $work 'bangla-crm-common.ps1')

$script:Events = New-Object System.Collections.ArrayList
$script:Images = @{}
$script:PullId = ''
$script:PullFails = $false
$script:StartFails = $false
$script:Latest = ''

function docker {
    $argv = @($args | ForEach-Object { [string]$_ })
    $global:LASTEXITCODE = 0
    if ($argv[0] -eq 'image' -and $argv[1] -eq 'inspect') {
        $tag = $argv[-1].Split(':')[-1]
        if ($script:Images.ContainsKey($tag)) { return $script:Images[$tag] }
        $global:LASTEXITCODE = 1; return
    }
    if ($argv[0] -eq 'compose' -and $argv[1] -eq 'pull') {
        $tag = if ($env:TAG) { $env:TAG } else { Get-EnvValue 'TAG' 'latest' }
        [void]$script:Events.Add('pull:' + $tag + ' env=' + (Get-EnvValue 'TAG' 'latest'))
        if ($script:PullFails) { $global:LASTEXITCODE = 1; return }
        $script:Images[$tag] = $script:PullId
        return
    }
    if ($argv[0] -eq 'tag') { $script:Images[$argv[2].Split(':')[-1]] = $argv[1]; [void]$script:Events.Add('tag:' + $argv[1] + '->' + $argv[2]); return }
    if ($argv[0] -eq 'image' -and $argv[1] -eq 'rm') { [void]$script:Events.Add('rm:' + $argv[2]); return }
}
function Invoke-Backup { [void]$script:Events.Add('backup'); $script:BackupDir = 'backups\stub' }
function Start-All { [void]$script:Events.Add('start:' + (Get-EnvValue 'TAG' 'latest')); if ($script:StartFails) { throw 'stub start failure' } }
function Invoke-Restore([string]$BackupDir, [switch]$Yes) { [void]$script:Events.Add('restore:' + (Get-EnvValue 'TAG' 'latest')) }
function Get-LatestRelease { $script:Latest }

$failures = 0
function Check([bool]$Ok, [string]$What) {
    if ($Ok) { Write-Host ('  ok   ' + $What) } else { Write-Host ('  FAIL ' + $What) -ForegroundColor Red; $script:failures++ }
}
function Reset-Stub([string]$Tag, [hashtable]$Images, [string]$PullId) {
    [IO.File]::WriteAllText((Join-Path $work '.env'), "TAG=$Tag`n")
    $script:Events.Clear(); $script:Images = $Images; $script:PullId = $PullId
    $script:PullFails = $false; $script:StartFails = $false; $script:Latest = ''
}
function Run-Update([string]$Version = '', [switch]$AllowDowngrade) {
    try { Invoke-Update $Version -AllowDowngrade:$AllowDowngrade 6>$null; return '' } catch { return $_.Exception.Message }
}
function Events { $script:Events -join ' | ' }

Write-Host 'A: 0.1.0 -> newest release 0.2.0'
Reset-Stub '0.1.0' @{ '0.1.0' = 'sha:old' } 'sha:new'; $script:Latest = '0.2.0'
$err = Run-Update
Check ($err -eq '') 'update succeeds'
Check ((Events) -eq 'pull:0.2.0 env=0.1.0 | backup | start:0.2.0 | rm:ghcr.io/rabbit-s-hat/bangla-crm:0.1.0') ('order pull -> backup -> switch -> prune: ' + (Events))
Check ((Get-EnvValue 'TAG') -eq '0.2.0') '.env TAG = 0.2.0'
Check (-not $env:TAG) 'temporary TAG environment override removed'

Write-Host 'B: the newest release is older than the installed version'
Reset-Stub '0.3.0-rc.1' @{ '0.3.0-rc.1' = 'sha:old' } 'sha:new'; $script:Latest = '0.2.0'
$err = Run-Update
Check (($err -eq '') -and ($script:Events.Count -eq 0)) ('nothing downloaded or changed: ' + (Events))

Write-Host 'C: explicit downgrade 0.2.0 -> 0.1.0'
Reset-Stub '0.2.0' @{ '0.2.0' = 'sha:old' } 'sha:new'
$err = Run-Update '0.1.0'
Check (($err -match 'AllowDowngrade') -and ($script:Events.Count -eq 0)) 'refused without -AllowDowngrade, nothing changed'
$err = Run-Update '0.1.0' -AllowDowngrade
Check (($err -eq '') -and ((Get-EnvValue 'TAG') -eq '0.1.0')) 'allowed with -AllowDowngrade'

Write-Host 'D: TAG=latest, the new image does not start'
Reset-Stub 'latest' @{ 'latest' = 'sha:old' } 'sha:new'
$script:StartFails = $true
$err = Run-Update
Check ($err -match 'put back') 'update reports the rollback'
Check ((Events) -eq 'pull:latest env=latest | backup | start:latest | tag:sha:old->ghcr.io/rabbit-s-hat/bangla-crm:latest | restore:latest') ('latest re-pointed at the old image before restore: ' + (Events))
Check ($script:Images['latest'] -eq 'sha:old') 'local latest tag = previous image'

Write-Host 'E: TAG=latest and nothing new was published'
Reset-Stub 'latest' @{ 'latest' = 'sha:same' } 'sha:same'
$err = Run-Update
Check (($err -eq '') -and ((Events) -eq 'pull:latest env=latest')) ('no backup, no restart: ' + (Events))

Write-Host 'F: download fails'
Reset-Stub '0.1.0' @{ '0.1.0' = 'sha:old' } 'sha:new'; $script:PullFails = $true
$err = Run-Update '0.2.0'
Check (($err -match 'Nothing was changed') -and ((Events) -eq 'pull:0.2.0 env=0.1.0') -and ((Get-EnvValue 'TAG') -eq '0.1.0')) 'no backup, TAG unchanged'

Set-Location -LiteralPath $pkg   # bangla-crm-common.ps1 moved into the temp folder
Remove-Item -LiteralPath $work -Recurse -Force
if ($failures -gt 0) { Write-Host "$failures check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All update stub checks passed.'
