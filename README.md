# autopilot-info

Single-script Windows 11 Pro deployment toolkit for Microsoft 365 Business Premium / Intune / Autopilot environments.

---

## Quick reference

All commands use the same script. Run from an **elevated PowerShell prompt**.

> **Tip:** Copy the base command once, then add the flags you need.

`powershell
# Base command (substitute flags below)
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) <flags>
`

| Task | Command |
|---|---|
| Collect hardware hash | `-CollectHash` |
| Prep Windows 11 USB for Pro install | `-PrepUSB` |
| Both at once | `-PrepUSB -CollectHash` |
| Specify USB drive letter | `-PrepUSB -DriveLetter E` |
| Save hash to custom path | `-CollectHash -OutputPath C:\Temp\autopilot.csv` |

### Examples

`powershell
# Most common — collect hash on the target device
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -CollectHash

# Prep a USB drive (auto-detects the drive)
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -PrepUSB

# Prep USB on drive E: and collect hash in one shot
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -PrepUSB -DriveLetter E -CollectHash
`

---

## Full deployment workflow

### Step 1 — Register the device in Autopilot

Run this on the **target device** (can be done before reimaging if the machine already has Windows on it):

`powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -CollectHash
`

- Saves `autopilot.csv` to `C:\Users\Public\Desktop\`
- Go to [Intune admin centre](https://intune.microsoft.com) > **Devices > Enroll devices > Windows enrollment > Devices > Import**
- Upload the CSV and wait 5–15 minutes for the device to appear

### Step 2 — Prep the install USB

Do this on **any PC** with the Windows 11 USB already inserted. Write the ISO first using the [Microsoft Media Creation Tool](https://www.microsoft.com/software-download/windows11) or [Rufus](https://rufus.ie), then run:

`powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -PrepUSB
`

**Why this is needed:** OEM machines often ship with Windows 11 Home. Autopilot requires **Windows 11 Pro** (included in Microsoft 365 Business Premium). This injects an `ei.cfg` file into the USB that tells Windows Setup to install Pro automatically — no edition selection screen appears.

### Step 3 — Clean install and OOBE

1. Boot the target PC from the prepared USB
2. Delete all partitions during setup for a clean install
3. Windows 11 Pro installs automatically
4. At OOBE, **connect to the internet** — Autopilot detects the registered device and takes over
5. The user signs in with their work account (`user@yourdomain.com`) and Intune enrols the device

---

## Requirements

| Requirement | Detail |
|---|---|
| Licence | Microsoft 365 Business Premium (includes Windows 11 Pro) |
| PowerShell | 5.1 or later |
| Elevation | Run as Administrator |
| Internet | Required for PowerShell Gallery (hash collection) and Autopilot detection at OOBE |

## Notes

- `irm` / `iex` runs the script as a string in-memory — execution policy does not apply.
- The hash CSV contains serial number, Windows product ID, and hardware hash only — no personal data.
- If a device was previously registered in Autopilot under a different tenant, it must be deregistered there first.
- The individual scripts (`Get-AutopilotHash.ps1`, `Set-Win11ProUSB.ps1`) are still available in this repo if needed standalone.