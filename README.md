# autopilot-info

Single-script Windows 11 Pro deployment toolkit for Microsoft 365 Business Premium / Intune / Autopilot environments.

---

## Quick reference

Run from an **elevated PowerShell prompt**. Copy the base command, then append the flag you need.

**Base command:**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) <flags>
```

| Task | Flag |
|---|---|
| Collect hardware hash (saves to USB automatically) | `-CollectHash` |
| Prep Windows 11 USB for Pro install | `-PrepUSB` |
| Both at once | `-PrepUSB -CollectHash` |
| Force a specific USB drive letter | `-PrepUSB -DriveLetter E` |
| Override hash output path | `-CollectHash -OutputPath C:\Temp\hash.csv` |

---

## Full examples

```powershell
# Collect hash — insert a USB first, it auto-detects and saves there
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -CollectHash

# Prep a Windows 11 USB for Pro install — auto-detects the USB
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -PrepUSB

# Prep USB on drive E: explicitly
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -PrepUSB -DriveLetter E

# Prep USB and collect hash in one shot
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -PrepUSB -CollectHash
```

---

## Full deployment workflow

### Step 1 — Collect the hardware hash

Insert a USB drive into the target device, then run:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -CollectHash
```

The script auto-detects the USB and saves `autopilot-<hostname>.csv` into an `AutopilotHashes\` folder on it. If no USB is found it falls back to the Public Desktop.

You can batch multiple machines onto the same USB — each device writes its own file named after its hostname.

**Import into Intune:**

1. Open [Intune admin centre](https://intune.microsoft.com)
2. Go to **Devices > Enroll devices > Windows enrollment > Devices**
3. Click **Import** and upload each CSV
4. Wait 5–15 minutes for devices to appear

### Step 2 — Prep the install USB

Write the Windows 11 ISO to a USB first using the [Microsoft Media Creation Tool](https://www.microsoft.com/software-download/windows11) or [Rufus](https://rufus.ie), then run on any PC with the USB inserted:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -PrepUSB
```

**Why this is needed:** OEM machines often ship with Windows 11 Home. Autopilot requires **Windows 11 Pro**, which is included in Microsoft 365 Business Premium. This injects an `ei.cfg` into the USB so Windows Setup installs Pro automatically with no manual edition selection.

### Step 3 — Clean install and OOBE

1. Boot the target PC from the prepared USB
2. Delete all existing partitions during setup for a clean install
3. Windows 11 Pro installs automatically — no edition prompt
4. At OOBE, **connect to the internet** — Autopilot detects the registered device and takes over
5. The user signs in with their work account (`user@yourdomain.com`) and Intune enrols the device

---

## Requirements

| Requirement | Detail |
|---|---|
| Licence | Microsoft 365 Business Premium (includes Windows 11 Pro) |
| PowerShell | 5.1 or later |
| Elevation | Run as Administrator |
| Internet | Required for PowerShell Gallery and Autopilot detection at OOBE |

## Notes

- `irm` / scriptblock pattern runs the script in-memory — execution policy does not apply.
- The hash CSV contains serial number, Windows product ID, and hardware hash only — no personal data.
- Filenames include the device hostname (`autopilot-<hostname>.csv`) so multiple devices can share one USB.
- If a device was previously registered under a different tenant, it must be deregistered there first.