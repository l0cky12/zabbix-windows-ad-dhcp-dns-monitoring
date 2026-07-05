<#
.SYNOPSIS
    Central Active Directory health check script for Zabbix monitoring.
.DESCRIPTION
    Performs specific AD health checks based on switch parameters. Designed to be called
    by Zabbix UserParameter definitions. Returns single-value machine-parseable output
    for Zabbix item collection, plus human-readable Write-Host output.
.PARAMETER CheckDcdiagServices
    Runs dcdiag /test:Services. Returns "OK" or "FAIL:<details>".
.PARAMETER CheckDcdiagAdvertising
    Runs dcdiag /test:Advertising. Returns "OK" or "FAIL:<details>".
.PARAMETER CheckReplication
    Runs repadmin /replsummary. Returns count of failed replication partners (integer).
.PARAMETER CheckOldestReplication
    Returns the oldest last-successful replication time in minutes (integer).
.PARAMETER CheckSYSVOL
    Checks if SYSVOL share exists via net share. Returns "OK" or "MISSING".
.PARAMETER CheckNETLOGON
    Checks if NETLOGON share exists via net share. Returns "OK" or "MISSING".
.PARAMETER CheckDFSRState
    Checks DFSR state for SYSVOL using dfsrdiag. Returns state number (4=Normal).
.PARAMETER CheckClockOffset
    Runs w32tm /stripchart to measure clock offset. Returns offset in seconds (integer).
.PARAMETER CheckAll
    Runs all checks above and returns formatted summary output.
.EXAMPLE
    .\check-ad-health.ps1 -CheckDcdiagServices
    .\check-ad-health.ps1 -CheckReplication
    .\check-ad-health.ps1 -CheckAll
.NOTES
    Author: Zabbix Monitoring Team
    Version: 1.0
    Requires: ActiveDirectory PowerShell module, Remote Server Administration Tools (RSAT),
              local admin or delegated permissions. Run on Domain Controllers.
    Exit Codes: 0 = success, 1 = warning/error
#>

[CmdletBinding()]
param(
    [switch]$CheckDcdiagServices,
    [switch]$CheckDcdiagAdvertising,
    [switch]$CheckReplication,
    [switch]$CheckOldestReplication,
    [switch]$CheckSYSVOL,
    [switch]$CheckNETLOGON,
    [switch]$CheckDFSRState,
    [switch]$CheckClockOffset,
    [switch]$CheckAll
)

# Set strict mode and error action preference
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Helper function: write both human-readable and Zabbix-parsable output
function Write-CheckResult {
    param([string]$CheckName, [string]$Value)
    Write-Host "[$CheckName] $Value"
    Write-Output $Value
}

# Helper function: run dcdiag tests safely
function Invoke-DcdiagTest {
    param([string]$TestName, [string]$TestDescription)

    try {
        Write-Host "Running dcdiag /test:$TestName..."
        $result = dcdiag /test:$TestName /s:$env:COMPUTERNAME 2>&1
        $output = $result -join "`n"

        if ($output -match "passed test $TestName") {
            Write-CheckResult -CheckName "Dcdiag$TestName" -Value "OK"
            return "OK"
        } else {
            # Extract relevant failure details
            $details = ($output | Select-String -Pattern "failed|error|FAILED|Error" -SimpleMatch) -join "; "
            if ([string]::IsNullOrEmpty($details)) {
                $details = "Test $TestName did not pass cleanly. Check dcdiag output manually."
            }
            Write-CheckResult -CheckName "Dcdiag$TestName" -Value "FAIL:$details"
            return "FAIL:$details"
        }
    }
    catch {
        $errMsg = "Exception running dcdiag /test:$TestName : $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "FAIL:$errMsg"
        return "FAIL:$errMsg"
    }
}

# --- CheckDcdiagServices ---
function Check-DcdiagServices {
    return Invoke-DcdiagTest -TestName "Services" -TestDescription "Checks AD services"
}

# --- CheckDcdiagAdvertising ---
function Check-DcdiagAdvertising {
    return Invoke-DcdiagTest -TestName "Advertising" -TestDescription "Checks DC advertising"
}

# --- CheckReplication ---
function Check-ReplicationFailures {
    try {
        Write-Host "Running repadmin /replsummary..."
        $result = repadmin /replsummary 2>&1
        $output = $result -join "`n"

        # Parse the summary table for "FAIL" column
        $failCount = 0
        $lines = $output -split "`n"
        $inData = $false
        foreach ($line in $lines) {
            if ($line -match "^\s*Source\s+DSA") { $inData = $true; continue }
            if ($line -match "^\s*-+") { continue }
            if ($inData -and $line -match "^\s*\S+") {
                # Line with replication data; parse the fail column
                $parts = $line -split "\s+" | Where-Object { $_ -ne '' }
                if ($parts.Count -ge 4) {
                    $failVal = $parts[3] -as [int]
                    if ($failVal -is [int] -and $failVal -gt 0) {
                        $failCount += $failVal
                    }
                }
            }
        }

        Write-CheckResult -CheckName "ReplicationFailures" -Value $failCount
        return $failCount
    }
    catch {
        $errMsg = "Exception running repadmin /replsummary : $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return -1
    }
}

# --- CheckOldestReplication ---
function Check-OldestReplication {
    try {
        Write-Host "Checking oldest replication time..."
        $result = repadmin /showrepl * /csv 2>&1
        $output = $result -join "`n"
        $lines = $output -split "`n"

        $oldestMinutes = 0
        $now = Get-Date

        foreach ($line in $lines) {
            if ($line -match ".*,\d+,\d+,\d+/,(\d{1,2}/\d{1,2}/\d{4}\s+\d{1,2}:\d{2}:\d{2}\s+[AP]M)") {
                $dateStr = $Matches[1]
                try {
                    $lastSuccess = [datetime]::ParseExact($dateStr, "M/d/yyyy h:mm:ss tt", $null)
                    $minutes = ($now - $lastSuccess).TotalMinutes
                    if ($minutes -gt $oldestMinutes) {
                        $oldestMinutes = [math]::Round($minutes)
                    }
                }
                catch {
                    # Skip unparseable dates
                }
            }
        }

        Write-CheckResult -CheckName "OldestReplication" -Value $oldestMinutes
        return $oldestMinutes
    }
    catch {
        $errMsg = "Exception checking oldest replication: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return -1
    }
}

# --- CheckSYSVOL ---
function Check-SYSVOLShare {
    try {
        Write-Host "Checking SYSVOL share..."
        $shares = net share 2>&1 | Out-String
        if ($shares -match "SYSVOL") {
            Write-CheckResult -CheckName "SYSVOL" -Value "OK"
            return "OK"
        } else {
            Write-CheckResult -CheckName "SYSVOL" -Value "MISSING"
            return "MISSING"
        }
    }
    catch {
        $errMsg = "Exception checking SYSVOL share: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return "ERROR:$errMsg"
    }
}

# --- CheckNETLOGON ---
function Check-NETLOGONShare {
    try {
        Write-Host "Checking NETLOGON share..."
        $shares = net share 2>&1 | Out-String
        if ($shares -match "NETLOGON") {
            Write-CheckResult -CheckName "NETLOGON" -Value "OK"
            return "OK"
        } else {
            Write-CheckResult -CheckName "NETLOGON" -Value "MISSING"
            return "MISSING"
        }
    }
    catch {
        $errMsg = "Exception checking NETLOGON share: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return "ERROR:$errMsg"
    }
}

# --- CheckDFSRState ---
function Check-DFSRState {
    try {
        Write-Host "Checking DFSR state for SYSVOL..."

        # Try using DFSR module first, fall back to dfsrdiag
        if (Get-Module -ListAvailable -Name DFSR) {
            try {
                Import-Module DFSR -ErrorAction Stop
                $membership = Get-DfsrMembership | Where-Object { $_.FolderName -eq "SYSVOL Share" }
                if ($membership) {
                    $state = $membership.State
                    Write-CheckResult -CheckName "DFSRState" -Value $state
                    return $state
                }
            }
            catch {
                Write-Host "DFSR module failed, falling back to dfsrdiag..."
            }
        }

        # Fall back to dfsrdiag
        $result = dfsrdiag /poll /count:1 2>&1
        $output = $result -join "`n"

        # Parse state from output - look for state number
        if ($output -match "state\s*[=:]\s*(\d+)") {
            $state = [int]$Matches[1]
        }
        elseif ($output -match "State:\s*(\d+)") {
            $state = [int]$Matches[1]
        }
        else {
            # If we can't parse, assume something went wrong
            $state = 0
        }

        Write-CheckResult -CheckName "DFSRState" -Value $state
        return $state
    }
    catch {
        $errMsg = "Exception checking DFSR state: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return -1
    }
}

# --- CheckClockOffset ---
function Check-ClockOffset {
    try {
        Write-Host "Checking clock offset via w32tm..."
        # Target a reliable time source; using DC's PDC emulator as default
        $result = w32tm /stripchart /computer:$env:COMPUTERNAME /samples:1 /dataonly 2>&1
        $output = $result -join "`n"

        # Parse offset: typically ",-XX.XXXXXXXs" or similar
        if ($output -match "[,.](-?\d+\.?\d*)s") {
            $offset = [math]::Round([double]$Matches[1])
        }
        elseif ($output -match "offset[=:]\s*(-?\d+\.?\d*)") {
            $offset = [math]::Round([double]$Matches[1])
        }
        else {
            # Try w32tm /query instead
            try {
                $queryResult = w32tm /query /status 2>&1 | Out-String
                if ($queryResult -match "PhaseOffset\s*:\s*(-?\d+\.?\d*)") {
                    $offset = [math]::Round([double]$Matches[1])
                }
                else {
                    $offset = 9999  # Sentinel for couldn't determine
                }
            }
            catch {
                $offset = 9999
            }
        }

        Write-CheckResult -CheckName "ClockOffset" -Value $offset
        return $offset
    }
    catch {
        $errMsg = "Exception checking clock offset: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return 9999
    }
}

# --- Main execution ---
try {
    $anyCheckSelected = $CheckDcdiagServices -or $CheckDcdiagAdvertising -or $CheckReplication -or `
                         $CheckOldestReplication -or $CheckSYSVOL -or $CheckNETLOGON -or `
                         $CheckDFSRState -or $CheckClockOffset -or $CheckAll

    if (-not $anyCheckSelected) {
        Write-Host "ERROR: No check parameter specified."
        Write-Host "Usage: .\check-ad-health.ps1 [-CheckDcdiagServices] [-CheckDcdiagAdvertising] [-CheckReplication]"
        Write-Host "       [-CheckOldestReplication] [-CheckSYSVOL] [-CheckNETLOGON] [-CheckDFSRState]"
        Write-Host "       [-CheckClockOffset] [-CheckAll]"
        Write-Output "ERROR:NoCheckSpecified"
        exit 1
    }

    $hasFailures = $false

    if ($CheckDcdiagServices -or $CheckAll) {
        $result = Check-DcdiagServices
        if ($result -ne "OK") { $hasFailures = $true }
    }

    if ($CheckDcdiagAdvertising -or $CheckAll) {
        $result = Check-DcdiagAdvertising
        if ($result -ne "OK") { $hasFailures = $true }
    }

    if ($CheckReplication -or $CheckAll) {
        $result = Check-ReplicationFailures
        if ($result -gt 0) { $hasFailures = $true }
    }

    if ($CheckOldestReplication -or $CheckAll) {
        $result = Check-OldestReplication
        if ($result -lt 0) { $hasFailures = $true }
    }

    if ($CheckSYSVOL -or $CheckAll) {
        $result = Check-SYSVOLShare
        if ($result -ne "OK") { $hasFailures = $true }
    }

    if ($CheckNETLOGON -or $CheckAll) {
        $result = Check-NETLOGONShare
        if ($result -ne "OK") { $hasFailures = $true }
    }

    if ($CheckDFSRState -or $CheckAll) {
        $result = Check-DFSRState
        if ($result -ne 4) { $hasFailures = $true }
    }

    if ($CheckClockOffset -or $CheckAll) {
        $result = Check-ClockOffset
        # 9999 = error sentinel; actual offset >300s = 5min skew threshold
        if ($result -eq 9999 -or [math]::Abs($result) -gt 300) { $hasFailures = $true }
    }

    if ($hasFailures) {
        exit 1
    } else {
        exit 0
    }
}
catch {
    Write-Host "Unhandled exception in check-ad-health.ps1: $($_.Exception.Message)"
    Write-Output "UNHANDLED_ERROR:$($_.Exception.Message)"
    exit 1
}