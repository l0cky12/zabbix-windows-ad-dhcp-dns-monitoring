<#
.SYNOPSIS
    Central DHCP health check script for Zabbix monitoring.
.DESCRIPTION
    Performs specific DHCP health checks based on switch parameters. Designed to be called
    by Zabbix UserParameter definitions. Returns single-value machine-parseable output
    for Zabbix item collection, plus human-readable Write-Host output.
.PARAMETER CheckService
    Returns "Running" or "Stopped" for the DHCPServer service.
.PARAMETER DiscoverScopes
    Returns a JSON array of scope details for Low-Level Discovery (LLD).
    Fields: ScopeId, ScopeName, SubnetMask, State.
.PARAMETER ScopeId
    Specifies the DHCP scope ID (e.g., "10.0.0.0") for scope-specific checks.
.PARAMETER CheckScopeUtilization
    Checks free address percentage and count for the specified ScopeId.
    Returns free percentage (integer 0-100).
.PARAMETER CheckAuthorization
    Returns "Authorized" or "Unauthorized" for DHCP server in Active Directory.
.PARAMETER CheckFailoverState
    Returns the failover relationship state for the specified ScopeId.
    Values: NORMAL, CommDown, PARTNER_DOWN, etc.
.PARAMETER CheckEvent1046
    Checks Application event log for Event ID 1046 in the last 24 hours.
    Returns count (integer).
.PARAMETER CheckEvent1051
    Checks Application event log for Event ID 1051 in the last 24 hours.
    Returns count (integer).
.EXAMPLE
    .\check-dhcp-health.ps1 -CheckService
    .\check-dhcp-health.ps1 -DiscoverScopes
    .\check-dhcp-health.ps1 -CheckScopeUtilization -ScopeId "10.0.0.0"
    .\check-dhcp-health.ps1 -CheckEvent1046
.NOTES
    Author: Zabbix Monitoring Team
    Version: 1.0
    Requires: DhcpServer PowerShell module (part of Remote Server Administration Tools).
              Run on DHCP servers. Requires administrative privileges.
    Exit Codes: 0 = success, 1 = warning/error
#>

[CmdletBinding()]
param(
    [switch]$CheckService,
    [switch]$DiscoverScopes,
    [string]$ScopeId = "",
    [switch]$CheckScopeUtilization,
    [switch]$CheckAuthorization,
    [switch]$CheckFailoverState,
    [switch]$CheckEvent1046,
    [switch]$CheckEvent1051
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

# --- CheckService ---
function Check-DhcpService {
    try {
        Write-Host "Checking DHCP Server service state..."
        $service = Get-Service -Name "DHCPServer" -ErrorAction Stop
        $status = $service.Status.ToString()
        Write-CheckResult -CheckName "DHCPService" -Value $status
        return $status
    }
    catch {
        $errMsg = "Exception checking DHCP service: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return "ERROR"
    }
}

# --- DiscoverScopes ---
function Discover-DhcpScopes {
    try {
        Write-Host "Discovering DHCP scopes..."
        Import-Module DhcpServer -ErrorAction Stop -WarningAction SilentlyContinue

        $scopes = Get-DhcpServerv4Scope -ErrorAction Stop
        $scopeList = @()

        foreach ($scope in $scopes) {
            $scopeList += @{
                ScopeId    = $scope.ScopeId.IPAddressToString
                ScopeName  = $scope.Name
                SubnetMask = $scope.SubnetMask.IPAddressToString
                State      = $scope.State.ToString()
            }
        }

        if ($scopeList.Count -eq 0) {
            Write-Host "No DHCP scopes found."
            Write-Output "[]"
            return @()
        }

        $json = $scopeList | ConvertTo-Json -Compress
        Write-Host "Discovered $($scopeList.Count) scope(s)."
        Write-Output $json
        return $scopeList
    }
    catch {
        $errMsg = "Exception discovering DHCP scopes: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return @()
    }
}

# --- CheckScopeUtilization ---
function Check-ScopeUtilization {
    param([string]$ScopeAddress)

    try {
        if ([string]::IsNullOrEmpty($ScopeAddress)) {
            Write-Host "ERROR: ScopeId parameter is required for -CheckScopeUtilization"
            Write-Output "ERROR:NoScopeIdProvided"
            return -1
        }

        Write-Host "Checking utilization for scope $ScopeAddress..."
        Import-Module DhcpServer -ErrorAction Stop -WarningAction SilentlyContinue

        $scope = Get-DhcpServerv4Scope -ScopeId $ScopeAddress -ErrorAction Stop

        $totalAddresses = $scope.NumberOfAddresses
        $inUseAddresses = $scope.NumberOfAddressesInUse

        if ($totalAddresses -eq 0) {
            Write-Host "WARNING: Scope $ScopeAddress has 0 total addresses."
            Write-Output "0"
            return 0
        }

        $freeAddresses = $totalAddresses - $inUseAddresses
        $freePercent = [math]::Round(($freeAddresses / $totalAddresses) * 100)

        Write-Host "Scope $ScopeAddress - Free: $freeAddresses / $totalAddresses ($freePercent%)"
        Write-CheckResult -CheckName "ScopeUtilization_$ScopeAddress" -Value $freePercent.ToString()

        # Also output the free count on a second line so Zabbix can be configured to capture it separately
        Write-Output "FREE_COUNT:$freeAddresses"

        return $freePercent
    }
    catch {
        $errMsg = "Exception checking scope utilization: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return -1
    }
}

# --- CheckAuthorization ---
function Check-DhcpAuthorization {
    try {
        Write-Host "Checking DHCP server authorization in AD..."
        Import-Module DhcpServer -ErrorAction Stop -WarningAction SilentlyContinue

        $server = Get-DhcpServerInDC -ErrorAction SilentlyContinue

        if ($server -and $server.Count -gt 0) {
            Write-CheckResult -CheckName "DHPCAuthorization" -Value "Authorized"
            return "Authorized"
        } else {
            Write-CheckResult -CheckName "DHCPAuthorization" -Value "Unauthorized"
            return "Unauthorized"
        }
    }
    catch {
        $errMsg = "Exception checking DHCP authorization: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return "ERROR"
    }
}

# --- CheckFailoverState ---
function Check-FailoverState {
    param([string]$ScopeAddress)

    try {
        if ([string]::IsNullOrEmpty($ScopeAddress)) {
            Write-Host "ERROR: ScopeId parameter is required for -CheckFailoverState"
            Write-Output "ERROR:NoScopeIdProvided"
            return "ERROR"
        }

        Write-Host "Checking failover state for scope $ScopeAddress..."
        Import-Module DhcpServer -ErrorAction Stop -WarningAction SilentlyContinue

        $failover = Get-DhcpServerv4Failover -ScopeId $ScopeAddress -ErrorAction SilentlyContinue

        if (-not $failover) {
            Write-Host "No failover relationship found for scope $ScopeAddress."
            Write-Output "NONE"
            return "NONE"
        }

        $state = $failover.State.ToString()
        Write-CheckResult -CheckName "FailoverState_$ScopeAddress" -Value $state
        return $state
    }
    catch {
        $errMsg = "Exception checking failover state: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return "ERROR"
    }
}

# --- CheckEvent1046 ---
function Check-DhcpEvent1046 {
    try {
        Write-Host "Checking DHCP Event ID 1046 in last 24 hours..."
        $cutoff = (Get-Date).AddHours(-24)
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Microsoft-Windows-DHCP Server/Operational'
            ID        = 1046
            StartTime = $cutoff
        } -ErrorAction SilentlyContinue

        $count = 0
        if ($events) {
            $count = @($events).Count
        }

        Write-Host "Event 1046 count (last 24h): $count"
        Write-CheckResult -CheckName "DHCPEvent1046" -Value $count.ToString()
        return $count
    }
    catch {
        # Event log may not exist on non-DHCP servers; treat as 0
        if ($_.Exception.Message -match "No events were found|log file.*does not exist|not found") {
            Write-Host "DHCP operational log not available (may not be a DHCP server). Count: 0"
            Write-Output "0"
            return 0
        }
        $errMsg = "Exception checking Event 1046: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return -1
    }
}

# --- CheckEvent1051 ---
function Check-DhcpEvent1051 {
    try {
        Write-Host "Checking DHCP Event ID 1051 in last 24 hours..."
        $cutoff = (Get-Date).AddHours(-24)
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'Microsoft-Windows-DHCP Server/Operational'
            ID        = 1051
            StartTime = $cutoff
        } -ErrorAction SilentlyContinue

        $count = 0
        if ($events) {
            $count = @($events).Count
        }

        Write-Host "Event 1051 count (last 24h): $count"
        Write-CheckResult -CheckName "DHCPEvent1051" -Value $count.ToString()
        return $count
    }
    catch {
        if ($_.Exception.Message -match "No events were found|log file.*does not exist|not found") {
            Write-Host "DHCP operational log not available (may not be a DHCP server). Count: 0"
            Write-Output "0"
            return 0
        }
        $errMsg = "Exception checking Event 1051: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return -1
    }
}

# --- Main execution ---
try {
    $anyCheckSelected = $CheckService -or $DiscoverScopes -or $CheckScopeUtilization -or `
                         $CheckAuthorization -or $CheckFailoverState -or $CheckEvent1046 -or `
                         $CheckEvent1051

    if (-not $anyCheckSelected) {
        Write-Host "ERROR: No check parameter specified."
        Write-Host "Usage: .\check-dhcp-health.ps1 [-CheckService] [-DiscoverScopes] [-CheckScopeUtilization -ScopeId <id>]"
        Write-Host "       [-CheckAuthorization] [-CheckFailoverState -ScopeId <id>]"
        Write-Host "       [-CheckEvent1046] [-CheckEvent1051]"
        Write-Output "ERROR:NoCheckSpecified"
        exit 1
    }

    $hasFailures = $false

    if ($CheckService) {
        $result = Check-DhcpService
        if ($result -ne "Running") { $hasFailures = $true }
    }

    if ($DiscoverScopes) {
        $result = Discover-DhcpScopes
        # Discovery failure is non-fatal; just returns empty
    }

    if ($CheckScopeUtilization) {
        $result = Check-ScopeUtilization -ScopeAddress $ScopeId
        if ($result -lt 0) { $hasFailures = $true }
    }

    if ($CheckAuthorization) {
        $result = Check-DhcpAuthorization
        if ($result -ne "Authorized") { $hasFailures = $true }
    }

    if ($CheckFailoverState) {
        $result = Check-FailoverState -ScopeAddress $ScopeId
        if ($result -eq "ERROR") { $hasFailures = $true }
    }

    if ($CheckEvent1046) {
        $result = Check-DhcpEvent1046
        if ($result -gt 0) { $hasFailures = $true }
    }

    if ($CheckEvent1051) {
        $result = Check-DhcpEvent1051
        if ($result -gt 0) { $hasFailures = $true }
    }

    if ($hasFailures) {
        exit 1
    } else {
        exit 0
    }
}
catch {
    Write-Host "Unhandled exception in check-dhcp-health.ps1: $($_.Exception.Message)"
    Write-Output "UNHANDLED_ERROR:$($_.Exception.Message)"
    exit 1
}