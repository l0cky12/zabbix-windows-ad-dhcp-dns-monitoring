<#
.SYNOPSIS
    Disk health check for role-relevant volumes (AD, DHCP, DNS) for Zabbix monitoring.
.DESCRIPTION
    Performs disk space health checks on volumes relevant to AD DS, DHCP, DNS,
    and other Windows Server roles. Designed to be called by Zabbix UserParameter
    definitions. Returns JSON and/or single-value parsible output.
.PARAMETER DiscoverVolumes
    Discovers all fixed drives on the system. Returns JSON array for Low-Level Discovery (LLD).
    Fields: {Drive, SizeGB, Label, IsRoleRelevant}.
.PARAMETER DriveLetter
    Specifies the drive letter for volume-specific checks (e.g., "C:").
.PARAMETER CheckVolume
    Returns free space info for the specified DriveLetter.
.PARAMETER CheckOSVolume
    Returns C: drive free space info.
.PARAMETER CheckNTDSVolume
    Finds the volume containing NTDS.dit (AD database) and returns free space info.
.PARAMETER CheckADLogVolume
    Finds the volume containing AD transaction logs and returns free space info.
.PARAMETER CheckSYSVOLVolume
    Finds the volume containing SYSVOL and returns free space info.
.PARAMETER CheckDHCPDataVolume
    Finds the volume containing DHCP database and returns free space info.
.EXAMPLE
    .\check-role-disk-health.ps1 -DiscoverVolumes
    .\check-role-disk-health.ps1 -CheckVolume -DriveLetter "C:"
    .\check-role-disk-health.ps1 -CheckNTDSVolume
    .\check-role-disk-health.ps1 -CheckOSVolume
.NOTES
    Author: Zabbix Monitoring Team
    Version: 1.0
    Uses Get-Volume, Win32_LogicalDisk WMI class, and registry queries to locate
    role-specific data paths. Run with administrative privileges for best results.
    Exit Codes: 0 = success, 1 = warning/error
#>

[CmdletBinding()]
param(
    [switch]$DiscoverVolumes,
    [string]$DriveLetter = "",
    [switch]$CheckVolume,
    [switch]$CheckOSVolume,
    [switch]$CheckNTDSVolume,
    [switch]$CheckADLogVolume,
    [switch]$CheckSYSVOLVolume,
    [switch]$CheckDHCPDataVolume
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

# Helper function: Get volume info by drive letter
function Get-VolumeInfo {
    param([string]$Drive)

    try {
        # Normalize drive letter
        if ($Drive -notmatch ':$') {
            $Drive = "${Drive}:"
        }

        # Use WMI for most reliable cross-version results
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='$Drive'" -ErrorAction Stop

        if (-not $disk) {
            Write-Host "WARNING: Drive $Drive not found."
            return $null
        }

        $totalGB = [math]::Round($disk.Size / 1GB, 1)
        $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        $freePct = 0
        if ($disk.Size -gt 0) {
            $freePct = [math]::Round(($disk.FreeSpace / $disk.Size) * 100)
        }

        # Try to get volume label
        $label = ""
        try {
            $vol = Get-Volume -DriveLetter $Drive.TrimEnd(':') -ErrorAction SilentlyContinue
            if ($vol) {
                $label = $vol.FileSystemLabel
            }
        }
        catch { $label = "" }

        return @{
            Drive     = $Drive
            FreeGB    = $freeGB
            TotalGB   = $totalGB
            FreePct   = $freePct
            Label     = $label
        }
    }
    catch {
        Write-Host "Exception getting volume info for $Drive : $($_.Exception.Message)"
        return $null
    }
}

# Helper: Get drive letter from a file path
function Get-DriveFromPath {
    param([string]$Path)
    if ([string]::IsNullOrEmpty($Path)) { return $null }
    $driveInfo = [System.IO.Path]::GetPathRoot($Path)
    if ($driveInfo) {
        return $driveInfo.TrimEnd('\')
    }
    return $null
}

# Helper: Find NTDS.dit path
function Find-NTDSDatabasePath {
    try {
        $ntdsPath = $null
        # Check registry for NTDS settings
        $regKey = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" -Name "DSA Database file" -ErrorAction SilentlyContinue
        if ($regKey -and $regKey."DSA Database file") {
            $ntdsPath = $regKey."DSA Database file"
            Write-Host "NTDS database path (registry): $ntdsPath"
            return $ntdsPath
        }

        # Check common locations
        $commonPaths = @(
            "$env:SystemRoot\NTDS\ntds.dit",
            "$env:WINDIR\NTDS\ntds.dit"
        )
        foreach ($path in $commonPaths) {
            if (Test-Path $path -ErrorAction SilentlyContinue) {
                Write-Host "NTDS database found at: $path"
                return $path
            }
        }

        Write-Host "WARNING: NTDS.dit not found. Server may not be a Domain Controller."
        return $null
    }
    catch {
        Write-Host "Exception finding NTDS database: $($_.Exception.Message)"
        return $null
    }
}

# Helper: Find AD log path
function Find-ADLogPath {
    try {
        $logPath = $null
        # Check registry for AD log files
        $regKey = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" -Name "Database log files path" -ErrorAction SilentlyContinue
        if ($regKey -and $regKey."Database log files path") {
            $logPath = $regKey."Database log files path"
            Write-Host "AD log path (registry): $logPath"
            return $logPath
        }

        # Default location
        $defaultPath = "$env:SystemRoot\NTDS"
        if (Test-Path $defaultPath -ErrorAction SilentlyContinue) {
            # Check if log files exist
            $logFiles = Get-ChildItem -Path $defaultPath -Filter "*.log" -ErrorAction SilentlyContinue
            if ($logFiles -and $logFiles.Count -gt 0) {
                Write-Host "AD log files found at: $defaultPath"
                return $defaultPath
            }
        }

        return $null
    }
    catch {
        Write-Host "Exception finding AD log path: $($_.Exception.Message)"
        return $null
    }
}

# Helper: Find SYSVOL path
function Find-SYSVOLPath {
    try {
        $sysvolPath = $null
        # Check registry for SYSVOL
        $regKey = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\DFSR\Parameters\Replication\Sysvol" -Name "Root Path" -ErrorAction SilentlyContinue
        if ($regKey -and $regKey."Root Path") {
            $sysvolPath = $regKey."Root Path"
            Write-Host "SYSVOL path (registry): $sysvolPath"
            return $sysvolPath
        }

        # Common locations
        $commonPaths = @(
            "$env:SystemRoot\SYSVOL",
            "$env:WINDIR\SYSVOL",
            "$env:SystemRoot\Sysvol"
        )
        foreach ($path in $commonPaths) {
            if (Test-Path $path -ErrorAction SilentlyContinue) {
                Write-Host "SYSVOL found at: $path"
                return $path
            }
        }

        return $null
    }
    catch {
        Write-Host "Exception finding SYSVOL path: $($_.Exception.Message)"
        return $null
    }
}

# Helper: Find DHCP database path
function Find-DHCPDataPath {
    try {
        $dhcpPath = $null
        # Check registry for DHCP database path
        $regKey = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\DHCPServer\Parameters" -Name "DatabasePath" -ErrorAction SilentlyContinue
        if ($regKey -and $regKey.DatabasePath) {
            $dhcpPath = $regKey.DatabasePath
            Write-Host "DHCP data path (registry): $dhcpPath"
            return $dhcpPath
        }

        # Default location
        $defaultPath = "$env:SystemRoot\System32\dhcp"
        if (Test-Path $defaultPath -ErrorAction SilentlyContinue) {
            Write-Host "DHCP data found at: $defaultPath"
            return $defaultPath
        }

        return $null
    }
    catch {
        Write-Host "Exception finding DHCP data path: $($_.Exception.Message)"
        return $null
    }
}

# Helper: Output volume check result as JSON
function Write-VolumeResult {
    param($VolumeInfo, [string]$CheckName)

    if (-not $VolumeInfo) {
        $result = @{
            Drive          = "N/A"
            FreeGB         = -1
            TotalGB        = -1
            FreePct        = -1
            Label          = "Not found"
            IsRoleRelevant = $true
        }
        $json = $result | ConvertTo-Json -Compress
        Write-CheckResult -CheckName $CheckName -Value $json
        return $result
    }

    $result = @{
        Drive          = $VolumeInfo.Drive
        FreeGB         = $VolumeInfo.FreeGB
        TotalGB        = $VolumeInfo.TotalGB
        FreePct        = $VolumeInfo.FreePct
        Label          = $VolumeInfo.Label
        IsRoleRelevant = $true
    }
    $json = $result | ConvertTo-Json -Compress
    Write-Host "Volume: $($VolumeInfo.Drive) - Free: $($VolumeInfo.FreeGB)GB / $($VolumeInfo.TotalGB)GB ($($VolumeInfo.FreePct)%)"
    Write-CheckResult -CheckName $CheckName -Value $json
    return $result
}

# --- DiscoverVolumes ---
function Get-AllVolumes {
    try {
        Write-Host "Discovering fixed drives..."
        $drives = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop

        $volumeList = @()
        foreach ($drive in $drives) {
            $totalGB = [math]::Round($drive.Size / 1GB, 1)
            $label = ""
            try {
                $vol = Get-Volume -DriveLetter $drive.DeviceID.TrimEnd(':') -ErrorAction SilentlyContinue
                if ($vol) { $label = $vol.FileSystemLabel }
            }
            catch { }

            $volumeList += @{
                Drive          = $drive.DeviceID
                SizeGB         = $totalGB
                Label          = $label
                IsRoleRelevant = $false  # Consumer decides relevance
            }
        }

        $json = $volumeList | ConvertTo-Json -Compress
        Write-Host "Discovered $($volumeList.Count) fixed drive(s)."
        Write-Output $json
        return $volumeList
    }
    catch {
        $errMsg = "Exception discovering volumes: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return @()
    }
}

# --- CheckVolume ---
function Check-VolumeByLetter {
    param([string]$Drive)

    try {
        if ([string]::IsNullOrEmpty($Drive)) {
            Write-Host "ERROR: DriveLetter parameter is required for -CheckVolume"
            Write-Output "ERROR:NoDriveLetterProvided"
            return $null
        }

        $volInfo = Get-VolumeInfo -Drive $Drive
        $result = Write-VolumeResult -VolumeInfo $volInfo -CheckName "Volume_$Drive"
        return $result
    }
    catch {
        $errMsg = "Exception checking volume $Drive : $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return $null
    }
}

# --- CheckOSVolume ---
function Check-OSVolume {
    try {
        Write-Host "Checking OS volume (C: drive)..."
        $volInfo = Get-VolumeInfo -Drive "C:"
        $result = Write-VolumeResult -VolumeInfo $volInfo -CheckName "OSVolume"
        return $result
    }
    catch {
        $errMsg = "Exception checking OS volume: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return $null
    }
}

# --- CheckNTDSVolume ---
function Check-NTDSVolume {
    try {
        Write-Host "Checking NTDS volume..."
        $dbPath = Find-NTDSDatabasePath
        $drive = Get-DriveFromPath -Path $dbPath

        if (-not $drive) {
            Write-Host "NTDS volume not found."
            $result = Write-VolumeResult -VolumeInfo $null -CheckName "NTDSVolume"
            return $result
        }

        $volInfo = Get-VolumeInfo -Drive $drive
        $result = Write-VolumeResult -VolumeInfo $volInfo -CheckName "NTDSVolume"
        return $result
    }
    catch {
        $errMsg = "Exception checking NTDS volume: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return $null
    }
}

# --- CheckADLogVolume ---
function Check-ADLogVolume {
    try {
        Write-Host "Checking AD log volume..."
        $logPath = Find-ADLogPath
        $drive = Get-DriveFromPath -Path $logPath

        if (-not $drive) {
            Write-Host "AD log volume not found."
            $result = Write-VolumeResult -VolumeInfo $null -CheckName "ADLogVolume"
            return $result
        }

        $volInfo = Get-VolumeInfo -Drive $drive
        $result = Write-VolumeResult -VolumeInfo $volInfo -CheckName "ADLogVolume"
        return $result
    }
    catch {
        $errMsg = "Exception checking AD log volume: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return $null
    }
}

# --- CheckSYSVOLVolume ---
function Check-SYSVOLVolume {
    try {
        Write-Host "Checking SYSVOL volume..."
        $sysvolPath = Find-SYSVOLPath
        $drive = Get-DriveFromPath -Path $sysvolPath

        if (-not $drive) {
            Write-Host "SYSVOL volume not found."
            $result = Write-VolumeResult -VolumeInfo $null -CheckName "SYSVOLVolume"
            return $result
        }

        $volInfo = Get-VolumeInfo -Drive $drive
        $result = Write-VolumeResult -VolumeInfo $volInfo -CheckName "SYSVOLVolume"
        return $result
    }
    catch {
        $errMsg = "Exception checking SYSVOL volume: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return $null
    }
}

# --- CheckDHCPDataVolume ---
function Check-DHCPDataVolume {
    try {
        Write-Host "Checking DHCP data volume..."
        $dhcpPath = Find-DHCPDataPath
        $drive = Get-DriveFromPath -Path $dhcpPath

        if (-not $drive) {
            Write-Host "DHCP data volume not found."
            $result = Write-VolumeResult -VolumeInfo $null -CheckName "DHCPDataVolume"
            return $result
        }

        $volInfo = Get-VolumeInfo -Drive $drive
        $result = Write-VolumeResult -VolumeInfo $volInfo -CheckName "DHCPDataVolume"
        return $result
    }
    catch {
        $errMsg = "Exception checking DHCP data volume: $($_.Exception.Message)"
        Write-Host $errMsg
        Write-Output "ERROR:$errMsg"
        return $null
    }
}

# --- Main execution ---
try {
    $anyCheckSelected = $DiscoverVolumes -or $CheckVolume -or $CheckOSVolume -or `
                         $CheckNTDSVolume -or $CheckADLogVolume -or $CheckSYSVOLVolume -or `
                         $CheckDHCPDataVolume

    if (-not $anyCheckSelected) {
        Write-Host "ERROR: No check parameter specified."
        Write-Host "Usage: .\check-role-disk-health.ps1 [-DiscoverVolumes]"
        Write-Host "       [-CheckVolume -DriveLetter <letter>] [-CheckOSVolume]"
        Write-Host "       [-CheckNTDSVolume] [-CheckADLogVolume] [-CheckSYSVOLVolume] [-CheckDHCPDataVolume]"
        Write-Output "ERROR:NoCheckSpecified"
        exit 1
    }

    $hasFailures = $false

    if ($DiscoverVolumes) {
        $result = Get-AllVolumes
        # Discovery failure is non-fatal
    }

    if ($CheckVolume) {
        $result = Check-VolumeByLetter -Drive $DriveLetter
        if ($null -eq $result -or $result.FreePct -lt 0) { $hasFailures = $true }
    }

    if ($CheckOSVolume) {
        $result = Check-OSVolume
        if ($null -eq $result -or $result.FreePct -lt 0) { $hasFailures = $true }
    }

    if ($CheckNTDSVolume) {
        $result = Check-NTDSVolume
        if ($null -eq $result) { $hasFailures = $true }
    }

    if ($CheckADLogVolume) {
        $result = Check-ADLogVolume
        if ($null -eq $result) { $hasFailures = $true }
    }

    if ($CheckSYSVOLVolume) {
        $result = Check-SYSVOLVolume
        if ($null -eq $result) { $hasFailures = $true }
    }

    if ($CheckDHCPDataVolume) {
        $result = Check-DHCPDataVolume
        if ($null -eq $result) { $hasFailures = $true }
    }

    if ($hasFailures) {
        exit 1
    } else {
        exit 0
    }
}
catch {
    Write-Host "Unhandled exception in check-role-disk-health.ps1: $($_.Exception.Message)"
    Write-Output "UNHANDLED_ERROR:$($_.Exception.Message)"
    exit 1
}