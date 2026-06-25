# Invoke-AutopilotSetup.ps1
# Single-script Autopilot deployment tool for Microsoft 365 Business Premium environments.
#
# USAGE (run from elevated PowerShell):
#
#   Collect hardware hash only (most common — run on the target device):
#     & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -CollectHash
#
#   Prep a Windows 11 USB for Pro install only (run on any PC with the USB inserted):
#     & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -PrepUSB
#
#   Prep USB and collect hash in one go:
#     & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -PrepUSB -CollectHash
#
#   Specify USB drive letter explicitly:
#     & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -PrepUSB -DriveLetter E
#
#   Save hash CSV to a custom path:
#     & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) -CollectHash -OutputPath "C:\Temp\autopilot.csv"

param(
    [switch]$PrepUSB,
    [switch]$CollectHash,
    [string]$DriveLetter,
    [string]$OutputPath = "C:\Users\Public\Desktop\autopilot.csv"
)

# ── Header ────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  Autopilot Setup Tool" -ForegroundColor Cyan
Write-Host "  Microsoft 365 Business Premium" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ── Show usage if no flags ─────────────────────────────────────────────────────

if (-not $PrepUSB -and -not $CollectHash) {
    Write-Host "No action specified. Available flags:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  -PrepUSB       Injects ei.cfg into a Windows 11 USB to force Pro edition" -ForegroundColor White
    Write-Host "  -CollectHash   Collects the Autopilot hardware hash and saves autopilot.csv" -ForegroundColor White
    Write-Host "  -DriveLetter   USB drive letter to use with -PrepUSB (e.g. -DriveLetter E)" -ForegroundColor White
    Write-Host "  -OutputPath    Where to save the hash CSV (default: Public Desktop)" -ForegroundColor White
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host '  & ([scriptblock]::Create((irm <url>))) -CollectHash' -ForegroundColor DarkGray
    Write-Host '  & ([scriptblock]::Create((irm <url>))) -PrepUSB -DriveLetter E' -ForegroundColor DarkGray
    Write-Host '  & ([scriptblock]::Create((irm <url>))) -PrepUSB -CollectHash' -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

# ── Function: Prep USB ─────────────────────────────────────────────────────────

function Invoke-PrepUSB {
    param([string]$Drive)

    Write-Host "[PrepUSB] Searching for Windows 11 USB..." -ForegroundColor Cyan

    if ($Drive) {
        $Drive = $Drive.TrimEnd(':').ToUpper()
        $root = "${Drive}:\"
        if (-not (Test-Path "${root}sources\install.wim") -and -not (Test-Path "${root}sources\install.esd")) {
            Write-Host "[PrepUSB] ERROR: Drive ${Drive}: doesn't look like a Windows 11 USB (sources\install.wim not found)." -ForegroundColor Red
            return $false
        }
    } else {
        $candidates = Get-PSDrive -PSProvider FileSystem | Where-Object {
            $_.Root -ne ($env:SystemDrive + "\") -and
            ((Test-Path "$($_.Root)sources\install.wim") -or (Test-Path "$($_.Root)sources\install.esd"))
        }

        if (-not $candidates) {
            Write-Host "[PrepUSB] ERROR: No Windows 11 USB found. Write the ISO to a USB first, then re-run." -ForegroundColor Red
            return $false
        }

        if (@($candidates).Count -gt 1) {
            Write-Host "[PrepUSB] Multiple Windows USB drives found:" -ForegroundColor Yellow
            $candidates | ForEach-Object { Write-Host "  $($_.Name): — $($_.Root)" -ForegroundColor White }
            $Drive = (Read-Host "[PrepUSB] Enter drive letter to use").TrimEnd(':').ToUpper()
        } else {
            $Drive = @($candidates)[0].Name.TrimEnd(':').ToUpper()
        }

        $root = "${Drive}:\"
    }

    $eiCfgPath = "${root}sources\ei.cfg"

    if (Test-Path $eiCfgPath) {
        Write-Host "[PrepUSB] ei.cfg already exists. Overwriting..." -ForegroundColor Yellow
    }

    $eiCfg = "[EditionID]`r`nProfessional`r`n[Channel]`r`n_Default`r`n[VL]`r`n0`r`n"

    try {
        Set-Content -Path $eiCfgPath -Value $eiCfg -Encoding ASCII -Force
        Write-Host "[PrepUSB] Done. ei.cfg written — USB will install Windows 11 Pro automatically." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[PrepUSB] ERROR: Could not write ei.cfg — $_" -ForegroundColor Red
        Write-Host "[PrepUSB] Ensure the USB is not write-protected and you are running as Administrator." -ForegroundColor Yellow
        return $false
    }
}

# ── Function: Collect Hash ─────────────────────────────────────────────────────

function Invoke-CollectHash {
    param([string]$Output)

    Write-Host "[CollectHash] Installing Get-WindowsAutopilotInfo..." -ForegroundColor Cyan

    try {
        Install-Script -Name Get-WindowsAutopilotInfo -Force -ErrorAction Stop
    } catch {
        Write-Host "[CollectHash] ERROR: Failed to install Get-WindowsAutopilotInfo — $_" -ForegroundColor Red
        Write-Host "[CollectHash] Check internet access and that you are running as Administrator." -ForegroundColor Yellow
        return $false
    }

    Write-Host "[CollectHash] Collecting hardware hash..." -ForegroundColor Cyan

    try {
        Get-WindowsAutopilotInfo -OutputFile $Output -ErrorAction Stop
    } catch {
        Write-Host "[CollectHash] ERROR: Get-WindowsAutopilotInfo failed — $_" -ForegroundColor Red
        return $false
    }

    if (Test-Path $Output) {
        Write-Host "[CollectHash] Done. Hash saved to: $Output" -ForegroundColor Green
        Write-Host "[CollectHash] Import this file into Intune: Devices > Enroll devices > Windows enrollment > Devices > Import" -ForegroundColor DarkGray
        return $true
    } else {
        Write-Host "[CollectHash] ERROR: File not found at $Output after collection." -ForegroundColor Red
        return $false
    }
}

# ── Run selected actions ────────────────────────────────────────────────────────

$usbOk   = $true
$hashOk  = $true

if ($PrepUSB) {
    $usbOk = Invoke-PrepUSB -Drive $DriveLetter
    Write-Host ""
}

if ($CollectHash) {
    $hashOk = Invoke-CollectHash -Output $OutputPath
    Write-Host ""
}

# ── Summary ────────────────────────────────────────────────────────────────────

Write-Host "  ─────────────────────────────────" -ForegroundColor DarkGray
if ($PrepUSB)    { Write-Host "  PrepUSB     $(if ($usbOk)  { '✓ Complete' } else { '✗ Failed' })" -ForegroundColor $(if ($usbOk)  { 'Green' } else { 'Red' }) }
if ($CollectHash){ Write-Host "  CollectHash $(if ($hashOk) { '✓ Complete' } else { '✗ Failed' })" -ForegroundColor $(if ($hashOk) { 'Green' } else { 'Red' }) }
Write-Host ""

if ($PrepUSB -and $usbOk) {
    Write-Host "  Next: Boot the target PC from the USB and complete the Windows 11 Pro install." -ForegroundColor Cyan
    Write-Host "        At OOBE, connect to the internet — Autopilot will take over automatically." -ForegroundColor Cyan
    Write-Host ""
}