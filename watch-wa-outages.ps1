param(
    [int]$Threshold = 10000,
    [int]$IntervalSeconds = 300,
    [string]$Url = "https://poweroutage.us/area/state/washington",
    [string]$StateFile = "",
    [string]$StatusFile = "",
    [string]$WebhookUrl = "",
    [switch]$Once
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($StateFile)) {
    $StateFile = Join-Path -Path $PSScriptRoot -ChildPath "wa-monitor-state.json"
}

if ([string]::IsNullOrWhiteSpace($StatusFile)) {
    $StatusFile = Join-Path -Path $PSScriptRoot -ChildPath "app\status.json"
}

function Get-State {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{
            lastCount = $null
            lastAlertCount = $null
            lastAlertAt = $null
        }
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw
        $parsed = $raw | ConvertFrom-Json
        return @{
            lastCount = if ($null -ne $parsed.lastCount) { [int]$parsed.lastCount } else { $null }
            lastAlertCount = if ($null -ne $parsed.lastAlertCount) { [int]$parsed.lastAlertCount } else { $null }
            lastAlertAt = $parsed.lastAlertAt
        }
    }
    catch {
        Write-Warning "Could not read state file at '$Path'. Starting with a clean state."
        return @{
            lastCount = $null
            lastAlertCount = $null
            lastAlertAt = $null
        }
    }
}

function Save-State {
    param(
        [string]$Path,
        [hashtable]$State
    )

    $json = [pscustomobject]@{
        lastCount = $State.lastCount
        lastAlertCount = $State.lastAlertCount
        lastAlertAt = $State.lastAlertAt
    } | ConvertTo-Json

    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Save-Status {
    param(
        [string]$Path,
        [pscustomobject]$Snapshot,
        [int]$ThresholdValue,
        [hashtable]$State
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $payload = [pscustomobject]@{
        state = "Washington"
        customersOut = $Snapshot.Count
        threshold = $ThresholdValue
        status = if ($Snapshot.Count -ge $ThresholdValue) { "alert" } else { "normal" }
        sourceUpdated = $Snapshot.UpdatedText
        checkedAt = $Snapshot.CheckedAt
        sourceUrl = $Snapshot.SourceUrl
        lastAlertAt = $State.lastAlertAt
        lastAlertCount = $State.lastAlertCount
    } | ConvertTo-Json

    Set-Content -LiteralPath $Path -Value $payload -Encoding UTF8
}

function Get-OutageSnapshot {
    param(
        [string]$PageUrl
    )

    $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"
    $curlCommand = if (Get-Command "curl.exe" -ErrorAction SilentlyContinue) { "curl.exe" } else { "curl" }
    $curlArgs = @(
        "--silent",
        "--show-error",
        "--location",
        "--max-time", "30",
        "--user-agent", $userAgent,
        "--header", "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "--header", "Accept-Language: en-US,en;q=0.9",
        "--header", "Cache-Control: no-cache",
        "--header", "Pragma: no-cache",
        $PageUrl
    )

    $content = & $curlCommand @curlArgs
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($content)) {
        throw "$curlCommand could not fetch $PageUrl"
    }

    $countPatterns = @(
        '(?is)"name"\s*:\s*"Current Outages"\s*,\s*"value"\s*:\s*([0-9,]+)',
        '(?is)Right now,\s*<strong>\s*([0-9,]+)\s*</strong>\s*homes and businesses',
        '(?is)Customers Out\s*([0-9,]+)'
    )

    $count = $null
    foreach ($pattern in $countPatterns) {
        $countMatch = [regex]::Match($content, $pattern)
        if ($countMatch.Success) {
            $count = [int]($countMatch.Groups[1].Value -replace ",", "")
            break
        }
    }

    if ($null -eq $count) {
        throw "Unable to find the Washington outage total on $PageUrl"
    }

    $updatedPatterns = @(
        '(?is)Last updated:\s*([0-9]+\s*[a-z]+ ago)',
        '(?is)Updated\s*([0-9]+\s*[a-z]+ ago)'
    )

    $updatedText = "unknown"
    foreach ($pattern in $updatedPatterns) {
        $updatedMatch = [regex]::Match($content, $pattern)
        if ($updatedMatch.Success) {
            $updatedText = $updatedMatch.Groups[1].Value.Trim()
            break
        }
    }

    return [pscustomobject]@{
        Count = $count
        UpdatedText = $updatedText
        CheckedAt = (Get-Date).ToString("o")
        SourceUrl = $PageUrl
    }
}

function Send-WebhookAlert {
    param(
        [string]$Destination,
        [pscustomobject]$Snapshot,
        [int]$ThresholdValue
    )

    if ([string]::IsNullOrWhiteSpace($Destination)) {
        return
    }

    $payload = [pscustomobject]@{
        state = "Washington"
        customersOut = $Snapshot.Count
        threshold = $ThresholdValue
        sourceUrl = $Snapshot.SourceUrl
        sourceUpdated = $Snapshot.UpdatedText
        checkedAt = $Snapshot.CheckedAt
        alert = "Washington outages are at or above threshold."
    } | ConvertTo-Json

    Invoke-RestMethod `
        -Method Post `
        -Uri $Destination `
        -ContentType "application/json" `
        -Body $payload `
        -TimeoutSec 30 | Out-Null
}

function Write-Alert {
    param(
        [pscustomobject]$Snapshot,
        [int]$ThresholdValue
    )

    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
    $message = "[ALERT $now] Washington outages at $($Snapshot.Count.ToString("N0")) customers (threshold: $($ThresholdValue.ToString("N0"))). Source updated $($Snapshot.UpdatedText)."
    Write-Host $message -ForegroundColor Yellow

    try {
        [console]::Beep(1200, 350)
        [console]::Beep(1500, 350)
    }
    catch {
        Write-Verbose "Console beep not supported in this session."
    }
}

function Write-Status {
    param(
        [pscustomobject]$Snapshot,
        [int]$ThresholdValue
    )

    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
    $status = if ($Snapshot.Count -ge $ThresholdValue) { "ABOVE" } else { "below" }
    $line = "[$now] Washington outages: $($Snapshot.Count.ToString("N0")) ($status threshold $($ThresholdValue.ToString("N0"))). Source updated $($Snapshot.UpdatedText)."
    Write-Host $line -ForegroundColor Cyan
}

$state = Get-State -Path $StateFile

while ($true) {
    try {
        $snapshot = Get-OutageSnapshot -PageUrl $Url
        Write-Status -Snapshot $snapshot -ThresholdValue $Threshold

        $isAboveThreshold = $snapshot.Count -ge $Threshold
        $crossedThreshold = ($null -eq $state.lastCount) -or ($state.lastCount -lt $Threshold)
        $changedWhileAbove = ($null -eq $state.lastAlertCount) -or ($snapshot.Count -ne $state.lastAlertCount)

        if ($isAboveThreshold -and ($crossedThreshold -or $changedWhileAbove)) {
            Write-Alert -Snapshot $snapshot -ThresholdValue $Threshold
            Send-WebhookAlert -Destination $WebhookUrl -Snapshot $snapshot -ThresholdValue $Threshold
            $state.lastAlertCount = $snapshot.Count
            $state.lastAlertAt = $snapshot.CheckedAt
        }

        $state.lastCount = $snapshot.Count
        Save-State -Path $StateFile -State $state
        Save-Status -Path $StatusFile -Snapshot $snapshot -ThresholdValue $Threshold -State $state
    }
    catch {
        $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
        Write-Warning "[$now] Check failed: $($_.Exception.Message)"
    }

    if ($Once) {
        break
    }

    Start-Sleep -Seconds $IntervalSeconds
}
