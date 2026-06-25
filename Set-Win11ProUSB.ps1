# Set-Win11ProUSB.ps1
# Adds ei.cfg to a Windows 11 bootable USB to force Pro edition during clean install.
# Run from an elevated PowerShell prompt AFTER writing the Windows 11 ISO to the USB.
#
# Usage: .\Set-Win11ProUSB.ps1
#        .\Set-Win11ProUSB.ps1 -DriveLetter E

param(
    [string]$DriveLetter
)

function Get-Win11USBDrives {
    Get-PSDrive -PSProvider FileSystem | Where-Object {
        $_.Root -ne $env:SystemDrive + "\" -and
        (Test-Path "$($_.Root)sources\install.wim") -or
        (Test-Path "$($_.Root)sources\install.esd")
    }
}

Write-Host "`nWindows 11 Pro USB Prep Tool" -ForegroundColor Cyan
Write-Host "============================`n" -ForegroundColor Cyan

# Auto-detect or validate provided drive letter
if ($DriveLetter) {
    $DriveLetter = $DriveLetter.TrimEnd(':').ToUpper()
    $root = "${DriveLetter}:\"
    if (-not (Test-Path "${root}sources\install.wim") -and -not (Test-Path "${root}sources\install.esd")) {
        Write-Host "ERROR: Drive ${DriveLetter}: doesn't look like a Windows 11 USB (sources\install.wim not found)." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Scanning for Windows 11 USB drives..." -ForegroundColor Yellow
    $candidates = Get-Win11USBDrives
    if (-not $candidates) {
        Write-Host "ERROR: No Windows 11 USB found. Make sure the ISO has been written to the USB first." -ForegroundColor Red
        Write-Host "       Use the Microsoft Media Creation Tool or Rufus to write the ISO, then re-run this script." -ForegroundColor Yellow
        exit 1
    }
    if ($candidates.Count -gt 1) {
        Write-Host "Multiple Windows USB drives found:" -ForegroundColor Yellow
        $candidates | ForEach-Object { Write-Host "  $($_.Name): — $($_.Root)" }
        $DriveLetter = Read-Host "Enter the drive letter to use"
        $DriveLetter = $DriveLetter.TrimEnd(':').ToUpper()
    } else {
        $DriveLetter = $candidates[0].Name.TrimEnd(':').ToUpper()
        Write-Host "Found Windows 11 USB at drive ${DriveLetter}:" -ForegroundColor Green
    }
    $root = "${DriveLetter}:\"
}

$sourcesPath = "${root}sources"
$eiCfgPath   = "${sourcesPath}\ei.cfg"

# Check for existing ei.cfg
if (Test-Path $eiCfgPath) {
    Write-Host "`nei.cfg already exists at $eiCfgPath" -ForegroundColor Yellow
    $existing = Get-Content $eiCfgPath -Raw
    Write-Host "Current content:`n$existing" -ForegroundColor Gray
    $overwrite = Read-Host "Overwrite? (Y/N)"
    if ($overwrite -notmatch '^[Yy]') {
        Write-Host "Aborted — existing ei.cfg left unchanged." -ForegroundColor Yellow
        exit 0
    }
}

# Write ei.cfg — forces Windows 11 Pro, no edition prompt during setup
$eiCfg = @"
[EditionID]
Professional
[Channel]
_Default
[VL]
0
"@

try {
    Set-Content -Path $eiCfgPath -Value $eiCfg -Encoding ASCII -Force
    Write-Host "`nDone. ei.cfg written to $eiCfgPath" -ForegroundColor Green
    Write-Host "`nThe USB will now install Windows 11 Pro automatically." -ForegroundColor Green
    Write-Host "No edition selection screen will appear during setup.`n" -ForegroundColor Green
} catch {
    Write-Host "`nERROR: Could not write ei.cfg — $_" -ForegroundColor Red
    Write-Host "Make sure the USB is not write-protected and you are running as Administrator." -ForegroundColor Yellow
    exit 1
}

Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Boot the target PC from this USB" -ForegroundColor White
Write-Host "  2. Complete the Windows 11 Pro install (delete all partitions for a clean install)" -ForegroundColor White
Write-Host "  3. At OOBE, connect to the internet — Autopilot will take over automatically" -ForegroundColor White
Write-Host "  4. Sign in with a work account when prompted (user@yourdomain.com)`n" -ForegroundColor White