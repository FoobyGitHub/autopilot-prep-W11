# autopilot-info

A lightweight PowerShell script that collects the Windows Autopilot hardware hash from a device and saves it as a CSV file ready for upload to Microsoft Intune.

## What it does

1. Sets the PowerShell execution policy to `RemoteSigned` for the current user
2. Installs the `Get-WindowsAutopilotInfo` script from the PowerShell Gallery
3. Runs the script and saves the hardware hash to `C:\Users\Public\Desktop\autopilot.csv`

## Usage

Run on the target device — no pre-installation required beyond PowerShell.

**Option A — Right-click**

1. Download `Get-AutopilotHash.ps1`
2. Right-click the file → **Run with PowerShell**

**Option B — Elevated prompt**

```powershell
.\Get-AutopilotHash.ps1
```

## Output

A file named `autopilot.csv` is saved to the Public Desktop (`C:\Users\Public\Desktop\`). This file can be imported directly into **Microsoft Intune > Devices > Enroll devices > Windows enrollment > Automatic Enrollment > Import**.

## Requirements

- Windows 10 / 11
- PowerShell 5.1 or later
- Internet access (to download `Get-WindowsAutopilotInfo` from the PowerShell Gallery)
- Administrator rights are recommended for execution policy changes to take effect globally

## Notes

- The script uses `-Scope CurrentUser` for the execution policy change, so it does not require elevation solely for that step, but `Get-WindowsAutopilotInfo` itself may prompt for elevation.
- The output CSV contains the device serial number, Windows product ID, and hardware hash — no personal user data.