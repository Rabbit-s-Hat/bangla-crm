# Everyday commands for Bangla CRM on Windows. Double-click the .cmd files in this folder, or run
# from a Command Prompt here (the .cmd files pass options through):
#   Start-Bangla-CRM.cmd / Stop-Bangla-CRM.cmd     start (and open the browser) / stop (data is kept)
#   Backup-Bangla-CRM.cmd [-KeepDays N]           save database + uploaded files + settings into backups\<date-time>\
#   Update-Bangla-CRM.cmd [-Version X]            back up, then install the newest release (or version X)
#   Restore-Bangla-CRM.cmd [backups\<date-time>]  replace ALL current data with a backup (asks which one)
#   Logs-Bangla-CRM.cmd                           show the logs (Ctrl+C to quit)
# Same as: powershell -ExecutionPolicy Bypass -File bangla-crm.ps1 start|stop|restart|status|logs|open|backup|update|restore
# ASCII-only on purpose (Windows PowerShell 5.1).
param(
    [Parameter(Position = 0)]
    [string]$Command = 'help',
    [Parameter(Position = 1)]
    [string]$Path = '',
    [string]$Version = '',
    [int]$KeepDays = 0
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bangla-crm-common.ps1')

function Main {
    $known = @('start', 'stop', 'restart', 'status', 'logs', 'open', 'backup', 'update', 'restore', 'help')
    if ($known -notcontains $Command) { Fail ("Unknown command: $Command  (try: bangla-crm.ps1 help)") }
    if ($Command -eq 'help') {
        Get-Content -LiteralPath $PSCommandPath -TotalCount 9 | ForEach-Object { Say ($_ -replace '^# ?', '') }
        return
    }
    if ($Command -eq 'open') { Open-BanglaCrm; return }
    if (-not (Test-Path -LiteralPath (Get-EnvPath))) { Fail 'No .env file in this folder. Run Install-Bangla-CRM.cmd first.' }
    Assert-Docker

    switch ($Command) {
        'start' { Start-All; Open-BanglaCrm }
        'stop' {
            Invoke-Docker @('compose', 'stop') | Out-Null
            Say 'Bangla CRM is stopped. Your data is kept.'
        }
        'restart' {
            Invoke-Docker @('compose', 'stop') | Out-Null
            Start-All
            Open-BanglaCrm
        }
        'status' { Invoke-Docker @('compose', 'ps') | Out-Null }
        'logs' { Invoke-Docker @('compose', 'logs', '-f', '--tail', '200', 'server', 'worker') -AllowFail | Out-Null }
        'backup' { Invoke-Backup $KeepDays }
        'update' { Invoke-Update $Version }
        'restore' { Invoke-Restore $Path }
    }
}

try {
    Main
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
