# Shared helpers for install-windows.ps1 and bangla-crm.ps1 (dot-sourced; not run directly).
# Written for Windows PowerShell 5.1. Keep this file ASCII-only: PowerShell 5.1 misreads
# non-ASCII characters in scripts saved without a byte-order mark.

$script:Root = $PSScriptRoot
$script:StoragePath = '/app/packages/twenty-server/.local-storage'
$script:ReleasesApi = 'https://api.github.com/repos/Rabbit-s-Hat/bangla-crm/releases/latest'
$script:ServerTries = 360   # x 5 s = 30 minutes (the first start creates the database)
$script:BackupDir = ''
Set-Location -LiteralPath $script:Root

function Say([string]$Message = '') { Write-Host $Message }
function Warn([string]$Message) { Write-Host ('WARNING: ' + $Message) -ForegroundColor Yellow }
function Fail([string]$Message) { throw $Message }

# ---------------------------------------------------------------------------------------------
# .env helpers (UTF-8 without BOM, LF line endings: what Docker Compose expects)

function Get-EnvPath { Join-Path $script:Root '.env' }

function Read-EnvLines([string]$Path = '') {
    if (-not $Path) { $Path = Get-EnvPath }
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return [System.IO.File]::ReadAllLines($Path)
}

function Write-EnvLines([string[]]$Lines) {
    $text = ($Lines -join "`n") + "`n"
    [System.IO.File]::WriteAllText((Get-EnvPath), $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-EnvValue([string]$Key, [string]$Default = '', [string]$Path = '') {
    foreach ($line in (Read-EnvLines $Path)) {
        if ($line.StartsWith($Key + '=')) {
            $value = $line.Substring($Key.Length + 1)
            if ($value) { return $value }
            break
        }
    }
    return $Default
}

function Set-EnvValue([string]$Key, [string]$Value) {
    $out = New-Object System.Collections.Generic.List[string]
    $done = $false
    foreach ($line in (Read-EnvLines)) {
        if ((-not $done) -and $line.StartsWith($Key + '=')) {
            $out.Add($Key + '=' + $Value)
            $done = $true
        } else {
            $out.Add($line)
        }
    }
    if (-not $done) { $out.Add($Key + '=' + $Value) }
    Write-EnvLines $out.ToArray()
}

function New-RandomBytes([int]$Count) {
    $bytes = New-Object byte[] $Count
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return , $bytes
}
function New-RandomBase64 { [Convert]::ToBase64String((New-RandomBytes 32)) }
function New-RandomHex { -join ((New-RandomBytes 24) | ForEach-Object { $_.ToString('x2') }) }

function Test-Version([string]$Version) {
    return ($Version -eq 'latest' -or $Version -match '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$')
}

# Only the current user, SYSTEM and Administrators may read secrets (.env, backups).
function Protect-Path([string]$Path) {
    try {
        $who = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        # (OI)(CI) = inherit to files/subfolders; only valid on folders.
        $inherit = ''
        if (Test-Path -LiteralPath $Path -PathType Container) { $inherit = '(OI)(CI)' }
        & icacls.exe $Path /inheritance:r /grant:r ($who + ':' + $inherit + 'F') ('*S-1-5-18:' + $inherit + 'F') ('*S-1-5-32-544:' + $inherit + 'F') *> $null
    } catch { }
}

# The address to open on THIS computer (network installs also work at localhost).
function Get-LocalUrl { 'http://localhost:' + (Get-EnvValue 'HTTP_PORT' '3000') }

# ---------------------------------------------------------------------------------------------
# Docker helpers. Native commands are never run with redirected stderr while
# $ErrorActionPreference is 'Stop' (PowerShell 5.1 would turn every stderr line into an error).

function Invoke-Docker([string[]]$ArgList, [switch]$AllowFail) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # Out-Host: show docker's output instead of returning it, so the function returns only the exit code.
        & docker @ArgList | Out-Host
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
    if (($code -ne 0) -and (-not $AllowFail)) {
        Fail ('Command failed: docker ' + ($ArgList -join ' '))
    }
    return $code
}

function Get-DockerOutput([string[]]$ArgList) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & docker @ArgList 2>$null
        if ($LASTEXITCODE -ne 0) { return '' }
        return (($out | Out-String).Trim())
    } finally {
        $ErrorActionPreference = $old
    }
}

function Test-DockerCommand([string[]]$ArgList) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & docker @ArgList *> $null
        return ($LASTEXITCODE -eq 0)
    } finally {
        $ErrorActionPreference = $old
    }
}

function Get-ContainerId([string]$Service, [switch]$All) {
    $a = @('compose', 'ps', '-q')
    if ($All) { $a += '-a' }
    $a += $Service
    $out = Get-DockerOutput $a
    if (-not $out) { return '' }
    return ($out -split "`r?`n")[0].Trim()
}

function Test-ServiceRunning([string]$Service) {
    return [bool](Get-DockerOutput @('compose', 'ps', '--status', 'running', '-q', $Service))
}

function Test-VolumeExists([string]$Name) { Test-DockerCommand @('volume', 'inspect', ('bangla-crm_' + $Name)) }

function Assert-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Fail 'Docker Desktop is not installed. Run Install-Bangla-CRM.cmd, or install it from https://www.docker.com/products/docker-desktop/'
    }
    if (-not (Test-DockerCommand @('compose', 'version'))) {
        Fail "Docker Compose v2 ('docker compose') is missing. Update Docker Desktop."
    }
    if (Test-DockerCommand @('info')) { return }

    $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (Test-Path -LiteralPath $desktop) {
        Say 'Starting Docker Desktop (this can take a minute or two)...'
        Start-Process -FilePath $desktop
        for ($i = 0; $i -lt 60; $i++) {
            Start-Sleep -Seconds 5
            if (Test-DockerCommand @('info')) { Say 'Docker is running.'; return }
        }
    }
    Fail 'Docker is not running. Open Docker Desktop, wait until it says "Engine running", then try again. (If Docker Desktop reports that virtualization is not enabled, turn on virtualization / SVM / VT-x in the BIOS.)'
}

function Wait-Healthy([string]$Service = 'server', [int]$Tries = 0) {
    if ($Tries -le 0) { $Tries = $script:ServerTries }
    $id = Get-ContainerId $Service
    if (-not $id) { Fail ("The $Service container is not running. See: docker compose logs $Service") }
    $format = '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}'
    for ($i = 0; $i -lt $Tries; $i++) {
        $status = Get-DockerOutput @('inspect', '--format', $format, $id)
        if ($status -eq 'healthy') { Write-Host ''; return }
        if (@('unhealthy', 'exited', 'dead') -contains $status) {
            Write-Host ''
            Fail ("The $Service container stopped or reported a problem. See: docker compose logs $Service")
        }
        Write-Host '.' -NoNewline
        Start-Sleep -Seconds 5
    }
    Write-Host ''
    Fail ("$Service is still not ready after $([int]($Tries * 5 / 60)) minutes. See: docker compose logs $Service")
}

# Start everything: database first, then the server (with a visible progress line), then the rest.
function Start-All {
    Say 'Starting Bangla CRM. The first start sets up the database and can take 5-15 minutes; later starts take about a minute.'
    Invoke-Docker @('compose', 'up', '-d', 'db', 'redis') | Out-Null
    Wait-Healthy 'db' 60
    Invoke-Docker @('compose', 'up', '-d', 'server') | Out-Null
    Wait-Healthy 'server'
    Invoke-Docker @('compose', 'up', '-d') | Out-Null
}

function Open-BanglaCrm {
    $url = Get-LocalUrl
    try { Start-Process $url } catch { }
    Say ('Bangla CRM: ' + $url)
}

# A port is unusable if something listens on it OR Windows reserved it (excluded port ranges).
function Test-PortInUse([int]$Port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $attempt = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if ($attempt.AsyncWaitHandle.WaitOne(700) -and $client.Connected) { return $true }
    } catch {
    } finally {
        $client.Close()
    }
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
    try {
        $listener.Start()
        return $false
    } catch {
        return $true
    } finally {
        try { $listener.Stop() } catch { }
    }
}

# ---------------------------------------------------------------------------------------------
# Backup / restore / update

function Invoke-Backup([int]$KeepDays = 0) {
    if (-not (Test-ServiceRunning 'db')) {
        Say 'Starting the database for the backup...'
        Invoke-Docker @('compose', 'up', '-d', 'db') | Out-Null
        Wait-Healthy 'db' 60
    }
    $user = Get-EnvValue 'PG_DATABASE_USER' 'postgres'
    $db = Get-EnvValue 'PG_DATABASE_NAME' 'default'

    $backups = Join-Path $script:Root 'backups'
    New-Item -ItemType Directory -Force -Path $backups | Out-Null
    Protect-Path $backups

    # Free space: 2x the database size + 1 GB is a safe margin for the dump and files.
    [long]$dbBytes = 0
    $sizeText = Get-DockerOutput @('compose', 'exec', '-T', 'db', 'psql', '-U', $user, '-d', $db, '-tAc', 'SELECT pg_database_size(current_database())')
    [void][long]::TryParse(($sizeText -replace '[^0-9]', ''), [ref]$dbBytes)
    $need = 2 * $dbBytes + 1GB
    $drive = New-Object System.IO.DriveInfo ([System.IO.Path]::GetPathRoot($backups))
    if ($drive.AvailableFreeSpace -lt $need) {
        Fail ('Not enough free disk space for a backup (need about ' + [int]($need / 1MB) + ' MB). Delete old backups or free some space.')
    }

    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $dir = Join-Path $backups $stamp
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    Say 'Saving the database...'
    Invoke-Docker @('compose', 'exec', '-T', 'db', 'pg_dump', '-U', $user, '-d', $db, '-Fc', '-f', '/tmp/bangla-crm-backup.dump') | Out-Null
    $dbId = Get-ContainerId 'db' -All
    Invoke-Docker @('cp', ($dbId + ':/tmp/bangla-crm-backup.dump'), (Join-Path $dir 'database.dump')) | Out-Null
    Invoke-Docker @('compose', 'exec', '-T', 'db', 'rm', '-f', '/tmp/bangla-crm-backup.dump') | Out-Null

    Say 'Saving uploaded files...'
    $serverId = Get-ContainerId 'server' -All
    if (-not $serverId) {
        Invoke-Docker @('compose', 'create', 'server') -AllowFail | Out-Null
        $serverId = Get-ContainerId 'server' -All
    }
    if (-not $serverId) { Fail ("Could not reach the uploaded files. The database part of the backup is in $dir.") }
    Invoke-Docker @('cp', ($serverId + ':' + $script:StoragePath), (Join-Path $dir 'files')) | Out-Null

    $image = Get-DockerOutput @('compose', 'images', 'server')
    [System.IO.File]::WriteAllText((Join-Path $dir 'version.txt'), ($image + "`n"))
    Copy-Item -LiteralPath (Get-EnvPath) -Destination (Join-Path $dir 'env.txt')
    $script:BackupDir = $dir
    Say ('Backup saved in: ' + $dir)
    Say 'It contains your encryption key. Keep it private, and copy it to another disk or cloud storage.'

    if ($KeepDays -gt 0) {
        $limit = (Get-Date).AddDays(-$KeepDays)
        Get-ChildItem -LiteralPath $backups -Directory |
            Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{6}$' -and $_.LastWriteTime -lt $limit } |
            Remove-Item -Recurse -Force -Confirm:$false
    }
}

function Select-Backup {
    $backups = Join-Path $script:Root 'backups'
    $list = @()
    if (Test-Path -LiteralPath $backups) {
        $list = @(Get-ChildItem -LiteralPath $backups -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'database.dump') } |
            Sort-Object Name -Descending)
    }
    if ($list.Count -eq 0) { Fail 'No backups found in the backups folder.' }
    Say 'Available backups (newest first):'
    for ($i = 0; $i -lt [Math]::Min($list.Count, 20); $i++) { Say ('  ' + ($i + 1) + '. ' + $list[$i].Name) }
    $answer = Read-Host 'Type the number of the backup to restore (or press Enter to cancel)'
    $n = 0
    if (-not [int]::TryParse($answer, [ref]$n) -or $n -lt 1 -or $n -gt [Math]::Min($list.Count, 20)) { Fail 'Cancelled. Nothing was changed.' }
    return $list[$n - 1].FullName
}

# Invoke-Restore DIR [-Yes]  (-Yes: no questions and no safety backup; used by the update rollback)
function Invoke-Restore([string]$BackupDir, [switch]$Yes) {
    if (-not $BackupDir) { $BackupDir = Select-Backup }
    $resolved = Resolve-Path -LiteralPath $BackupDir -ErrorAction SilentlyContinue
    if (-not $resolved) { Fail ("Folder not found: $BackupDir") }
    $dir = $resolved.ProviderPath.TrimEnd('\')
    $dump = Join-Path $dir 'database.dump'
    if (-not (Test-Path -LiteralPath $dump) -or (Get-Item -LiteralPath $dump).Length -eq 0) { Fail ("$dump not found or empty.") }

    if (-not $Yes) {
        Say ("This REPLACES everything in Bangla CRM with the backup in $dir.")
        Say '(A safety backup of the current data is made first.)'
        $answer = Read-Host 'Type RESTORE to continue'
        if ($answer -cne 'RESTORE') { Fail 'Cancelled. Nothing was changed.' }
        Say 'Making a safety backup of the current data first...'
        Invoke-Backup
        Say ('Safety backup: ' + $script:BackupDir)
    }

    $user = Get-EnvValue 'PG_DATABASE_USER' 'postgres'
    $db = Get-EnvValue 'PG_DATABASE_NAME' 'default'
    $tmp = $db + '_restore'
    Invoke-Docker @('compose', 'stop', 'server', 'worker') -AllowFail | Out-Null
    Invoke-Docker @('compose', 'up', '-d', 'db', 'redis') | Out-Null
    Wait-Healthy 'db' 60

    Say 'Checking and restoring the database (into a temporary database first)...'
    $dbId = Get-ContainerId 'db' -All
    Invoke-Docker @('cp', $dump, ($dbId + ':/tmp/bangla-crm-restore.dump')) | Out-Null
    if (-not (Test-DockerCommand @('compose', 'exec', '-T', 'db', 'pg_restore', '-l', '/tmp/bangla-crm-restore.dump'))) {
        Invoke-Docker @('compose', 'up', '-d') -AllowFail | Out-Null
        Fail 'The backup file is damaged (pg_restore cannot read it). Nothing was changed.'
    }
    Invoke-Docker @('compose', 'exec', '-T', 'db', 'dropdb', '-U', $user, '--if-exists', '--force', $tmp) | Out-Null
    Invoke-Docker @('compose', 'exec', '-T', 'db', 'createdb', '-U', $user, $tmp) | Out-Null
    $code = Invoke-Docker @('compose', 'exec', '-T', 'db', 'pg_restore', '-U', $user, '-d', $tmp, '--no-owner', '--single-transaction', '/tmp/bangla-crm-restore.dump') -AllowFail
    if ($code -ne 0) {
        Invoke-Docker @('compose', 'exec', '-T', 'db', 'dropdb', '-U', $user, '--if-exists', '--force', $tmp) -AllowFail | Out-Null
        Invoke-Docker @('compose', 'exec', '-T', 'db', 'rm', '-f', '/tmp/bangla-crm-restore.dump') -AllowFail | Out-Null
        Invoke-Docker @('compose', 'up', '-d') -AllowFail | Out-Null
        Fail 'The database could not be restored (errors above). Your current data was NOT changed.'
    }
    Invoke-Docker @('compose', 'exec', '-T', 'db', 'dropdb', '-U', $user, '--if-exists', '--force', $db) | Out-Null
    Invoke-Docker @('compose', 'exec', '-T', 'db', 'psql', '-U', $user, '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c',
        ('ALTER DATABASE "' + $tmp + '" RENAME TO "' + $db + '"')) | Out-Null
    Invoke-Docker @('compose', 'exec', '-T', 'db', 'rm', '-f', '/tmp/bangla-crm-restore.dump') | Out-Null

    # The restored data is encrypted with the key from the backup's settings.
    $envBackup = Join-Path $dir 'env.txt'
    if (Test-Path -LiteralPath $envBackup) {
        $backupKey = Get-EnvValue 'ENCRYPTION_KEY' '' $envBackup
        $backupFallback = Get-EnvValue 'FALLBACK_ENCRYPTION_KEY' '' $envBackup
        if ($backupKey -and ($backupKey -ne (Get-EnvValue 'ENCRYPTION_KEY'))) {
            $saved = Join-Path $script:Root ('.env.before-restore-' + (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
            Copy-Item -LiteralPath (Get-EnvPath) -Destination $saved
            Protect-Path $saved
            Set-EnvValue 'ENCRYPTION_KEY' $backupKey
            Set-EnvValue 'FALLBACK_ENCRYPTION_KEY' $backupFallback
            Say ('Switched to the encryption key from the backup (previous settings saved in ' + (Split-Path $saved -Leaf) + ').')
        }
    } else {
        Warn 'env.txt is missing from this backup: if it came from another installation, saved passwords and connected accounts will not work.'
    }

    $files = Join-Path $dir 'files'
    if (Test-Path -LiteralPath $files) {
        Say 'Restoring uploaded files...'
        $p = $script:StoragePath
        $shellCommand = "rm -rf $p/* && cp -a /restore/. $p/ && chown -R 1000:1000 $p"
        $code = Invoke-Docker @('compose', 'run', '--rm', '--no-deps', '--user', 'root', '-v', ($files + ':/restore:ro'),
            '--entrypoint', 'sh', 'server', '-c', $shellCommand) -AllowFail
        if ($code -ne 0) { Warn 'Uploaded files could not be restored (the database was restored).' }
    }

    Start-All
    Say 'Restore finished.'
}

function Get-LatestRelease {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $release = Invoke-RestMethod -Uri $script:ReleasesApi -UseBasicParsing -TimeoutSec 20
        $tag = [string]$release.tag_name
        if ($tag.StartsWith('bangla-v')) { return $tag.Substring(8) }
    } catch { }
    return ''
}

function Invoke-Update([string]$Version = '') {
    $oldVersion = Get-EnvValue 'TAG' 'latest'
    if (-not $Version) {
        if ($oldVersion -eq 'latest') {
            $Version = 'latest'
        } else {
            Say 'Checking for a new version...'
            $Version = Get-LatestRelease
            if (-not $Version) { Fail 'Could not check for new versions (no internet?). You can name one: Update-Bangla-CRM.cmd -Version 0.2.0' }
            if ($Version -eq $oldVersion) { Say ("Bangla CRM is up to date (version $oldVersion)."); return }
        }
    }
    if (-not (Test-Version $Version)) { Fail 'Version must look like 0.2.0.' }
    Say ("Updating Bangla CRM: $oldVersion -> $Version")

    Say 'Making a backup before updating...'
    Invoke-Backup
    $preBackup = $script:BackupDir

    Set-EnvValue 'TAG' $Version
    $code = Invoke-Docker @('compose', 'pull') -AllowFail
    if ($code -ne 0) {
        Set-EnvValue 'TAG' $oldVersion
        Fail ("Download failed. Nothing was changed; Bangla CRM keeps running version $oldVersion.")
    }
    try {
        Start-All
        Say ("Bangla CRM is now running version $Version. (Backup from before the update: $preBackup)")
        return
    } catch {
        Warn ("The new version did not start: " + $_.Exception.Message)
    }
    Warn ("Going back to version $oldVersion and the backup made just before the update...")
    Set-EnvValue 'TAG' $oldVersion
    Invoke-Restore $preBackup -Yes
    Fail ("The update to $Version failed, and Bangla CRM was put back to $oldVersion. Please contact support with the output of: docker compose logs server")
}
