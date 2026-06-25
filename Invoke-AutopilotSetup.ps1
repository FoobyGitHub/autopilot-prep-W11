# Invoke-AutopilotSetup.ps1
# Single-script Autopilot deployment tool for Microsoft 365 Business Premium environments.
#
# Run from an elevated PowerShell prompt using:
#
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-info/main/Invoke-AutopilotSetup.ps1))) <flags>
#
# Flags:
#   -CollectHash          Collect hardware hash and save to USB (or desktop if no USB found)
#   -PrepUSB              Inject ei.cfg into Windows 11 USB to force Pro edition
#   -DriveLetter <X>      Force a specific drive letter for -PrepUSB (optional)
#   -OutputPath <path>    Override the output path for the hash CSV (optional)

param(
    [switch]$PrepUSB,
    [switch]$CollectHash,
    [string]$DriveLetter,
    [string]$OutputPath
)

Write-Host ""
Write-Host "  Autopilot Setup Tool" -ForegroundColor Cyan
Write-Host "  Microsoft 365 Business Premium" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

if (-not $PrepUSB -and -not $CollectHash) {
    Write-Host "No action specified. Use one or more flags:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  -CollectHash     Collect Autopilot hardware hash -> saves to USB AutopilotHashes folder" -ForegroundColor White
    Write-Host "  -PrepUSB         Inject ei.cfg into Windows 11 USB to force Pro edition" -ForegroundColor White
    Write-Host "  -DriveLetter E   Force USB drive letter for -PrepUSB" -ForegroundColor White
    Write-Host "  -OutputPath      Override hash CSV output path" -ForegroundColor White
    Write-Host ""
    Write-Host "Example (run from elevated PowerShell):" -ForegroundColor Cyan
    Write-Host "  & ([scriptblock]::Create((irm <url>))) -CollectHash" -ForegroundColor DarkGray
    Write-Host "  & ([scriptblock]::Create((irm <url>))) -PrepUSB -DriveLetter E" -ForegroundColor DarkGray
    Write-Host "  & ([scriptblock]::Create((irm <url>))) -PrepUSB -CollectHash" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

# ── Shared: find a removable/external USB drive ────────────────────────────────

function Find-AnyUSB {
    # Returns the root of the first non-system drive found
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -ne ($env:SystemDrive + "\") }
    if ($drives) { return @($drives)[0].Root }
    return $null
}

function Find-Windows11USB {
    # Returns the root of the first drive containing Windows 11 setup files
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object {
        $_.Root -ne ($env:SystemDrive + "\") -and
        ((Test-Path "$($_.Root)sources\install.wim") -or (Test-Path "$($_.Root)sources\install.esd"))
    }
    if ($drives) { return @($drives)[0] }
    return $null
}

# ── PrepUSB ────────────────────────────────────────────────────────────────────

function Invoke-PrepUSB {
    param([string]$Drive)

    Write-Host "[PrepUSB] Looking for Windows 11 USB..." -ForegroundColor Cyan

    if ($Drive) {
        $Drive = $Drive.TrimEnd(':').ToUpper()
        $root = "${Drive}:\"
        if (-not (Test-Path "${root}sources\install.wim") -and -not (Test-Path "${root}sources\install.esd")) {
            Write-Host "[PrepUSB] ERROR: Drive ${Drive}: does not contain Windows 11 setup files." -ForegroundColor Red
            return $false
        }
    } else {
        $found = Find-Windows11USB
        if (-not $found) {
            Write-Host "[PrepUSB] ERROR: No Windows 11 USB detected. Write the ISO to a USB first, then re-run." -ForegroundColor Red
            return $false
        }
        $Drive = $found.Name.TrimEnd(':').ToUpper()
        $root  = $found.Root
        Write-Host "[PrepUSB] Found Windows 11 USB at drive ${Drive}:" -ForegroundColor Green
    }

    $eiCfgPath = "${root}sources\ei.cfg"

    if (Test-Path $eiCfgPath) {
        Write-Host "[PrepUSB] Existing ei.cfg found — overwriting." -ForegroundColor Yellow
    }

    $eiCfg = "[EditionID]`r`nProfessional`r`n[Channel]`r`n_Default`r`n[VL]`r`n0`r`n"

    try {
        Set-Content -Path $eiCfgPath -Value $eiCfg -Encoding ASCII -Force
        Write-Host "[PrepUSB] Done — USB will now install Windows 11 Pro automatically. No edition prompt will appear." -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[PrepUSB] ERROR: Could not write ei.cfg: $_" -ForegroundColor Red
        Write-Host "[PrepUSB] Make sure the USB is not write-protected and you are running as Administrator." -ForegroundColor Yellow
        return $false
    }
}

# ── CollectHash ────────────────────────────────────────────────────────────────

function Invoke-CollectHash {
    param([string]$OverridePath)

    # Determine output path
    if ($OverridePath) {
        $outPath = $OverridePath
        Write-Host "[CollectHash] Output path overridden to: $outPath" -ForegroundColor Yellow
    } else {
        $usbRoot = Find-AnyUSB
        if ($usbRoot) {
            $hashFolder = "${usbRoot}AutopilotHashes"
            New-Item -ItemType Directory -Force -Path $hashFolder | Out-Null
            $outPath = "$hashFolder\autopilot-$(hostname).csv"
            Write-Host "[CollectHash] USB detected at ${usbRoot} — hash will be saved to: $outPath" -ForegroundColor Green
        } else {
            $outPath = "C:\Users\Public\Desktop\autopilot-$(hostname).csv"
            Write-Host "[CollectHash] No USB detected — saving to Public Desktop: $outPath" -ForegroundColor Yellow
        }
    }

    Write-Host "[CollectHash] Installing Get-WindowsAutopilotInfo..." -ForegroundColor Cyan

    try {
        Install-Script -Name Get-WindowsAutopilotInfo -Force -ErrorAction Stop
    } catch {
        Write-Host "[CollectHash] ERROR: Failed to install Get-WindowsAutopilotInfo: $_" -ForegroundColor Red
        Write-Host "[CollectHash] Check internet access and ensure you are running as Administrator." -ForegroundColor Yellow
        return $false
    }

    Write-Host "[CollectHash] Collecting hardware hash for $(hostname)..." -ForegroundColor Cyan

    try {
        Get-WindowsAutopilotInfo -OutputFile $outPath -ErrorAction Stop
    } catch {
        Write-Host "[CollectHash] ERROR: Get-WindowsAutopilotInfo failed: $_" -ForegroundColor Red
        return $false
    }

    if (Test-Path $outPath) {
        Write-Host "[CollectHash] Done. Hash saved to: $outPath" -ForegroundColor Green
        Write-Host "[CollectHash] Import into Intune: Devices > Enroll devices > Windows enrollment > Devices > Import" -ForegroundColor DarkGray
        return $true
    } else {
        Write-Host "[CollectHash] ERROR: File not found at $outPath after collection." -ForegroundColor Red
        return $false
    }
}

# ── Run ────────────────────────────────────────────────────────────────────────

$usbOk  = $true
$hashOk = $true

if ($PrepUSB)    { $usbOk  = Invoke-PrepUSB -Drive $DriveLetter;    Write-Host "" }
if ($CollectHash){ $hashOk = Invoke-CollectHash -OverridePath $OutputPath; Write-Host "" }

Write-Host "  ─────────────────────────────────" -ForegroundColor DarkGray
if ($PrepUSB)    { Write-Host "  PrepUSB     $(if ($usbOk)  { '✓ Complete' } else { '✗ Failed' })" -ForegroundColor $(if ($usbOk)  { 'Green' } else { 'Red' }) }
if ($CollectHash){ Write-Host "  CollectHash $(if ($hashOk) { '✓ Complete' } else { '✗ Failed' })" -ForegroundColor $(if ($hashOk) { 'Green' } else { 'Red' }) }
Write-Host ""

if ($PrepUSB -and $usbOk) {
    Write-Host "  Next: Boot the target PC from the USB and complete the Windows 11 Pro install." -ForegroundColor Cyan
    Write-Host "        At OOBE, connect to the internet — Autopilot will take over automatically." -ForegroundColor Cyan
    Write-Host ""
}