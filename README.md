# autopilot-info

Single-script Windows 11 Pro deployment toolkit for Microsoft 365 Business Premium / Intune / Autopilot environments.

---

## For field engineers — collect hardware hash

Insert a USB drive into the device, open **PowerShell as Administrator**, and run:

```powershell
irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1 | iex
```

That is all. The script auto-detects the USB and saves `autopilot-<hostname>.csv` into an `AutopilotHashes\` folder on it. Multiple devices can share the same USB — each file is named after the device hostname.

---

## For IT — prep a Windows 11 USB for Pro install

Write the Windows 11 ISO to a USB first (use [Media Creation Tool](https://www.microsoft.com/software-download/windows11) or [Rufus](https://rufus.ie)), insert it, then run from **PowerShell as Administrator**:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -PrepUSB
```

To specify a drive letter manually:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -PrepUSB -DriveLetter E
```

**Why this is needed:** OEM machines often ship with Windows 11 Home. Autopilot requires Windows 11 Pro (included in Microsoft 365 Business Premium). This injects an `ei.cfg` into the USB so Windows Setup installs Pro silently — no edition selection screen appears.

---

## Full deployment workflow

### 1. Collect hardware hashes

Run the simple one-liner on each target device (USB inserted). Gather all the CSV files from the `AutopilotHashes\` folder on the USB and import them into Intune:

**Intune admin centre > Devices > Enroll devices > Windows enrollment > Devices > Import**

Wait 5–15 minutes for devices to appear before proceeding.

### 2. Prep the install USB

Run the `-PrepUSB` command on any PC with the Windows 11 USB inserted.

### 3. Clean install and OOBE

1. Boot the target PC from the prepared USB
2. Delete all existing partitions for a clean install
3. Windows 11 Pro installs automatically — no edition prompt
4. At OOBE, **connect to the internet** — Autopilot detects the registered device and takes over
5. The user signs in with their work account (`user@yourdomain.com`) and Intune enrols the device

---

## All available flags

| Flag | Description |
|---|---|
| _(none)_ | Collect hardware hash (default) |
| `-CollectHash` | Collect hardware hash explicitly |
| `-PrepUSB` | Inject `ei.cfg` into Windows 11 USB to force Pro edition |
| `-PrepUSB -CollectHash` | Do both in one run |
| `-DriveLetter E` | Force drive letter for `-PrepUSB` |
| `-OutputPath C:\path\file.csv` | Override hash CSV save location |

## Requirements

| Requirement | Detail |
|---|---|
| Licence | Microsoft 365 Business Premium (includes Windows 11 Pro) |
| PowerShell | 5.1 or later |
| Elevation | Run as Administrator |
| Internet | Required for PowerShell Gallery and Autopilot detection at OOBE |

## Notes

- `irm | iex` runs the script in-memory — execution policy does not apply.
- The hash CSV contains serial number, Windows product ID, and hardware hash only — no personal data.
- If a device was previously registered in Autopilot under a different tenant, it must be deregistered there first.