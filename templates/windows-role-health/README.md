# Windows Role Health by Zabbix agent

## Template Name

`Windows Role Health by Zabbix agent`

## Purpose

Supplementary template for monitoring Windows Server role health on domain controllers and DHCP/DNS servers. This template provides infrastructure-level health checks — disk free space on role-relevant volumes (NTDS database, AD transaction logs, SYSVOL, DHCP database), OS volume capacity via low-level discovery, and shared time synchronization health (W32Time service status, clock offset).

This template is designed to be **linked alongside** the AD DS, DHCP, or DNS templates. It does not duplicate the service-critical checks in those templates but adds the supporting infrastructure health layer (disk and time) that keeps those roles stable.

Designed for Zabbix 6.0+ environments using Zabbix agent with PowerShell-based UserParameters and low-level discovery (LLD) for fixed drives.

## Monitored Items

### Static Items (Role-Relevant Volumes & Time)

| # | Item Key | Description | Type | Value Type |
|---|----------|-------------|------|------------|
| 6 | `windows.health.w32time.status` | W32Time service running (1/0) | ZABBIX_PASSIVE | UNSIGNED |
| 7 | `windows.health.time.offset` | Clock offset from time source (seconds) | ZABBIX_PASSIVE | UNSIGNED |
| 2 | `windows.health.disk.ntds.pct` | NTDS database volume free (%) | ZABBIX_PASSIVE | FLOAT |
| 2 | `windows.health.disk.ntds.gb` | NTDS database volume free (GB) | ZABBIX_PASSIVE | FLOAT |
| 3 | `windows.health.disk.adlogs.pct` | AD transaction logs volume free (%) | ZABBIX_PASSIVE | FLOAT |
| 3 | `windows.health.disk.adlogs.gb` | AD transaction logs volume free (GB) | ZABBIX_PASSIVE | FLOAT |
| 4 | `windows.health.disk.sysvol.pct` | SYSVOL volume free (%) | ZABBIX_PASSIVE | FLOAT |
| 4 | `windows.health.disk.sysvol.gb` | SYSVOL volume free (GB) | ZABBIX_PASSIVE | FLOAT |
| 5 | `windows.health.disk.dhcp.pct` | DHCP database volume free (%) | ZABBIX_PASSIVE | FLOAT |
| 5 | `windows.health.disk.dhcp.gb` | DHCP database volume free (GB) | ZABBIX_PASSIVE | FLOAT |

### LLD-Discovered Items (All Fixed Drives)

| # | Item Key | Description | Type | Value Type |
|---|----------|-------------|------|------------|
| 1 | `windows.health.disk.pct[{#DISK_LETTER}]` | Free space % for drive {#DISK_LETTER} | ZABBIX_PASSIVE | FLOAT |
| 1 | `windows.health.disk.gb[{#DISK_LETTER}]` | Free space GB for drive {#DISK_LETTER} | ZABBIX_PASSIVE | FLOAT |

## Triggers

| Trigger Name | Expression Logic | Severity | Description |
|-------------|-----------------|----------|-------------|
| NTDS volume low space | `<{$ROLE_DISK_FREE_PCT_WARN}%` or `<{$ROLE_DISK_FREE_GB_WARN}GB` | HIGH | NTDS volume warning |
| NTDS volume critical space | `<{$ROLE_DISK_FREE_PCT_CRIT}%` or `<{$ROLE_DISK_FREE_GB_CRIT}GB` | CRITICAL | NTDS volume critical |
| AD logs volume low space | `<{$ROLE_DISK_FREE_PCT_WARN}%` or `<{$ROLE_DISK_FREE_GB_WARN}GB` | HIGH | AD logs volume warning |
| AD logs volume critical space | `<{$ROLE_DISK_FREE_PCT_CRIT}%` or `<{$ROLE_DISK_FREE_GB_CRIT}GB` | CRITICAL | AD logs volume critical |
| SYSVOL volume low space | `<{$ROLE_DISK_FREE_PCT_WARN}%` or `<{$ROLE_DISK_FREE_GB_WARN}GB` | HIGH | SYSVOL volume warning |
| SYSVOL volume critical space | `<{$ROLE_DISK_FREE_PCT_CRIT}%` or `<{$ROLE_DISK_FREE_GB_CRIT}GB` | CRITICAL | SYSVOL volume critical |
| DHCP data volume low space | `<{$ROLE_DISK_FREE_PCT_WARN}%` or `<{$ROLE_DISK_FREE_GB_WARN}GB` | HIGH | DHCP volume warning |
| DHCP data volume critical space | `<{$ROLE_DISK_FREE_PCT_CRIT}%` or `<{$ROLE_DISK_FREE_GB_CRIT}GB` | CRITICAL | DHCP volume critical |

## Macros

| Macro | Default | Description |
|-------|---------|-------------|
| `{$ROLE_DISK_FREE_PCT_WARN}` | `15` | Warning threshold for disk free space percentage |
| `{$ROLE_DISK_FREE_PCT_CRIT}` | `10` | Critical threshold for disk free space percentage |
| `{$ROLE_DISK_FREE_GB_WARN}` | `25` | Warning threshold for disk free space in GB |
| `{$ROLE_DISK_FREE_GB_CRIT}` | `15` | Critical threshold for disk free space in GB |

## Tags

All items and triggers are tagged with the following classification tags:

| Tag | Values |
|-----|--------|
| `component` | `role-health` |
| `scope` | `disk-capacity`, `time-sync` |
| `priority` | `critical`, `high`, `info` |

## Required UserParameters

Add the following UserParameter definitions to the Zabbix agent configuration (`zabbix_agentd.conf.d/userparameter_role_health.conf`) on each monitored server:

```ini
### Role Health Checks - Time Sync
UserParameter=windows.health.w32time.status,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_w32time_status.ps1"
UserParameter=windows.health.time.offset,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_time_offset.ps1"

### Role Health Checks - Disk Discovery
UserParameter=windows.health.discover.disks,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\discover_fixed_disks.ps1"
UserParameter=windows.health.disk.pct[*],powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_disk_free_pct.ps1" "$1"
UserParameter=windows.health.disk.gb[*],powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_disk_free_gb.ps1" "$1"

### Role Health Checks - Role-Specific Volumes
UserParameter=windows.health.disk.ntds.pct,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_disk_ntds_free_pct.ps1"
UserParameter=windows.health.disk.ntds.gb,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_disk_ntds_free_gb.ps1"
UserParameter=windows.health.disk.adlogs.pct,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_disk_adlogs_free_pct.ps1"
UserParameter=windows.health.disk.adlogs.gb,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_disk_adlogs_free_gb.ps1"
UserParameter=windows.health.disk.sysvol.pct,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_disk_sysvol_free_pct.ps1"
UserParameter=windows.health.disk.sysvol.gb,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_disk_sysvol_free_gb.ps1"
UserParameter=windows.health.disk.dhcp.pct,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_disk_dhcp_free_pct.ps1"
UserParameter=windows.health.disk.dhcp.gb,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_disk_dhcp_free_gb.ps1"
```

## PowerShell Script Dependencies

Place the following scripts in `C:\scripts\windows\` (or adjust the path in UserParameters):

| Script | Purpose | Returns |
|--------|---------|---------|
| `check_w32time_status.ps1` | Checks W32Time service via `Get-Service` | "1" (Running) or "0" (stopped) |
| `check_time_offset.ps1` | Runs `w32tm /stripchart` | Absolute offset in seconds |
| `discover_fixed_disks.ps1` | Discovers all fixed drives via `Get-Volume` or `Get-WmiObject` | LLD JSON with {#DISK_LETTER}, {#DISK_LABEL}, {#DISK_SIZE_GB} |
| `check_disk_free_pct.ps1` | Gets free % for a drive letter | Percentage (float) |
| `check_disk_free_gb.ps1` | Gets free GB for a drive letter | GB (float) |
| `check_disk_ntds_free_pct.ps1` | Finds NTDS volume from registry, returns free % | Percentage (float) |
| `check_disk_ntds_free_gb.ps1` | Finds NTDS volume from registry, returns free GB | GB (float) |
| `check_disk_adlogs_free_pct.ps1` | Finds AD logs volume from registry, returns free % | Percentage (float) |
| `check_disk_adlogs_free_gb.ps1` | Finds AD logs volume from registry, returns free GB | GB (float) |
| `check_disk_sysvol_free_pct.ps1` | Finds SYSVOL volume from share path, returns free % | Percentage (float) |
| `check_disk_sysvol_free_gb.ps1` | Finds SYSVOL volume from share path, returns free GB | GB (float) |
| `check_disk_dhcp_free_pct.ps1` | Finds DHCP data volume from registry, returns free % | Percentage (float) |
| `check_disk_dhcp_free_gb.ps1` | Finds DHCP data volume from registry, returns free GB | GB (float) |

## Low-Level Discovery Details

The LLD rule `windows.health.discover.disks` runs hourly and discovers all fixed (local) drives. The discovery script must return a valid Zabbix LLD JSON structure:

```json
{
  "data": [
    {
      "{#DISK_LETTER}": "C",
      "{#DISK_LABEL}": "System",
      "{#DISK_SIZE_GB}": "238"
    },
    {
      "{#DISK_LETTER}": "E",
      "{#DISK_LABEL}": "Data",
      "{#DISK_SIZE_GB}": "476"
    }
  ]
}
```

## Volume Lookup Mechanism

The role-specific volume items (NTDS, AD logs, SYSVOL, DHCP) use registry paths to identify the correct volume:

| Role | Registry Key | Registry Value |
|------|-------------|----------------|
| NTDS | `HKLM\SYSTEM\CurrentControlSet\Services\NTDS\Parameters` | `DSA Database file` |
| AD Logs | `HKLM\SYSTEM\CurrentControlSet\Services\NTDS\Parameters` | `DSA Log file` |
| SYSVOL | `HKLM\SYSTEM\CurrentControlSet\Services\DFSR\Parameters\Replication` | SYSVOL share path (or net share) |
| DHCP | `HKLM\SYSTEM\CurrentControlSet\Services\DHCPServer\Parameters` | `DatabasePath` |

The corresponding script extracts the path, determines the drive letter, and reports free space for that volume.

## Version

1.0.0 — Compatible with Zabbix 6.0+