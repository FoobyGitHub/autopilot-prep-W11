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
    [switch]$ForceDrivers,
    [string]$DriveLetter,
    [string]$OutputPath,
    [string]$TenantId,
    [string]$AppClientId,
    [string]$AppCertThumbprint
)

$LogFile = "$env:TEMP\AutopilotSetup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param(
        [string]$Message,
        [string]$ForegroundColor = 'White'
    )
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$ts] " -ForegroundColor DarkGray -NoNewline
    Write-Host $Message -ForegroundColor $ForegroundColor
    Add-Content -Path $LogFile -Value "[$ts] $Message" -Encoding UTF8
}

# ── Execution policy ───────────────────────────────────────────────────────────
Write-Host ""
Write-Log "  Autopilot Setup Tool" -ForegroundColor Cyan
Write-Log "  Microsoft 365 Business Premium" -ForegroundColor Cyan
Write-Log "  ─────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Log "[Setup] Setting execution policy to RemoteSigned (CurrentUser)..." -ForegroundColor DarkGray

try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
    Write-Log "[Setup] Execution policy set." -ForegroundColor DarkGray
} catch {
    Write-Log "[Setup] WARNING: Could not set execution policy: $_" -ForegroundColor Yellow
    Write-Log "[Setup] Script installation from PSGallery may fail. Try running as Administrator." -ForegroundColor Yellow
}

Write-Host ""

# ── Show help if no flags ──────────────────────────────────────────────────────

if (-not $PrepUSB -and -not $CollectHash -and -not $PatchISO) {
    Write-Log "No action specified. Available flags:" -ForegroundColor Yellow
    Write-Host ""
    Write-Log "  -CollectHash                Collect hash and upload to Intune (device code sign-in — browser prompted)" -ForegroundColor White
    Write-Log "  -PrepUSB                    Inject ei.cfg and drivers into a Windows 11 USB" -ForegroundColor White
    Write-Log "  -PatchISO                   Pre-stage a Windows 11 ISO with drivers and Pro edition config — outputs a patched ISO ready to burn with Rufus" -ForegroundColor White
    Write-Log "  -DriveLetter X              Force a specific drive letter for -PrepUSB  (e.g. -DriveLetter E)" -ForegroundColor White
    Write-Log "  -OutputPath path            Override the hash CSV save location" -ForegroundColor White
    Write-Log "  -ForceDrivers               Force full driver injection (VMD, Wi-Fi/BT, Chipset, Touchpad) regardless of what is detected on this machine. Use when prepping a USB or ISO on a different PC to the one being built." -ForegroundColor White
    Write-Host ""
    Write-Log "  Option 1 — certificate authentication (unattended, no browser prompt):" -ForegroundColor DarkGray
    Write-Log "  -TenantId <id>              Azure AD tenant ID" -ForegroundColor White
    Write-Log "  -AppClientId <id>           App registration client ID" -ForegroundColor White
    Write-Log "  -AppCertThumbprint <val>    Certificate thumbprint (cert with private key in local machine store)" -ForegroundColor White
    Write-Host ""
    Write-Log "Copy and run one of these commands:" -ForegroundColor Cyan
    Write-Host ""
    Write-Log "  Collect hash + upload to Intune (device code sign-in):" -ForegroundColor DarkGray
    Write-Log "  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -CollectHash" -ForegroundColor White
    Write-Host ""
    Write-Log "  Collect hash + upload silently (certificate auth — Option 1):" -ForegroundColor DarkGray
    Write-Log "  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -CollectHash -TenantId <id> -AppClientId <id> -AppCertThumbprint <thumbprint>" -ForegroundColor White
    Write-Host ""
    Write-Log "  Prep a Windows 11 USB for Pro install (auto-detects CPU, injects drivers if needed):" -ForegroundColor DarkGray
    Write-Log "  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -PrepUSB" -ForegroundColor White
    Write-Host ""
    Write-Log "  Prep USB on drive E specifically:" -ForegroundColor DarkGray
    Write-Log "  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -PrepUSB -DriveLetter E" -ForegroundColor White
    Write-Host ""
    Write-Log "  Do both in one shot:" -ForegroundColor DarkGray
    Write-Log "  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -PrepUSB -CollectHash" -ForegroundColor White
    Write-Host ""
    Write-Log "  Pre-stage a patched ISO (file + folder pickers open automatically):" -ForegroundColor DarkGray
    Write-Log "  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main/Invoke-AutopilotSetup.ps1))) -PatchISO" -ForegroundColor White
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

# ── Driver detection ───────────────────────────────────────────────────────────

function Get-DriversRequired {
    param(
        [bool]$Force = $false,
        [string]$Tag = '[Driver]'
    )

    Write-Log "--- Get-DriversRequired started ---" -ForegroundColor DarkGray

    if ($Force) {
        Write-Log "$Tag -ForceDrivers specified — injecting all driver sets regardless of detected hardware." -ForegroundColor Yellow
        return 'all'
    }

    try {
        $cpuName = (Get-WmiObject -Class Win32_Processor | Select-Object -ExpandProperty Name -First 1).Trim()
        Write-Log "$Tag CPU: $cpuName" -ForegroundColor Cyan
    } catch {
        Write-Log "$Tag WARNING: Could not read CPU info — $_" -ForegroundColor Yellow
        return $false
    }

    # AMD / Qualcomm / ARM — no VMD or platform drivers applicable
    if ($cpuName -match '(AMD|Ryzen|EPYC|Qualcomm|Snapdragon)') {
        Write-Log "$Tag AMD/Qualcomm CPU detected — driver injection not required." -ForegroundColor DarkGray
        return $false
    }

    if ($cpuName -notmatch 'Intel') {
        Write-Log "$Tag Non-Intel CPU detected — driver injection not required." -ForegroundColor DarkGray
        return $false
    }

    # Intel Core Ultra series — model number suffix determines series
    # 100-series = Series 1 (Meteor Lake)  → VMD only
    # 200-series = Series 2 (Arrow Lake)   → all driver sets
    # 300-series = Series 3+               → no injection needed
    if ($cpuName -match 'Core\s*\(TM\)\s*Ultra\s+\d+\s+(\d{3})') {
        $series = [math]::Floor([int]$Matches[1] / 100)
        if ($series -ge 3) {
            Write-Log "$Tag Intel Core Ultra Series $series detected — driver injection not required." -ForegroundColor DarkGray
            return $false
        }
        if ($series -eq 2) {
            Write-Log "$Tag Intel Core Ultra Series 2 (Arrow Lake) detected — full driver set required." -ForegroundColor Cyan
            return 'all'
        }
        Write-Log "$Tag Intel Core Ultra Series $series (Meteor Lake) detected — VMD driver required." -ForegroundColor Cyan
        return 'vmd-only'
    }

    # Intel Core i-series (traditional generations)
    # Model number format: i7-1165G7 → 4 digits → gen 11
    #                      i9-13900K → 5 digits → gen 13
    if ($cpuName -match 'Core\s*\(TM\)\s+i\d+-(\d{4,5})') {
        $modelStr = $Matches[1]
        $gen = if ($modelStr.Length -eq 4) {
            [math]::Floor([int]$modelStr / 100)
        } else {
            [math]::Floor([int]$modelStr / 1000)
        }

        if ($gen -ge 11 -and $gen -le 14) {
            Write-Log "$Tag Intel ${gen}th gen detected — VMD driver required." -ForegroundColor Cyan
            return 'vmd-only'
        }
        Write-Log "$Tag Intel ${gen}th gen detected — driver injection not required." -ForegroundColor DarkGray
        return $false
    }

    Write-Log "$Tag Intel CPU generation unrecognised ('$cpuName') — skipping driver injection." -ForegroundColor Yellow
    return $false
}

# ── Shared DISM injection helper ───────────────────────────────────────────────

function Invoke-WimDriverSet {
    param(
        [string]$Root,
        [string]$DriverDir,
        [string]$Tag,
        [string]$Label,
        [bool]$BootWimOnly = $false,
        [bool]$InstallWimOnly = $false
    )

    Write-Log "--- Invoke-WimDriverSet started ($Label) ---" -ForegroundColor DarkGray

    # ── boot.wim injection (index 2) ──────────────────────────────────────────
    if (-not $InstallWimOnly) {
        $bootWim  = "${Root}sources\boot.wim"
        $mountDir = Join-Path $env:TEMP "WimMount_$(Get-Random)"
        New-Item -ItemType Directory -Path $mountDir -Force | Out-Null
        $bootOk = $false

        Write-Log "$Tag Injecting $Label driver into boot.wim (index 2) using dism.exe..." -ForegroundColor Cyan

        try {
            & "$env:SystemRoot\System32\attrib.exe" -R "$bootWim" 2>&1 | Out-Null
            Write-Log "$Tag Read-only attribute cleared on boot.wim." -ForegroundColor DarkGray

            $out = & "$env:SystemRoot\System32\dism.exe" /Mount-Wim /WimFile:"$bootWim" /Index:2 /MountDir:"$mountDir" 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Mount failed (exit $LASTEXITCODE): $($out -join ' ')" }

            $out = & "$env:SystemRoot\System32\dism.exe" /Image:"$mountDir" /Add-Driver /Driver:"$DriverDir" /Recurse 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Add-Driver failed (exit $LASTEXITCODE): $($out -join ' ')" }

            $out = & "$env:SystemRoot\System32\dism.exe" /Unmount-Wim /MountDir:"$mountDir" /Commit 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Unmount/commit failed (exit $LASTEXITCODE): $($out -join ' ')" }

            $bootOk = $true

        } catch {
            Write-Log "$Tag ERROR: DISM injection into boot.wim failed for $Label — $_" -ForegroundColor Red
        } finally {
            if (-not $bootOk) {
                & "$env:SystemRoot\System32\dism.exe" /Unmount-Wim /MountDir:"$mountDir" /Discard 2>&1 | Out-Null
            }
            Remove-Item -Path $mountDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        if (-not $bootOk) { return $false }

        Write-Log "$Tag $Label driver injected into boot.wim." -ForegroundColor Green
    }

    if ($BootWimOnly) { return $true }

    # ── install.wim injection (all indexes) ───────────────────────────────────
    $installWim = "${Root}sources\install.wim"
    $installEsd = "${Root}sources\install.esd"

    if (-not (Test-Path $installWim)) {
        if (Test-Path $installEsd) {
            Write-Log "$Tag WARNING: install.esd detected (MCT-created USB) — install.wim injection skipped. Boot disk detection is fixed but OS may BSOD on first boot. Recreate the USB using Rufus (see README) for full driver support." -ForegroundColor Yellow
        } else {
            Write-Log "$Tag WARNING: install.wim not found — skipping install.wim injection." -ForegroundColor Yellow
        }
        return $true
    }

    Write-Log "$Tag Enumerating install.wim indexes for $Label..." -ForegroundColor Cyan
    $wimInfoOut = & "$env:SystemRoot\System32\dism.exe" /Get-WimInfo /WimFile:"$installWim" 2>&1
    $indexCount = ($wimInfoOut | Select-String -Pattern '^\s*Index\s*:\s*\d+').Count

    if ($indexCount -eq 0) {
        Write-Log "$Tag ERROR: Could not determine index count from install.wim." -ForegroundColor Red
        return $false
    }

    Write-Log "$Tag Found $indexCount index(es) in install.wim — injecting $Label driver into each..." -ForegroundColor Cyan

    & "$env:SystemRoot\System32\attrib.exe" -R "$installWim" 2>&1 | Out-Null
    Write-Log "$Tag Read-only attribute cleared on install.wim." -ForegroundColor DarkGray

    $installOk = $true

    for ($idx = 1; $idx -le $indexCount; $idx++) {
        $installMountDir = Join-Path $env:TEMP "InstallWimMount_$(Get-Random)"
        New-Item -ItemType Directory -Path $installMountDir -Force | Out-Null
        $idxOk = $false

        Write-Log "$Tag Processing install.wim index $idx of $indexCount..." -ForegroundColor Cyan

        try {
            $out = & "$env:SystemRoot\System32\dism.exe" /Mount-Wim /WimFile:"$installWim" /Index:$idx /MountDir:"$installMountDir" 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Mount failed (exit $LASTEXITCODE): $($out -join ' ')" }

            $out = & "$env:SystemRoot\System32\dism.exe" /Image:"$installMountDir" /Add-Driver /Driver:"$DriverDir" /Recurse 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Add-Driver failed (exit $LASTEXITCODE): $($out -join ' ')" }

            $out = & "$env:SystemRoot\System32\dism.exe" /Unmount-Wim /MountDir:"$installMountDir" /Commit 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Unmount/commit failed (exit $LASTEXITCODE): $($out -join ' ')" }

            $idxOk = $true

        } catch {
            Write-Log "$Tag ERROR: DISM injection into install.wim index $idx failed for $Label — $_" -ForegroundColor Red
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
        Write-Log "$Tag ERROR: $Label injection into install.wim failed — see above." -ForegroundColor Red
        return $false
    }

    Write-Log "$Tag $Label driver injected into install.wim ($indexCount indexes)." -ForegroundColor Green
    return $true
}

# ── Driver download and injection ──────────────────────────────────────────────

function Invoke-DriverInjection {
    param(
        [string]$Root,
        [string]$Tag,
        [string]$Mode  # 'vmd-only' or 'all'
    )

    Write-Log "--- Invoke-DriverInjection started (mode: $Mode) ---" -ForegroundColor DarkGray

    $apiUrl   = 'https://api.github.com/repos/FoobyGitHub/autopilot-prep-W11/git/trees/main?recursive=1'
    $repoBase = 'https://raw.githubusercontent.com/FoobyGitHub/autopilot-prep-W11/main'

    $driverSets = if ($Mode -eq 'vmd-only') {
        @(
            @{ Name = 'VMD'; InstallWimOnly = $false }
        )
    } else {
        @(
            @{ Name = 'VMD';  InstallWimOnly = $false },
            @{ Name = 'WiFi'; InstallWimOnly = $false }
        )
    }

    Write-Log "$Tag Fetching driver file list from repo..." -ForegroundColor Cyan
    $tree = $null
    try {
        $tree = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Log "$Tag ERROR: Could not fetch driver file list from GitHub — $_" -ForegroundColor Red
        return $false
    }

    $injectionOk = $true

    foreach ($set in $driverSets) {
        $setName        = $set.Name
        $installWimOnly = $set.InstallWimOnly

        $stagingDir = Join-Path $env:TEMP "DriverStaging_${setName}_$(Get-Random)"
        if (Test-Path $stagingDir) {
            Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

        try {
            $setFiles = $tree.tree | Where-Object { $_.type -eq 'blob' -and $_.path -like "drivers/$setName/*" }

            if (-not $setFiles) {
                Write-Log "$Tag ERROR: No $setName driver files found in repo at drivers/$setName/." -ForegroundColor Red
                throw "No driver files for $setName"
            }

            Write-Log "$Tag Downloading $setName driver files from repo..." -ForegroundColor Cyan

            try {
                foreach ($file in $setFiles) {
                    $relPath = $file.path -replace "^drivers/$setName/", ''
                    $dest    = Join-Path $stagingDir ($relPath -replace '/', '\')
                    $destDir = Split-Path $dest -Parent
                    if (-not (Test-Path $destDir)) {
                        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                    }
                    Invoke-WebRequest -Uri "$repoBase/$($file.path)" -OutFile $dest -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
                    Write-Log "$Tag   $relPath" -ForegroundColor DarkGray
                }
                Write-Log "$Tag $setName driver files ready." -ForegroundColor Cyan
            } catch {
                Write-Log "$Tag ERROR: Could not download $setName driver files — $_" -ForegroundColor Red
                throw
            }

            $result = [bool](Invoke-WimDriverSet -Root $Root -DriverDir $stagingDir -Tag $Tag -Label $setName -InstallWimOnly $installWimOnly)

            if (-not $result) {
                throw "Injection failed for $setName"
            }

        } catch {
            Write-Log "$Tag ERROR: $setName driver set failed — $_" -ForegroundColor Red
            $injectionOk = $false
        } finally {
            Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    return $injectionOk
}

# ── PrepUSB ────────────────────────────────────────────────────────────────────

function Invoke-PrepUSB {
    param(
        [string]$Drive
    )

    Write-Log "--- Invoke-PrepUSB started ---" -ForegroundColor DarkGray
    Write-Log "[PrepUSB] Looking for Windows 11 USB..." -ForegroundColor Cyan

    if ($Drive) {
        $Drive = $Drive.TrimEnd(':').ToUpper()
        $root = "${Drive}:\"
        if (-not (Test-IsWindows11USB -Root $root)) {
            Write-Log "[PrepUSB] ERROR: Drive ${Drive}: does not contain Windows 11 setup files." -ForegroundColor Red
            return $false
        }
    } else {
        $found = Find-Windows11USB
        if (-not $found) {
            Write-Log "[PrepUSB] ERROR: No Windows 11 USB detected. Write the ISO to a USB first, then re-run." -ForegroundColor Red
            return $false
        }
        $Drive = $found.Name.TrimEnd(':').ToUpper()
        $root  = $found.Root
        Write-Log "[PrepUSB] Found Windows 11 USB at drive ${Drive}:" -ForegroundColor Green
    }

    # ── Write ei.cfg to force Pro edition ─────────────────────────────────────
    $eiCfgPath = "${root}sources\ei.cfg"

    if (Test-Path $eiCfgPath) {
        Write-Log "[PrepUSB] Existing ei.cfg found — overwriting." -ForegroundColor Yellow
    }

    $eiCfg = "[EditionID]`r`nProfessional`r`n[Channel]`r`n_Default`r`n[VL]`r`n0`r`n"

    try {
        Set-Content -Path $eiCfgPath -Value $eiCfg -Encoding ASCII -Force
        Write-Log "[PrepUSB] ei.cfg written — USB will install Windows 11 Pro automatically." -ForegroundColor Green
    } catch {
        Write-Log "[PrepUSB] ERROR: Could not write ei.cfg: $_" -ForegroundColor Red
        Write-Log "[PrepUSB] Ensure the USB is not write-protected and you are running as Administrator." -ForegroundColor Yellow
        return $false
    }

    # ── Driver detection and injection ─────────────────────────────────────────
    $driverMode = Get-DriversRequired -Force $ForceDrivers.IsPresent -Tag '[PrepUSB]'
    if ($driverMode) {
        $driverOk = [bool](Invoke-DriverInjection -Root $root -Tag '[PrepUSB]' -Mode $driverMode)
        if (-not $driverOk) { return $false }
    }

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
            Write-Log "[CollectHash] Uploaded to Intune: $serial" -ForegroundColor Green
        } catch {
            Write-Log "[CollectHash] ERROR: Failed to upload $serial — $_" -ForegroundColor Red
            $allOk = $false
        }
    }

    if ($allOk) {
        Write-Log "[CollectHash] Device registered in Intune — visible under Devices > Enroll devices > Windows enrollment > Devices within 15 minutes." -ForegroundColor Green
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
        Write-Log "[CollectHash] ERROR: Could not initiate device code flow — $_" -ForegroundColor Red
        return $null
    }

    $userCode   = $dcResp.user_code
    $deviceCode = $dcResp.device_code
    $interval   = [int]$dcResp.interval
    $expiresIn  = [int]$dcResp.expires_in

    Write-Log "[CollectHash] Open https://microsoft.com/devicelogin and enter code: $userCode" -ForegroundColor Cyan
    Write-Log "[CollectHash] Waiting for sign-in (expires in $expiresIn seconds)..." -ForegroundColor DarkGray

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
            Write-Log "[CollectHash] Authentication successful." -ForegroundColor Green
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
                Write-Log "[CollectHash] Authentication declined by user." -ForegroundColor Red
                return $null
            } elseif ($errBody -and $errBody -match '"expired_token"') {
                Write-Log "[CollectHash] Device code expired before sign-in completed." -ForegroundColor Red
                return $null
            } else {
                if ($errBody) {
                    Write-Log "[CollectHash] ERROR during authentication: $errBody" -ForegroundColor Red
                } else {
                    Write-Log "[CollectHash] ERROR during authentication: $pollErr" -ForegroundColor Red
                }
                return $null
            }
        }
    }

    Write-Log "[CollectHash] Timed out waiting for sign-in." -ForegroundColor Red
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

    Write-Log "--- Invoke-CollectHash started ---" -ForegroundColor DarkGray

    $useCertAuth = ($AppCertThumbprint -ne '')

    # ── Validate cert auth params ──────────────────────────────────────────────
    if ($useCertAuth -and -not $TenantId) {
        Write-Log "[CollectHash] ERROR: -AppCertThumbprint requires -TenantId." -ForegroundColor Red
        return $false
    }
    if ($useCertAuth -and -not $AppClientId) {
        Write-Log "[CollectHash] ERROR: -AppCertThumbprint requires -AppClientId." -ForegroundColor Red
        Write-Log "[CollectHash] Provide the Application (client) ID from your Entra app registration." -ForegroundColor Yellow
        return $false
    }

    # ── Determine output path ──────────────────────────────────────────────────
    if ($OverridePath) {
        $outPath = $OverridePath
        Write-Log "[CollectHash] Output path overridden: $outPath" -ForegroundColor Yellow
    } else {
        $usbRoot = Find-DataUSB
        if ($usbRoot) {
            $hashFolder = "${usbRoot}AutopilotHashes"
            New-Item -ItemType Directory -Force -Path $hashFolder | Out-Null
            $outPath = "$hashFolder\autopilot-$(hostname).csv"
            Write-Log "[CollectHash] USB detected at ${usbRoot} — saving to: $outPath" -ForegroundColor Green
        } else {
            $outPath = "C:\Users\Public\Desktop\autopilot-$(hostname).csv"
            Write-Log "[CollectHash] No separate data USB detected — saving to Public Desktop: $outPath" -ForegroundColor Yellow
            Write-Log "[CollectHash] (Insert a separate USB to save the hash there instead)" -ForegroundColor DarkGray
        }
    }

    # ── Install Get-WindowsAutopilotInfo ───────────────────────────────────────
    Write-Log "[CollectHash] Installing Get-WindowsAutopilotInfo..." -ForegroundColor Cyan

    try {
        Install-Script -Name Get-WindowsAutopilotInfo -Force -ErrorAction Stop
    } catch {
        Write-Log "[CollectHash] ERROR: Failed to install Get-WindowsAutopilotInfo: $_" -ForegroundColor Red
        Write-Log "[CollectHash] Check internet access and ensure you are running as Administrator." -ForegroundColor Yellow
        return $false
    }

    # ── Collect hash to CSV ────────────────────────────────────────────────────
    Write-Log "[CollectHash] Collecting hardware hash for $(hostname)..." -ForegroundColor Cyan

    try {
        Get-WindowsAutopilotInfo -OutputFile $outPath -ErrorAction Stop
    } catch {
        Write-Log "[CollectHash] ERROR: Get-WindowsAutopilotInfo failed: $_" -ForegroundColor Red
        return $false
    }

    if (-not (Test-Path $outPath)) {
        Write-Log "[CollectHash] ERROR: Hash file not found at $outPath after collection." -ForegroundColor Red
        return $false
    }

    Write-Log "[CollectHash] Hash saved to: $outPath" -ForegroundColor Green

    # ── Upload to Intune ───────────────────────────────────────────────────────
    if ($useCertAuth) {
        # ── Option 1: Certificate-based authentication (unattended) ───────────
        Write-Log "[CollectHash] Using certificate authentication (Option 1 — unattended)" -ForegroundColor Cyan

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
            Write-Log "[CollectHash] Certificate authentication successful." -ForegroundColor Green

        } catch {
            Write-Log "[CollectHash] ERROR: Certificate authentication failed — $_" -ForegroundColor Red
            return $false
        }

        return Invoke-AutopilotGraphUpload -CsvPath $outPath -Token $token

    } else {
        # ── Device code flow (default) ─────────────────────────────────────────
        $token = Get-DeviceCodeToken

        if (-not $token) {
            Write-Log "[CollectHash] Graph upload failed — CSV saved locally for manual import." -ForegroundColor Yellow
            Write-Log "[CollectHash] Import: Intune > Devices > Enroll devices > Windows enrollment > Devices > Import" -ForegroundColor DarkGray
            return $true
        }

        $uploadOk = Invoke-AutopilotGraphUpload -CsvPath $outPath -Token $token
        if (-not $uploadOk) {
            Write-Log "[CollectHash] Graph upload failed — CSV saved locally for manual import." -ForegroundColor Yellow
            Write-Log "[CollectHash] Import: Intune > Devices > Enroll devices > Windows enrollment > Devices > Import" -ForegroundColor DarkGray
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
    Write-Log "--- Get-ADKOscdimg started ---" -ForegroundColor DarkGray

    $paths = @(
        'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe',
        'C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
    )

    foreach ($p in $paths) { if (Test-Path $p) { return $p } }

    Write-Log "[PatchISO] Windows ADK (Deployment Tools) not found." -ForegroundColor Yellow
    Write-Log "[PatchISO] The Deployment Tools feature (~200MB) will be downloaded and installed automatically." -ForegroundColor Yellow
    Write-Log "[PatchISO] Press Ctrl+C now to cancel, or wait 10 seconds to continue..." -ForegroundColor Yellow

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
        Write-Log "[PatchISO] ERROR: ADK download failed — $($dlState.Err)" -ForegroundColor Red
        return $null
    }

    Write-Log "[PatchISO] Installing ADK Deployment Tools — this may take a few minutes..." -ForegroundColor Cyan
    Start-Process -FilePath "$env:TEMP\adksetup.exe" -ArgumentList "/quiet /features OptionId.DeploymentTools /norestart" -Wait -NoNewWindow

    foreach ($p in $paths) { if (Test-Path $p) { return $p } }

    Write-Log "[PatchISO] ERROR: oscdimg.exe not found after ADK installation. Check the installation manually." -ForegroundColor Red
    return $null
}

function Invoke-PatchISO {
    Write-Log "--- Invoke-PatchISO started ---" -ForegroundColor DarkGray

    # ── Select ISO ────────────────────────────────────────────────────────────
    $isoPath = Show-FilePickerDialog
    if (-not $isoPath) {
        Write-Log "[PatchISO] No ISO selected. Exiting." -ForegroundColor Yellow
        return $false
    }
    Write-Log "[PatchISO] ISO selected: $isoPath" -ForegroundColor Cyan

    # ── Locate oscdimg ────────────────────────────────────────────────────────
    $oscdimg = Get-ADKOscdimg
    if (-not $oscdimg) { return $false }

    # ── Select output folder ──────────────────────────────────────────────────
    $outputFolder = Show-FolderPickerDialog
    if (-not $outputFolder) {
        Write-Log "[PatchISO] No output folder selected. Exiting." -ForegroundColor Yellow
        return $false
    }

    # ── Mount ISO ─────────────────────────────────────────────────────────────
    Write-Log "[PatchISO] Mounting ISO..." -ForegroundColor Cyan
    try {
        $diskImg     = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
        $driveLetter = ($diskImg | Get-Volume).DriveLetter
        $mountDrive  = "${driveLetter}:\"
        Write-Log "[PatchISO] ISO mounted at ${driveLetter}:" -ForegroundColor Green
    } catch {
        Write-Log "[PatchISO] ERROR: Could not mount ISO — $_" -ForegroundColor Red
        return $false
    }

    # ── Copy to staging ───────────────────────────────────────────────────────
    $stagingRoot = "$env:TEMP\W11PatchStaging\"
    if (Test-Path $stagingRoot) {
        Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

    Write-Log "[PatchISO] Copying ISO contents to temp staging folder — this may take a few minutes..." -ForegroundColor Cyan

    & robocopy.exe $mountDrive $stagingRoot /E /COPYALL 2>&1 | Out-Null
    $rcExit = $LASTEXITCODE

    # robocopy exit codes 0-7 are success variants; 8+ are errors
    if ($rcExit -ge 8) {
        Write-Log "[PatchISO] ERROR: Robocopy failed (exit $rcExit)." -ForegroundColor Red
        Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
        Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }
    Write-Log "[PatchISO] Copy complete." -ForegroundColor Cyan

    # ── Dismount ISO ──────────────────────────────────────────────────────────
    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
    Write-Log "[PatchISO] ISO dismounted." -ForegroundColor DarkGray

    # ── Export Pro edition only (reduces DISM injection cycles) ───────────────
    $installWim = "${stagingRoot}sources\install.wim"
    Write-Log "[PatchISO] Detecting Windows 11 Pro edition index in install.wim..." -ForegroundColor Cyan
    try {
        $wimInfo    = & "$env:SystemRoot\System32\dism.exe" /Get-WimInfo /WimFile:"$installWim" 2>&1
        $proIndex   = $null
        $currentIdx = $null
        foreach ($line in $wimInfo) {
            if ($line -match '^\s*Index\s*:\s*(\d+)') {
                $currentIdx = $matches[1]
            }
            if ($line -match '^\s*Name\s*:\s*Windows 11 Pro\s*$' -and $currentIdx) {
                $proIndex = [int]$currentIdx
                break
            }
        }

        if ($proIndex) {
            $installWimTmp = "${stagingRoot}sources\install_pro.wim"
            Write-Log "[PatchISO] Exporting Windows 11 Pro (index $proIndex) — this may take a few minutes..." -ForegroundColor Cyan

            $out = & "$env:SystemRoot\System32\dism.exe" /Export-Image /SourceImageFile:"$installWim" /SourceIndex:$proIndex /DestinationImageFile:"$installWimTmp" /Compress:max 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "DISM Export-Image failed (exit $LASTEXITCODE): $($out -join ' ')"
            }

            Remove-Item -Path $installWim -Force -ErrorAction Stop
            Rename-Item -Path $installWimTmp -NewName 'install.wim' -ErrorAction Stop

            Write-Log "[PatchISO] Exported Windows 11 Pro (index $proIndex) — install.wim now single-edition." -ForegroundColor Green
        } else {
            Write-Log "[PatchISO] WARNING: Could not identify Windows 11 Pro index — skipping export, injecting all editions." -ForegroundColor Yellow
        }
    } catch {
        Write-Log "[PatchISO] ERROR: install.wim Pro export failed — $_" -ForegroundColor Red
        Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    # ── Inject ei.cfg ─────────────────────────────────────────────────────────
    $eiCfgPath = "${stagingRoot}sources\ei.cfg"
    $eiCfg     = "[EditionID]`r`nProfessional`r`n[Channel]`r`n_Default`r`n[VL]`r`n0`r`n"
    Set-Content -Path $eiCfgPath -Value $eiCfg -Encoding ASCII -Force
    Write-Log "[PatchISO] ei.cfg injected — USB will install Windows 11 Pro automatically." -ForegroundColor Green

    # ── Driver detection and injection ────────────────────────────────────────
    $driverMode = Get-DriversRequired -Force $ForceDrivers.IsPresent -Tag '[PatchISO]'
    if ($driverMode) {
        $driverOk = [bool](Invoke-DriverInjection -Root $stagingRoot -Tag '[PatchISO]' -Mode $driverMode)
        if (-not $driverOk) {
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

    Write-Log "[PatchISO] Building patched ISO with oscdimg..." -ForegroundColor Cyan

    $oscdimgOut = & $oscdimg -m -o -u2 -udfver102 "-bootdata:$bootData" $stagingRoot $outputIsoPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "[PatchISO] ERROR: oscdimg failed (exit $LASTEXITCODE): $($oscdimgOut -join ' ')" -ForegroundColor Red
        Remove-Item -Path $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    Write-Log "[PatchISO] Patched ISO created: $outputIsoPath" -ForegroundColor Green
    Write-Log "[PatchISO] Burn this ISO with Rufus to create deployment USBs — no further prep needed." -ForegroundColor Cyan

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

Write-Log "  ─────────────────────────────────" -ForegroundColor DarkGray
if ($PrepUSB)    { Write-Log "  PrepUSB     $(if ($usbOk)  { 'Complete' } else { 'Failed' })" -ForegroundColor $(if ($usbOk)  { 'Green' } else { 'Red' }) }
if ($CollectHash){ Write-Log "  CollectHash $(if ($hashOk) { 'Complete' } else { 'Failed' })" -ForegroundColor $(if ($hashOk) { 'Green' } else { 'Red' }) }
if ($PatchISO)   { Write-Log "  PatchISO    $(if ($isoOk)  { 'Complete' } else { 'Failed' })" -ForegroundColor $(if ($isoOk)  { 'Green' } else { 'Red' }) }
Write-Host ""

if ($PrepUSB -and $usbOk) {
    Write-Log "  Next: Boot the target PC from the USB and complete the Windows 11 Pro install." -ForegroundColor Cyan
    Write-Log "        At OOBE, connect to the internet — Autopilot will take over automatically." -ForegroundColor Cyan
    Write-Host ""
}

Write-Log "Log saved to: $LogFile" -ForegroundColor Cyan
