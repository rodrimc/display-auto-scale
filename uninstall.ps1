<#
.SYNOPSIS
    Removes the DisplayAutoScale scheduled task.
#>

$taskName = "DisplayAutoScale"

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
