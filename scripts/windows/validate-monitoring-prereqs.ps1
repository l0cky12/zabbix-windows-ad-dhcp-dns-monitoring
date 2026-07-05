<#
.SYNOPSIS
    Validate that a Windows server meets prerequisites for the AD/DHCP/DNS monitoring templates.
.DESCRIPTION
    Performs read-only checks against a Windows server to verify it meets all
    prerequisites for Zabbix monitoring of Active Directory Domain Services, DHCP,
    DNS, and Role Health. Returns a clear pass/fail for each check and a JSON
    summary at the end. Exit code 0 if all pass, 1 if any fail.
.PARAMETER Detailed
    When specified, shows additional diagnostic information for each check.
.EXAMPLE
    .\validate-monitoring-prereqs.ps1
    .\validate-monitoring-prereqs.ps1 -Detailed
.NOTES
    Author: Zabbix Monitoring Team
    Version: 1.0
    Non-destructive - read-only checks only.
    Run with administrative privileges for complete results.
    Exit Codes: 0 = all prerequisites met, 1 = one or more checks failed
#>

[CmdletBinding()]
param(
    [switch]$Detailed
)

# Set strict mode and error action preference
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Results array for JSON summary
$script:checkResults = @()

# Helper: Record a check result
function Add-CheckResult {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Detail = ""
    )

    $result = @{
        Check  = $Name
        Status = if ($Passed) { "PASS" } else { "FAIL" }
        Detail = $Detail
    }

    $script:checkResults += $result

    $statusChar = if ($Passed) { "[PASS]" } else { "[FAIL]" }
    $details = if ($Detail -and $Detailed) { " - $Detail" } else { "" }
    Write-Host "$statusChar $Name$details"
}

# Helper: Check if a command exists in PATH
function Test-CommandAvailability {
    param([string]$CommandName)
    try {
        $cmd = Get-Command -Name $CommandName -ErrorAction Stop
        if ($Detailed) {
            return $true, "Found at: $($cmd.Source)"
        }
        return $true, "Available"
    }
    catch {
        return $false, "Not found in PATH"
    }
}

# Helper: Check if a PowerShell module is available
function Test-PSModuleAvailability {
    param([string]$ModuleName)
    try {
        $module = Get-Module -ListAvailable -Name $ModuleName -ErrorAction Stop
        if ($module) {
            $version = $module.Version -join ", "
            if ($Detailed) {
                return $true, "Available (v$version)"
            }
            return $true, "Available"
        }
        return $false, "Module not found"
    }
    catch {
        return $false, "Module not found"
    }
}

# --- Check 1: Is this a Domain Controller? ---
function Check-DomainController {
    Write-Host ""
    Write-Host "--- Check 1: Domain Controller ---"

    try {
        # Test if AD module is available first
        $adModuleAvailable = Test-PSModuleAvailability -ModuleName "ActiveDirectory"
        if (-not $adModuleAvailable[0]) {
            $detail = "ActiveDirectory module not available. This may not be a DC."
            Add-CheckResult -Name "Domain Controller" -Passed $false -Detail $detail
            return $false
        }

        Import-Module ActiveDirectory -ErrorAction Stop -WarningAction SilentlyContinue
        $dc = Get-ADDomainController -ErrorAction Stop

        if ($dc -and $dc.Count -gt 0) {
            $detail = if ($Detailed) { "Server '$($dc.Name)' is a Domain Controller (Site: $($dc.Site))" } else { "" }
            Add-CheckResult -Name "Domain Controller" -Passed $true -Detail $detail
            return $true
        } else {
            Add-CheckResult -Name "Domain Controller" -Passed $false -Detail "Not a Domain Controller"
            return $false
        }
    }
    catch {
        $detail = "Not a Domain Controller or insufficient permissions: $($_.Exception.Message)"
        Add-CheckResult -Name "Domain Controller" -Passed $false -Detail $detail
        return $false
    }
}

# --- Check 2: Required PowerShell modules ---
function Check-RequiredModules {
    Write-Host ""
    Write-Host "--- Check 2: Required PowerShell Modules ---"

    $modules = @("ActiveDirectory", "DhcpServer", "DnsServer")
    $allPassed = $true

    foreach ($moduleName in $modules) {
        $available, $detail = Test-PSModuleAvailability -ModuleName $moduleName
        Add-CheckResult -Name "Module: $moduleName" -Passed $available -Detail $detail
        if (-not $available) { $allPassed = $false }
    }

    return $allPassed
}

# --- Check 3: Zabbix Agent installed ---
function Check-ZabbixAgent {
    Write-Host ""
    Write-Host "--- Check 3: Zabbix Agent Installed ---"

    $found = $false
    $detail = ""

    # Check by service names
    $serviceNames = @("Zabbix Agent", "Zabbix Agent 2", "Zabbix Agent 2")
    foreach ($svcName in $serviceNames) {
        try {
            $service = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($service) {
                $found = $true
                $detail = if ($Detailed) { "Service '$($service.DisplayName)' installed, status: $($service.Status)" } else { "Service installed" }
                break
            }
        }
        catch { }
    }

    # Check by registry
    if (-not $found) {
        try {
            $regKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Zabbix" -ErrorAction SilentlyContinue
            if ($regKey) {
                $found = $true
                $detail = if ($Detailed) { "Zabbix registry key found" } else { "Found in registry" }
            }
        }
        catch { }
    }

    # Check by common install paths
    if (-not $found) {
        $commonPaths = @(
            "C:\Program Files\Zabbix Agent",
            "C:\Program Files\Zabbix Agent 2",
            "C:\zabbix"
        )
        foreach ($path in $commonPaths) {
            if (Test-Path $path -ErrorAction SilentlyContinue) {
                $found = $true
                $detail = if ($Detailed) { "Installation directory found: $path" } else { "Installation directory found" }
                break
            }
        }
    }

    if (-not $found) {
        $detail = "Zabbix Agent not found (checked services, registry, and common paths)"
    }

    Add-CheckResult -Name "Zabbix Agent Installed" -Passed $found -Detail $detail
    return $found
}

# --- Check 4: dcdiag available ---
function Check-Dcdiag {
    Write-Host ""
    Write-Host "--- Check 4: dcdiag available ---"

    $available, $detail = Test-CommandAvailability -CommandName "dcdiag"
    Add-CheckResult -Name "dcdiag" -Passed $available -Detail $detail
    return $available
}

# --- Check 5: repadmin available ---
function Check-Repadmin {
    Write-Host ""
    Write-Host "--- Check 5: repadmin available ---"

    $available, $detail = Test-CommandAvailability -CommandName "repadmin"
    Add-CheckResult -Name "repadmin" -Passed $available -Detail $detail
    return $available
}

# --- Check 6: dfsrdiag available ---
function Check-Dfsrdiag {
    Write-Host ""
    Write-Host "--- Check 6: dfsrdiag available ---"

    $available, $detail = Test-CommandAvailability -CommandName "dfsrdiag"
    Add-CheckResult -Name "dfsrdiag" -Passed $available -Detail $detail
    return $available
}

# --- Check 7: Monitoring scripts present ---
function Check-MonitoringScripts {
    Write-Host ""
    Write-Host "--- Check 7: Monitoring Scripts in C:\Scripts\ ---"

    $scriptDir = "C:\Scripts"
    $requiredScripts = @(
        "check-ad-health.ps1",
        "check-dhcp-health.ps1",
        "check-dns-health.ps1",
        "check-role-disk-health.ps1"
    )

    if (-not (Test-Path $scriptDir -ErrorAction SilentlyContinue)) {
        $detail = "Script directory not found: $scriptDir"
        Add-CheckResult -Name "Monitoring Scripts" -Passed $false -Detail $detail
        return $false
    }

    $allPresent = $true
    $missingScripts = @()

    foreach ($script in $requiredScripts) {
        $scriptPath = Join-Path -Path $scriptDir -ChildPath $script
        if (-not (Test-Path $scriptPath -ErrorAction SilentlyContinue)) {
            $allPresent = $false
            $missingScripts += $script
        }
    }

    if ($allPresent) {
        $detail = if ($Detailed) { "All $($requiredScripts.Count) scripts present in $scriptDir" } else { "" }
        Add-CheckResult -Name "Monitoring Scripts" -Passed $true -Detail $detail
    } else {
        $detail = "Missing scripts: $($missingScripts -join ', ')"
        Add-CheckResult -Name "Monitoring Scripts" -Passed $false -Detail $detail
    }

    return $allPresent
}

# --- Check 8: UserParameters configured ---
function Check-UserParameters {
    Write-Host ""
    Write-Host "--- Check 8: Zabbix UserParameters configured ---"

    $commonConfigPaths = @(
        "C:\Program Files\Zabbix Agent\zabbix_agentd.conf",
        "C:\Program Files\Zabbix Agent\zabbix_agent2.conf",
        "C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf",
        "C:\zabbix\zabbix_agentd.conf",
        "C:\zabbix\zabbix_agent2.conf",
        "C:\Program Files\Zabbix Agent\zabbix_agent2.d\ad-dhcp-dns-monitoring.conf",
        "C:\Program Files\Zabbix Agent 2\zabbix_agent2.d\ad-dhcp-dns-monitoring.conf"
    )

    $foundAny = $false
    $foundKeys = @()
    $searchKeys = @(
        "windows.ad.dcdiag.services",
        "windows.dhcp.service",
        "windows.dns.service",
        "windows.health.disk.os"
    )

    foreach ($cfgPath in $commonConfigPaths) {
        if (-not (Test-Path $cfgPath -ErrorAction SilentlyContinue)) { continue }

        try {
            $content = Get-Content -Path $cfgPath -ErrorAction Stop
            foreach ($line in $content) {
                if ($line -match '^\s*UserParameter=(windows\.\S+)') {
                    $foundAny = $true
                    $foundKeys += $Matches[1]
                }
            }
        }
        catch { }
    }

    # Check how many of the expected keys are present
    $matchedKeys = 0
    foreach ($searchKey in $searchKeys) {
        if ($foundKeys -contains $searchKey) {
            $matchedKeys++
        }
    }

    $threshold = [math]::Ceiling($searchKeys.Count / 2)
    $configured = $matchedKeys -ge $threshold

    if ($configured) {
        $detail = if ($Detailed) { "Found $matchedKeys of $($searchKeys.Count) expected UserParameter keys" } else { "" }
        Add-CheckResult -Name "UserParameters Configured" -Passed $true -Detail $detail
    } else {
        $detail = "Only $matchedKeys of $($searchKeys.Count) expected UserParameter keys found. Run configure-zabbix-agent.ps1"
        Add-CheckResult -Name "UserParameters Configured" -Passed $false -Detail $detail
    }

    return $configured
}

# --- Check 9: Windows Firewall allows Zabbix agent (port 10050) ---
function Check-FirewallRule {
    Write-Host ""
    Write-Host "--- Check 9: Windows Firewall - Zabbix Agent Port 10050 ---"

    try {
        $rules = Get-NetFirewallRule -Direction Inbound -Enabled True -ErrorAction Stop |
            Where-Object { $_.Profile -ne "" }

        $portFound = $false
        $ruleName = ""

        # Check for rules that include port 10050
        foreach ($rule in $rules) {
            try {
                $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
                if ($portFilter -and $portFilter.LocalPort -contains 10050) {
                    $portFound = $true
                    $ruleName = $rule.DisplayName
                    break
                }
            }
            catch { }
        }

        if ($portFound) {
            $detail = if ($Detailed) { "Firewall rule '$ruleName' allows inbound port 10050" } else { "" }
            Add-CheckResult -Name "Firewall Port 10050" -Passed $true -Detail $detail
            return $true
        } else {
            # Check if firewall might be disabled entirely
            $fwProfile = Get-NetFirewallProfile -Profile Domain -ErrorAction SilentlyContinue
            if ($fwProfile -and $fwProfile.Enabled -eq $false) {
                $detail = if ($Detailed) { "Domain firewall profile is disabled; no restriction" } else { "Domain firewall disabled" }
                Add-CheckResult -Name "Firewall Port 10050" -Passed $true -Detail $detail
                return $true
            }

            $detail = "No inbound rule found for port 10050. Add rule: 'netsh advfirewall firewall add rule name=\"Zabbix Agent\" dir=in action=allow protocol=TCP localport=10050'"
            Add-CheckResult -Name "Firewall Port 10050" -Passed $false -Detail $detail
            return $false
        }
    }
    catch {
        $detail = "Could not check firewall rules: $($_.Exception.Message)"
        Add-CheckResult -Name "Firewall Port 10050" -Passed $false -Detail $detail
        return $false
    }
}

# --- Check 10: Execution Policy ---
function Check-ExecutionPolicy {
    Write-Host ""
    Write-Host "--- Check 10: PowerShell Execution Policy ---"

    try {
        $policy = Get-ExecutionPolicy -ErrorAction Stop

        # Compatible policies: RemoteSigned, AllSigned, Unrestricted, Bypass
        $compatiblePolicies = @("RemoteSigned", "AllSigned", "Unrestricted", "Bypass")
        $compatible = $compatiblePolicies -contains $policy

        if ($compatible) {
            $detail = if ($Detailed) { "Current policy: $policy" } else { "" }
            Add-CheckResult -Name "Execution Policy (RemoteSigned+)" -Passed $true -Detail $detail
        } else {
            $detail = "Current policy: $policy. Required: RemoteSigned or better. Run: Set-ExecutionPolicy RemoteSigned"
            Add-CheckResult -Name "Execution Policy (RemoteSigned+)" -Passed $false -Detail $detail
        }

        return $compatible
    }
    catch {
        $detail = "Could not check execution policy: $($_.Exception.Message)"
        Add-CheckResult -Name "Execution Policy (RemoteSigned+)" -Passed $false -Detail $detail
        return $false
    }
}

# --- Main execution ---
try {
    Write-Host ""
    Write-Host "============================================"
    Write-Host "  Pre-requisite Validation"
    Write-Host "  Zabbix Monitoring - AD/DHCP/DNS/Role Health"
    Write-Host "============================================"
    Write-Host ""
    Write-Host "Server: $env:COMPUTERNAME"
    Write-Host "OS: $((Get-WmiObject Win32_OperatingSystem).Caption)"
    Write-Host "PS Version: $($PSVersionTable.PSVersion)"
    Write-Host ""

    # Run all checks
    $check1 = Check-DomainController
    $check2 = Check-RequiredModules
    $check3 = Check-ZabbixAgent
    $check4 = Check-Dcdiag
    $check5 = Check-Repadmin
    $check6 = Check-Dfsrdiag
    $check7 = Check-MonitoringScripts
    $check8 = Check-UserParameters
    $check9 = Check-FirewallRule
    $check10 = Check-ExecutionPolicy

    # Summary
    $passedCount = ($script:checkResults | Where-Object { $_.Status -eq "PASS" }).Count
    $failedCount = ($script:checkResults | Where-Object { $_.Status -eq "FAIL" }).Count
    $totalCount = $script:checkResults.Count

    Write-Host ""
    Write-Host "============================================"
    Write-Host "  Validation Summary"
    Write-Host "============================================"
    Write-Host "  Passed: $passedCount / $totalCount"
    Write-Host "  Failed: $failedCount / $totalCount"

    # Output JSON summary for Zabbix parsing
    $summaryJson = @{
        Server       = $env:COMPUTERNAME
        Timestamp    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        TotalChecks  = $totalCount
        Passed       = $passedCount
        Failed       = $failedCount
        AllPassed    = ($failedCount -eq 0)
        Details      = $script:checkResults
    } | ConvertTo-Json

    Write-Host ""
    Write-Host "--- JSON Summary ---"
    Write-Output $summaryJson

    if ($failedCount -gt 0) {
        Write-Host ""
        Write-Host "[RESULT] $failedCount check(s) failed. Review details above." -ForegroundColor Yellow
        Write-Host "[RESULT] Please address the FAIL items before enabling Zabbix monitoring." -ForegroundColor Yellow
        exit 1
    } else {
        Write-Host ""
        Write-Host "[RESULT] All checks passed! Server is ready for monitoring." -ForegroundColor Green
        exit 0
    }
}
catch {
    Write-Host ""
    Write-Host "[FATAL] Unhandled exception in validation script: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "[FATAL] Stack: $($_.ScriptStackTrace)" -ForegroundColor Red

    $errorJson = @{
        Server       = $env:COMPUTERNAME
        Timestamp    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        TotalChecks  = 0
        Passed       = 0
        Failed       = 1
        AllPassed    = $false
        Error        = $_.Exception.Message
    } | ConvertTo-Json

    Write-Output $errorJson
    exit 1
}