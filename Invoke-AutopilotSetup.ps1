# Invoke-AutopilotSetup.ps1
# Autopilot deployment tool for Microsoft 365 Business Premium environments.
#
# Run from an elevated PowerShell prompt:
#
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -CollectHash
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -PrepUSB
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -PrepUSB -CollectHash

param(
    [switch]$PrepUSB,
    [switch]$CollectHash,
    [switch]$PatchISO,
    [switch]$ForceWiFi,
    [switch]$ForceVMD,
    [string]$DriveLetter,
    [string]$OutputPath,
    [string]$TenantId,
    [string]$AppClientId,
    [string]$AppCertThumbprint
)

# ── Execution policy ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Autopilot Setup Tool" -ForegroundColor Cyan
Write-Host "  Microsoft 365 Business Premium" -ForegroundColor Cyan
Write-Host "  ─────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "[Setup] Setting execution policy to RemoteSigned (CurrentUser)..." -ForegroundColor DarkGray

try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
    Write-Host "[Setup] Execution policy set." -ForegroundColor DarkGray
} catch {
    Write-Host "[Setup] WARNING: Could not set execution policy: $_" -ForegroundColor Yellow
    Write-Host "[Setup] Script installation from PSGallery may fail. Try running as Administrator." -ForegroundColor Yellow
}

Write-Host ""

# ── Show help if no flags ──────────────────────────────────────────────────────

if (-not $PrepUSB -and -not $CollectHash -and -not $PatchISO) {
    Write-Host "No action specified. Available flags:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  -CollectHash                Collect hash and upload to Intune (device code sign-in — browser prompted)" -ForegroundColor White
    Write-Host "  -PrepUSB                    Inject ei.cfg + VMD driver into a Windows 11 USB" -ForegroundColor White
    Write-Host "  -PatchISO                   Pre-stage a Windows 11 ISO with VMD drivers and Pro edition config — outputs a patched ISO ready to burn with Rufus" -ForegroundColor White
    Write-Host "  -DriveLetter X              Force a specific drive letter for -PrepUSB  (e.g. -DriveLetter E)" -ForegroundColor White
    Write-Host "  -OutputPath path            Override the hash CSV save location" -ForegroundColor White
    Write-Host "  -ForceWiFi                  Force Wi-Fi/BT driver injection even if Intel BE201 is not detected on this machine. Use when prepping a USB or ISO on a different PC to the one being built." -ForegroundColor White
    Write-Host "  -ForceVMD                   Force VMD driver injection even if the CPU on this machine does not require it. Use when prepping a USB or ISO on a different PC to the one being built." -ForegroundColor White
    Write-Host ""
    Write-Host "  Option 1 — certificate authentication (unattended, no browser prompt):" -ForegroundColor DarkGray
    Write-Host "  -TenantId <id>              Azure AD tenant ID" -ForegroundColor White
    Write-Host "  -AppClientId <id>           App registration client ID" -ForegroundColor White
    Write-Host "  -AppCertThumbprint <val>    Certificate thumbprint (cert with private key in local machine store)" -ForegroundColor White
    Write-Host ""
    Write-Host "Copy and run one of these commands:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Collect hash + upload to Intune (device code sign-in):" -ForegroundColor DarkGray
    Write-Host "  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -CollectHash" -ForegroundColor White
    Write-Host ""
    Write-Host "  Collect hash + upload silently (certificate auth — Option 1):" -ForegroundColor DarkGray
    Write-Host "  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -CollectHash -TenantId <id> -AppClientId <id> -AppCertThumbprint <thumbprint>" -ForegroundColor White
    Write-Host ""
    Write-Host "  Prep a Windows 11 USB for Pro install (auto-detects CPU, injects VMD driver if needed):" -ForegroundColor DarkGray
    Write-Host "  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -PrepUSB" -ForegroundColor White
    Write-Host ""
    Write-Host "  Prep USB on drive E specifically:" -ForegroundColor DarkGray
    Write-Host "  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -PrepUSB -DriveLetter E" -ForegroundColor White
    Write-Host ""
    Write-Host "  Do both in one shot:" -ForegroundColor DarkGray
    Write-Host "  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -PrepUSB -CollectHash" -ForegroundColor White
    Write-Host ""
    Write-Host "  Pre-stage a patched ISO (file + folder pickers open automatically):" -ForegroundColor DarkGray
    Write-Host "  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -PatchISO" -ForegroundColor White
    Write-Host ""
    exit 0
}

# ── Shared helpers ─────────────────────────────────────────────────────────────

function Test-IsWindows11USB {
    param([string]$Root)
    # boot.wim is always present on any Windows install USB (MCT or Rufus).
    # install.wim / install.esd may be absent on MCT-created ESD-USB drives.
    return (Test-Path "${Root}sources\boot.wim") -or
           (Test-Path "${Root}sources\install.wim") -or
           (Test-Path "${Root}sources\install.esd")
}

function Find-DataUSB {
    # Returns the first non-system drive that is NOT a Windows 11 install USB.
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object {
        $_.Root -ne ($env:SystemDrive + "\") -and
        -not (Test-IsWindows11USB -Root $_.Root)
    }
    if ($drives) { return @($drives)[0].Root }
    return $null
}

function Find-Windows11USB {
    # Returns the first drive that looks like a Windows install USB.
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object {
        $_.Root -ne ($env:SystemDrive + "\") -and
        (Test-IsWindows11USB -Root $_.Root)
    }
    if ($drives) { return @($drives)[0] }
    return $null
}

# ── VMD detection helpers ──────────────────────────────────────────────────────

function Get-CPUVMDStatus {
    param(
        [string]$CpuName,
        [bool]$Force = $false
    )

    if ($Force) {
        return @{ NeedsVMD = $true; Reason = "-ForceVMD specified" }
    }

    # AMD / Qualcomm / ARM — no VMD controller present
    if ($CpuName -match '(AMD|Ryzen|EPYC|Qualcomm|Snapdragon)') {
        return @{ NeedsVMD = $false; Reason = "AMD/Qualcomm CPU detected — VMD not applicable, skipping" }
    }

    if ($CpuName -notmatch 'Intel') {
        return @{ NeedsVMD = $false; Reason = "Non-Intel CPU detected — skipping VMD check" }
    }

    # Intel Core Ultra series (Meteor Lake / Lunar Lake / Arrow Lake)
    # Naming pattern: "Intel(R) Core(TM) Ultra 5 125H"
    #   100-series = Series 1 (Meteor Lake)   → VMD required
    #   200-series = Series 2 (Lunar Lake / Arrow Lake) → VMD required
    #   300-series = Series 3 (per spec: no VMD)
    if ($CpuName -match 'Core\s*\(TM\)\s*Ultra\s+\d+\s+(\d{3})') {
        $series = [math]::Floor([int]$Matches[1] / 100)
        if ($series -ge 3) {
            return @{ NeedsVMD = $false; Reason = "Intel Core Ultra Series $series detected — VMD not required" }
        }
        return @{ NeedsVMD = $true; Reason = "Intel Core Ultra Series $series detected — VMD driver required" }
    }

    # Intel Core i-series (traditional generations)
    # Model number format: i7-1165G7 → captures "1165" (4 digits) → gen 11
    #                      i9-13900K → captures "13900" (5 digits) → gen 13
    if ($CpuName -match 'Core\s*\(TM\)\s+i\d+-(\d{4,5})') {
        $modelStr = $Matches[1]
        $gen = if ($modelStr.Length -eq 4) {
            [math]::Floor([int]$modelStr / 100)    # 1165 → 11
        } else {
            [math]::Floor([int]$modelStr / 1000)   # 13900 → 13
        }

        if ($gen -ge 11 -and $gen -le 14) {
            return @{ NeedsVMD = $true; Reason = "Intel ${gen}th gen detected — VMD driver required" }
        }
        return @{ NeedsVMD = $false; Reason = "Intel ${gen}th gen detected — VMD not required" }
    }

    # Unrecognised Intel CPU string — skip with a warning
    return @{ NeedsVMD = $false; Reason = "Intel CPU generation unrecognised ('$CpuName') — skipping VMD injection" }
}

function Invoke-WimVmdInjection {
    param(
        [string]$Root,
        [string]$DriverDir,
        [string]$Tag
    )

    # ── boot.wim injection (index 2) ──────────────────────────────────────────
    $bootWim  = "${Root}sources\boot.wim"
    $mountDir = Join-Path $env:TEMP "WimMount_$(Get-Random)"
    New-Item -ItemType Directory -Path $mountDir -Force | Out-Null
    $dismOk = $false

    Write-Host "$Tag Injecting VMD driver into boot.wim (index 2) using dism.exe..." -ForegroundColor Cyan

    try {
        & "$env:SystemRoot\System32\attrib.exe" -R "$bootWim" 2>&1 | Out-Null
        Write-Host "$Tag Read-only attribute cleared on boot.wim." -ForegroundColor DarkGray

        $out = & "$env:SystemRoot\System32\dism.exe" /Mount-Wim /WimFile:"$bootWim" /Index:2 /MountDir:"$mountDir" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Mount failed (exit $LASTEXITCODE): $($out -join ' ')" }

        $out = & "$env:SystemRoot\System32\dism.exe" /Image:"$mountDir" /Add-Driver /Driver:"$DriverDir" /Recurse 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Add-Driver failed (exit $LASTEXITCODE): $($out -join ' ')" }

        $out = & "$env:SystemRoot\System32\dism.exe" /Unmount-Wim /MountDir:"$mountDir" /Commit 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Unmount/commit failed (exit $LASTEXITCODE): $($out -join ' ')" }

        $dismOk = $true

    } catch {
        Write-Host "$Tag ERROR: DISM injection into boot.wim failed — $_" -ForegroundColor Red
    } finally {
        if (-not $dismOk) {
            & "$env:SystemRoot\System32\dism.exe" /Unmount-Wim /MountDir:"$mountDir" /Discard 2>&1 | Out-Null
        }
        Remove-Item -Path $mountDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not $dismOk) { return $false }

    Write-Host "$Tag VMD driver injected into boot.wim — disk will be detected automatically during Windows setup." -ForegroundColor Green

    # ── install.wim injection (all indexes) ───────────────────────────────────
    $installWim = "${Root}sources\install.wim"
    $installEsd = "${Root}sources\install.esd"

    if (-not (Test-Path $installWim)) {
        if (Test-Path $installEsd) {
            Write-Host "$Tag WARNING: install.esd detected (MCT-created USB) — install.wim injection skipped. Boot disk detection is fixed but OS may BSOD on first boot. Recreate the USB using Rufus (see README) for full VMD support." -ForegroundColor Yellow
        } else {
            Write-Host "$Tag WARNING: install.wim not found — skipping install.wim injection." -ForegroundColor Yellow
        }
        return $true
    }

    Write-Host "$Tag Enumerating install.wim indexes..." -ForegroundColor Cyan
    $wimInfoOut = & "$env:SystemRoot\System32\dism.exe" /Get-WimInfo /WimFile:"$installWim" 2>&1
    $indexCount = ($wimInfoOut | Select-String -Pattern '^\s*Index\s*:\s*\d+').Count

    if ($indexCount -eq 0) {
        Write-Host "$Tag ERROR: Could not determine index count from install.wim." -ForegroundColor Red
        return $false
    }

    Write-Host "$Tag Found $indexCount index(es) in install.wim — injecting VMD driver into each..." -ForegroundColor Cyan

    & "$env:SystemRoot\System32\attrib.exe" -R "$installWim" 2>&1 | Out-Null
    Write-Host "$Tag Read-only attribute cleared on install.wim." -ForegroundColor DarkGray

    $installOk = $true

    for ($idx = 1; $idx -le $indexCount; $idx++) {
        $installMountDir = Join-Path $env:TEMP "InstallWimMount_$(Get-Random)"
        New-Item -ItemType Directory -Path $installMountDir -Force | Out-Null
        $idxOk = $false

        Write-Host "$Tag Processing install.wim index $idx of $indexCount..." -ForegroundColor Cyan

        try {
            $out = & "$env:SystemRoot\System32\dism.exe" /Mount-Wim /WimFile:"$installWim" /Index:$idx /MountDir:"$installMountDir" 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Mount failed (exit $LASTEXITCODE): $($out -join ' ')" }

            $out = & "$env:SystemRoot\System32\dism.exe" /Image:"$installMountDir" /Add-Driver /Driver:"$DriverDir" /Recurse 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Add-Driver failed (exit $LASTEXITCODE): $($out -join ' ')" }

            $out = & "$env:SystemRoot\System32\dism.exe" /Unmount-Wim /MountDir:"$installMountDir" /Commit 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Unmount/commit failed (exit $LASTEXITCODE): $($out -join ' ')" }

            $idxOk = $true

        } catch {
            Write-Host "$Tag ERROR: DISM injection into install.wim index $idx failed — $_" -ForegroundColor Red
            $installOk = $false
        } finally {
            if (-not $idxOk) {
                & "$env:SystemRoot\System32\dism.exe" /Unmount-Wim /MountDir:"$installMountDir" /Discard 2>&1 | Out-Null
            }
            Remove-Item -Path $installMountDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        if (-not $idxOk) { break }
    }

    if (-not $installOk) {
        Write-Host "$Tag ERROR: VMD injection into install.wim failed — see above." -ForegroundColor Red
        return $false
    }

    Write-Host "$Tag VMD driver injected into install.wim ($indexCount indexes) — installed OS will boot correctly." -ForegroundColor Green
    return $true
}

# ── Wi-Fi / BT detection and injection ────────────────────────────────────────

function Get-WiFiDriverRequired {
    param([bool]$Force = $false)
    if ($Force) {
        Write-Host "[PrepUSB] -ForceWiFi specified — injecting Wi-Fi/BT drivers regardless of detected hardware." -ForegroundColor Yellow
        return $true
    }
    Write-Host "[PrepUSB] Checking for Intel BE201 Wi-Fi 7 adapter..." -ForegroundColor Cyan
    try {
        $found = Get-WmiObject -Class Win32_PnPEntity |
                 Where-Object { $_.PNPDeviceID -match 'DEV_272B' } |
                 Select-Object -First 1
        if ($found) {
            Write-Host "[PrepUSB] Intel BE201 detected — Wi-Fi/BT driver injection required." -ForegroundColor Yellow
            return $true
        }
        Write-Host "[PrepUSB] Intel BE201 not detected — skipping Wi-Fi/BT driver injection." -ForegroundColor DarkGray
        return $false
    } catch {
        Write-Host "[PrepUSB] WARNING: Could not query PnP devices for BE201 detection — $_" -ForegroundColor Yellow
        return $false
    }
}

function Invoke-WiFiDriverInjection {
    param(
        [string]$Root,
        [string]$Tag
    )

    $stagingDir = "$env:TEMP\WiFiDriverStaging"
    if (Test-Path $stagingDir) {
        Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

    # Enumerate files from the repo tree then download each one
    $apiUrl    = 'https://api.github.com/repos/FoobyGitHub/autopilot-prep-W11/git/trees/main?recursive=1'
    $wifiFiles = $null
    try {
        $tree      = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
        $wifiFiles = $tree.tree | Where-Object { $_.type -eq 'blob' -and $_.path -like 'drivers/WiFi/*' }
    } catch {
        Write-Host "$Tag ERROR: Could not fetch Wi-Fi driver file list from GitHub — $_" -ForegroundColor Red
        Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    if (-not $wifiFiles) {
        Write-Host "$Tag ERROR: No Wi-Fi driver files found in repo at drivers/WiFi/." -ForegroundColor Red
        Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    $repoBase = 'https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main'
    Write-Host "$Tag Downloading Wi-Fi/BT driver files from repo..." -ForegroundColor Cyan

    try {
        foreach ($file in $wifiFiles) {
            $relPath = $file.path -replace '^drivers/WiFi/', ''
            $dest    = Join-Path $stagingDir ($relPath -replace '/', '\')
            $destDir = Split-Path $dest -Parent
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Invoke-WebRequest -Uri "$repoBase/$($file.path)" -OutFile $dest -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            Write-Host "$Tag   $relPath" -ForegroundColor DarkGray
        }
        Write-Host "$Tag Driver files ready." -ForegroundColor Cyan
    } catch {
        Write-Host "$Tag ERROR: Could not download Wi-Fi/BT driver files — $_" -ForegroundColor Red
        Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    # ── boot.wim injection (index 2) ──────────────────────────────────────────
    $bootWim  = "${Root}sources\boot.wim"
    $mountDir = Join-Path $env:TEMP "WimMount_$(Get-Random)"
    New-Item -ItemType Directory -Path $mountDir -Force | Out-Null
    $bootOk   = $false

    Write-Host "$Tag Injecting Wi-Fi/BT driver into boot.wim (index 2) using dism.exe..." -ForegroundColor Cyan

    try {
        & "$env:SystemRoot\System32\attrib.exe" -R "$bootWim" 2>&1 | Out-Null
        Write-Host "$Tag Read-only attribute cleared on boot.wim." -ForegroundColor DarkGray

        $out = & "$env:SystemRoot\System32\dism.exe" /Mount-Wim /WimFile:"$bootWim" /Index:2 /MountDir:"$mountDir" 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Mount failed (exit $LASTEXITCODE): $($out -join ' ')" }

        $out = & "$env:SystemRoot\System32\dism.exe" /Image:"$mountDir" /Add-Driver /Driver:"$stagingDir" /Recurse 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Add-Driver failed (exit $LASTEXITCODE): $($out -join ' ')" }

        $out = & "$env:SystemRoot\System32\dism.exe" /Unmount-Wim /MountDir:"$mountDir" /Commit 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Unmount/commit failed (exit $LASTEXITCODE): $($out -join ' ')" }

        $bootOk = $true

    } catch {
        Write-Host "$Tag ERROR: DISM injection into boot.wim failed — $_" -ForegroundColor Red
    } finally {
        if (-not $bootOk) {
            & "$env:SystemRoot\System32\dism.exe" /Unmount-Wim /MountDir:"$mountDir" /Discard 2>&1 | Out-Null
        }
        Remove-Item -Path $mountDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not $bootOk) {
        Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    # ── install.wim injection (all indexes) ───────────────────────────────────
    $installWim = "${Root}sources\install.wim"
    $installEsd = "${Root}sources\install.esd"

    if (-not (Test-Path $installWim)) {
        if (Test-Path $installEsd) {
            Write-Host "$Tag WARNING: install.esd detected (MCT-created USB) — install.wim injection skipped. Boot disk detection is fixed but OS may BSOD on first boot. Recreate the USB using Rufus (see README) for full VMD support." -ForegroundColor Yellow
        } else {
            Write-Host "$Tag WARNING: install.wim not found — skipping install.wim injection." -ForegroundColor Yellow
        }
        Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        return $true
    }

    Write-Host "$Tag Enumerating install.wim indexes for Wi-Fi/BT injection..." -ForegroundColor Cyan
    $wimInfoOut = & "$env:SystemRoot\System32\dism.exe" /Get-WimInfo /WimFile:"$installWim" 2>&1
    $indexCount = ($wimInfoOut | Select-String -Pattern '^\s*Index\s*:\s*\d+').Count

    if ($indexCount -eq 0) {
        Write-Host "$Tag ERROR: Could not determine index count from install.wim." -ForegroundColor Red
        Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    Write-Host "$Tag Found $indexCount index(es) in install.wim — injecting Wi-Fi/BT driver into each..." -ForegroundColor Cyan

    & "$env:SystemRoot\System32\attrib.exe" -R "$installWim" 2>&1 | Out-Null
    Write-Host "$Tag Read-only attribute cleared on install.wim." -ForegroundColor DarkGray

    $installOk = $true

    for ($idx = 1; $idx -le $indexCount; $idx++) {
        $installMountDir = Join-Path $env:TEMP "InstallWimMount_$(Get-Random)"
        New-Item -ItemType Directory -Path $installMountDir -Force | Out-Null
        $idxOk = $false

        Write-Host "$Tag Processing install.wim index $idx of $indexCount..." -ForegroundColor Cyan

        try {
            $out = & "$env:SystemRoot\System32\dism.exe" /Mount-Wim /WimFile:"$installWim" /Index:$idx /MountDir:"$installMountDir" 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Mount failed (exit $LASTEXITCODE): $($out -join ' ')" }

            $out = & "$env:SystemRoot\System32\dism.exe" /Image:"$installMountDir" /Add-Driver /Driver:"$stagingDir" /Recurse 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Add-Driver failed (exit $LASTEXITCODE): $($out -join ' ')" }

            $out = & "$env:SystemRoot\System32\dism.exe" /Unmount-Wim /MountDir:"$installMountDir" /Commit 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Unmount/commit failed (exit $LASTEXITCODE): $($out -join ' ')" }

            $idxOk = $true

        } catch {
            Write-Host "$Tag ERROR: DISM injection into install.wim index $idx failed — $_" -ForegroundColor Red
            $installOk = $false
        } finally {
            if (-not $idxOk) {
                & "$env:SystemRoot\System32\dism.exe" /Unmount-Wim /MountDir:"$installMountDir" /Discard 2>&1 | Out-Null
            }
            Remove-Item -Path $installMountDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        if (-not $idxOk) { break }
    }

    Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue

    if (-not $installOk) {
        Write-Host "$Tag ERROR: Wi-Fi/BT injection into install.wim failed — see above." -ForegroundColor Red
        return $false
    }

    Write-Host "$Tag Wi-Fi/BT driver injected into boot.wim and install.wim." -ForegroundColor Green
    return $true
}

function Invoke-VMDDriverInjection {
    param(
        [string]$UsbRoot
    )

    if ($ForceVMD.IsPresent) {
        Write-Host "[PrepUSB] -ForceVMD specified — injecting VMD drivers regardless of detected CPU." -ForegroundColor Yellow
        $vmdStatus = Get-CPUVMDStatus -CpuName '' -Force $true
    } else {
        Write-Host "[PrepUSB] Detecting CPU generation for VMD requirement..." -ForegroundColor Cyan
        try {
            $cpuName = (Get-WmiObject -Class Win32_Processor | Select-Object -ExpandProperty Name -First 1).Trim()
            Write-Host "[PrepUSB] CPU: $cpuName" -ForegroundColor Cyan
        } catch {
            Write-Host "[PrepUSB] ERROR: Could not read CPU info — $_" -ForegroundColor Red
            return $false
        }
        $vmdStatus = Get-CPUVMDStatus -CpuName $cpuName
    }

    if (-not $vmdStatus.NeedsVMD) {
        Write-Host "[PrepUSB] CPU does not require VMD driver — skipping injection." -ForegroundColor DarkGray
        return $true
    }

    Write-Host "[PrepUSB] $($vmdStatus.Reason)" -ForegroundColor Cyan

    $tempDir     = Join-Path $env:TEMP "AutopilotVMD_$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $repoBase    = "https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/drivers/VMD"
    $driverFiles = @('iaStorVD.cat','iaStorVD.inf','iaStorVD.sys','RstMwEventLogMsg.dll','RstMwService.exe')

    try {
        Write-Host "[PrepUSB] Downloading VMD driver files from repo..." -ForegroundColor Cyan
        foreach ($file in $driverFiles) {
            $dest = Join-Path $tempDir $file
            Invoke-WebRequest -Uri "$repoBase/$file" -OutFile $dest -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            Write-Host "[PrepUSB]   $file" -ForegroundColor DarkGray
        }
        Write-Host "[PrepUSB] Driver files ready." -ForegroundColor Cyan
    } catch {
        Write-Host "[PrepUSB] ERROR: Could not download VMD driver files — $_" -ForegroundColor Red
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    $wifiRequired = Get-WiFiDriverRequired -Force $ForceWiFi.IsPresent
    $result = Invoke-WimVmdInjection -Root $UsbRoot -DriverDir $tempDir -Tag '[PrepUSB]'
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $result) { return $false }
    if ($wifiRequired) {
        $wifiResult = Invoke-WiFiDriverInjection -Root $UsbRoot -Tag '[PrepUSB]'
        if (-not $wifiResult) { return $false }
    }
    return $true
}

# ── PrepUSB ────────────────────────────────────────────────────────────────────

function Invoke-PrepUSB {
    param(
        [string]$Drive
    )

    Write-Host "[PrepUSB] Looking for Windows 11 USB..." -ForegroundColor Cyan

    if ($Drive) {
        $Drive = $Drive.TrimEnd(':').ToUpper()
        $root = "${Drive}:\"
        if (-not (Test-IsWindows11USB -Root $root)) {
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

    # ── Write ei.cfg to force Pro edition ─────────────────────────────────────
    $eiCfgPath = "${root}sources\ei.cfg"

    if (Test-Path $eiCfgPath) {
        Write-Host "[PrepUSB] Existing ei.cfg found — overwriting." -ForegroundColor Yellow
    }

    $eiCfg = "[EditionID]`r`nProfessional`r`n[Channel]`r`n_Default`r`n[VL]`r`n0`r`n"

    try {
        Set-Content -Path $eiCfgPath -Value $eiCfg -Encoding ASCII -Force
        Write-Host "[PrepUSB] ei.cfg written — USB will install Windows 11 Pro automatically." -ForegroundColor Green
    } catch {
        Write-Host "[PrepUSB] ERROR: Could not write ei.cfg: $_" -ForegroundColor Red
        Write-Host "[PrepUSB] Ensure the USB is not write-protected and you are running as Administrator." -ForegroundColor Yellow
        return $false
    }

    # ── VMD driver detection and injection ─────────────────────────────────────
    $vmdOk = Invoke-VMDDriverInjection -UsbRoot $root
    if (-not $vmdOk) { return $false }

    return $true
}

# ── Intune upload helpers ──────────────────────────────────────────────────────

function Invoke-AutopilotGraphUpload {
    param(
        [string]$CsvPath,
        [string]$Token
    )

    $graphUrl = "https://graph.microsoft.com/beta/deviceManagement/importedWindowsAutopilotDeviceIdentities"
    $headers  = @{
        Authorization  = "Bearer $Token"
        'Content-Type' = 'application/json'
    }

    $devices = Import-Csv -Path $CsvPath
    $allOk   = $true

    foreach ($device in $devices) {
        $serial  = $device.'Device Serial Number'
        $payload = ConvertTo-Json -InputObject @{
            '@odata.type'      = '#microsoft.graph.importedWindowsAutopilotDeviceIdentity'
            orderIdentifier    = ''
            serialNumber       = $serial
            productKey         = $device.'Windows Product ID'
            hardwareIdentifier = $device.'Hardware Hash'
        }

        try {
            Invoke-RestMethod -Uri $graphUrl -Method Post -Headers $headers -Body $payload -ErrorAction Stop | Out-Null
            Write-Host "[CollectHash] Uploaded to Intune: $serial" -ForegroundColor Green
        } catch {
            Write-Host "[CollectHash] ERROR: Failed to upload $serial — $_" -ForegroundColor Red
            $allOk = $false
        }
    }

    if ($allOk) {
        Write-Host "[CollectHash] Device registered in Intune — visible under Devices > Enroll devices > Windows enrollment > Devices within 15 minutes." -ForegroundColor Green
    }
    return $allOk
}

function Get-DeviceCodeToken {
    $clientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
    $scope    = 'https://graph.microsoft.com/DeviceManagementServiceConfig.ReadWrite.All'
    $dcUrl    = 'https://login.microsoftonline.com/common/oauth2/v2.0/devicecode'
    $dcBody   = "client_id=$clientId&scope=$([Uri]::EscapeDataString($scope))"

    try {
        $dcResp = Invoke-RestMethod -Uri $dcUrl -Method Post -Body $dcBody `
                      -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
    } catch {
        Write-Host "[CollectHash] ERROR: Could not initiate device code flow — $_" -ForegroundColor Red
        return $null
    }

    $userCode   = $dcResp.user_code
    $deviceCode = $dcResp.device_code
    $interval   = [int]$dcResp.interval
    $expiresIn  = [int]$dcResp.expires_in

    Write-Host "[CollectHash] Open https://microsoft.com/devicelogin and enter code: $userCode" -ForegroundColor Cyan
    Write-Host "[CollectHash] Waiting for sign-in (expires in $expiresIn seconds)..." -ForegroundColor DarkGray

    $tokenUrl  = 'https://login.microsoftonline.com/common/oauth2/v2.0/token'
    $tokenBody = "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code" +
                 "&client_id=$clientId" +
                 "&device_code=$([Uri]::EscapeDataString($deviceCode))"

    $elapsed = 0

    while ($elapsed -lt $expiresIn) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval

        $pollErr = $null
        $errBody = $null

        try {
            $tokResp = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $tokenBody `
                           -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
            Write-Host "[CollectHash] Authentication successful." -ForegroundColor Green
            return $tokResp.access_token
        } catch {
            $pollErr = $_
            if ($pollErr.Exception.Response) {
                try {
                    $stream  = $pollErr.Exception.Response.GetResponseStream()
                    $reader  = New-Object System.IO.StreamReader($stream)
                    $errBody = $reader.ReadToEnd()
                    $reader.Dispose()
                } catch {}
            }

            if ($errBody -and $errBody -match '"authorization_pending"') {
                # User has not yet signed in — keep polling
            } elseif ($errBody -and $errBody -match '"authorization_declined"') {
                Write-Host "[CollectHash] Authentication declined by user." -ForegroundColor Red
                return $null
            } elseif ($errBody -and $errBody -match '"expired_token"') {
                Write-Host "[CollectHash] Device code expired before sign-in completed." -ForegroundColor Red
                return $null
            } else {
                if ($errBody) {
                    Write-Host "[CollectHash] ERROR during authentication: $errBody" -ForegroundColor Red
                } else {
                    Write-Host "[CollectHash] ERROR during authentication: $pollErr" -ForegroundColor Red
                }
                return $null
            }
        }
    }

    Write-Host "[CollectHash] Timed out waiting for sign-in." -ForegroundColor Red
    return $null
}

function New-CertJwtAssertion {
    param(
        [string]$TenantId,
        [string]$AppClientId,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert
    )

    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    # x5t: base64url encoding of the certificate SHA-1 hash bytes
    $x5t = ([System.Convert]::ToBase64String($Cert.GetCertHash())) -replace '\+','-' -replace '/','_' -replace '=',''

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $exp = $now + 600
    $jti = [Guid]::NewGuid().ToString()

    $headerJson  = "{`"alg`":`"RS256`",`"typ`":`"JWT`",`"x5t`":`"$x5t`"}"
    $payloadJson = "{`"aud`":`"$tokenUrl`",`"iss`":`"$AppClientId`",`"sub`":`"$AppClientId`",`"jti`":`"$jti`",`"nbf`":$now,`"exp`":$exp}"

    $headerB64  = ([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($headerJson)))  -replace '\+','-' -replace '/','_' -replace '=',''
    $payloadB64 = ([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payloadJson))) -replace '\+','-' -replace '/','_' -replace '=',''
    $sigInput   = "$headerB64.$payloadB64"
    $inputBytes = [System.Text.Encoding]::ASCII.GetBytes($sigInput)

    $privKey = $Cert.PrivateKey
    if (-not $privKey) {
        throw "Certificate '$($Cert.Thumbprint)' does not have an accessible private key. Ensure the certificate is installed with private key in the local machine cert store."
    }

    $sigBytes = $null
    if ($privKey -is [System.Security.Cryptography.RSACryptoServiceProvider]) {
        $sigBytes = $privKey.SignData($inputBytes, 'SHA256')
    } else {
        $rsa      = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Cert)
        $sigBytes = $rsa.SignData($inputBytes, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    }

    $sigB64 = ([System.Convert]::ToBase64String($sigBytes)) -replace '\+','-' -replace '/','_' -replace '=',''
    return "$sigInput.$sigB64"
}

# ── CollectHash ────────────────────────────────────────────────────────────────

function Invoke-CollectHash {
    param(
        [string]$OverridePath,
        [string]$TenantId,
        [string]$AppClientId,
        [string]$AppCertThumbprint
    )

    $useCertAuth = ($AppCertThumbprint -ne '')

    # ── Validate cert auth params ──────────────────────────────────────────────
    if ($useCertAuth -and -not $TenantId) {
        Write-Host "[CollectHash] ERROR: -AppCertThumbprint requires -TenantId." -ForegroundColor Red
        return $false
    }
    if ($useCertAuth -and -not $AppClientId) {
        Write-Host "[CollectHash] ERROR: -AppCertThumbprint requires -AppClientId." -ForegroundColor Red
        Write-Host "[CollectHash] Provide the Application (client) ID from your Entra app registration." -ForegroundColor Yellow
        return $false
    }

    # ── Determine output path ──────────────────────────────────────────────────
    if ($OverridePath) {
        $outPath = $OverridePath
        Write-Host "[CollectHash] Output path overridden: $outPath" -ForegroundColor Yellow
    } else {
        $usbRoot = Find-DataUSB
        if ($usbRoot) {
            $hashFolder = "${usbRoot}AutopilotHashes"
            New-Item -ItemType Directory -Force -Path $hashFolder | Out-Null
            $outPath = "$hashFolder\autopilot-$(hostname).csv"
            Write-Host "[CollectHash] USB detected at ${usbRoot} — saving to: $outPath" -ForegroundColor Green
        } else {
            $outPath = "C:\Users\Public\Desktop\autopilot-$(hostname).csv"
            Write-Host "[CollectHash] No separate data USB detected — saving to Public Desktop: $outPath" -ForegroundColor Yellow
            Write-Host "[CollectHash] (Insert a separate USB to save the hash there instead)" -ForegroundColor DarkGray
        }
    }

    # ── Install Get-WindowsAutopilotInfo ───────────────────────────────────────
    Write-Host "[CollectHash] Installing Get-WindowsAutopilotInfo..." -ForegroundColor Cyan

    try {
        Install-Script -Name Get-WindowsAutopilotInfo -Force -ErrorAction Stop
    } catch {
        Write-Host "[CollectHash] ERROR: Failed to install Get-WindowsAutopilotInfo: $_" -ForegroundColor Red
        Write-Host "[CollectHash] Check internet access and ensure you are running as Administrator." -ForegroundColor Yellow
        return $false
    }

    # ── Collect hash to CSV ────────────────────────────────────────────────────
    Write-Host "[CollectHash] Collecting hardware hash for $(hostname)..." -ForegroundColor Cyan

    try {
        Get-WindowsAutopilotInfo -OutputFile $outPath -ErrorAction Stop
    } catch {
        Write-Host "[CollectHash] ERROR: Get-WindowsAutopilotInfo failed: $_" -ForegroundColor Red
        return $false
    }

    if (-not (Test-Path $outPath)) {
        Write-Host "[CollectHash] ERROR: Hash file not found at $outPath after collection." -ForegroundColor Red
        return $false
    }

    Write-Host "[CollectHash] Hash saved to: $outPath" -ForegroundColor Green

    # ── Upload to Intune ───────────────────────────────────────────────────────
    if ($useCertAuth) {
        # ── Option 1: Certificate-based authentication (unattended) ───────────
        Write-Host "[CollectHash] Using certificate authentication (Option 1 — unattended)" -ForegroundColor Cyan

        $token = $null
        try {
            $cert = Get-ChildItem -Path 'Cert:\LocalMachine\My' |
                    Where-Object { $_.Thumbprint -eq $AppCertThumbprint } |
                    Select-Object -First 1
            if (-not $cert) {
                $cert = Get-ChildItem -Path 'Cert:\CurrentUser\My' |
                        Where-Object { $_.Thumbprint -eq $AppCertThumbprint } |
                        Select-Object -First 1
            }
            if (-not $cert) {
                throw "Certificate with thumbprint '$AppCertThumbprint' not found in LocalMachine\My or CurrentUser\My."
            }

            $assertion = New-CertJwtAssertion -TenantId $TenantId -AppClientId $AppClientId -Cert $cert

            $tokenUrl  = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
            $tokenBody = "grant_type=client_credentials" +
                         "&client_id=$([Uri]::EscapeDataString($AppClientId))" +
                         "&client_assertion_type=urn%3Aietf%3Aparams%3Aoauth%3Aclient-assertion-type%3Ajwt-bearer" +
                         "&client_assertion=$([Uri]::EscapeDataString($assertion))" +
                         "&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default"

            $tokResp = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $tokenBody `
                           -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
            $token = $tokResp.access_token
            Write-Host "[CollectHash] Certificate authentication successful." -ForegroundColor Green

        } catch {
            Write-Host "[CollectHash] ERROR: Certificate authentication failed — $_" -ForegroundColor Red
            return $false
        }

        return Invoke-AutopilotGraphUpload -CsvPath $outPath -Token $token

    } else {
        # ── Device code flow (default) ─────────────────────────────────────────
        $token = Get-DeviceCodeToken

        if (-not $token) {
            Write-Host "[CollectHash] Graph upload failed — CSV saved locally for manual import." -ForegroundColor Yellow
            Write-Host "[CollectHash] Import: Intune > Devices > Enroll devices > Windows enrollment > Devices > Import" -ForegroundColor DarkGray
            return $true
        }

        $uploadOk = Invoke-AutopilotGraphUpload -CsvPath $outPath -Token $token
        if (-not $uploadOk) {
            Write-Host "[CollectHash] Graph upload failed — CSV saved locally for manual import." -ForegroundColor Yellow
            Write-Host "[CollectHash] Import: Intune > Devices > Enroll devices > Windows enrollment > Devices > Import" -ForegroundColor DarkGray
        }
        return $true
    }
}

# ── PatchISO helpers ──────────────────────────────────────────────────────────

function Show-FilePickerDialog {
    [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
    $dlg        = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = 'Select Windows 11 ISO'
    $dlg.Filter = 'ISO files (*.iso)|*.iso'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dlg.FileName
    }
    return $null
}

function Show-FolderPickerDialog {
    [void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
    $dlg             = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Select output folder for patched ISO'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dlg.SelectedPath
    }
    return $null
}

function Get-ADKOscdimg {
    $paths = @(
        'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe',
        'C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
    )

    foreach ($p in $paths) { if (Test-Path $p) { return $p } }

    Write-Host "[PatchISO] Windows ADK (Deployment Tools) not found." -ForegroundColor Yellow
    Write-Host "[PatchISO] The Deployment Tools feature (~200MB) will be downloaded and installed automatically." -ForegroundColor Yellow
    Write-Host "[PatchISO] Press Ctrl+C now to cancel, or wait 10 seconds to continue..." -ForegroundColor Yellow

    for ($i = 10; $i -gt 0; $i--) {
        Write-Host "`r[PatchISO] Continuing in $i seconds..." -NoNewline
        Start-Sleep -Seconds 1
    }
    Write-Host ""

    $adkInstaller = "$env:TEMP\adksetup.exe"
    $dlState      = @{ Done = $false; Err = $null; Pct = 0 }
    $wc           = New-Object System.Net.WebClient

    $sub1 = Register-ObjectEvent -InputObject $wc -EventName DownloadProgressChanged -MessageData $dlState -Action {
        $Event.MessageData.Pct = $Event.SourceEventArgs.ProgressPercentage
    }
    $sub2 = Register-ObjectEvent -InputObject $wc -EventName DownloadFileCompleted -MessageData $dlState -Action {
        $Event.MessageData.Done = $true
        if ($Event.SourceEventArgs.Error) { $Event.MessageData.Err = $Event.SourceEventArgs.Error.Message }
    }

    $wc.DownloadFileAsync([Uri]'https://go.microsoft.com/fwlink/?linkid=2271337', $adkInstaller)

    $lastPct = -1
    while (-not $dlState.Done) {
        Start-Sleep -Milliseconds 500
        $pct = $dlState.Pct
        if ($pct -ne $lastPct) {
            $lastPct = $pct
            Write-Host "`r[PatchISO] Downloading ADK: $pct%" -NoNewline
        }
    }
    Write-Host ""

    Unregister-Event -SubscriptionId $sub1.Id -ErrorAction SilentlyContinue
    Unregister-Event -SubscriptionId $sub2.Id -ErrorAction SilentlyContinue
    Remove-Job $sub1 -Force -ErrorAction SilentlyContinue
    Remove-Job $sub2 -Force -ErrorAction SilentlyContinue
    $wc.Dispose()

    if ($dlState.Err) {
        Write-Host "[PatchISO] ERROR: ADK download failed — $($dlState.Err)" -ForegroundColor Red
        return $null
    }

    Write-Host "[PatchISO] Installing ADK Deployment Tools — this may take a few minutes..." -ForegroundColor Cyan
    $proc = Start-Process -FilePath $adkInstaller -ArgumentList '/quiet /features OptionId.DeploymentTools /norestart' -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Host "[PatchISO] ERROR: ADK installation failed (exit $($proc.ExitCode))." -ForegroundColor Red
        return $null
    }

    foreach ($p in $paths) { if (Test-Path $p) { return $p } }

    Write-Host "[PatchISO] ERROR: oscdimg.exe not found after ADK installation. Check the installation manually." -ForegroundColor Red
    return $null
}

function Invoke-PatchISO {
    # ── Select ISO ────────────────────────────────────────────────────────────
    $isoPath = Show-FilePickerDialog
    if (-not $isoPath) {
        Write-Host "[PatchISO] No ISO selected. Exiting." -ForegroundColor Yellow
        return $false
    }
    Write-Host "[PatchISO] ISO selected: $isoPath" -ForegroundColor Cyan

    # ── Locate oscdimg ────────────────────────────────────────────────────────
    $oscdimg = Get-ADKOscdimg
    if (-not $oscdimg) { return $false }

    # ── Select output folder ──────────────────────────────────────────────────
    $outputFolder = Show-FolderPickerDialog
    if (-not $outputFolder) {
        Write-Host "[PatchISO] No output folder selected. Exiting." -ForegroundColor Yellow
        return $false
    }

    # ── Mount ISO ─────────────────────────────────────────────────────────────
    Write-Host "[PatchISO] Mounting ISO..." -ForegroundColor Cyan
    try {
        $diskImg     = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
        $driveLetter = ($diskImg | Get-Volume).DriveLetter
        $mountDrive  = "${driveLetter}:\"
        Write-Host "[PatchISO] ISO mounted at ${driveLetter}:" -ForegroundColor Green
    } catch {
        Write-Host "[PatchISO] ERROR: Could not mount ISO — $_" -ForegroundColor Red
        return $false
    }

    # ── Copy to staging ───────────────────────────────────────────────────────
    $stagingRoot = "$env:TEMP\W11PatchStaging\"
    if (Test-Path $stagingRoot) {
        Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

    Write-Host "[PatchISO] Copying ISO contents to temp staging folder — this may take a few minutes..." -ForegroundColor Cyan

    & robocopy.exe $mountDrive $stagingRoot /E /COPYALL 2>&1 | Out-Null
    $rcExit = $LASTEXITCODE

    # robocopy exit codes 0-7 are success variants; 8+ are errors
    if ($rcExit -ge 8) {
        Write-Host "[PatchISO] ERROR: Robocopy failed (exit $rcExit)." -ForegroundColor Red
        Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
        Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
    Write-Host "[PatchISO] Copy complete." -ForegroundColor Cyan

    # ── Dismount ISO ──────────────────────────────────────────────────────────
    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
    Write-Host "[PatchISO] ISO dismounted." -ForegroundColor DarkGray

    # ── Inject ei.cfg ─────────────────────────────────────────────────────────
    $eiCfgPath = "${stagingRoot}sources\ei.cfg"
    $eiCfg     = "[EditionID]`r`nProfessional`r`n[Channel]`r`n_Default`r`n[VL]`r`n0`r`n"
    Set-Content -Path $eiCfgPath -Value $eiCfg -Encoding ASCII -Force
    Write-Host "[PatchISO] ei.cfg injected — USB will install Windows 11 Pro automatically." -ForegroundColor Green

    # ── Download and inject VMD drivers ───────────────────────────────────────
    $vmdTempDir  = Join-Path $env:TEMP "AutopilotVMD_$(Get-Random)"
    New-Item -ItemType Directory -Path $vmdTempDir -Force | Out-Null
    $driverOk    = $false
    $repoBase    = "https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/drivers/VMD"
    $driverFiles = @('iaStorVD.cat','iaStorVD.inf','iaStorVD.sys','RstMwEventLogMsg.dll','RstMwService.exe')

    try {
        Write-Host "[PatchISO] Downloading VMD driver files from repo..." -ForegroundColor Cyan
        foreach ($file in $driverFiles) {
            $dest = Join-Path $vmdTempDir $file
            Invoke-WebRequest -Uri "$repoBase/$file" -OutFile $dest -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
            Write-Host "[PatchISO]   $file" -ForegroundColor DarkGray
        }
        Write-Host "[PatchISO] Driver files ready." -ForegroundColor Cyan
        $driverOk = $true
    } catch {
        Write-Host "[PatchISO] ERROR: Could not download VMD driver files — $_" -ForegroundColor Red
    }

    if (-not $driverOk) {
        Remove-Item -Path $vmdTempDir  -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    $vmdOk = Invoke-WimVmdInjection -Root $stagingRoot -DriverDir $vmdTempDir -Tag '[PatchISO]'
    Remove-Item -Path $vmdTempDir -Recurse -Force -ErrorAction SilentlyContinue

    if (-not $vmdOk) {
        Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    # ── Wi-Fi/BT driver injection (if Intel BE201 detected) ───────────────────
    $wifiRequired = Get-WiFiDriverRequired -Force $ForceWiFi.IsPresent
    if ($wifiRequired) {
        $wifiOk = Invoke-WiFiDriverInjection -Root $stagingRoot -Tag '[PatchISO]'
        if (-not $wifiOk) {
            Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }
    }

    # ── Build patched ISO with oscdimg ────────────────────────────────────────
    $isoBaseName   = [System.IO.Path]::GetFileNameWithoutExtension($isoPath)
    $outputIsoPath = Join-Path $outputFolder "${isoBaseName}_patched.iso"
    $etfsboot      = "${stagingRoot}boot\etfsboot.com"
    $efisys        = "${stagingRoot}efi\microsoft\boot\efisys.bin"
    $bootData      = "2#p0,e,b$etfsboot#pEF,e,b$efisys"

    Write-Host "[PatchISO] Building patched ISO with oscdimg..." -ForegroundColor Cyan

    $oscdimgOut = & $oscdimg -m -o -u2 -udfver102 "-bootdata:$bootData" $stagingRoot $outputIsoPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[PatchISO] ERROR: oscdimg failed (exit $LASTEXITCODE): $($oscdimgOut -join ' ')" -ForegroundColor Red
        Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    Write-Host "[PatchISO] Patched ISO created: $outputIsoPath" -ForegroundColor Green
    Write-Host "[PatchISO] Burn this ISO with Rufus to create deployment USBs — no further prep needed." -ForegroundColor Cyan

    # ── Cleanup ───────────────────────────────────────────────────────────────
    Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue

    return $true
}

# ── Run ────────────────────────────────────────────────────────────────────────

$usbOk  = $true
$hashOk = $true
$isoOk  = $true

if ($PrepUSB)    { $usbOk  = Invoke-PrepUSB -Drive $DriveLetter; Write-Host "" }
if ($CollectHash){ $hashOk = Invoke-CollectHash -OverridePath $OutputPath -TenantId $TenantId -AppClientId $AppClientId -AppCertThumbprint $AppCertThumbprint; Write-Host "" }
if ($PatchISO)   { $isoOk  = Invoke-PatchISO; Write-Host "" }

Write-Host "  ─────────────────────────────────" -ForegroundColor DarkGray
if ($PrepUSB)    { Write-Host "  PrepUSB     $(if ($usbOk)  { 'Complete' } else { 'Failed' })" -ForegroundColor $(if ($usbOk)  { 'Green' } else { 'Red' }) }
if ($CollectHash){ Write-Host "  CollectHash $(if ($hashOk) { 'Complete' } else { 'Failed' })" -ForegroundColor $(if ($hashOk) { 'Green' } else { 'Red' }) }
if ($PatchISO)   { Write-Host "  PatchISO    $(if ($isoOk)  { 'Complete' } else { 'Failed' })" -ForegroundColor $(if ($isoOk)  { 'Green' } else { 'Red' }) }
Write-Host ""

if ($PrepUSB -and $usbOk) {
    Write-Host "  Next: Boot the target PC from the USB and complete the Windows 11 Pro install." -ForegroundColor Cyan
    Write-Host "        At OOBE, connect to the internet — Autopilot will take over automatically." -ForegroundColor Cyan
    Write-Host ""
}
