# Bangla CRM installer for Windows 10/11 (needs Docker Desktop).
# Easiest: double-click Install-Bangla-CRM.cmd. With options, from a Command Prompt in this folder:
#   Install-Bangla-CRM.cmd                  this computer only, at http://localhost:3000
#   Install-Bangla-CRM.cmd -Port 3100       use another port
#   Install-Bangla-CRM.cmd -Lan             also reachable from other computers on your network
#   Install-Bangla-CRM.cmd -Version 0.1.0   install a specific release (default: the one in .env)
# Running it again is safe: secrets in an existing .env are never replaced.
# ASCII-only on purpose (Windows PowerShell 5.1).
param(
    [string]$Version = '',
    [int]$Port = 0,
    [switch]$Lan
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bangla-crm-common.ps1')

# The IPv4 address of the network card that carries the default route (not VPN/hotspot/virtual adapters).
function Get-LanAddress {
    try {
        $routes = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
            Sort-Object { $_.RouteMetric + (Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).InterfaceMetric }
        foreach ($route in $routes) {
            $ip = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -notlike '169.254.*' } |
                Select-Object -First 1 -ExpandProperty IPAddress
            if ($ip) { return [string]$ip }
        }
    } catch { }
    return ''
}

function Install-DockerDesktop {
    Say 'Docker Desktop is required and is not installed on this computer.'
    Say 'Note: Docker Desktop is free for personal use, education and small businesses'
    Say '(fewer than 250 employees AND less than USD 10 million revenue); larger companies need a paid Docker subscription.'
    Say 'It also needs hardware virtualization enabled in the BIOS (it uses WSL 2).'
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $answer = Read-Host 'Install Docker Desktop now with winget? [Y/n]'
        if ($answer -notmatch '^[Nn]') {
            $old = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & winget install -e --id Docker.DockerDesktop --source winget --accept-source-agreements
            $code = $LASTEXITCODE
            $ErrorActionPreference = $old
            # -1978335189 (0x8A15002B) = already installed / no newer version
            if ($code -ne 0 -and $code -ne -1978335189) {
                Fail ("winget could not install Docker Desktop (code $code). Install it from https://www.docker.com/products/docker-desktop/ , restart Windows, then run this installer again.")
            }
            Say ''
            Say 'Docker Desktop is installed. Next:'
            Say '  1. Restart Windows (Docker Desktop needs this the first time).'
            Say '  2. Open Docker Desktop once, accept its terms and wait until it says "Engine running".'
            Say '  3. Double-click Install-Bangla-CRM.cmd again.'
            exit 0
        }
    }
    Fail 'Install Docker Desktop from https://www.docker.com/products/docker-desktop/ , restart Windows, then run this installer again.'
}

function Main {
    Say '== Bangla CRM installer =='
    if ($Version -and -not (Test-Version $Version)) { Fail '-Version must look like 0.1.0.' }
    if ($Port -ne 0 -and ($Port -lt 1 -or $Port -gt 65535)) { Fail '-Port must be a number from 1 to 65535.' }

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Install-DockerDesktop }
    Assert-Docker

    # .env: create once, never regenerate secrets
    $envPath = Get-EnvPath
    $newEnv = $false
    if (Test-Path -LiteralPath $envPath) {
        Say 'Keeping the existing .env (its secrets are never replaced).'
    } else {
        $example = Join-Path $script:Root '.env.example'
        if (-not (Test-Path -LiteralPath $example)) { Fail '.env.example is missing. Download the complete Bangla CRM package again.' }
        if (Test-VolumeExists 'db-data') {
            Fail ("Bangla CRM data already exists on this computer (from another Bangla CRM folder).`n" +
                "  Copy the .env file (and the backups folder) from your previous Bangla CRM folder into this folder,`n" +
                "  then run the installer again. You can also use env.txt from a backup, renamed to .env.`n" +
                "  To update, you do not need a new folder: double-click Update-Bangla-CRM.cmd in your existing folder.")
        }
        Write-EnvLines ([System.IO.File]::ReadAllLines($example))
        $newEnv = $true
    }
    Protect-Path $envPath
    if (-not (Get-EnvValue 'PG_DATABASE_PASSWORD')) { Set-EnvValue 'PG_DATABASE_PASSWORD' (New-RandomHex) }
    if (-not (Get-EnvValue 'ENCRYPTION_KEY')) { Set-EnvValue 'ENCRYPTION_KEY' (New-RandomBase64) }
    if ($Version) { Set-EnvValue 'TAG' $Version }

    if ($newEnv -or $Port -ne 0 -or $Lan) {
        if ($Port -eq 0) { $Port = [int](Get-EnvValue 'HTTP_PORT' '3000') }
        Set-EnvValue 'HTTP_PORT' ([string]$Port)
        if ($Lan) {
            Set-EnvValue 'BIND_ADDRESS' '0.0.0.0'
            $ip = Get-LanAddress
            if ($ip) {
                Set-EnvValue 'SERVER_URL' ("http://${ip}:$Port")
                Say ("Other computers can open: http://${ip}:$Port")
                Say '(Ask whoever manages your router to reserve this IP address for this computer, so it does not change.)'
            } else {
                Warn 'Could not find this computer''s network address; links in emails will use localhost.'
                Set-EnvValue 'SERVER_URL' ("http://localhost:$Port")
            }
            Say 'If other computers cannot connect, allow Docker Desktop through Windows Defender Firewall for Private networks.'
        } else {
            Set-EnvValue 'BIND_ADDRESS' '127.0.0.1'
            Set-EnvValue 'SERVER_URL' ("http://localhost:$Port")
        }
    }

    $httpPort = [int](Get-EnvValue 'HTTP_PORT' '3000')
    if ((-not (Test-ServiceRunning 'server')) -and (Test-PortInUse $httpPort)) {
        Fail "Port $httpPort is in use or reserved by Windows. From a Command Prompt in this folder run:  Install-Bangla-CRM.cmd -Port 3100"
    }

    Say ('Downloading Bangla CRM ' + (Get-EnvValue 'TAG' 'latest') + '. The first download is about 1 GB and can take a while...')
    $code = Invoke-Docker @('compose', 'pull') -AllowFail
    if ($code -ne 0) {
        Fail ("Download failed. Check the internet connection. If the message says 'denied' or 'not found', version '" + (Get-EnvValue 'TAG' 'latest') + "' is not published.")
    }
    Start-All

    # Desktop shortcut to the app (always via localhost on this computer)
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        if ($desktop) {
            [System.IO.File]::WriteAllText((Join-Path $desktop 'Bangla CRM.url'), ("[InternetShortcut]`r`nURL=" + (Get-LocalUrl) + "`r`n"), [System.Text.Encoding]::ASCII)
        }
    } catch { }

    Open-BanglaCrm
    Say ''
    Say 'Next steps:'
    Say '  1. Sign up in the browser window. The FIRST account becomes the administrator.'
    Say '  2. Use the Start / Stop / Backup / Update / Restore .cmd files in this folder.'
    Say '  3. Back up regularly and keep the .env file safe - it holds your encryption key.'
}

try {
    Main
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
