# autopilot-info

Scripts for deploying Windows 11 Pro via Microsoft Autopilot with Microsoft 365 Business Premium.

---

## Overview

This repo covers the two-step process for clean-building a PC into your Intune/Autopilot environment:

1. **Prep the install USB** — force Windows 11 Pro edition so Autopilot can enrol the device
2. **Collect the hardware hash** — register the device in Autopilot before (or after) the install

---

## Step 1 — Prep a Windows 11 Pro install USB

### Why this is needed

OEM machines often ship with Windows 11 Home. Intune and Autopilot require **Windows 11 Pro**, which is included in your Microsoft 365 Business Premium licence. By default, Windows Setup selects the edition silently based on OEM keys — this script overrides that by injecting an `ei.cfg` file into the USB that forces Pro.

### Prerequisites

- A USB drive (8 GB+) with the Windows 11 ISO already written to it
  - Use the [Microsoft Media Creation Tool](https://www.microsoft.com/software-download/windows11) or [Rufus](https://rufus.ie)
- Run the script from an **elevated PowerShell prompt** on any Windows machine

### One-liner

```powershell
irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Set-Win11ProUSB.ps1 | iex
```

Or if you want to specify the drive letter directly:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Set-Win11ProUSB.ps1))) -DriveLetter E
```

### What it does

- Scans for a USB drive containing Windows 11 setup files
- Writes an `ei.cfg` to the `sources\` folder on the USB that tells Windows Setup to install **Professional** edition automatically — no edition selection screen appears during setup

---

## Step 2 — Collect the Autopilot hardware hash

Run this on the **target device** (before or after the Windows install — most commonly before reimaging, or on a freshly installed machine before handing it to the user).

### One-liner

```powershell
irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Get-AutopilotHash.ps1 | iex
```

This saves `autopilot.csv` to `C:\Users\Public\Desktop\`.

### Import the CSV into Intune

1. Open [Intune admin centre](https://intune.microsoft.com)
2. Go to **Devices > Enroll devices > Windows enrollment > Devices**
3. Click **Import** and upload `autopilot.csv`
4. Wait for the device to appear (can take 5–15 minutes)

---

## Step 3 — Clean install and OOBE

1. Boot the target PC from the prepared USB
2. Delete all existing partitions during setup for a clean install
3. Windows 11 Pro installs automatically (no edition prompt)
4. At the Out of Box Experience (OOBE), **connect to the internet**
5. Autopilot detects the registered device and takes over — the user signs in with their work account (`user@yourdomain.com`) and Intune enrols the device automatically

---

## Requirements

| Requirement | Detail |
|---|---|
| Licence | Microsoft 365 Business Premium (includes Windows 11 Pro) |
| Edition | Windows 11 Pro (not Home) |
| PowerShell | 5.1 or later |
| Internet access | Required for PowerShell Gallery and Autopilot detection at OOBE |
| Admin rights | Required for `Install-Script` and writing to the USB |

## Notes

- When using `irm | iex`, execution policy is irrelevant — the script runs as a string in-memory, bypassing file-based policy checks.
- The hardware hash CSV contains serial number, Windows product ID, and hardware hash only — no personal user data.
- If a device was previously registered in Autopilot under a different tenant, it must be deregistered first.