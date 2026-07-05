# Windows AD DS by Zabbix agent

## Template Name

`Windows AD DS by Zabbix agent`

## Purpose

Monitors Active Directory Domain Services health on Windows Server domain controllers. This template provides comprehensive monitoring of AD DS availability, replication health, SYSVOL/NETLOGON readiness, DFSR state, time synchronization (Kerberos compliance), and critical AD-related Windows Event Log events.

Designed for Zabbix 6.0+ environments using Zabbix agent (passive and active checks) with PowerShell-based UserParameters.

## Monitored Items

| # | Item Key | Description | Type | Value Type |
|---|----------|-------------|------|------------|
| 1 | `windows.ad.dcdiag.services` | dcdiag /test:Services - PASS/FAIL | ZABBIX_PASSIVE | TEXT |
| 2 | `windows.ad.dcdiag.advertising` | dcdiag /test:Advertising - PASS/FAIL | ZABBIX_PASSIVE | TEXT |
| 3 | `windows.ad.replication.failures` | repadmin /replsummary failure count | ZABBIX_PASSIVE | UNSIGNED |
| 4 | `windows.ad.replication.oldest.age` | Oldest successful replication age (hours) | ZABBIX_PASSIVE | UNSIGNED |
| 5 | `windows.ad.sysvol.share` | SYSVOL share availability (1/0) | ZABBIX_PASSIVE | UNSIGNED |
| 6 | `windows.ad.netlogon.share` | NETLOGON share availability (1/0) | ZABBIX_PASSIVE | UNSIGNED |
| 7 | `windows.ad.dfsr.sysvol.state` | DFSR SYSVOL state (expected: 4=Normal) | ZABBIX_PASSIVE | UNSIGNED |
| 8 | `eventlog[DFS Replication,,2213,,,,0]` | DFSR Event 2213 | ZABBIX_ACTIVE | LOG |
| 9 | `eventlog[DFS Replication,,4012,,,,0]` | DFSR Event 4012 | ZABBIX_ACTIVE | LOG |
| 10 | `windows.ad.w32time.status` | W32Time service running (1/0) | ZABBIX_PASSIVE | UNSIGNED |
| 11 | `windows.ad.time.offset` | Clock offset from time source (seconds) | ZABBIX_PASSIVE | UNSIGNED |
| 12 | `windows.ad.pdc.time.health` | PDC emulator time health (0=healthy) | ZABBIX_PASSIVE | UNSIGNED |
| 13 | `eventlog[Directory Service,,2042,,,,0]` | Event 2042 - tombstone exceeded | ZABBIX_ACTIVE | LOG |
| 14 | `eventlog[Directory Service,,8614,,,,0]` | Event 8614 - replication error | ZABBIX_ACTIVE | LOG |

## Triggers

| Trigger Name | Expression | Severity | Description |
|-------------|------------|----------|-------------|
| AD: dcdiag /test:Services failed | `avg()>{$AD_SERVICE_DOWN_TIMEOUT}` | CRITICAL | Core AD services not running |
| AD: dcdiag /test:Advertising failed | `avg()>{$AD_SERVICE_DOWN_TIMEOUT}` | CRITICAL | DC not advertising itself |
| AD: Replication failures detected | `min()>{$AD_REPL_FAILURE_TIMEOUT}` | CRITICAL | Replication errors sustained |
| AD: SYSVOL share is missing | `last()=0` | CRITICAL | SYSVOL unavailable |
| AD: NETLOGON share is missing | `last()=0` | CRITICAL | NETLOGON unavailable |
| AD: DFSR SYSVOL state not Normal | `min()<>{$AD_DFSR_UNHEALTHY_TIMEOUT}` | CRITICAL | DFSR state != 4 |
| AD: DFSR Event 2213 detected | `last()>0` | CRITICAL | Immediate |
| AD: DFSR Event 4012 detected | `last()>0` | CRITICAL | Immediate |
| AD: Clock offset warning | `min()>={$AD_TIME_OFFSET_WARN}` | HIGH | Offset > 3 min |
| AD: Clock offset critical | `min()>={$AD_TIME_OFFSET_CRIT}` | CRITICAL | Offset > 5 min |
| AD: Event 2042 - tombstone exceeded | `last()>0` | CRITICAL | Immediate |
| AD: Event 8614 - replication error | `last()>0` | CRITICAL | Immediate |

## Macros

| Macro | Default | Description |
|-------|---------|-------------|
| `{$AD_SERVICE_DOWN_TIMEOUT}` | `2m` | Time before dcdiag failure escalates to CRITICAL |
| `{$AD_REPL_FAILURE_TIMEOUT}` | `15m` | Time before replication failures escalate to CRITICAL |
| `{$AD_DFSR_UNHEALTHY_TIMEOUT}` | `10m` | Time before non-Normal DFSR state escalates to CRITICAL |
| `{$AD_TIME_OFFSET_WARN}` | `180` | Clock offset warning threshold (seconds) |
| `{$AD_TIME_OFFSET_CRIT}` | `300` | Clock offset critical threshold (seconds) |
| `{$AD_TIME_OFFSET_DURATION}` | `5m` | Duration offset must exceed threshold before triggering |

## Tags

All items and triggers are tagged with the following classification tags:

| Tag | Values |
|-----|--------|
| `component` | `active-directory` |
| `scope` | `availability`, `advertising`, `replication`, `sysvol`, `dfsr`, `time-sync` |
| `priority` | `critical`, `high` |

## Required UserParameters

Add the following UserParameter definitions to the Zabbix agent configuration (`zabbix_agentd.conf.d/userparameter_ad.conf`) on each domain controller:

```ini
### AD DS Health Checks
UserParameter=windows.ad.dcdiag.services,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_dcdiag_services.ps1"
UserParameter=windows.ad.dcdiag.advertising,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_dcdiag_advertising.ps1"
UserParameter=windows.ad.replication.failures,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_repadmin_failures.ps1"
UserParameter=windows.ad.replication.oldest.age,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_replication_oldest_age.ps1"
UserParameter=windows.ad.sysvol.share,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_sysvol_share.ps1"
UserParameter=windows.ad.netlogon.share,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_netlogon_share.ps1"
UserParameter=windows.ad.dfsr.sysvol.state,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_dfsr_sysvol_state.ps1"
UserParameter=windows.ad.w32time.status,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_w32time_status.ps1"
UserParameter=windows.ad.time.offset,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_time_offset.ps1"
UserParameter=windows.ad.pdc.time.health,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_pdc_time_health.ps1"
```

## PowerShell Script Dependencies

Place the following scripts in `C:\scripts\windows\` (or adjust the path in UserParameters):

| Script | Purpose | Returns |
|--------|---------|---------|
| `check_dcdiag_services.ps1` | Runs `dcdiag /test:Services /q` | "0" (PASS) or "1" (FAIL) |
| `check_dcdiag_advertising.ps1` | Runs `dcdiag /test:Advertising /q` | "0" (PASS) or "1" (FAIL) |
| `check_repadmin_failures.ps1` | Runs `repadmin /replsummary` | Count of failures |
| `check_replication_oldest_age.ps1` | Parses repadmin for oldest last-success | Age in hours |
| `check_sysvol_share.ps1` | Checks `net share` for SYSVOL | "1" (exists) or "0" (missing) |
| `check_netlogon_share.ps1` | Checks `net share` for NETLOGON | "1" (exists) or "0" (missing) |
| `check_dfsr_sysvol_state.ps1` | Checks DFSR state via WMI/Get-DfsrState | State number (4=Normal) |
| `check_w32time_status.ps1` | Checks W32Time service via `Get-Service` | "1" (Running) or "0" (stopped) |
| `check_time_offset.ps1` | Runs `w32tm /stripchart` | Absolute offset in seconds |
| `check_pdc_time_health.ps1` | Validates PDCe time source | "0" (healthy) or "1" (error) |

## Event Log Dependencies

The following items use Zabbix active agent eventlog monitoring and require no additional scripting:

| Event ID | Log Name | Description |
|----------|----------|-------------|
| 2213 | DFS Replication | SYSVOL initial sync completed |
| 4012 | DFS Replication | DFSR replication error |
| 2042 | Directory Service | Tombstone lifetime exceeded |
| 8614 | Directory Service | Replication error |

## Zabbix Agent Configuration Notes

1. Event log monitoring (items 8, 9, 13, 14) requires Zabbix agent **active** checks.
2. The `ServerActive` parameter must point to the Zabbix server/proxy.
3. `EnableRemoteCommands=1` is **not required** — PowerShell scripts are executed locally via UserParameter.
4. Ensure the Zabbix agent service account has permissions to:
   - Execute `dcdiag`, `repadmin`, `w32tm` commands
   - Read DFS Replication and Directory Service event logs
   - Query WMI for DFSR state
5. For Event Log items with `delay: "0"`, the Zabbix agent collects events in near-real-time.

## Version

1.0.0 — Compatible with Zabbix 6.0+
