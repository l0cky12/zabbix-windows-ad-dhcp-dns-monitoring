<#
.SYNOPSIS
    Central DNS health check script for Zabbix monitoring.
.DESCRIPTION
    Performs specific DNS health checks based on switch parameters. Designed to be called
    by Zabbix UserParameter definitions. Returns single-value machine-parseable output
    for Zabbix item collection, plus human-readable Write-Host output.
.PARAMETER CheckService
    Returns "Running" or "Stopped" for the DNS service.
.PARAMETER RecordName
    Specifies the DNS record name to resolve (e.g., "hostname.domain.com").
.PARAMETER ResolveARecord
    Resolves an A record using Resolve-DnsName. Returns "OK" or "FAIL".
.PARAMETER ZoneName
    Specifies the DNS zone name (e.g., "domain.com") for SOA resolution.
.PARAMETER ResolveSOA
    Resolves the SOA record for the specified zone. Returns "OK" or "FAIL".
.PARAMETER DomainName
    Specifies the domain name for DC SRV record resolution.
.PARAMETER ResolveDCSRV
    Resolves _ldap._tcp.dc._msdcs.<DomainName> SRV records.
    Returns count of DC records (integer).
.PARAMETER CheckEvent4013
    Checks DNS Server event log for Event ID 4013 in the specified time window.
.PARAMETER Hours
    Time window in hours for event log checks. Default: 24.
.PARAMETER CheckAll
    Runs all basic checks (service + A record + SOA + DC SRV).
.EXAMPLE
    .\check-dns-health.ps1 -CheckService
    .\check-dns-health.ps1 -ResolveARecord -RecordName "hostname.example.com"
    .\check-dns-health.ps1 -ResolveSOA -ZoneName "example.com"
    .\check-dns-health.ps1 -ResolveDCSRV -DomainName "example.com"
    .\check-dns-health.ps1 -CheckEvent4013 -Hours 24
    .\check-dns-health.ps1 -CheckAll
.NOTES
    Author: Zabbix Monitoring Team
    Version: 1.0
    Requires: DnsServer PowerShell module for some checks.
              Resolve-DnsName is built-in on Windows Server 2012+.
              Run on DNS servers. Requires administrative privileges for service checks.
    Exit Codes: 0 = success, 1 = warning/error
#>

[CmdletBinding()]
param(
    [switch]$CheckService,
    [string]$RecordName = "",
    [switch]$ResolveARecord,
    [string]$ZoneName = "",
    [switch]$ResolveSOA,
    [string]$DomainName = "",
    [switch]$ResolveDCSRV,
    [switch]$CheckEvent4013,
    [int]$Hours = 24,
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

# --- CheckService ---
function Check-DnsService {
    try {
        Write-Host "Checking DNS service state..."
        $service = Get-Service -Name "DNS" -ErrorAction Stop
        $status = $service.Status.ToString()
        Write-CheckResult -CheckName "DNSService" -Value $status
        return $status
    }
    catch {
        $errMsg = "Exception checking DNS service: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return "ERROR"
    }
}

# --- ResolveARecord ---
function Resolve-ARecord {
    param([string]$Name)

    try {
        if ([string]::IsNullOrEmpty($Name)) {
            Write-Host "ERROR: RecordName parameter is required for -ResolveARecord"
            Write-Output "ERROR:NoRecordNameProvided"
            return "ERROR"
        }

        Write-Host "Resolving A record for $Name..."
        $resolved = Resolve-DnsName -Name $Name -Type A -ErrorAction Stop
        if ($resolved -and $resolved.Count -gt 0) {
            $ipAddresses = ($resolved | Where-Object { $_.QueryType -eq 'A' } | Select-Object -ExpandProperty IPAddress) -join ", "
            Write-Host "Resolved $Name to: $ipAddresses"
            Write-CheckResult -CheckName "ResolveA_$Name" -Value "OK"
            return "OK"
        } else {
            Write-CheckResult -CheckName "ResolveA_$Name" -Value "FAIL"
            return "FAIL"
        }
    }
    catch {
        $errMsg = "Exception resolving A record for $Name : $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "FAIL:$errMsg"
        return "FAIL"
    }
}

# --- ResolveSOA ---
function Resolve-SOA {
    param([string]$Zone)

    try {
        if ([string]::IsNullOrEmpty($Zone)) {
            Write-Host "ERROR: ZoneName parameter is required for -ResolveSOA"
            Write-Output "ERROR:NoZoneNameProvided"
            return "ERROR"
        }

        Write-Host "Resolving SOA record for zone $Zone..."
        $resolved = Resolve-DnsName -Name $Zone -Type SOA -ErrorAction Stop
        if ($resolved -and $resolved.Count -gt 0) {
            $primaryServer = $resolved[0].PrimaryServer
            Write-Host "SOA resolved for $Zone : Primary server = $primaryServer"
            Write-CheckResult -CheckName "ResolveSOA_$Zone" -Value "OK"
            return "OK"
        } else {
            Write-CheckResult -CheckName "ResolveSOA_$Zone" -Value "FAIL"
            return "FAIL"
        }
    }
    catch {
        $errMsg = "Exception resolving SOA for zone $Zone : $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "FAIL:$errMsg"
        return "FAIL"
    }
}

# --- ResolveDCSRV ---
function Resolve-DCSRV {
    param([string]$Domain)

    try {
        if ([string]::IsNullOrEmpty($Domain)) {
            Write-Host "ERROR: DomainName parameter is required for -ResolveDCSRV"
            Write-Output "ERROR:NoDomainNameProvided"
            return -1
        }

        $srvQuery = "_ldap._tcp.dc._msdcs.$Domain"
        Write-Host "Resolving DC SRV records: $srvQuery..."

        $resolved = Resolve-DnsName -Name $srvQuery -Type SRV -ErrorAction Stop
        $dcCount = 0
        if ($resolved) {
            $dcRecords = $resolved | Where-Object { $_.QueryType -eq 'SRV' }
            $dcCount = @($dcRecords).Count
            $dcNames = ($dcRecords | Select-Object -ExpandProperty NameTarget) -join ", "
            Write-Host "Found $dcCount DC(s): $dcNames"
        }

        Write-CheckResult -CheckName "DCSRV_$Domain" -Value $dcCount.ToString()
        return $dcCount
    }
    catch {
        $errMsg = "Exception resolving DC SRV records: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return -1
    }
}

# --- CheckEvent4013 ---
function Check-DnsEvent4013 {
    param([int]$WindowHours)

    try {
        Write-Host "Checking DNS Event ID 4013 in last $WindowHours hour(s)..."
        $cutoff = (Get-Date).AddHours(-$WindowHours)

        # DNS Server event log
        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'DNS Server'
            ID        = 4013
            StartTime = $cutoff
        } -ErrorAction SilentlyContinue

        $count = 0
        $lastTimestamp = "Never"

        if ($events) {
            $eventList = @($events)
            $count = $eventList.Count
            $lastTimestamp = $eventList[-1].TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
        }

        Write-Host "Event 4013 count (last $WindowHours h): $count, Last: $lastTimestamp"
        Write-CheckResult -CheckName "DNSEvent4013" -Value $count.ToString()
        # Also output the timestamp of last occurrence for additional context
        Write-Output "LAST_TIMESTAMP:$lastTimestamp"

        return $count
    }
    catch {
        # DNS Server log may not exist on non-DNS servers; treat as 0
        if ($_.Exception.Message -match "No events were found|log file.*does not exist|not found") {
            Write-Host "DNS Server event log not available. Count: 0"
            Write-Output "0"
            Write-Output "LAST_TIMESTAMP:N/A"
            return 0
        }
        $errMsg = "Exception checking DNS Event 4013: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return -1
    }
}

# --- Main execution ---
try {
    $anyCheckSelected = $CheckService -or $ResolveARecord -or $ResolveSOA -or `
                         $ResolveDCSRV -or $CheckEvent4013 -or $CheckAll

    if (-not $anyCheckSelected) {
        Write-Host "ERROR: No check parameter specified."
        Write-Host "Usage: .\check-dns-health.ps1 [-CheckService] [-ResolveARecord -RecordName <name>]"
        Write-Host "       [-ResolveSOA -ZoneName <zone>] [-ResolveDCSRV -DomainName <domain>]"
        Write-Host "       [-CheckEvent4013 [-Hours <n>]] [-CheckAll]"
        Write-Output "ERROR:NoCheckSpecified"
        exit 1
    }

    $hasFailures = $false

    if ($CheckService -or $CheckAll) {
        $result = Check-DnsService
        if ($result -ne "Running") { $hasFailures = $true }
    }

    if ($CheckAll) {
        # When CheckAll, run the synthetic checks with default placeholders
        try {
            $domain = $env:USERDNSDOMAIN
            if ([string]::IsNullOrEmpty($domain)) {
                $domain = "example.local"
                Write-Host "WARNING: USERDNSDOMAIN not set, using placeholder."
            }

            # Build a hostname from the domain
            $hostname = "hostname.$domain"

            $result = Resolve-ARecord -Name $hostname
            if ($result -ne "OK") { $hasFailures = $true }

            $result = Resolve-SOA -Zone $domain
            if ($result -ne "OK") { $hasFailures = $true }

            $result = Resolve-DCSRV -Domain $domain
            if ($result -lt 0) { $hasFailures = $true }
        }
        catch {
            Write-Host "WARNING: CheckAll synthetic checks encountered issues: $($_.Exception.Message)"
        }
    }
    else {
        if ($ResolveARecord) {
            $result = Resolve-ARecord -Name $RecordName
            if ($result -ne "OK") { $hasFailures = $true }
        }

        if ($ResolveSOA) {
            $result = Resolve-SOA -Zone $ZoneName
            if ($result -ne "OK") { $hasFailures = $true }
        }

        if ($ResolveDCSRV) {
            $result = Resolve-DCSRV -Domain $DomainName
            if ($result -lt 0) { $hasFailures = $true }
        }
    }

    if ($CheckEvent4013) {
        $result = Check-DnsEvent4013 -WindowHours $Hours
        if ($result -gt 0) { $hasFailures = $true }
    }

    if ($hasFailures) {
        exit 1
    } else {
        exit 0
    }
}
catch {
    Write-Host "Unhandled exception in check-dns-health.ps1: $($_.Exception.Message)"
    Write-Output "UNHANDLED_ERROR:$($_.Exception.Message)"
    exit 1
}