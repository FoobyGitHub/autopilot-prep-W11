# autopilot-prep-W11

Single-script Windows 11 Pro deployment toolkit for Microsoft 365 Business Premium / Intune / Autopilot environments.

## Intel VMD disk controller — automatic detection and fix

Many Intel 11th–14th gen machines (Tiger Lake through Raptor Lake Refresh) use an Intel VMD (Volume Management Device) controller to manage NVMe storage. Windows Setup does not include the VMD driver by default — without it, the disk is invisible at the *"Where do you want to install Windows?"* screen and the install cannot proceed.

This script solves that automatically. It reads the CPU model, determines whether VMD injection is required, and if so injects the driver directly into `boot.wim` on the install USB using inbox `dism.exe` — before the machine ever boots from it. No engineer decision, no "Load Driver" prompt during setup, no manual driver handling.

> **The install USB must be created with [Rufus](https://rufus.ie).** Microsoft Media Creation Tool produces ESD-format USBs that DISM cannot modify — the VMD driver cannot be injected into `install.wim`, and the installed OS may BSOD on first boot on VMD-affected machines. Rufus creates WIM-format USBs that allow full driver injection. See [Prep the install USB](#2-prep-the-install-usb) for step-by-step instructions.

The bundled VMD driver covers:

| Platform | VMD required |
|---|---|
| Intel 11th–14th gen Core i-series (Tiger Lake → Raptor Lake Refresh) | Yes — injected automatically |
| Intel Core Ultra Series 1–2 (Meteor Lake / Arrow Lake / Lunar Lake) | Yes — injected automatically |
| Intel Core Ultra Series 3+ / 15th gen and newer | No — skipped |
| AMD / Qualcomm | No — skipped |

## Windows 11 Pro edition enforcement

OEM machines frequently ship with Windows 11 Home. Microsoft 365 Business Premium requires Windows 11 Pro for Autopilot enrolment to function correctly. The script injects an `ei.cfg` file into the USB so Windows Setup installs Pro silently — no edition selection screen, no risk of an engineer picking the wrong edition.

---

## Commands

Run from an **elevated PowerShell prompt**. Copy the command for the task you need.

**Collect hardware hash** — uploads directly to Intune (browser sign-in prompted); insert a separate USB first for local CSV backup:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -CollectHash
```

**Prep a Windows 11 USB for Pro install** — auto-detects the USB, CPU, and injects VMD driver if needed:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -PrepUSB
```

**Prep USB on a specific drive letter:**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -PrepUSB -DriveLetter E
```

**Both at once:**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -PrepUSB -CollectHash
```

**Pre-stage a patched ISO** — file and folder pickers open automatically:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -PatchISO
```

**No flags** — prints a help screen with all options and the above commands ready to copy.

---

## Intune Upload

The script uploads hardware hashes directly to Intune via Microsoft Graph — no CSV file to handle, no manual import step.

### Option 3 — Device Code Flow (default, no setup required)

When `-CollectHash` is run without any upload flags, the script collects the hash then prompts the technician to authenticate via browser:

1. The script prints a code and the URL: `https://microsoft.com/devicelogin`
2. The technician opens that URL in any browser, enters the code, and signs in
3. The signed-in account must have the following Microsoft Graph permission (delegated): `DeviceManagementServiceConfig.ReadWrite.All`
4. Once authenticated, the hash is uploaded automatically

If the upload succeeds, the device appears in Intune within 15 minutes. If it fails or times out, the CSV is saved locally and the script prints manual import instructions.

### Option 1 — Certificate Authentication (unattended, recommended for automation)

> ⚠️ This feature is untested. If you encounter issues, please [log a bug](https://github.com/FoobyGitHub/autopilot-prep-W11/issues).

Requires an Entra ID App Registration with:
- API permission: `DeviceManagementServiceConfig.ReadWrite.All` (application, not delegated)
- A certificate uploaded to the app registration (not a client secret)
- The certificate private key installed in the local machine cert store on the machine running the script

Run with:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -CollectHash -TenantId "your-tenant-id" -AppClientId "your-app-client-id" -AppCertThumbprint "your-cert-thumbprint"
```

**Steps to set up the App Registration:**

1. Go to **Entra ID → App registrations → New registration**
2. Name it e.g. `Autopilot Hash Upload`
3. Go to **API permissions → Add → Microsoft Graph → Application permissions → DeviceManagementServiceConfig.ReadWrite.All** → Grant admin consent
4. Go to **Certificates & secrets → Certificates → Upload your certificate public key** (`.cer` file)
5. Note the **Application (client) ID** and your **tenant ID**
6. Install the certificate (with private key) into the local machine cert store on the prep machine

---

## What `-PrepUSB` does automatically

Running `-PrepUSB` performs three steps with no engineer input required:

### 1. Forces Windows 11 Pro edition

Injects an `ei.cfg` file into the `sources\` folder on the USB. This tells Windows Setup to install Pro silently — no edition selection screen appears. Required because OEM machines often ship with Windows 11 Home, and Autopilot requires Pro (included in Microsoft 365 Business Premium).

### 2. Detects the CPU and determines VMD requirement

Reads the CPU model using `Win32_Processor` and classifies it:

| CPU type | VMD required |
|---|---|
| Intel 11th–14th gen (Tiger Lake → Raptor Lake Refresh) | Yes |
| Intel Core Ultra Series 1–2 (Meteor Lake / Arrow Lake / Lunar Lake) | Yes |
| Intel Core Ultra Series 3+ (15th gen and newer) | No |
| AMD / Qualcomm | No |

### 3. Injects the Intel VMD driver (if required)

If the CPU requires VMD, the script downloads the bundled driver files from this repo (`drivers/VMD/`) and injects them into **both** WIM files on the USB using inbox `dism.exe` — no ADK required:

| Target | Why |
|---|---|
| `boot.wim` index 2 | The Windows Setup environment — disk must be visible at the *"Where do you want to install Windows?"* screen |
| `install.wim` all indexes | The installed OS image — without the driver, Windows BSODs with `INACCESSIBLE_BOOT_DEVICE` on first boot |

The script enumerates the index count in `install.wim` automatically and loops through every edition present (Home, Pro, etc.) so no index is missed.

For each WIM file: if injection fails, DISM discards the mount and `-PrepUSB` reports **Failed** — no silent fallback.

> **MCT ESD-USB:** If the USB was created with the Microsoft Media Creation Tool, `install.wim` is packaged as `install.esd` — DISM cannot modify it. The script detects this, patches `boot.wim` only (so disk detection works at setup), and prints a warning. The installed OS may BSOD on first boot on VMD-affected machines. Recreate the USB with [Rufus](https://rufus.ie) for full support.

---

## USB detection

The script distinguishes between two types of USB drive automatically:

| Drive type | How it is detected | Used for |
|---|---|---|
| Windows 11 install USB | Contains `sources\boot.wim` | `-PrepUSB` targets this drive |
| Data USB (any other) | Any non-system drive without `boot.wim` | `-CollectHash` saves here |

You can have both plugged in at the same time and each flag will target the correct drive.

If `-CollectHash` finds no data USB, it falls back to saving the CSV to the Public Desktop.

> **Note:** The Microsoft Media Creation Tool labels the USB "ESD-USB" and does not always include `install.wim` or `install.esd` in `sources\`. Detection uses `sources\boot.wim` instead, which is always present regardless of how the USB was created.

---

## Full deployment workflow

### 1. Collect hardware hashes

Insert a data USB into the target device and run `-CollectHash`. The script saves `autopilot-<hostname>.csv` into an `AutopilotHashes\` folder on the USB. Multiple devices can share the same USB — each writes its own file named after its hostname. If no data USB is found, the file falls back to the Public Desktop.

**Import into Intune once you have the CSVs:**

1. Open [Intune admin centre](https://intune.microsoft.com)
2. Go to **Devices > Enroll devices > Windows enrollment > Devices**
3. Click **Import** and upload each CSV
4. Wait 5–15 minutes for devices to appear

### Option 2 — Pre-stage a golden ISO (-PatchISO)

For engineers who want to create a reusable patched ISO that can be burned to multiple USBs without running `-PrepUSB` each time.

**Requirements:** Internet access (if ADK not installed). Windows ADK Deployment Tools (~200MB) — installed automatically if not present.

**What it does:**
- Prompts for the source Windows 11 ISO via file picker
- Prompts for output folder via folder picker
- Injects VMD drivers into both `boot.wim` and `install.wim`
- Injects `ei.cfg` for Windows 11 Pro
- Repacks to a new patched ISO using `oscdimg.exe`
- Output ISO can be burned with Rufus directly — no `-PrepUSB` needed

**Command:**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -PatchISO
```

**Workflow:**
1. Run the command above from an elevated PowerShell prompt
2. Select your Windows 11 ISO when the file picker opens
3. Select your output folder
4. Wait for patching to complete (5–15 minutes depending on hardware)
5. Burn the output ISO with Rufus
6. Every USB burned from this ISO is pre-patched — no further steps needed

> **Note:** The first run will download and install Windows ADK Deployment Tools (~200MB) if not already present. A 10-second warning is shown before any download begins.

---

### 2. Prep the install USB

> **The USB must be created with Rufus.** Microsoft Media Creation Tool creates USBs in ESD format — the script cannot inject the VMD driver into `install.wim` on an ESD USB. Boot disk detection will still be fixed, but the installed OS may BSOD on first boot on VMD-affected machines.

**Create the USB with [Rufus](https://rufus.ie):**

1. Download the Windows 11 ISO from [microsoft.com/software-download/windows11](https://www.microsoft.com/software-download/windows11)
2. Insert a USB drive (8 GB minimum)
3. Open Rufus and select the USB drive
4. Click **SELECT** and choose the Windows 11 ISO
5. When Rufus asks **"Windows User Experience"** — leave all options unchecked and click **OK**
6. Leave all other settings as default and click **START**
7. Rufus will warn the USB will be erased — confirm
8. Wait for Rufus to complete — this creates `install.wim` format which the script can modify

Once complete, insert the USB into any PC and run `-PrepUSB`. The script handles everything else automatically — Pro edition enforcement and VMD driver injection into both `boot.wim` and `install.wim`.

> **Microsoft Media Creation Tool** can also be used but only `boot.wim` will be patched — the installed OS may BSOD on first boot on VMD-affected machines.

### 3. Clean install and OOBE

1. Boot the target PC from the prepared USB
2. Delete all existing partitions for a clean install
3. Windows 11 Pro installs automatically — no edition prompt, no Load Driver prompt
4. At OOBE, **connect to the internet** — Autopilot detects the registered device and takes over
5. The user signs in with their work account (`user@yourdomain.com`) and Intune enrols the device

---

## Requirements

| Requirement | Detail |
|---|---|
| Licence | Microsoft 365 Business Premium (includes Windows 11 Pro) |
| PowerShell | 5.1 or later |
| Elevation | Run as Administrator |
| Internet | Required for VMD driver fetch from GitHub, PSGallery (`-CollectHash`), and Autopilot detection at OOBE |
| ADK | Not required — `dism.exe` is used from `C:\Windows\System32\` |

## Notes

- The script sets `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force` automatically, preventing PSGallery install failures on machines with a restrictive default policy.
- The hash CSV contains serial number, Windows product ID, and hardware hash only — no personal data.
- If a device was previously registered in Autopilot under a different tenant, it must be deregistered there first.
