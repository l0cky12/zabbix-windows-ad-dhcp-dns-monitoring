# Windows DHCP by Zabbix agent

## Template Name

`Windows DHCP by Zabbix agent`

## Purpose

Monitors the DHCP Server role on Windows Server. This template provides comprehensive monitoring of DHCP service availability, scope capacity (free address percentage), Active Directory authorization status, failover state health, and critical DHCP-related Windows Event Log events.

Designed for Zabbix 6.0+ environments using Zabbix agent with PowerShell-based UserParameters and low-level discovery (LLD) for DHCP scopes.

## Monitored Items

### Static Items

| # | Item Key | Description | Type | Value Type |
|---|----------|-------------|------|------------|
| 1 | `windows.dhcp.service.status` | DHCPServer service running (1/0) | ZABBIX_PASSIVE | UNSIGNED |
| 3 | `windows.dhcp.authorization.status` | DHCP authorized in AD (1/0) | ZABBIX_PASSIVE | UNSIGNED |
| 4 | `eventlog[System,,1046,DhcpServer,,,,0]` | DHCP Event 1046 - unauthorized | ZABBIX_ACTIVE | LOG |
| 5 | `eventlog[System,,1051,DhcpServer,,,,0]` | DHCP Event 1051 - operational | ZABBIX_ACTIVE | LOG |
| 7 | `windows.dhcp.failover.commdown` | Failover CommDown scope count | ZABBIX_PASSIVE | UNSIGNED |
| 8 | `windows.dhcp.failover.partnerdown` | Failover PARTNER DOWN scope count | ZABBIX_PASSIVE | UNSIGNED |

### LLD-Discovered Per-Scope Items

| # | Item Key | Description | Type | Value Type |
|---|----------|-------------|------|------------|
| 2 | `windows.dhcp.scope.free.pct[{#SCOPE_ID}]` | Scope free address % | ZABBIX_PASSIVE | FLOAT |
| - | `windows.dhcp.scope.free.count[{#SCOPE_ID}]` | Scope free address count | ZABBIX_PASSIVE | UNSIGNED |
| 6 | `windows.dhcp.scope.failover.state[{#SCOPE_ID}]` | Scope failover state (0=NORMAL) | ZABBIX_PASSIVE | UNSIGNED |

## Triggers

| Trigger Name | Expression | Severity | Description |
|-------------|------------|----------|-------------|
| DHCP: DHCPServer service not running | `avg()=0` for {$DHCP_SERVICE_DOWN_TIMEOUT} | CRITICAL | Service down |
| DHCP: Server unauthorized in AD | `last()=0` | CRITICAL | Not authorized |
| DHCP: Event 1046 - unauthorized | `last()>0` | CRITICAL | Immediate |
| DHCP: Event 1051 | `last()>0` | CRITICAL | Immediate |
| DHCP: Scope free < {$DHCP_FREE_PCT_WARN}% | `last()<{$DHCP_FREE_PCT_WARN}` | HIGH | Capacity warning |
| DHCP: Scope critically low free | `last()<{$DHCP_FREE_PCT_CRIT}%` or `<{$DHCP_MIN_FREE_ADDR}` | CRITICAL | Capacity critical |
| DHCP: Failover not NORMAL | `min()<>0` for {$DHCP_FAILOVER_TIMEOUT} | CRITICAL | Failover degraded |
| DHCP: CommDown state | `min()>0` for {$DHCP_FAILOVER_TIMEOUT} | CRITICAL | Communication down |
| DHCP: PARTNER DOWN state | `min()>0` for {$DHCP_FAILOVER_TIMEOUT} | CRITICAL | Partner unavailable |

## Macros

| Macro | Default | Description |
|-------|---------|-------------|
| `{$DHCP_SERVICE_DOWN_TIMEOUT}` | `2m` | Time before service outage escalates to CRITICAL |
| `{$DHCP_FREE_PCT_WARN}` | `20` | Warning threshold for scope free address percentage |
| `{$DHCP_FREE_PCT_CRIT}` | `10` | Critical threshold for scope free address percentage |
| `{$DHCP_MIN_FREE_ADDR}` | `20` | Minimum free address count before CRITICAL alert |
| `{$DHCP_FAILOVER_TIMEOUT}` | `5m` | Time before failover state degradation escalates to CRITICAL |

## Tags

All items and triggers are tagged with the following classification tags:

| Tag | Values |
|-----|--------|
| `component` | `dhcp` |
| `scope` | `availability`, `authorization`, `capacity`, `failover`, `operational` |
| `priority` | `critical`, `high` |

## Required UserParameters

Add the following UserParameter definitions to the Zabbix agent configuration (`zabbix_agentd.conf.d/userparameter_dhcp.conf`) on each DHCP server:

```ini
### DHCP Health Checks
UserParameter=windows.dhcp.service.status,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_dhcp_service_status.ps1"
UserParameter=windows.dhcp.authorization.status,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_dhcp_authorization.ps1"
UserParameter=windows.dhcp.failover.commdown,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_dhcp_failover_commdown.ps1"
UserParameter=windows.dhcp.failover.partnerdown,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_dhcp_failover_partnerdown.ps1"
UserParameter=windows.dhcp.discover.scopes,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\discover_dhcp_scopes.ps1"
UserParameter=windows.dhcp.scope.free.pct[*],powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_dhcp_scope_free_pct.ps1" "$1"
UserParameter=windows.dhcp.scope.free.count[*],powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_dhcp_scope_free_count.ps1" "$1"
UserParameter=windows.dhcp.scope.failover.state[*],powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_dhcp_scope_failover_state.ps1" "$1"
```

## PowerShell Script Dependencies

Place the following scripts in `C:\scripts\windows\` (or adjust the path in UserParameters):

| Script | Purpose | Returns |
|--------|---------|---------|
| `check_dhcp_service_status.ps1` | Checks DHCPServer service via `Get-Service` | "1" (Running) or "0" (stopped) |
| `check_dhcp_authorization.ps1` | Checks authorization via `Get-DhcpServerInDC` | "1" (authorized) or "0" (not authorized) |
| `check_dhcp_failover_commdown.ps1` | Counts scopes in CommDown state | Count (0 = healthy) |
| `check_dhcp_failover_partnerdown.ps1` | Counts scopes in PARTNER DOWN state | Count (0 = healthy) |
| `discover_dhcp_scopes.ps1` | Discovers all scopes via `Get-DhcpServerv4Scope` | LLD JSON with {#SCOPE_ID}, {#SCOPE_NAME}, {#SCOPE_SUBNETMASK} |
| `check_dhcp_scope_free_pct.ps1` | Calculates free % for a specific scope ID | Percentage (float) |
| `check_dhcp_scope_free_count.ps1` | Returns free address count for a scope ID | Count (unsigned) |
| `check_dhcp_scope_failover_state.ps1` | Returns failover state for a scope ID | 0=NORMAL, 1=CommDown, 2=PARTNER DOWN |

## Low-Level Discovery Details

The LLD rule `windows.dhcp.discover.scopes` runs hourly and discovers all IPv4 DHCP scopes. The discovery script must return a valid Zabbix LLD JSON structure:

```json
{
  "data": [
    {
      "{#SCOPE_ID}": "10.0.1.0",
      "{#SCOPE_NAME}": "Office VLAN 10",
      "{#SCOPE_SUBNETMASK}": "255.255.255.0"
    }
  ]
}
```

## Event Log Dependencies

The following items use Zabbix active agent eventlog monitoring:

| Event ID | Log Name | Source | Description |
|----------|----------|--------|-------------|
| 1046 | System | DhcpServer | Detected as unauthorized by another DHCP server |
| 1051 | System | DhcpServer | DHCP service operational issue |

## Zabbix Agent Configuration Notes

1. Event log monitoring requires Zabbix agent **active** checks.
2. The `ServerActive` parameter must point to the Zabbix server/proxy.
3. Ensure Zabbix agent runs under an account with permissions to:
   - Execute `Get-DhcpServerv4Scope` and related DHCP cmdlets
   - Read System event log for DHCP Server source events
4. DHCP Server PowerShell module (`DhcpServer`) must be available on the monitored server.
   - Install via: `Add-WindowsFeature -Name DHCP`

## Version

1.0.0 — Compatible with Zabbix 6.0+