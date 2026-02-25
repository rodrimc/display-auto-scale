<#
.SYNOPSIS
    Automatically adjusts laptop display scaling based on external monitor presence.
.DESCRIPTION
    When external monitors are connected, sets the laptop's internal display to a
    higher scale (default 125%). When no external monitors are present, reverts to
    a lower scale (default 100%).

    Uses the DisplayConfig API (same as Windows Settings) for immediate, reliable
    DPI changes without Explorer restart.

    Use -Watch to continuously monitor for display changes.
.PARAMETER Watch
    Continuously monitor for display changes and adjust scaling automatically.
.PARAMETER ScaleWithExternal
    Scale percentage when external monitors are connected (default: 125).
.PARAMETER ScaleWithoutExternal
    Scale percentage when no external monitors are connected (default: 100).
.EXAMPLE
    .\display-auto-scale.ps1
    # One-shot: detect monitors and adjust scaling.
.EXAMPLE
    .\display-auto-scale.ps1 -Watch
    # Continuously watch for monitor changes.
.EXAMPLE
    .\display-auto-scale.ps1 -Watch -ScaleWithExternal 150 -ScaleWithoutExternal 125
    # Custom scale values.
#>
param(
    [switch]$Watch,
    [int]$ScaleWithExternal = 125,
    [int]$ScaleWithoutExternal = 100
)

$ScaleSteps = @(100, 125, 150, 175, 200, 225, 250, 300, 350)

# --- P/Invoke for DisplayConfig DPI APIs ---
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class DisplayScale {

    [StructLayout(LayoutKind.Sequential)]
    public struct LUID {
        public uint LowPart;
        public int  HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_SOURCE_INFO {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_RATIONAL {
        public uint Numerator;
        public uint Denominator;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_TARGET_INFO {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint outputTechnology;
        public uint rotation;
        public uint scaling;
        public DISPLAYCONFIG_RATIONAL refreshRate;
        public uint scanLineOrdering;
        public int  targetAvailable;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_INFO {
        public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo;
        public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo;
        public uint flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_MODE_INFO {
        public uint infoType;
        public uint id;
        public LUID adapterId;
        public ulong d0; public ulong d1; public ulong d2;
        public ulong d3; public ulong d4; public ulong d5;
    }

    [DllImport("user32.dll")]
    public static extern int GetDisplayConfigBufferSizes(
        uint flags, out uint numPaths, out uint numModes);

    [DllImport("user32.dll")]
    public static extern int QueryDisplayConfig(
        uint flags,
        ref uint numPaths,
        [Out] DISPLAYCONFIG_PATH_INFO[] pathArray,
        ref uint numModes,
        [Out] DISPLAYCONFIG_MODE_INFO[] modeArray,
        IntPtr currentTopologyId);

    [DllImport("user32.dll")]
    static extern int DisplayConfigGetDeviceInfo(IntPtr requestPacket);

    [DllImport("user32.dll")]
    static extern int DisplayConfigSetDeviceInfo(IntPtr setPacket);

    public const uint QDC_ONLY_ACTIVE_PATHS = 2;
    public const uint OUTPUT_TECHNOLOGY_INTERNAL = 0x80000000;

    // Header layout: type(4) + size(4) + LUID(8) + id(4) = 20 bytes
    // GET buffer:    header(20) + min(4) + cur(4) + max(4) = 32 bytes
    // SET buffer:    header(20) + scaleRel(4) = 24 bytes

    public static DISPLAYCONFIG_PATH_INFO[] GetActivePaths() {
        uint numPaths, numModes;
        int err = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out numPaths, out numModes);
        if (err != 0) return null;

        var paths = new DISPLAYCONFIG_PATH_INFO[numPaths];
        var modes = new DISPLAYCONFIG_MODE_INFO[numModes];
        err = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref numPaths, paths, ref numModes, modes, IntPtr.Zero);
        if (err != 0) return null;

        if (numPaths < paths.Length) Array.Resize(ref paths, (int)numPaths);
        return paths;
    }

    public static int GetDpiInfo(LUID adapterId, uint sourceId,
        out int minRel, out int curRel, out int maxRel) {
        minRel = 0; curRel = 0; maxRel = 0;
        const int bufSize = 32;
        IntPtr buf = Marshal.AllocHGlobal(bufSize);
        try {
            for (int i = 0; i < bufSize; i++) Marshal.WriteByte(buf, i, 0);
            Marshal.WriteInt32(buf, 0, -3);                       // type = GET_DPI_SCALE
            Marshal.WriteInt32(buf, 4, bufSize);                  // size
            Marshal.WriteInt32(buf, 8, (int)adapterId.LowPart);  // LUID low
            Marshal.WriteInt32(buf, 12, adapterId.HighPart);      // LUID high
            Marshal.WriteInt32(buf, 16, (int)sourceId);           // id

            int err = DisplayConfigGetDeviceInfo(buf);
            if (err == 0) {
                minRel = Marshal.ReadInt32(buf, 20);
                curRel = Marshal.ReadInt32(buf, 24);
                maxRel = Marshal.ReadInt32(buf, 28);
            }
            return err;
        } finally {
            Marshal.FreeHGlobal(buf);
        }
    }

    public static int SetDpiScale(LUID adapterId, uint sourceId, int scaleRel) {
        const int bufSize = 24;
        IntPtr buf = Marshal.AllocHGlobal(bufSize);
        try {
            for (int i = 0; i < bufSize; i++) Marshal.WriteByte(buf, i, 0);
            Marshal.WriteInt32(buf, 0, -4);                       // type = SET_DPI_SCALE
            Marshal.WriteInt32(buf, 4, bufSize);                  // size
            Marshal.WriteInt32(buf, 8, (int)adapterId.LowPart);  // LUID low
            Marshal.WriteInt32(buf, 12, adapterId.HighPart);      // LUID high
            Marshal.WriteInt32(buf, 16, (int)sourceId);           // id
            Marshal.WriteInt32(buf, 20, scaleRel);                // scaleRel

            return DisplayConfigSetDeviceInfo(buf);
        } finally {
            Marshal.FreeHGlobal(buf);
        }
    }
}
'@ -ErrorAction Stop

function Write-Log([string]$Message) {
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] $Message"
}

function Get-MonitorCount {
    return @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue).Count
}

function Set-InternalDisplayScale {
    param([int]$ScalePercent)

    $paths = [DisplayScale]::GetActivePaths()
    if (-not $paths) {
        Write-Log "WARNING: Failed to query active display paths."
        return $false
    }

    # Find the internal display path (outputTechnology = 0x80000000 = 2147483648)
    $internalPath = $null
    foreach ($p in $paths) {
        if ($p.targetInfo.outputTechnology -eq [uint32]2147483648) {
            $internalPath = $p
            break
        }
    }

    if (-not $internalPath) {
        Write-Log "WARNING: No internal display found in active paths."
        return $false
    }

    $adapterId = $internalPath.sourceInfo.adapterId
    $sourceId = $internalPath.sourceInfo.id

    # Read current DPI state
    [int]$minRel = 0; [int]$curRel = 0; [int]$maxRel = 0
    $err = [DisplayScale]::GetDpiInfo($adapterId, $sourceId, [ref]$minRel, [ref]$curRel, [ref]$maxRel)
    if ($err -ne 0) {
        Write-Log "WARNING: DisplayConfigGetDeviceInfo failed with error $err."
        return $false
    }

    # The recommended scale is at step 0. Calculate which step we need.
    # curRel=0 means recommended. We need to find the absolute recommended index first.
    $recommendedIdx = -$minRel  # minRel is negative, e.g. -1 means 100% is one step below recommended
    $recommendedPercent = if ($recommendedIdx -ge 0 -and $recommendedIdx -lt $ScaleSteps.Count) { $ScaleSteps[$recommendedIdx] } else { 100 }

    $targetIdx = [Array]::IndexOf($ScaleSteps, $ScalePercent)
    if ($targetIdx -lt 0) {
        Write-Log "WARNING: Unsupported scale $ScalePercent%. Supported: $($ScaleSteps -join ', ')"
        return $false
    }

    $targetRel = $targetIdx - $recommendedIdx

    # Clamp to display's supported range
    if ($targetRel -lt $minRel) { $targetRel = $minRel }
    if ($targetRel -gt $maxRel) { $targetRel = $maxRel }

    $currentPercent = if (($recommendedIdx + $curRel) -ge 0 -and ($recommendedIdx + $curRel) -lt $ScaleSteps.Count) {
        $ScaleSteps[$recommendedIdx + $curRel]
    } else { "unknown" }

    Write-Log "Internal display: recommended=$recommendedPercent%, current=$currentPercent% (step=$curRel), range=[$minRel..$maxRel]"

    if ($curRel -eq $targetRel) {
        Write-Log "Already at $ScalePercent% (step=$targetRel). No change needed."
        return $false
    }

    Write-Log "Setting internal display to $ScalePercent% (step=$targetRel)..."
    $err = [DisplayScale]::SetDpiScale($adapterId, $sourceId, $targetRel)
    if ($err -ne 0) {
        Write-Log "ERROR: DisplayConfigSetDeviceInfo failed with error $err."
        return $false
    }

    Write-Log "Internal display set to $ScalePercent%."
    return $true
}

function Update-DisplayScale {
    $monitorCount = Get-MonitorCount
    $hasExternal = $monitorCount -gt 1

    if ($hasExternal) {
        Write-Log "External monitor(s) detected ($monitorCount total). Target: $ScaleWithExternal%"
        Set-InternalDisplayScale -ScalePercent $ScaleWithExternal
    } else {
        Write-Log "No external monitors (laptop only). Target: $ScaleWithoutExternal%"
        Set-InternalDisplayScale -ScalePercent $ScaleWithoutExternal
    }
}

# --- Main ---
Write-Log "display-auto-scale started"
Write-Log "  Internal display scale (no external): $ScaleWithoutExternal%"
Write-Log "  Internal display scale (with external): $ScaleWithExternal%"
Write-Log ""

if ($Watch) {
    Write-Log "Watching for display changes via DisplaySettingsChanged event (Ctrl+C to stop)..."
    Write-Log ""

    # Initial check
    $script:lastMonitorCount = Get-MonitorCount
    Update-DisplayScale

    # Use .NET DisplaySettingsChanged event (fires on monitor connect/disconnect)
    Add-Type -AssemblyName System.Windows.Forms

    [Microsoft.Win32.SystemEvents]::add_DisplaySettingsChanged({
        # Let the display configuration settle before querying
        Start-Sleep -Seconds 2
        try {
            $currentCount = Get-MonitorCount
            if ($currentCount -ne $script:lastMonitorCount) {
                Write-Log "Monitor count changed: $($script:lastMonitorCount) -> $currentCount"
                Update-DisplayScale
                $script:lastMonitorCount = $currentCount
            }
        } catch {
            Write-Log "WARNING: Monitor detection failed (transient): $_"
        }
    })

    # Run a message loop (required for SystemEvents to fire) — no window needed
    [System.Windows.Forms.Application]::Run(
        [System.Windows.Forms.ApplicationContext]::new()
    )
} else {
    Update-DisplayScale
}
