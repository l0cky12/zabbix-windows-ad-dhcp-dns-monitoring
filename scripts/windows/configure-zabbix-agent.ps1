<#
.SYNOPSIS
    Configure Zabbix Agent UserParameters for AD, DHCP, DNS, and Role Health monitoring.
.DESCRIPTION
    Reads, validates, and adds the required UserParameter entries to Zabbix Agent or
    Agent 2 configuration files. Supports dry-run (-WhatIf), rollback (-Rollback),
    and custom include directories. Does NOT restart the Zabbix agent automatically
    (administrator should do that manually after review). The script:
      1. Detects the Zabbix agent config location
      2. Validates the config file exists
      3. Adds or removes the required UserParameter entries
      4. Optionally creates an include directory for modular config management
.PARAMETER ConfigPath
    Explicit path to the Zabbix agent configuration file. If omitted, the script
    will search common locations for zabbix_agentd.conf or zabbix_agent2.conf.
.PARAMETER WhatIf
    Dry-run mode. Shows what changes would be made without actually modifying any files.
.PARAMETER Rollback
    Removes all previously added monitoring UserParameter entries from the config.
.PARAMETER IncludeDir
    Directory path for Zabbix agent include files. If provided, a dedicated config
    snippet file will be created here instead of modifying the main config.
.EXAMPLE
    .\configure-zabbix-agent.ps1 -WhatIf
    .\configure-zabbix-agent.ps1
    .\configure-zabbix-agent.ps1 -Rollback
    .\configure-zabbix-agent.ps1 -IncludeDir "C:\Program Files\Zabbix Agent\zabbix_agent2.d"
.NOTES
    Author: Zabbix Monitoring Team
    Version: 1.0
    Does NOT restart Zabbix agent. Administrator must restart manually.
    Run with administrative privileges for best results.
    Exit Codes: 0 = success, 1 = warning/error
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$ConfigPath = "",
    [switch]$WhatIf,
    [switch]$Rollback,
    [string]$IncludeDir = ""
)

# Set strict mode and error action preference
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Define the required UserParameter entries
$userParameters = @(
    # AD Health Checks
    @{Key = "windows.ad.dcdiag.services";           Value = 'powershell -NoProfile -File "C:\Scripts\check-ad-health.ps1" -CheckDcdiagServices'}
    @{Key = "windows.ad.dcdiag.advertising";        Value = 'powershell -NoProfile -File "C:\Scripts\check-ad-health.ps1" -CheckDcdiagAdvertising'}
    @{Key = "windows.ad.replication.failures";      Value = 'powershell -NoProfile -File "C:\Scripts\check-ad-health.ps1" -CheckReplication'}
    @{Key = "windows.ad.replication.oldest";        Value = 'powershell -NoProfile -File "C:\Scripts\check-ad-health.ps1" -CheckOldestReplication'}
    @{Key = "windows.ad.sysvol";                     Value = 'powershell -NoProfile -File "C:\Scripts\check-ad-health.ps1" -CheckSYSVOL'}
    @{Key = "windows.ad.netlogon";                   Value = 'powershell -NoProfile -File "C:\Scripts\check-ad-health.ps1" -CheckNETLOGON'}
    @{Key = "windows.ad.dfsr.state";                 Value = 'powershell -NoProfile -File "C:\Scripts\check-ad-health.ps1" -CheckDFSRState'}
    @{Key = "windows.ad.clock.offset";               Value = 'powershell -NoProfile -File "C:\Scripts\check-ad-health.ps1" -CheckClockOffset'}

    # DHCP Health Checks
    @{Key = "windows.dhcp.service";                  Value = 'powershell -NoProfile -File "C:\Scripts\check-dhcp-health.ps1" -CheckService'}
    @{Key = "windows.dhcp.discover.scopes";          Value = 'powershell -NoProfile -File "C:\Scripts\check-dhcp-health.ps1" -DiscoverScopes'}
    @{Key = "windows.dhcp.scope.free[*]";            Value = 'powershell -NoProfile -File "C:\Scripts\check-dhcp-health.ps1" -CheckScopeUtilization -ScopeId "$1"'}
    @{Key = "windows.dhcp.authorization";            Value = 'powershell -NoProfile -File "C:\Scripts\check-dhcp-health.ps1" -CheckAuthorization'}
    @{Key = "windows.dhcp.failover.state[*]";        Value = 'powershell -NoProfile -File "C:\Scripts\check-dhcp-health.ps1" -CheckFailoverState -ScopeId "$1"'}
    @{Key = "windows.dhcp.event.1046";               Value = 'powershell -NoProfile -File "C:\Scripts\check-dhcp-health.ps1" -CheckEvent1046'}
    @{Key = "windows.dhcp.event.1051";               Value = 'powershell -NoProfile -File "C:\Scripts\check-dhcp-health.ps1" -CheckEvent1051'}

    # DNS Health Checks
    @{Key = "windows.dns.service";                   Value = 'powershell -NoProfile -File "C:\Scripts\check-dns-health.ps1" -CheckService'}
    @{Key = "windows.dns.synthetic.a[*]";            Value = 'powershell -NoProfile -File "C:\Scripts\check-dns-health.ps1" -ResolveARecord -RecordName "$1"'}
    @{Key = "windows.dns.synthetic.soa[*]";          Value = 'powershell -NoProfile -File "C:\Scripts\check-dns-health.ps1" -ResolveSOA -ZoneName "$1"'}
    @{Key = "windows.dns.synthetic.dc.srv[*]";      Value = 'powershell -NoProfile -File "C:\Scripts\check-dns-health.ps1" -ResolveDCSRV -DomainName "$1"'}
    @{Key = "windows.dns.event.4013[*]";             Value = 'powershell -NoProfile -File "C:\Scripts\check-dns-health.ps1" -CheckEvent4013 -Hours "$1"'}

    # Role Disk Health Checks
    @{Key = "windows.health.disk.discover";          Value = 'powershell -NoProfile -File "C:\Scripts\check-role-disk-health.ps1" -DiscoverVolumes'}
    @{Key = "windows.health.disk.check[*]";          Value = 'powershell -NoProfile -File "C:\Scripts\check-role-disk-health.ps1" -CheckVolume -DriveLetter "$1"'}
    @{Key = "windows.health.disk.os";                Value = 'powershell -NoProfile -File "C:\Scripts\check-role-disk-health.ps1" -CheckOSVolume'}
    @{Key = "windows.health.disk.ntds";              Value = 'powershell -NoProfile -File "C:\Scripts\check-role-disk-health.ps1" -CheckNTDSVolume'}
    @{Key = "windows.health.disk.adlogs";            Value = 'powershell -NoProfile -File "C:\Scripts\check-role-disk-health.ps1" -CheckADLogVolume'}
    @{Key = "windows.health.disk.sysvol";            Value = 'powershell -NoProfile -File "C:\Scripts\check-role-disk-health.ps1" -CheckSYSVOLVolume'}
    @{Key = "windows.health.disk.dhcpdata";          Value = 'powershell -NoProfile -File "C:\Scripts\check-role-disk-health.ps1" -CheckDHCPDataVolume'}
)

# Common Zabbix agent config paths
$commonConfigPaths = @(
    "C:\Program Files\Zabbix Agent\zabbix_agentd.conf",
    "C:\Program Files\Zabbix Agent\zabbix_agent2.conf",
    "C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf",
    "C:\zabbix\zabbix_agentd.conf",
    "C:\zabbix\zabbix_agent2.conf",
    "$env:ProgramFiles\Zabbix Agent\zabbix_agentd.conf",
    "$env:ProgramFiles\Zabbix Agent\zabbix_agent2.conf",
    "$env:ProgramFiles\Zabbix Agent 2\zabbix_agent2.conf"
)

# Helper: write human-readable output
function Write-Action {
    param([string]$Message, [string]$Type = "INFO")
    $prefix = switch ($Type) {
        "INFO"    { "[INFO]" }
        "OK"      { "[ OK ]" }
        "WARN"    { "[WARN]" }
        "ERROR"   {"[ERR ]"}
        "ACTION"  {"[ACTN]"}
        default   { "[INFO]" }
    }
    Write-Host "$prefix $Message"
}

# Helper: Build UserParameter line from key/value
function Build-UserParameterLine {
    param([string]$Key, [string]$Value)
    return "UserParameter=$Key,$Value"
}

# Helper: Escape regex special characters
function Escape-Regex {
    param([string]$Text)
    return [regex]::Escape($Text)
}

# --- Find Zabbix Agent Config ---
function Find-ZabbixConfig {
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrEmpty($ExplicitPath)) {
        if (Test-Path $ExplicitPath -ErrorAction SilentlyContinue) {
            Write-Action -Message "Using explicit config path: $ExplicitPath" -Type "OK"
            return $ExplicitPath
        } else {
            Write-Action -Message "Specified config path does not exist: $ExplicitPath" -Type "ERROR"
            return $null
        }
    }

    # Scan common paths
    foreach ($path in $commonConfigPaths) {
        if (Test-Path $path -ErrorAction SilentlyContinue) {
            Write-Action -Message "Found Zabbix agent config: $path" -Type "OK"
            return $path
        }
    }

    # Try to get config path from registry
    try {
        $regKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Zabbix" -ErrorAction SilentlyContinue
        if ($regKey) {
            $confPath = $regKey."ConfigPath"
            if ($confPath -and (Test-Path $confPath -ErrorAction SilentlyContinue)) {
                Write-Action -Message "Found Zabbix config from registry: $confPath" -Type "OK"
                return $confPath
            }
        }
    }
    catch {
        # Registry not available
    }

    return $null
}

# --- Check for Include Dir support in config ---
function Get-IncludeDir {
    param([string]$ConfigFilePath)

    try {
        $content = Get-Content -Path $ConfigFilePath -ErrorAction Stop
        foreach ($line in $content) {
            if ($line -match '^\s*Include\s*=\s*(.+)\s*$') {
                $includePath = $Matches[1].Trim()
                Write-Action -Message "Found Include directive: $includePath" -Type "INFO"
                return $includePath
            }
        }
    }
    catch { }

    return $null
}

# --- Add UserParameter entries ---
function Add-UserParameters {
    param([string]$TargetFile)

    Write-Action -Message "Processing config file: $TargetFile" -Type "INFO"

    # Read existing content
    $existingContent = @()
    try {
        $existingContent = Get-Content -Path $TargetFile -ErrorAction Stop
    }
    catch {
        Write-Action -Message "Cannot read config file: $($_.Exception.Message)" -Type "ERROR"
        return $false
    }

    $changesMade = $false
    $addedCount = 0
    $skipCount = 0

    # Build a set of existing UserParameter keys for quick lookup
    $existingKeys = @{}
    foreach ($line in $existingContent) {
        if ($line -match '^\s*UserParameter\s*=\s*([^,]+)') {
            $existingKey = $Matches[1].Trim()
            # Handle wildcard keys by removing [*]
            $baseKey = $existingKey -replace '\[.*\]$', ''
            $existingKeys[$baseKey] = $true
        }
    }

    foreach ($param in $userParameters) {
        $line = Build-UserParameterLine -Key $param.Key -Value $param.Value
        $baseKey = $param.Key -replace '\[.*\]$', ''

        if ($existingKeys.ContainsKey($baseKey)) {
            Write-Action -Message "SKIP: UserParameter '$($param.Key)' already exists" -Type "INFO"
            $skipCount++
            continue
        }

        if ($WhatIf) {
            Write-Action -Message "WOULD ADD: $line" -Type "ACTION"
            $changesMade = $true
            $addedCount++
            continue
        }

        try {
            Add-Content -Path $TargetFile -Value $line -ErrorAction Stop
            Write-Action -Message "ADDED: UserParameter '$($param.Key)'" -Type "OK"
            $changesMade = $true
            $addedCount++
        }
        catch {
            Write-Action -Message "FAILED to add UserParameter '$($param.Key)': $($_.Exception.Message)" -Type "ERROR"
        }
    }

    Write-Action -Message "Summary: $addedCount added, $skipCount skipped" -Type "INFO"

    if ($WhatIf -and $changesMade) {
        Write-Action -Message "DRY-RUN: No changes were made. Run without -WhatIf to apply." -Type "WARN"
    }

    return $changesMade
}

# --- Remove UserParameter entries ---
function Remove-UserParameters {
    param([string]$TargetFile)

    Write-Action -Message "Rolling back UserParameter entries from: $TargetFile" -Type "INFO"

    $existingContent = @()
    try {
        $existingContent = Get-Content -Path $TargetFile -ErrorAction Stop
    }
    catch {
        Write-Action -Message "Cannot read config file: $($_.Exception.Message)" -Type "ERROR"
        return $false
    }

    $newContent = @()
    $removedCount = 0
    $skipCount = 0

    foreach ($line in $existingContent) {
        $shouldRemove = $false

        foreach ($param in $userParameters) {
            # Build the full UserParameter line to match
            $targetLine = Build-UserParameterLine -Key $param.Key -Value $param.Value

            # Use flexible matching - strip whitespace for comparison
            $strippedLine = $line.Trim()
            $strippedTarget = $targetLine.Trim()

            if ($strippedLine -eq $strippedTarget) {
                $shouldRemove = $true
                break
            }

            # Also match just the key part for 'UserParameter=<key>,' prefix
            if ($strippedLine -match "^UserParameter=$([regex]::Escape($param.Key)),") {
                $shouldRemove = $true
                break
            }
        }

        if ($shouldRemove) {
            if ($WhatIf) {
                Write-Action -Message "WOULD REMOVE: $line" -Type "ACTION"
            }
            $removedCount++
        } else {
            $newContent += $line
        }
    }

    if (-not $WhatIf) {
        try {
            $newContent | Set-Content -Path $TargetFile -ErrorAction Stop
            Write-Action -Message "Removed $removedCount UserParameter entr(ies)" -Type "OK"
        }
        catch {
            Write-Action -Message "FAILED to write updated config: $($_.Exception.Message)" -Type "ERROR"
            return $false
        }
    } else {
        Write-Action -Message "WOULD REMOVE $removedCount entr(ies) (dry-run)" -Type "INFO"
    }

    return $removedCount -gt 0
}

# --- Generate include file ---
function Create-IncludeFile {
    param([string]$IncludeDirPath)

    $includeFilePath = Join-Path -Path $IncludeDirPath -ChildPath "ad-dhcp-dns-monitoring.conf"

    if ($WhatIf) {
        Write-Action -Message "WOULD CREATE: $includeFilePath" -Type "ACTION"
        Write-Action -Message "WOULD ADD $($userParameters.Count) UserParameter entries" -Type "INFO"
        return $true
    }

    # Create include directory if needed
    if (-not (Test-Path $IncludeDirPath -ErrorAction SilentlyContinue)) {
        try {
            New-Item -Path $IncludeDirPath -ItemType Directory -ErrorAction Stop | Out-Null
            Write-Action -Message "Created include directory: $IncludeDirPath" -Type "OK"
        }
        catch {
            Write-Action -Message "Failed to create include directory: $($_.Exception.Message)" -Type "ERROR"
            return $false
        }
    }

    # Generate the include file content
    $lines = @(
        "# Zabbix monitoring UserParameters for AD DS, DHCP, DNS, and Role Health"
        "# Generated by configure-zabbix-agent.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "# Do not edit manually - use configure-zabbix-agent.ps1 -Rollback to remove"
        ""
    )

    foreach ($param in $userParameters) {
        $lines += Build-UserParameterLine -Key $param.Key -Value $param.Value
    }

    # Handle rollback scenario - check if file already exists
    if (Test-Path $includeFilePath -ErrorAction SilentlyContinue) {
        Write-Action -Message "Include file already exists: $includeFilePath" -Type "WARN"
        Write-Action -Message "Backing up existing file to: $includeFilePath.bak" -Type "INFO"
        try {
            Copy-Item -Path $includeFilePath -Destination "${includeFilePath}.bak" -Force -ErrorAction Stop
        }
        catch {
            Write-Action -Message "Failed to backup existing file: $($_.Exception.Message)" -Type "WARN"
        }
    }

    try {
        $lines | Set-Content -Path $includeFilePath -ErrorAction Stop
        Write-Action -Message "Created include file: $includeFilePath ($($lines.Count - 3) UserParameter entries)" -Type "OK"
        return $true
    }
    catch {
        Write-Action -Message "Failed to create include file: $($_.Exception.Message)" -Type "ERROR"
        return $false
    }
}

# --- Main execution ---
try {
    Write-Host ""
    Write-Host "============================================"
    Write-Host "  Zabbix Monitoring Configuration Script"
    Write-Host "  AD DS / DHCP / DNS / Role Health"
    Write-Host "============================================"
    Write-Host ""

    # Determine operation mode
    if ($WhatIf) {
        Write-Action -Message "DRY-RUN MODE (WhatIf) - No changes will be made" -Type "WARN"
        Write-Host ""
    }

    if ($Rollback) {
        Write-Action -Message "ROLLBACK MODE - Removing monitoring UserParameters" -Type "WARN"
        Write-Host ""
    }

    # Find config path
    $resolvedConfigPath = $null

    # If IncludeDir is specified, use that approach instead of editing main config
    $useIncludeDir = -not [string]::IsNullOrEmpty($IncludeDir)

    if ($useIncludeDir) {
        Write-Action -Message "Using include directory mode: $IncludeDir" -Type "INFO"

        if ($Rollback) {
            $includeFilePath = Join-Path -Path $IncludeDir -ChildPath "ad-dhcp-dns-monitoring.conf"
            if (Test-Path $includeFilePath -ErrorAction SilentlyContinue) {
                if ($WhatIf) {
                    Write-Action -Message "WOULD DELETE: $includeFilePath" -Type "ACTION"
                } else {
                    try {
                        Remove-Item -Path $includeFilePath -Force -ErrorAction Stop
                        Write-Action -Message "Deleted include file: $includeFilePath" -Type "OK"
                    }
                    catch {
                        Write-Action -Message "Failed to delete include file: $($_.Exception.Message)" -Type "ERROR"
                        exit 1
                    }
                }
                Write-Action -Message "Rollback complete. Restart Zabbix agent to apply changes." -Type "INFO"
                exit 0
            } else {
                Write-Action -Message "No include file found at: $includeFilePath" -Type "INFO"
                exit 0
            }
        } else {
            $success = Create-IncludeFile -IncludeDirPath $IncludeDir
            if ($success -and -not $WhatIf) {
                Write-Action -Message "Configuration complete. Restart Zabbix agent manually to apply changes." -Type "OK"
            }
            exit 0
        }
    }

    # Traditional approach: edit main config file
    if (-not [string]::IsNullOrEmpty($ConfigPath)) {
        $resolvedConfigPath = $ConfigPath
        if (-not (Test-Path $resolvedConfigPath -ErrorAction SilentlyContinue)) {
            Write-Action -Message "Specified config path not found: $resolvedConfigPath" -Type "ERROR"
            exit 1
        }
    } else {
        $resolvedConfigPath = Find-ZabbixConfig
    }

    if (-not $resolvedConfigPath) {
        Write-Action -Message "Zabbix agent configuration file not found!" -Type "ERROR"
        Write-Action -Message "Searched common paths and registry. Specify manually with -ConfigPath." -Type "INFO"
        Write-Action -Message "Common paths checked:" -Type "INFO"
        foreach ($p in $commonConfigPaths) {
            Write-Action -Message "  - $p" -Type "INFO"
        }
        exit 1
    }

    Write-Action -Message "Using config file: $resolvedConfigPath" -Type "OK"
    Write-Host ""

    if ($Rollback) {
        $changed = Remove-UserParameters -TargetFile $resolvedConfigPath
        if ($changed) {
            Write-Action -Message "Rollback complete. Restart Zabbix agent to apply changes." -Type "OK"
        } else {
            Write-Action -Message "No monitoring UserParameter entries found to remove." -Type "INFO"
        }
    } else {
        $changed = Add-UserParameters -TargetFile $resolvedConfigPath
        if ($changed) {
            Write-Action -Message "Configuration complete. Restart Zabbix agent to apply changes." -Type "OK"
        } else {
            Write-Action -Message "No changes needed. All UserParameters already exist." -Type "INFO"
        }
    }

    exit 0
}
catch {
    Write-Host "[ERROR] Unhandled exception: $($_.Exception.Message)"
    Write-Host "[ERROR] Stack trace: $($_.ScriptStackTrace)"
    exit 1
}