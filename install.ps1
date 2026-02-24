<#
.SYNOPSIS
    Installs a scheduled task to run display-auto-scale at logon.
.DESCRIPTION
    Creates a Windows Task Scheduler task that launches the watcher script
    when the current user logs on. The task runs hidden in the background.
#>

$ErrorActionPreference = 'Stop'

$taskName = "DisplayAutoScale"
$scriptPath = Join-Path $PSScriptRoot "display-auto-scale.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Error "display-auto-scale.ps1 not found at: $scriptPath"
    exit 1
}

# Remove existing task if present
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Removing existing '$taskName' task..."
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Build the task
$action = New-ScheduledTaskAction `
    -Execute "conhost.exe" `
    -Argument "--headless powershell.exe -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -Watch"

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "Automatically adjusts laptop display scaling when external monitors are connected/disconnected." `
    | Out-Null

# Set the task to run hidden (no window flash)
$task = Get-ScheduledTask -TaskName $taskName
$task.Settings.Hidden = $true
$task | Set-ScheduledTask | Out-Null

Write-Host ""
Write-Host "Scheduled task '$taskName' installed successfully." -ForegroundColor Green
Write-Host ""

Start-ScheduledTask -TaskName $taskName
Write-Host "Watcher started. It will also start automatically at logon."
Write-Host ""
Write-Host "To customize scale values, edit the -Argument in Task Scheduler or"
Write-Host "re-run install.ps1 after modifying the default parameters."
