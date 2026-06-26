# Invoke-AutopilotHash.ps1
#
# .SYNOPSIS
#   Collects Windows Autopilot hardware hash from WinPE and uploads to Microsoft Intune.
#
# .DESCRIPTION
#   Uses oa3tool.exe and PCPKsp.dll to collect the 4K hardware hash including TPM information.
#   Uploads via Microsoft Graph API using client credentials auth. Credentials are injected at
#   USB build time — not stored in the public repo.
#
# .NOTES
#   OA3Tool-based WinPE hash collection technique adapted from Mike Meierm's blog
#   (https://mikemdm.de/2023/01/29/can-you-create-a-autopilot-hash-from-winpe-yes/) and the
#   WinPEAP project (https://github.com/blawalt/WinPEAP). This implementation is written
#   independently.
#
#   Credentials are injected by Build-WinPEUSB.ps1 via token substitution.
#   Do not edit the ##TOKEN## placeholders manually.

param(
    [switch]$Force
)

# Credentials injected at build time
$TenantId  = "##TENANTID##"
$AppId     = "##APPID##"
$AppSecret = "##APPSECRET##"
$GroupTag  = ""

$ErrorActionPreference = 'Stop'

function Write-Status {
    param(
        [string]$Message,
        [string]$ForegroundColor = 'White'
    )
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$ts] $Message" -ForegroundColor $ForegroundColor
}

Write-Host ""
Write-Status "  AutopilotPrep — WinPE Hash Upload" -ForegroundColor Cyan
Write-Status "  ────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

function Show-PostUploadMenu {
    param(
        [string]$Serial
    )

    Clear-Host
    Write-Host ""
    Write-Host ""
    Write-Status "  ════════════════════════════════════════" -ForegroundColor Green
    Write-Status "  SUCCESS — Autopilot Registration Complete" -ForegroundColor Green
    Write-Status "  ════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Status "  Serial: $Serial" -ForegroundColor White
    Write-Host ""
    Write-Status "  ────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Status "  [1] Finish — remove USB and power off" -ForegroundColor White
    Write-Status "  [2] Deploy Windows — launch OSDCloud" -ForegroundColor White
    Write-Status "  ────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Status "Press 1 or 2 to continue..." -ForegroundColor Cyan

    while ($true) {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').Character
        if ($key -eq '1') {
            Write-Host ""
            Write-Status "Remove the USB drive now. Powering off in 5 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
            & wpeutil.exe shutdown
            exit 0
        }
        if ($key -eq '2') {
            Write-Host ""
            Write-Status "Starting OSDCloud..." -ForegroundColor Cyan

            if (Get-Command -Name Start-OSDCloudGUI -ErrorAction SilentlyContinue) {
                Start-OSDCloudGUI
                exit 0
            }

            if (Get-Command -Name Start-OSDCloud -ErrorAction SilentlyContinue) {
                Write-Status "Start-OSDCloudGUI not available — falling back to Start-OSDCloud." -ForegroundColor Yellow
                Start-OSDCloud
                exit 0
            }

            Write-Status "ERROR: Neither Start-OSDCloudGUI nor Start-OSDCloud is available." -ForegroundColor Red
            Write-Status "Remove the USB drive now. Powering off in 5 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
            & wpeutil.exe shutdown
            exit 1
        }
    }
}

# ── STEP 1 — Detect WinPE ────────────────────────────────────────────────────

Write-Status "[Step 1] Checking for WinPE environment..." -ForegroundColor Cyan

if (-not (Test-Path 'X:\Windows\System32\wpeutil.exe')) {
    Write-Status "[Step 1] WARNING: Not running in WinPE — this script is intended for WinPE only." -ForegroundColor Yellow
    if (-not $Force) {
        Write-Status "[Step 1] Use -Force to bypass this check for testing purposes." -ForegroundColor Yellow
        exit 1
    }
    Write-Status "[Step 1] -Force specified — continuing outside WinPE." -ForegroundColor Yellow
} else {
    Write-Status "[Step 1] WinPE environment confirmed." -ForegroundColor Green
}

# ── STEP 2 — Register PCPKsp.dll ─────────────────────────────────────────────

Write-Host ""
Write-Status "[Step 2] Setting up PCPKsp.dll for TPM support..." -ForegroundColor Cyan

$pcpSource = Join-Path $PSScriptRoot 'PCPKsp.dll'
$pcpDest   = 'X:\Windows\System32\PCPKsp.dll'

if (-not (Test-Path $pcpSource)) {
    Write-Status "[Step 2] WARNING: PCPKsp.dll not found at $pcpSource — TPM information will be missing from hash." -ForegroundColor Yellow
} else {
    try {
        Copy-Item -Path $pcpSource -Destination $pcpDest -Force -ErrorAction Stop
        Write-Status "[Step 2] PCPKsp.dll copied to $pcpDest." -ForegroundColor DarkGray
    } catch {
        Write-Status "[Step 2] WARNING: Could not copy PCPKsp.dll — $_" -ForegroundColor Yellow
    }

    if (Test-Path $pcpDest) {
        try {
            $regOut  = & rundll32.exe $pcpDest,DllInstall 2>&1
            Write-Status "[Step 2] PCPKsp.dll registered." -ForegroundColor Green
        } catch {
            Write-Status "[Step 2] WARNING: rundll32 registration returned an error — $_" -ForegroundColor Yellow
        }
    }
}

# ── STEP 3 — Run oa3tool ─────────────────────────────────────────────────────

Write-Host ""
Write-Status "[Step 3] Running oa3tool to collect hardware hash..." -ForegroundColor Cyan

$oa3xml    = Join-Path $PSScriptRoot 'OA3.xml'
$oa3tool   = Join-Path $PSScriptRoot 'oa3tool.exe'
$oa3cfg    = Join-Path $PSScriptRoot 'oa3.cfg'

if (Test-Path $oa3xml) {
    Remove-Item -Path $oa3xml -Force -ErrorAction SilentlyContinue
    Write-Status "[Step 3] Removed existing OA3.xml." -ForegroundColor DarkGray
}

if (-not (Test-Path $oa3tool)) {
    Write-Status "[Step 3] ERROR: oa3tool.exe not found at $oa3tool — cannot collect hash." -ForegroundColor Red
    exit 1
}

$oa3Out  = & $oa3tool /Report /ConfigFile="$oa3cfg" /NoKeyCheck 2>&1
$oa3Exit = $LASTEXITCODE

if ($oa3Exit -ne 0) {
    Write-Status "[Step 3] WARNING: oa3tool exited with code $oa3Exit." -ForegroundColor Yellow
    Write-Status "[Step 3] Output: $($oa3Out -join ' ')" -ForegroundColor DarkGray
} else {
    Write-Status "[Step 3] oa3tool completed successfully." -ForegroundColor Green
}

# ── STEP 4 — Read and validate hash ──────────────────────────────────────────

Write-Host ""
Write-Status "[Step 4] Reading hardware hash from OA3.xml..." -ForegroundColor Cyan

if (-not (Test-Path $oa3xml)) {
    Write-Status "[Step 4] ERROR: oa3tool did not produce OA3.xml — cannot continue." -ForegroundColor Red
    exit 1
}

try {
    [xml]$xml  = Get-Content -Path $oa3xml -ErrorAction Stop
    $hash      = $xml.Key.HardwareHash
} catch {
    Write-Status "[Step 4] ERROR: Could not parse OA3.xml — $_" -ForegroundColor Red
    Remove-Item -Path $oa3xml -Force -ErrorAction SilentlyContinue
    exit 1
}

try {
    $serial = (Get-WmiObject -Class Win32_BIOS -ErrorAction Stop).SerialNumber
} catch {
    Write-Status "[Step 4] ERROR: Could not read serial number from WMI — $_" -ForegroundColor Red
    Remove-Item -Path $oa3xml -Force -ErrorAction SilentlyContinue
    exit 1
}

if (-not $hash -or $hash.Trim() -eq '') {
    Write-Status "[Step 4] ERROR: HardwareHash value is empty — oa3tool may have failed silently." -ForegroundColor Red
    Remove-Item -Path $oa3xml -Force -ErrorAction SilentlyContinue
    exit 1
}

if (-not $serial -or $serial.Trim() -eq '') {
    Write-Status "[Step 4] ERROR: Serial number is empty — cannot upload without a serial number." -ForegroundColor Red
    Remove-Item -Path $oa3xml -Force -ErrorAction SilentlyContinue
    exit 1
}

Remove-Item -Path $oa3xml -Force -ErrorAction SilentlyContinue

Write-Status "[Step 4] Serial number : $serial" -ForegroundColor Green
Write-Status "[Step 4] Hash length   : $($hash.Length) characters" -ForegroundColor Green

# ── CSV backup — write hash locally before attempting upload ──────────────────

Write-Host ""
Write-Status "[CSV] Writing local CSV backup..." -ForegroundColor Cyan

$csvDir = $null
# Try to find a writable USB partition (not X: which is the WinPE ramdisk)
$drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $_.Root -ne 'X:\' -and $_.Free -gt 0 }
if ($drives) {
    $csvDir = $drives[0].Root
} else {
    $csvDir = 'X:\Windows\Temp'
}

$csvPath = Join-Path $csvDir "AutopilotHash_$serial.csv"

if ($GroupTag -ne '') {
    $csvHeader = '"Device Serial Number","Windows Product ID","Hardware Hash","Group Tag"'
    $csvRow    = """$serial"","""",""$hash"",""$GroupTag"""
} else {
    $csvHeader = '"Device Serial Number","Windows Product ID","Hardware Hash"'
    $csvRow    = """$serial"","""",""$hash"""
}

try {
    Set-Content -Path $csvPath -Value "$csvHeader`r`n$csvRow" -Encoding ASCII -Force -ErrorAction Stop
    Write-Status "[CSV] Backup CSV written to: $csvPath" -ForegroundColor Green
    Write-Status "[CSV] If upload fails, this file can be imported manually into Intune." -ForegroundColor DarkGray
} catch {
    Write-Status "[CSV] WARNING: Could not write CSV backup — $_" -ForegroundColor Yellow
    Write-Status "[CSV] Continuing with upload attempt." -ForegroundColor DarkGray
}

# ── STEP 5 — Get auth token ───────────────────────────────────────────────────

Write-Host ""
Write-Status "[Step 5] Acquiring access token from Azure AD..." -ForegroundColor Cyan

$tokenUrl  = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
$tokenBody = "grant_type=client_credentials" +
             "&client_id=$([Uri]::EscapeDataString($AppId))" +
             "&client_secret=$([Uri]::EscapeDataString($AppSecret))" +
             "&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default"

$token = $null
try {
    $tokenResp = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $tokenBody `
                     -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing -ErrorAction Stop
    $token = $tokenResp.access_token
    Write-Status "[Step 5] Token acquired." -ForegroundColor Green
} catch {
    $statusCode = $null
    if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
    if ($statusCode) {
        Write-Status "[Step 5] ERROR: Token request failed with HTTP $statusCode — $_" -ForegroundColor Red
    } else {
        Write-Status "[Step 5] ERROR: Token request failed — $_" -ForegroundColor Red
    }
    exit 1
}

$authHeader = @{
    Authorization  = "Bearer $token"
    'Content-Type' = 'application/json'
}

# ── STEP 6 — Check if device already exists in Autopilot ─────────────────────

Write-Host ""
Write-Status "[Step 6] Checking whether device is already registered in Autopilot..." -ForegroundColor Cyan

$serialEncoded  = [Uri]::EscapeDataString($serial)
$existingUrl    = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=contains(serialNumber,'$serialEncoded')"

try {
    $existingResp = Invoke-RestMethod -Uri $existingUrl -Method Get -Headers $authHeader `
                        -UseBasicParsing -ErrorAction Stop

    if ($existingResp.value.Count -gt 0) {
        foreach ($existing in $existingResp.value) {
            if ($existing.serialNumber -eq $serial) {
                Write-Status "[Step 6] Device already registered in Autopilot (serial: $serial) — skipping upload." -ForegroundColor Yellow
                exit 0
            }
        }
    }
    Write-Status "[Step 6] Device not yet registered — proceeding with upload." -ForegroundColor DarkGray
} catch {
    Write-Status "[Step 6] WARNING: Could not check existing registrations — $_. Proceeding with upload." -ForegroundColor Yellow
}

# ── STEP 7 — Upload hash to Autopilot ────────────────────────────────────────

Write-Host ""
Write-Status "[Step 7] Uploading hardware hash to Microsoft Intune..." -ForegroundColor Cyan

$uploadUrl = 'https://graph.microsoft.com/v1.0/deviceManagement/importedWindowsAutopilotDeviceIdentities'

$uploadBodyObj = @{
    serialNumber       = $serial
    hardwareIdentifier = $hash
}

if ($GroupTag -ne '') {
    $uploadBodyObj.groupTag = $GroupTag
}

$uploadBody = $uploadBodyObj | ConvertTo-Json

$importId = $null
try {
    $uploadResp = Invoke-RestMethod -Uri $uploadUrl -Method Post -Headers $authHeader `
                      -Body $uploadBody -UseBasicParsing -ErrorAction Stop
    $importId   = $uploadResp.id
    Write-Status "[Step 7] Upload submitted — import ID: $importId" -ForegroundColor Green
} catch {
    $statusCode = $null
    if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
    if ($statusCode) {
        Write-Status "[Step 7] ERROR: Upload failed with HTTP $statusCode — $_" -ForegroundColor Red
    } else {
        Write-Status "[Step 7] ERROR: Upload failed — $_" -ForegroundColor Red
    }
    exit 1
}

# ── STEP 8 — Poll for completion ──────────────────────────────────────────────

Write-Host ""
Write-Status "[Step 8] Polling for import completion (up to 5 minutes)..." -ForegroundColor Cyan

$pollUrl    = "https://graph.microsoft.com/v1.0/deviceManagement/importedWindowsAutopilotDeviceIdentities/$importId"
$maxRetries = 20
$attempt    = 0

while ($attempt -lt $maxRetries) {
    $attempt++
    Start-Sleep -Seconds 15

    try {
        $pollResp = Invoke-RestMethod -Uri $pollUrl -Method Get -Headers $authHeader `
                        -UseBasicParsing -ErrorAction Stop
        $status   = $pollResp.state.deviceImportStatus

        Write-Status "[Step 8] Attempt $attempt / $maxRetries — status: $status" -ForegroundColor DarkGray

        if ($status -eq 'complete') {
            Write-Host ""
            Write-Status "  ────────────────────────────────────────" -ForegroundColor DarkGray
            Write-Status "  SUCCESS — Device registered in Autopilot" -ForegroundColor Green
            Write-Status "  Serial      : $serial" -ForegroundColor White
            Write-Status "  Import ID   : $importId" -ForegroundColor White
            Write-Status "  ────────────────────────────────────────" -ForegroundColor DarkGray
            Write-Host ""
            Show-PostUploadMenu -Serial $serial
        }

        if ($status -eq 'error') {
            $errCode = $pollResp.state.deviceErrorCode
            $errName = $pollResp.state.deviceErrorName
            Write-Status "[Step 8] ERROR: Import failed — code: $errCode, name: $errName" -ForegroundColor Red
            exit 1
        }

    } catch {
        Write-Status "[Step 8] WARNING: Poll request failed on attempt $attempt — $_" -ForegroundColor Yellow
    }
}

Write-Status "[Step 8] ERROR: Import did not complete within the expected time. Check Intune for status." -ForegroundColor Red
exit 1
