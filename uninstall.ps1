<#
.SYNOPSIS
    Removes the DockScale scheduled task.
#>

$taskName = "DockScale"

$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing) {
    # Stop if running
    if ($existing.State -eq 'Running') {
        Stop-ScheduledTask -TaskName $taskName
        Write-Host "Stopped running task."
    }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Scheduled task '$taskName' removed." -ForegroundColor Green
} else {
    Write-Host "Scheduled task '$taskName' not found. Nothing to remove."
}

# Remove installed script
$installDir = Join-Path $env:LOCALAPPDATA "DockScale"
if (Test-Path $installDir) {
    Remove-Item -Path $installDir -Recurse -Force
    Write-Host "Removed installed files from: $installDir"
}
