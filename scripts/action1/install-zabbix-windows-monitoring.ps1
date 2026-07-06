<#
.SYNOPSIS
    Action1 deployment script for Zabbix Windows AD/DHCP/DNS monitoring scripts.
.DESCRIPTION
    Downloads the GitHub repository ZIP, copies the monitoring PowerShell scripts to
    C:\Scripts, configures Zabbix Agent or Zabbix Agent 2 UserParameters, restarts the
    agent service, and verifies that the scripts and UserParameters are present.

    Designed to be pasted directly into an Action1 "Run PowerShell" action.

.NOTES
    Run as Administrator / LocalSystem from Action1.
    First run uses PowerShell -ExecutionPolicy Bypass in Action1 if needed.
    Script output is also logged to:
      C:\ProgramData\ZabbixWindowsMonitoring\install.log
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoZipUrl = "https://github.com/l0cky12/zabbix-windows-ad-dhcp-dns-monitoring/archive/refs/heads/main.zip",
    [string]$InstallDir = "C:\Scripts",
    [string]$WorkDir = "C:\ProgramData\ZabbixWindowsMonitoring",
    [string]$ConfigPath = "",
    [string]$ZabbixServerIp = "",
    [switch]$SkipFirewallRule,
    [switch]$SkipAgentRestart,
    [switch]$SkipLiveChecks
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RequiredScripts = @(
    "check-ad-health.ps1",
    "check-dhcp-health.ps1",
    "check-dns-health.ps1",
    "check-role-disk-health.ps1",
    "configure-zabbix-agent.ps1",
    "validate-monitoring-prereqs.ps1"
)

$ExpectedKeys = @(
    "windows.ad.dcdiag.services",
    "windows.ad.dcdiag.advertising",
    "windows.ad.replication.failures",
    "windows.ad.replication.oldest",
    "windows.ad.sysvol",
    "windows.ad.netlogon",
    "windows.ad.dfsr.state",
    "windows.ad.clock.offset",
    "windows.dhcp.service",
    "windows.dhcp.discover.scopes",
    "windows.dhcp.scope.free[*]",
    "windows.dhcp.authorization",
    "windows.dhcp.failover.state[*]",
    "windows.dhcp.event.1046",
    "windows.dhcp.event.1051",
    "windows.dns.service",
    "windows.dns.synthetic.a[*]",
    "windows.dns.synthetic.soa[*]",
    "windows.dns.synthetic.dc.srv[*]",
    "windows.dns.event.4013[*]",
    "windows.health.disk.discover",
    "windows.health.disk.check[*]",
    "windows.health.disk.os",
    "windows.health.disk.ntds",
    "windows.health.disk.adlogs",
    "windows.health.disk.sysvol",
    "windows.health.disk.dhcpdata"
)

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet("INFO", "OK", "WARN", "ERROR")][string]$Level = "INFO"
    )
    $line = "[{0}] {1}" -f $Level, $Message
    Write-Host $line
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "This script must run elevated. In Action1, run as LocalSystem or Administrator."
    }
    Write-Log "Running with administrative privileges as $($identity.Name)" "OK"
}

function Find-ZabbixConfigPath {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (Test-Path -LiteralPath $ExplicitPath) { return $ExplicitPath }
        throw "Explicit Zabbix config path does not exist: $ExplicitPath"
    }

    $candidates = @(
        "C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf",
        "C:\Program Files\Zabbix Agent\zabbix_agent2.conf",
        "C:\Program Files\Zabbix Agent\zabbix_agentd.conf",
        "C:\zabbix\zabbix_agent2.conf",
        "C:\zabbix\zabbix_agentd.conf"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    throw "Could not find zabbix_agentd.conf or zabbix_agent2.conf. Install Zabbix agent first or pass -ConfigPath."
}

function Find-ZabbixTestExe {
    param([string]$DetectedConfigPath)

    $agent2Candidates = @(
        "C:\Program Files\Zabbix Agent 2\zabbix_agent2.exe",
        "C:\Program Files\Zabbix Agent\zabbix_agent2.exe",
        "C:\zabbix\zabbix_agent2.exe"
    )
    $agent1Candidates = @(
        "C:\Program Files\Zabbix Agent\zabbix_agentd.exe",
        "C:\zabbix\zabbix_agentd.exe"
    )

    if ($DetectedConfigPath -like "*agent2*") {
        foreach ($candidate in $agent2Candidates) { if (Test-Path -LiteralPath $candidate) { return $candidate } }
    }

    foreach ($candidate in ($agent1Candidates + $agent2Candidates)) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    return $null
}

function Get-ZabbixServiceName {
    $services = Get-Service -Name "Zabbix Agent 2", "ZabbixAgent2", "Zabbix Agent", "ZabbixAgent" -ErrorAction SilentlyContinue
    if (-not $services) { return $null }
    $running = $services | Where-Object { $_.Status -eq "Running" } | Select-Object -First 1
    if ($running) { return $running.Name }
    return ($services | Select-Object -First 1).Name
}

function Download-And-ExtractRepo {
    param(
        [string]$Url,
        [string]$DestinationRoot
    )

    New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
    $zipPath = Join-Path $DestinationRoot "zabbix-monitoring.zip"
    $extractRoot = Join-Path $DestinationRoot "repo"

    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    if (Test-Path -LiteralPath $extractRoot) { Remove-Item -LiteralPath $extractRoot -Recurse -Force }

    Write-Log "Downloading repo ZIP from $Url"
    Invoke-WebRequest -Uri $Url -OutFile $zipPath -UseBasicParsing

    Write-Log "Extracting ZIP to $extractRoot"
    Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force

    $scriptsDir = Get-ChildItem -Path $extractRoot -Recurse -Directory |
        Where-Object { $_.FullName -match "[\\/]scripts[\\/]windows$" } |
        Select-Object -First 1

    if (-not $scriptsDir) {
        throw "Could not find scripts\windows inside downloaded repo."
    }

    return $scriptsDir.FullName
}

function Install-MonitoringScripts {
    param(
        [string]$SourceScriptsDir,
        [string]$TargetDir
    )

    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null

    foreach ($scriptName in $RequiredScripts) {
        $source = Join-Path $SourceScriptsDir $scriptName
        $target = Join-Path $TargetDir $scriptName

        if (-not (Test-Path -LiteralPath $source)) {
            throw "Missing expected source script: $source"
        }

        Copy-Item -LiteralPath $source -Destination $target -Force
        if (Get-Command Unblock-File -ErrorAction SilentlyContinue) {
            try { Unblock-File -LiteralPath $target -ErrorAction SilentlyContinue } catch { }
        }
    }

    Write-Log "Installed monitoring scripts to $TargetDir" "OK"
}

function Verify-InstalledScripts {
    param([string]$TargetDir)

    $missing = @()
    foreach ($scriptName in $RequiredScripts) {
        $path = Join-Path $TargetDir $scriptName
        if (-not (Test-Path -LiteralPath $path)) { $missing += $scriptName }
    }

    if ($missing.Count -gt 0) {
        throw "Missing installed scripts in $TargetDir`: $($missing -join ', ')"
    }

    Write-Log "Verified all required scripts are present in $TargetDir" "OK"
    Get-ChildItem -Path $TargetDir -Filter "*.ps1" | Sort-Object Name | ForEach-Object {
        Write-Log ("  {0} ({1} bytes)" -f $_.Name, $_.Length)
    }
}

function Configure-ZabbixUserParameters {
    param(
        [string]$ScriptDir,
        [string]$DetectedConfigPath
    )

    $configureScript = Join-Path $ScriptDir "configure-zabbix-agent.ps1"

    Write-Log "Configuring Zabbix UserParameters in $DetectedConfigPath"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $configureScript -ConfigPath $DetectedConfigPath

    Write-Log "Zabbix UserParameters configured" "OK"
}

function Ensure-FirewallRule {
    param([string]$RemoteAddress)

    if ($SkipFirewallRule) {
        Write-Log "Skipping firewall rule because -SkipFirewallRule was set" "WARN"
        return
    }

    if (-not $RemoteAddress) {
        Write-Log "No -ZabbixServerIp provided. Skipping firewall rule to avoid opening 10050 broadly." "WARN"
        return
    }

    $ruleName = "Zabbix Agent from Zabbix Server"
    $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        Set-NetFirewallRule -DisplayName $ruleName -Enabled True -Action Allow | Out-Null
        Set-NetFirewallAddressFilter -AssociatedNetFirewallRule $existing -RemoteAddress $RemoteAddress | Out-Null
        Write-Log "Updated firewall rule for TCP 10050 from $RemoteAddress" "OK"
    } else {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort 10050 -Action Allow -RemoteAddress $RemoteAddress | Out-Null
        Write-Log "Created firewall rule for TCP 10050 from $RemoteAddress" "OK"
    }
}

function Restart-ZabbixAgent {
    if ($SkipAgentRestart) {
        Write-Log "Skipping Zabbix agent restart because -SkipAgentRestart was set" "WARN"
        return
    }

    $serviceName = Get-ZabbixServiceName
    if (-not $serviceName) {
        throw "Could not find a Zabbix Agent service to restart."
    }

    Restart-Service -Name $serviceName -Force
    Start-Sleep -Seconds 3
    $svc = Get-Service -Name $serviceName
    if ($svc.Status -ne "Running") {
        throw "Zabbix service $serviceName is not running after restart. Current status: $($svc.Status)"
    }

    Write-Log "Restarted Zabbix service: $serviceName" "OK"
}

function Test-ZabbixRegistration {
    param([string]$ZabbixExe)

    if (-not $ZabbixExe) {
        Write-Log "Zabbix agent test executable was not found. Skipping UserParameter -p verification." "WARN"
        return
    }

    Write-Log "Testing loaded UserParameters with $ZabbixExe -p"
    $loaded = & $ZabbixExe -p 2>&1 | Out-String

    $missingKeys = @()
    foreach ($key in $ExpectedKeys) {
        $literalKey = $key.Replace("[*]", "[")
        if ($loaded -notmatch [regex]::Escape($literalKey)) {
            $missingKeys += $key
        }
    }

    if ($missingKeys.Count -gt 0) {
        Write-Log "Some expected UserParameter keys were not visible in agent -p output:" "WARN"
        $missingKeys | ForEach-Object { Write-Log "  $_" "WARN" }
    } else {
        Write-Log "Verified expected UserParameter keys are loaded by the Zabbix agent" "OK"
    }
}

function Test-SafeLiveChecks {
    param([string]$ZabbixExe)

    if ($SkipLiveChecks) {
        Write-Log "Skipping live checks because -SkipLiveChecks was set" "WARN"
        return
    }

    if (-not $ZabbixExe) {
        Write-Log "Zabbix agent test executable was not found. Skipping live -t checks." "WARN"
        return
    }

    $tests = @("windows.health.disk.os")

    if (Get-Service -Name "DNS" -ErrorAction SilentlyContinue) {
        $tests += "windows.dns.service"
    }
    if (Get-Service -Name "DHCPServer" -ErrorAction SilentlyContinue) {
        $tests += "windows.dhcp.service"
    }
    if (Get-Service -Name "NTDS" -ErrorAction SilentlyContinue) {
        $tests += "windows.ad.dcdiag.services"
    }

    foreach ($test in $tests | Select-Object -Unique) {
        Write-Log "Running live check: $test"
        $output = & $ZabbixExe -t $test 2>&1 | Out-String
        $cleanOutput = $output.Trim()
        Write-Log "  $cleanOutput"
        if ($cleanOutput -match "ZBX_NOTSUPPORTED|Cannot execute|No such file|not supported") {
            throw "Live check failed for $test`: $cleanOutput"
        }
    }

    Write-Log "Live check verification completed" "OK"
}

try {
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    $logPath = Join-Path $WorkDir "install.log"
    Start-Transcript -Path $logPath -Append | Out-Null

    Write-Log "Starting Zabbix Windows monitoring deployment"
    Assert-Admin

    $detectedConfigPath = Find-ZabbixConfigPath -ExplicitPath $ConfigPath
    Write-Log "Using Zabbix config: $detectedConfigPath" "OK"

    $sourceScriptsDir = Download-And-ExtractRepo -Url $RepoZipUrl -DestinationRoot $WorkDir
    Write-Log "Found source scripts: $sourceScriptsDir" "OK"

    Install-MonitoringScripts -SourceScriptsDir $sourceScriptsDir -TargetDir $InstallDir
    Verify-InstalledScripts -TargetDir $InstallDir

    Configure-ZabbixUserParameters -ScriptDir $InstallDir -DetectedConfigPath $detectedConfigPath
    Ensure-FirewallRule -RemoteAddress $ZabbixServerIp
    Restart-ZabbixAgent

    $zabbixExe = Find-ZabbixTestExe -DetectedConfigPath $detectedConfigPath
    if ($zabbixExe) { Write-Log "Using Zabbix test executable: $zabbixExe" "OK" }
    Test-ZabbixRegistration -ZabbixExe $zabbixExe
    Test-SafeLiveChecks -ZabbixExe $zabbixExe

    Write-Log "Deployment completed successfully" "OK"
    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}
