# autopilot-info

A lightweight PowerShell script that collects the Windows Autopilot hardware hash from a device and saves it as a CSV file ready for upload to Microsoft Intune.

## Quick start — one-liner

Run this in an elevated PowerShell prompt on the target device. No download required.

```powershell
irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Get-AutopilotHash.ps1 | iex
```

`irm` (Invoke-RestMethod) downloads the script as a string; `iex` (Invoke-Expression) executes it directly in the current session — no file saved, no execution policy prompt.

## What it does

1. Sets the PowerShell execution policy to `RemoteSigned` for the current user
2. Installs the `Get-WindowsAutopilotInfo` script from the PowerShell Gallery
3. Runs the script and saves the hardware hash to `C:\Users\Public\Desktop\autopilot.csv`

## Usage — running the script file directly

If you prefer to download and inspect the script first:

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
- Internet access (to reach the PowerShell Gallery and the raw GitHub URL)
- Administrator rights recommended — required for `Install-Script` to write to the system script path

## Notes

- When using the one-liner, execution policy is irrelevant — `iex` runs a string, not a file on disk, so the policy check is bypassed entirely.
- The output CSV contains the device serial number, Windows product ID, and hardware hash — no personal user data.