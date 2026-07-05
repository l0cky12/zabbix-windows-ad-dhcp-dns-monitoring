# Windows DNS by Zabbix agent

## Template Name

`Windows DNS by Zabbix agent`

## Purpose

Monitors the DNS Server role on Windows Server. This template provides monitoring of DNS Server service availability, synthetic DNS query resolution (A record, SOA query, SRV `_ldap._tcp.dc._msdcs`), and DNS AD-integrated startup readiness through Event ID 4013 tracking (ephemeral vs persistent vs unexpected occurrence).

Designed for Zabbix 6.0+ environments using Zabbix agent with PowerShell-based UserParameters.

## Monitored Items

| # | Item Key | Description | Type | Value Type |
|---|----------|-------------|------|------------|
| 1 | `windows.dns.service.status` | DNS Server service running (1/0) | ZABBIX_PASSIVE | UNSIGNED |
| - | `windows.dns.service.uptime` | DNS Server service uptime (seconds) | ZABBIX_PASSIVE | UNSIGNED |
| 2 | `windows.dns.query.a` | Synthetic A record query (1/0) | ZABBIX_PASSIVE | UNSIGNED |
| 2 | `windows.dns.query.soa` | Synthetic SOA query (1/0) | ZABBIX_PASSIVE | UNSIGNED |
| 2 | `windows.dns.query.srv.ldap` | SRV `_ldap._tcp.dc._msdcs` record count | ZABBIX_PASSIVE | UNSIGNED |
| 3 | `eventlog[DNS Server,,4013,,,,0]` | DNS Event 4013 - AD startup delay | ZABBIX_ACTIVE | LOG |

Note: Items 5 (persistent 4013) and 6 (unexpected 4013) are implemented as additional triggers on the same Event 4013 log item, distinguished by the expression logic (comparing against service uptime).

## Triggers

| Trigger Name | Expression Logic | Severity | Description |
|-------------|-----------------|----------|-------------|
| DNS: Service not running | `avg()=0` for {$DNS_SERVICE_DOWN_TIMEOUT} | CRITICAL | DNS service stopped |
| DNS: Synthetic query failure (A/SOA) | `last()=0` on A or SOA queries | CRITICAL | Server not answering |
| DNS: No _ldap SRV records | `last()=0` on SRV query | CRITICAL | No DCs advertising LDAP |
| DNS: Event 4013 cleared post-reboot | 4013 appeared then cleared within {$DNS_STARTUP_WARN_TIMEOUT} | HIGH | Normal startup, informational |
| DNS: Event 4013 persistent | 4013 persists > {$DNS_STARTUP_CRIT_TIMEOUT} after boot | CRITICAL | AD DNS not loaded |
| DNS: Unexpected 4013 | 4013 when uptime > {$DNS_STARTUP_CRIT_TIMEOUT} | CRITICAL | Out-of-window event |

## Macros

| Macro | Default | Description |
|-------|---------|-------------|
| `{$DNS_SERVICE_DOWN_TIMEOUT}` | `2m` | Time before DNS service outage escalates to CRITICAL |
| `{$DNS_STARTUP_WARN_TIMEOUT}` | `15m` | Time window for normal Event 4013 post-reboot startup delay |
| `{$DNS_STARTUP_CRIT_TIMEOUT}` | `20m` | Time after which persistent Event 4013 escalates to CRITICAL |

## Tags

All items and triggers are tagged with the following classification tags:

| Tag | Values |
|-----|--------|
| `component` | `dns` |
| `scope` | `availability`, `synthetic-query`, `startup` |
| `priority` | `critical`, `high`, `info` |

## Required UserParameters

Add the following UserParameter definitions to the Zabbix agent configuration (`zabbix_agentd.conf.d/userparameter_dns.conf`) on each DNS server:

```ini
### DNS Health Checks
UserParameter=windows.dns.service.status,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_dns_service_status.ps1"
UserParameter=windows.dns.service.uptime,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_dns_service_uptime.ps1"
UserParameter=windows.dns.query.a,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_dns_query_a.ps1"
UserParameter=windows.dns.query.soa,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_dns_query_soa.ps1"
UserParameter=windows.dns.query.srv.ldap,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\scripts\windows\check_dns_query_srv_ldap.ps1"
```

## PowerShell Script Dependencies

Place the following scripts in `C:\scripts\windows\` (or adjust the path in UserParameters):

| Script | Purpose | Returns |
|--------|---------|---------|
| `check_dns_service_status.ps1` | Checks DNS Server service via `Get-Service` | "1" (Running) or "0" (stopped) |
| `check_dns_service_uptime.ps1` | Gets DNS Server process/uptime in seconds | Uptime in seconds |
| `check_dns_query_a.ps1` | Resolves domain DC A record via `Resolve-DnsName` | "1" (success) or "0" (failure) |
| `check_dns_query_soa.ps1` | Resolves domain SOA record via `Resolve-DnsName` | "1" (success) or "0" (failure) |
| `check_dns_query_srv_ldap.ps1` | Resolves `_ldap._tcp.dc._msdcs.<domain>` via `Resolve-DnsName` | Count of SRV records returned |

## Event Log Dependencies

| Event ID | Log Name | Description |
|----------|----------|-------------|
| 4013 | DNS Server | DNS server waiting for AD DS to start (AD-integrated zone loading) |

## Zabbix Agent Configuration Notes

1. Event log monitoring requires Zabbix agent **active** checks.
2. The `ServerActive` parameter must point to the Zabbix server/proxy.
3. Ensure Zabbix agent runs under an account with permissions to:
   - Read DNS Server event log
   - Execute `Resolve-DnsName` cmdlet
   - Query service status via `Get-Service`
4. The `Resolve-DnsName` cmdlet is available on Windows Server 2012 R2+ (part of `DnsClient` module).
5. For the Event 4013 triggers, the template compares event timestamps against service uptime to distinguish between:
   - Normal post-reboot startup delay (clears within {$DNS_STARTUP_WARN_TIMEOUT})
   - Persistent failure (exceeds {$DNS_STARTUP_CRIT_TIMEOUT})
   - Unexpected occurrence (appears long after startup)

## Version

1.0.0 — Compatible with Zabbix 6.0+