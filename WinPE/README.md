# WinPE — AutopilotPrep Hash Upload

This folder contains the scripts and config that run inside WinPE to collect and upload the Windows Autopilot hardware hash.

## Contents

| File | Purpose |
|---|---|
| `Invoke-AutopilotHash.ps1` | Main WinPE script — collects hash with oa3tool, uploads to Intune via Graph API |
| `oa3.cfg` | Config file consumed by oa3tool.exe — sets OA3.xml as the output path |
| `PCPKsp.dll` | **Not in repo — must be sourced separately (see below)** |
| `oa3tool.exe` | **Not in repo — must be sourced separately (see below)** |

## Files you must source separately

These files cannot be distributed in this repo. Copy them into this folder before building the USB.

**PCPKsp.dll** — TPM Platform Crypto Provider. Required for the hash to include TPM information.

- Source from any Windows 11 machine:
  ```
  C:\Windows\System32\PCPKsp.dll
  ```

**oa3tool.exe** — OEM Activation 3.0 tool. Generates the 4K hardware hash.

- Source from the Windows ADK (Assessment and Deployment Kit):
  ```
  C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Licensing\OA30\oa3tool.exe
  ```
- The ADK can be downloaded from Microsoft. Install the **Deployment Tools** feature only.

If `PCPKsp.dll` is missing, the hash will still be collected but will not include TPM data. If `oa3tool.exe` is missing, the script will exit with an error.

## Credentials

`Invoke-AutopilotHash.ps1` contains `##TENANTID##`, `##APPID##`, and `##APPSECRET##` placeholder tokens. These are replaced automatically by `Build-WinPEUSB.ps1` when building the bootable USB.

Do not edit the credential tokens manually. Run `New-AutopilotAppRegistration.ps1` first to create the app registration and generate `autopilot-appreg.config`, then run `Build-WinPEUSB.ps1` to build the USB.

## Usage

This folder is not intended to be run directly. Use `Build-WinPEUSB.ps1` from the repo root to build the bootable USB — it copies this folder into the WinPE image and injects the credentials automatically.
