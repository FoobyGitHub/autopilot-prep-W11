# New-AutopilotAppRegistration.ps1
#
# .SYNOPSIS
#   Creates or validates the Entra app registration for AutopilotPrep WinPE hash upload.
#
# .DESCRIPTION
#   Sets up a single-tenant app registration with DeviceManagementServiceConfig.ReadWrite.All
#   permission. Outputs credentials to autopilot-appreg.config for use by Build-WinPEUSB.ps1.
#   Requires Global Administrator or Application Administrator + Intune Administrator.
#
# .NOTES
#   Credentials written to autopilot-appreg.config are sensitive. This file is automatically
#   added to .gitignore. Do not share or commit it. The client secret expires after 90 days —
#   re-run this script and rebuild the USB to rotate.
#
# Run from an elevated PowerShell prompt:
#
#   .\New-AutopilotAppRegistration.ps1

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Status {
    param(
        [string]$Message,
        [string]$ForegroundColor = 'White'
    )
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$ts] " -ForegroundColor DarkGray -NoNewline
    Write-Host $Message -ForegroundColor $ForegroundColor
}

# ── Microsoft.Graph.Authentication module ─────────────────────────────────────

Write-Host ""
Write-Status "  AutopilotPrep — Entra App Registration" -ForegroundColor Cyan
Write-Status "  ────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

Write-Status "[Setup] Checking for Microsoft.Graph.Authentication module..." -ForegroundColor DarkGray

if (-not (Get-Module -ListAvailable -Name 'Microsoft.Graph.Authentication')) {
    Write-Status "[Setup] Module not found — installing from PSGallery (CurrentUser scope)..." -ForegroundColor Yellow
    try {
        Install-Module -Name 'Microsoft.Graph.Authentication' -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Write-Status "[Setup] Module installed." -ForegroundColor Green
    } catch {
        Write-Status "[Setup] ERROR: Could not install Microsoft.Graph.Authentication — $_" -ForegroundColor Red
        Write-Status "[Setup] Run: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Status "[Setup] Microsoft.Graph.Authentication module found." -ForegroundColor DarkGray
}

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

# ── Interactive sign-in ────────────────────────────────────────────────────────

Write-Status "[Auth] Connecting to Microsoft Graph — a browser window will open for sign-in..." -ForegroundColor Cyan

try {
    Connect-MgGraph -Scopes "Application.ReadWrite.All","AppRoleAssignment.ReadWrite.All","Directory.ReadWrite.All" -ErrorAction Stop
    Write-Status "[Auth] Connected." -ForegroundColor Green
} catch {
    Write-Status "[Auth] ERROR: Could not connect to Microsoft Graph — $_" -ForegroundColor Red
    exit 1
}

# ── STEP 1 — Get tenant info ───────────────────────────────────────────────────

Write-Host ""
Write-Status "[Step 1] Retrieving tenant information..." -ForegroundColor Cyan

try {
    $orgResp = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization' -ErrorAction Stop
    $TenantId = $orgResp.value[0].id
    Write-Status "[Step 1] Tenant ID: $TenantId" -ForegroundColor Green
} catch {
    Write-Status "[Step 1] ERROR: Could not retrieve tenant information — $_" -ForegroundColor Red
    exit 1
}

# ── STEP 2 — Check if app registration already exists ─────────────────────────

$AppDisplayName = 'AutopilotPrep-HashUpload'

Write-Host ""
Write-Status "[Step 2] Checking for existing app registration '$AppDisplayName'..." -ForegroundColor Cyan

$appObjectId = $null
$appId       = $null

try {
    $filter  = [Uri]::EscapeDataString("displayName eq '$AppDisplayName'")
    $appResp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=$filter" -ErrorAction Stop

    if ($appResp.value.Count -gt 0) {
        $existingApp = $appResp.value[0]
        $appObjectId = $existingApp.id
        $appId       = $existingApp.appId
        Write-Status "[Step 2] App registration already exists — skipping creation." -ForegroundColor Yellow
        Write-Status "[Step 2]   Object ID : $appObjectId" -ForegroundColor DarkGray
        Write-Status "[Step 2]   App ID    : $appId" -ForegroundColor DarkGray
    } else {
        Write-Status "[Step 2] No existing registration found — will create." -ForegroundColor DarkGray
    }
} catch {
    Write-Status "[Step 2] ERROR: Could not query app registrations — $_" -ForegroundColor Red
    exit 1
}

# ── STEP 3 — Create app registration if it does not exist ─────────────────────

if (-not $appObjectId) {
    Write-Host ""
    Write-Status "[Step 3] Creating app registration '$AppDisplayName'..." -ForegroundColor Cyan

    $createBody = @{
        displayName    = $AppDisplayName
        signInAudience = 'AzureADMyOrg'
    } | ConvertTo-Json

    try {
        $createResp = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/applications' `
                          -Body $createBody -ContentType 'application/json' -ErrorAction Stop
        $appObjectId = $createResp.id
        $appId       = $createResp.appId
        Write-Status "[Step 3] App registration created." -ForegroundColor Green
        Write-Status "[Step 3]   Object ID : $appObjectId" -ForegroundColor DarkGray
        Write-Status "[Step 3]   App ID    : $appId" -ForegroundColor DarkGray
    } catch {
        Write-Status "[Step 3] ERROR: Could not create app registration — $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Status "[Step 3] Skipped — app already exists." -ForegroundColor DarkGray
}

# ── STEP 4 — Set API permissions ──────────────────────────────────────────────

$GraphResourceAppId = '00000003-0000-0000-c000-000000000000'
$DevMgmtRoleId      = '5ac13192-7ace-4fcf-b828-1a26f28068ee'

Write-Host ""
Write-Status "[Step 4] Checking API permissions on app registration..." -ForegroundColor Cyan

try {
    $appDetail = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/applications/$appObjectId" -ErrorAction Stop

    $alreadySet = $false
    if ($appDetail.requiredResourceAccess) {
        foreach ($rra in $appDetail.requiredResourceAccess) {
            if ($rra.resourceAppId -eq $GraphResourceAppId) {
                foreach ($ra in $rra.resourceAccess) {
                    if ($ra.id -eq $DevMgmtRoleId -and $ra.type -eq 'Role') {
                        $alreadySet = $true
                    }
                }
            }
        }
    }

    if ($alreadySet) {
        Write-Status "[Step 4] DeviceManagementServiceConfig.ReadWrite.All permission already set — skipping." -ForegroundColor DarkGray
    } else {
        Write-Status "[Step 4] Adding DeviceManagementServiceConfig.ReadWrite.All application permission..." -ForegroundColor Cyan

        $patchBody = @{
            requiredResourceAccess = @(
                @{
                    resourceAppId  = $GraphResourceAppId
                    resourceAccess = @(
                        @{
                            id   = $DevMgmtRoleId
                            type = 'Role'
                        }
                    )
                }
            )
        } | ConvertTo-Json -Depth 5

        Invoke-MgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/applications/$appObjectId" `
            -Body $patchBody -ContentType 'application/json' -ErrorAction Stop | Out-Null

        Write-Status "[Step 4] Permission added." -ForegroundColor Green
    }
} catch {
    Write-Status "[Step 4] ERROR: Could not set API permissions — $_" -ForegroundColor Red
    exit 1
}

# ── STEP 5 — Grant admin consent ──────────────────────────────────────────────

Write-Host ""
Write-Status "[Step 5] Granting admin consent for application permission..." -ForegroundColor Cyan

# Get or create service principal for our app
$ourSpId = $null
try {
    $spFilter  = [Uri]::EscapeDataString("appId eq '$appId'")
    $spResp    = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$spFilter" -ErrorAction Stop

    if ($spResp.value.Count -gt 0) {
        $ourSpId = $spResp.value[0].id
        Write-Status "[Step 5] Service principal exists: $ourSpId" -ForegroundColor DarkGray
    } else {
        Write-Status "[Step 5] Creating service principal for the app..." -ForegroundColor Cyan
        $spBody    = @{ appId = $appId } | ConvertTo-Json
        $spCreated = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/servicePrincipals' `
                         -Body $spBody -ContentType 'application/json' -ErrorAction Stop
        $ourSpId   = $spCreated.id
        Write-Status "[Step 5] Service principal created: $ourSpId" -ForegroundColor Green
    }
} catch {
    Write-Status "[Step 5] ERROR: Could not get or create service principal — $_" -ForegroundColor Red
    exit 1
}

# Get Microsoft Graph service principal id
$graphSpId = $null
try {
    $graphFilter = [Uri]::EscapeDataString("appId eq '$GraphResourceAppId'")
    $graphSpResp = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$graphFilter" -ErrorAction Stop
    if ($graphSpResp.value.Count -eq 0) {
        Write-Status "[Step 5] ERROR: Could not find Microsoft Graph service principal in this tenant." -ForegroundColor Red
        exit 1
    }
    $graphSpId = $graphSpResp.value[0].id
    Write-Status "[Step 5] Microsoft Graph SP ID: $graphSpId" -ForegroundColor DarkGray
} catch {
    Write-Status "[Step 5] ERROR: Could not retrieve Microsoft Graph service principal — $_" -ForegroundColor Red
    exit 1
}

# Check if role is already assigned
$roleAssigned = $false
try {
    $assignmentsResp = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$ourSpId/appRoleAssignments" -ErrorAction Stop

    foreach ($assignment in $assignmentsResp.value) {
        if ($assignment.appRoleId -eq $DevMgmtRoleId -and $assignment.resourceId -eq $graphSpId) {
            $roleAssigned = $true
        }
    }
} catch {
    Write-Status "[Step 5] WARNING: Could not check existing role assignments — will attempt to assign anyway." -ForegroundColor Yellow
}

if ($roleAssigned) {
    Write-Status "[Step 5] Admin consent already granted — skipping." -ForegroundColor DarkGray
} else {
    try {
        $assignBody = @{
            principalId = $ourSpId
            resourceId  = $graphSpId
            appRoleId   = $DevMgmtRoleId
        } | ConvertTo-Json

        Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$ourSpId/appRoleAssignments" `
            -Body $assignBody -ContentType 'application/json' -ErrorAction Stop | Out-Null

        Write-Status "[Step 5] Admin consent granted." -ForegroundColor Green
    } catch {
        Write-Status "[Step 5] ERROR: Could not grant admin consent — $_" -ForegroundColor Red
        Write-Status "[Step 5] You may need to grant consent manually in Entra: App registrations > $AppDisplayName > API permissions > Grant admin consent." -ForegroundColor Yellow
        exit 1
    }
}

# ── STEP 6 — Create or rotate client secret ───────────────────────────────────

Write-Host ""
$createSecret = Read-Host "[Step 6] Create a new client secret? (Y/N) - this will invalidate any existing USB builds"

$secretText   = $null
$secretExpiry = $null

if ($createSecret -match '^[Yy]') {
    Write-Status "[Step 6] Creating client secret (valid 90 days)..." -ForegroundColor Cyan

    $expiry    = (Get-Date).ToUniversalTime().AddDays(90).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $secretBody = @{
        passwordCredential = @{
            displayName = 'AutopilotPrep-WinPE'
            endDateTime = $expiry
        }
    } | ConvertTo-Json -Depth 3

    try {
        $secretResp   = Invoke-MgGraphRequest -Method POST `
                            -Uri "https://graph.microsoft.com/v1.0/applications/$appObjectId/addPassword" `
                            -Body $secretBody -ContentType 'application/json' -ErrorAction Stop
        $secretText   = $secretResp.secretText
        $secretExpiry = $expiry
        Write-Status "[Step 6] Secret created — expiry: $secretExpiry" -ForegroundColor Green
        Write-Status "[Step 6] This value is shown once only and will be written to autopilot-appreg.config." -ForegroundColor Yellow
    } catch {
        Write-Status "[Step 6] ERROR: Could not create client secret — $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Status "[Step 6] Skipped. You must supply the secret from a previous run or existing config file." -ForegroundColor Yellow
    $configPath = Join-Path $ScriptDir 'autopilot-appreg.config'
    if (Test-Path $configPath) {
        Write-Status "[Step 6] Existing config found at $configPath — reading stored values." -ForegroundColor DarkGray
        $existingLines = Get-Content $configPath
        foreach ($line in $existingLines) {
            if ($line -match '^AppSecret=(.+)$') { $secretText   = $Matches[1] }
            if ($line -match '^SecretExpiry=(.+)$') { $secretExpiry = $Matches[1] }
        }
        if (-not $secretText) {
            Write-Status "[Step 6] WARNING: Could not find AppSecret in existing config — config will be incomplete." -ForegroundColor Yellow
        }
    } else {
        Write-Status "[Step 6] WARNING: No existing config found. Config file will be written without a secret." -ForegroundColor Yellow
    }
}

# ── STEP 7 — Write config file ────────────────────────────────────────────────

Write-Host ""
Write-Status "[Step 7] Writing autopilot-appreg.config..." -ForegroundColor Cyan

$configPath  = Join-Path $ScriptDir 'autopilot-appreg.config'
$today       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

$configLines = @(
    "TenantId=$TenantId"
    "AppId=$appId"
    "AppSecret=$secretText"
    "SecretExpiry=$secretExpiry"
    "CreatedDate=$today"
)

try {
    Set-Content -Path $configPath -Value $configLines -Encoding UTF8 -Force
    Write-Status "[Step 7] Config written to: $configPath" -ForegroundColor Green
} catch {
    Write-Status "[Step 7] ERROR: Could not write config file — $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Status "[Step 7] WARNING: autopilot-appreg.config contains sensitive credentials." -ForegroundColor Yellow
Write-Status "[Step 7]          Do not commit, share, or store this file insecurely." -ForegroundColor Yellow

# Add to .gitignore
$gitignorePath = Join-Path $ScriptDir '.gitignore'
$configEntry   = 'autopilot-appreg.config'

if (Test-Path $gitignorePath) {
    $gitignoreContent = Get-Content $gitignorePath -Raw
    if ($gitignoreContent -notmatch [Regex]::Escape($configEntry)) {
        Add-Content -Path $gitignorePath -Value "`n$configEntry" -Encoding UTF8
        Write-Status "[Step 7] '$configEntry' added to existing .gitignore." -ForegroundColor Green
    } else {
        Write-Status "[Step 7] '$configEntry' is already listed in .gitignore." -ForegroundColor DarkGray
    }
} else {
    Set-Content -Path $gitignorePath -Value $configEntry -Encoding UTF8
    Write-Status "[Step 7] .gitignore created and '$configEntry' added." -ForegroundColor Green
}

# ── STEP 8 — Summary ──────────────────────────────────────────────────────────

Write-Host ""
Write-Status "  ────────────────────────────────────────" -ForegroundColor DarkGray
Write-Status "  Summary" -ForegroundColor Cyan
Write-Status "  ────────────────────────────────────────" -ForegroundColor DarkGray
Write-Status "  Tenant ID     : $TenantId" -ForegroundColor White
Write-Status "  App ID        : $appId" -ForegroundColor White
Write-Status "  Secret expiry : $secretExpiry" -ForegroundColor White
Write-Status "  Config file   : $configPath" -ForegroundColor White
Write-Status "  ────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Status "  Run Build-WinPEUSB.ps1 to build the bootable USB using these credentials." -ForegroundColor Cyan
Write-Host ""
