# display-auto-scale

Automatically adjusts your laptop's display scaling when external monitors are connected or disconnected. No polling, no Explorer restart — just instant DPI changes using the same API as the Windows Settings app.

![Windows](https://img.shields.io/badge/Windows-10%2F11-blue?logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)
![License](https://img.shields.io/badge/License-MIT-green)

## Why?

If you use a laptop with external monitors, you probably want different display scaling for each setup — higher scaling when docked (to match the external monitors' density) and lower when undocked. Windows doesn't do this automatically, so you end up manually adjusting the scale every time you plug or unplug.

This tool does it for you.

- **External monitors connected** → laptop display scales to **125%** (configurable)
- **No external monitors** → laptop display scales to **100%** (configurable)

## Quick Start

```powershell
# One-shot: detect and adjust now
.\display-auto-scale.ps1

# Watch mode: continuously monitor for changes
.\display-auto-scale.ps1 -Watch
```

## Install as Background Task

Run the install script (as Administrator) to start the watcher automatically at logon:

```powershell
.\install.ps1
```

The watcher starts immediately and will auto-start at every logon — completely hidden, no console window.

To remove:

```powershell
.\uninstall.ps1
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Watch` | off | Continuously monitor for display changes |
| `-ScaleWithExternal` | 125 | Scale % when external monitors are connected |
| `-ScaleWithoutExternal` | 100 | Scale % when no external monitors |

### Custom Scale Values

```powershell
.\display-auto-scale.ps1 -Watch -ScaleWithExternal 150 -ScaleWithoutExternal 125
```

To change the defaults in the scheduled task, edit `install.ps1` before running it, or modify the task action in Task Scheduler.

## How It Works

1. Listens for the .NET `DisplaySettingsChanged` event (no polling, zero CPU overhead)
2. Uses `QueryDisplayConfig` API to enumerate active display paths
3. Identifies the internal (laptop) display via `DISPLAYCONFIG_OUTPUT_TECHNOLOGY_INTERNAL`
4. Reads current/min/max DPI via `DisplayConfigGetDeviceInfo` — the same undocumented but stable API that the Windows Settings app uses
5. Sets the target DPI via `DisplayConfigSetDeviceInfo` — changes apply instantly, no Explorer restart

## License

[MIT](LICENSE)
