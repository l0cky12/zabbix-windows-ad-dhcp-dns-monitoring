# Zabbix Windows AD DS, DHCP & DNS Monitoring

A collection of separate Zabbix templates for monitoring Windows Server **Active Directory Domain Services (AD DS)**, **DHCP Server**, **DNS Server**, and shared **Windows Server role health** metrics. Each template targets a specific service role and can be linked independently to the appropriate hosts, providing focused, production-ready monitoring without unnecessary overhead.

The templates use native Zabbix agent passive checks, PowerShell scripts, Event Log monitoring, and low-level discovery (LLD) to surface service availability, replication health, DNS resolution integrity, DHCP capacity, and role-relevant disk utilisation — all without third-party agents or proprietary monitoring extensions.

---

## Monitoring Scope

1. **Core role service availability and DC advertising** — `dcdiag /test:Services`, `/test:Advertising`, DHCPServer service, DNS service
2. **AD replication health** — `repadmin /replsummary`, failed partners, Event 2042, error 8614
3. **SYSVOL and NETLOGON readiness plus DFSR health** — SYSVOL/NETLOGON shares, DFSR state (4=Normal), Events 2213/4012
4. **Time sync and Kerberos skew** — W32Time, clock offset, PDC emulator
5. **DHCP scope free-address capacity** — utilisation percentage, free addresses
6. **DHCP authorisation status and failover state** — authorisation in AD, Events 1046/1051, failover NORMAL/CommDown/PARTNER_DOWN
7. **Synthetic internal DNS resolution** — A record, SOA, `_ldap._tcp.dc._msdcs` SRV records
8. **DNS AD-integrated startup readiness** — Event 4013 detection
9. **Disk free space on role-relevant volumes** — OS volume, NTDS, AD logs, SYSVOL, DHCP data

---

## Repository Structure

```
zabbix-windows-ad-dhcp-dns-monitoring/
├── README.md
├── LICENSE
├── .gitignore
├── scripts/
│   ├── configure-zabbix-agent.ps1
│   ├── github/
│   │   └── create-public-repo-and-push.sh
│   └── powershell/
│       ├── Check-ADReplication.ps1
│       ├── Check-DHCPFailoverStatus.ps1
│       ├── Check-DNSStartupEvent.ps1
│       ├── Check-DFSRServices.ps1
│       ├── Check-DHCPScopeUtilization.ps1
│       ├── Check-DiskFreeSpace.ps1
│       ├── Check-ServiceDCDiag.ps1
│       ├── Check-TimeSyncKerberos.ps1
│       └── Test-DNSQuery.ps1
├── templates/
│   ├── template_windows_ad_ds.yaml
│   ├── template_windows_dhcp.yaml
│   ├── template_windows_dns.yaml
│   └── template_windows_role_health.yaml
└── docs/
    ├── windows-server-preparation.md
    ├── zabbix-agent-configuration.md
    ├── zabbix-server-import-guide.md
    ├── required-macros.md
    └── troubleshooting.md
```

---

## Templates

| Template | Linked To | Purpose |
|---|---|---|
| **template_windows_ad_ds.yaml** | Domain Controllers only | Monitors AD DS service health, DC advertising, replication, DFSR/SYSVOL, time sync, and Kerberos clock skew |
| **template_windows_dhcp.yaml** | DHCP Server hosts | Monitors DHCP service, scope utilisation, authorisation status, and failover state |
| **template_windows_dns.yaml** | DNS Server hosts (including DCs hosting DNS) | Monitors DNS service, AD-integrated startup readiness, and synthetic DNS resolution queries |
| **template_windows_role_health.yaml** | Any monitored Windows Server with AD/DHCP/DNS roles | Monitors disk free space on role-relevant volumes discovered via LLD |

Multiple templates can be linked to the same host when that host runs multiple roles (e.g. a Domain Controller also running DNS).

---

## Supported Versions

- **Zabbix**: 6.0 LTS or later
- **Windows Server**: 2016 or later
- **Windows Server 2012 R2**: Limited support — some PowerShell modules may need manual installation via RSAT

---

## Installation Steps

1. **Deploy scripts** — Copy the contents of `scripts/powershell/` to `C:\Scripts\` on each target Windows server.
2. **Configure Zabbix agent** — Run `configure-zabbix-agent.ps1` on each target to add the required `UserParameter` entries, or merge them manually into `zabbix_agentd.conf` / an included `.conf` file.
3. **Restart Zabbix agent** — `Restart-Service ZabbixAgent` (or `ZabbixAgent2` if using agent2).
4. **Import templates** — In the Zabbix Web UI, navigate to **Configuration → Templates → Import** and select each `.yaml` template file.
5. **Link templates** — Assign the appropriate templates to each host under **Configuration → Hosts → (host) → Templates**.
6. **Configure macros** — Review and adjust macro values at the host or template level (see [Required Macros](#required-macros-and-example-values)).

---

## Zabbix Agent Configuration

The templates use **passive Zabbix agent checks** over TCP port 10050. No active agent configuration is required beyond the `UserParameter` definitions.

The `configure-zabbix-agent.ps1` script appends all required `UserParameter` entries to the Zabbix agent configuration file (default: `C:\Program Files\Zabbix Agent\zabbix_agentd.conf`). Each `UserParameter` invokes a PowerShell script from `C:\Scripts\`.

**Event Log monitoring** requires the Zabbix agent service to run as a user with event log read permissions. The built-in `LOCAL SYSTEM` account satisfies this requirement for most Windows Event Logs.

### Verifying UserParameters

Run the following on the target Windows server to confirm a `UserParameter` is loaded correctly:

```powershell
# Zabbix Agent (1.x)
zabbix_agentd.exe -t ad.service.dcdiag

# Zabbix Agent 2
zabbix_agent2.exe -t ad.service.dcdiag
```

A successful response shows the key name, data type, and value.

---

## Windows Permissions

| Permission | Required For | Notes |
|---|---|---|
| **Local Administrator** | Script deployment, agent configuration | Required during installation only |
| **Domain Admin / Delegated Read** | `dcdiag` and `repadmin` execution | These tools query AD DS; delegated read access to the Domain NC and Configuration NC is sufficient |
| **Event Log Reader** | Event Log monitoring items | Built-in for LOCAL SYSTEM; otherwise add the agent's account to the **Event Log Readers** local group |
| **PowerShell ExecutionPolicy** | Running `.ps1` scripts | Must be `RemoteSigned` or less restrictive (see below) |

---

## PowerShell Execution Policy

The Zabbix agent runs PowerShell scripts as part of each `UserParameter`. The execution policy must permit script execution:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine
```

Alternatively, bypass the policy per invocation by modifying the `UserParameter` definition to include the `-ExecutionPolicy Bypass` flag:

```
UserParameter=ad.service.dcdiag,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Check-ServiceDCDiag.ps1"
```

---

## Windows Firewall Notes

Allow inbound TCP port 10050 from your Zabbix server or proxy IP addresses:

```powershell
New-NetFirewallRule -DisplayName "Zabbix Agent" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 10050 `
    -Action Allow `
    -RemoteAddress "10.0.0.10,10.0.0.11"   # Replace with Zabbix server/proxy IPs
```

---

## Required Macros and Example Values

All macros have sensible defaults defined in the templates. Override them at the host level when a specific server requires different thresholds.

| Macro | Default | Description | Template |
|---|---|---|---|
| `{$AD_SERVICE_DOWN_TIMEOUT}` | `2m` | Time window for AD service/dcdiag failure before trigger fires | AD DS |
| `{$AD_REPL_FAILURE_TIMEOUT}` | `15m` | Time window for replication failure before trigger fires | AD DS |
| `{$AD_DFSR_UNHEALTHY_TIMEOUT}` | `10m` | Time window for DFSR unhealthy state before trigger fires | AD DS |
| `{$AD_TIME_OFFSET_WARN}` | `180` | Clock offset warning threshold (seconds) | AD DS |
| `{$AD_TIME_OFFSET_CRIT}` | `300` | Clock offset critical threshold (seconds) | AD DS |
| `{$AD_TIME_OFFSET_DURATION}` | `5m` | Time window for sustained clock offset before trigger fires | AD DS |
| `{$DHCP_SERVICE_DOWN_TIMEOUT}` | `2m` | Time window for DHCP service down before trigger fires | DHCP |
| `{$DHCP_FREE_PCT_WARN}` | `20` | Warning threshold for free address percentage | DHCP |
| `{$DHCP_FREE_PCT_CRIT}` | `10` | Critical threshold for free address percentage | DHCP |
| `{$DHCP_MIN_FREE_ADDR}` | `20` | Minimum free addresses before critical trigger | DHCP |
| `{$DHCP_FAILOVER_TIMEOUT}` | `5m` | Time window for failover state change before trigger fires | DHCP |
| `{$DNS_SERVICE_DOWN_TIMEOUT}` | `2m` | Time window for DNS service down before trigger fires | DNS |
| `{$DNS_STARTUP_WARN_TIMEOUT}` | `15m` | Warning threshold for AD DNS startup delay (minutes) | DNS |
| `{$DNS_STARTUP_CRIT_TIMEOUT}` | `20m` | Critical threshold for AD DNS startup delay (minutes) | DNS |
| `{$ROLE_DISK_FREE_PCT_WARN}` | `15` | Warning threshold for disk free percentage | Role Health |
| `{$ROLE_DISK_FREE_PCT_CRIT}` | `10` | Critical threshold for disk free percentage | Role Health |
| `{$ROLE_DISK_FREE_GB_WARN}` | `25` | Warning threshold for disk free space (GB) | Role Health |
| `{$ROLE_DISK_FREE_GB_CRIT}` | `15` | Critical threshold for disk free space (GB) | Role Health |

---

## Testing Each Check

### Service Availability & DC Advertising
Force a service stop on the target DC to verify the trigger:
```powershell
Stop-Service NTDS -Force    # Do not run in production
```
Verify the `ad.service.dcdiag` item returns a non-zero exit code and the trigger activates within `{$AD_SERVICE_DOWN_TIMEOUT}`.

### AD Replication Health
Simulate a replication failure by introducing a firewall block on port 135 or 389 between domain controllers, or use:
```powershell
repadmin /syncall /d/e
```
Check that `ad.replication.summary` shows failed partners and triggers fire after `{$AD_REPL_FAILURE_TIMEOUT}`.

### SYSVOL / NETLOGON / DFSR
Verify the DFSR event log for Events 2213 (normal) or 4012 (unhealthy). Confirm SYSVOL and NETLOGON shares are accessible:
```powershell
net share SYSVOL
net share NETLOGON
```

### Time Sync / Kerberos Skew
Temporarily set the system clock ahead by >300 seconds:
```powershell
Set-Date (Get-Date).AddMinutes(6)
```
The `ad.time.offset` item should exceed the critical threshold.

### DHCP Scope Capacity
Create a scope with a small address range and rapidly lease addresses until the free pool drops below 20%.

### DHCP Authorisation / Failover
Unauthorise the DHCP server in AD or simulate a partner-down scenario by stopping the DHCP service on the failover partner.

### DNS Resolution
Verify synthetic query items by temporarily removing the test A record or breaking the `_ldap._tcp.dc._msdcs` SRV record registration.

### DNS AD-Integrated Startup
Restart the DNS service and observe the Event 4013 check:
```powershell
Restart-Service DNS
```
The trigger should not fire within `{$DNS_STARTUP_WARN_TIMEOUT}` under normal conditions.

### Disk Free Space
Fill a monitored volume until free space drops below 15 % to trigger the warning.

---

## Troubleshooting

| Symptom | Likely Cause | Resolution |
|---|---|---|
| Zabbix agent not returning data | Agent config, firewall, or service status | Verify `zabbix_agentd.conf` includes the `UserParameter` lines; check `zabbix_agentd.exe -t <key>`; confirm inbound port 10050 is open |
| `dcdiag` / `repadmin` access denied | Insufficient AD permissions | Run Zabbix agent as a domain-joined account with delegated read access to AD |
| PowerShell scripts not executing | Execution policy or script path | Verify `ExecutionPolicy` is `RemoteSigned` or add `-ExecutionPolicy Bypass`; confirm scripts exist at `C:\Scripts\` |
| Event Log checks returning nothing | Event log read access | Run agent as LOCAL SYSTEM or add agent account to **Event Log Readers** group |
| LLD not discovering scopes / disks | Missing PowerShell modules | Install `DhcpServer` / `DnsServer` modules via Server Manager or RSAT |
| Template not visible after import | Zabbix version mismatch | Verify the template YAML version matches your Zabbix server version (6.0 LTS or later) |

---

## Assumptions and Limitations

- Templates assume **Zabbix agent or agent 2** is installed and configured on all target hosts and can reach the Zabbix server/proxy on TCP 10050.
- PowerShell scripts are expected at **`C:\Scripts\`** on every target. If a different path is used, update the `UserParameter` entries accordingly.
- Templates rely on **PowerShell modules** that must be present on the target: `ActiveDirectory` (part of RSAT), `DhcpServer`, and `DnsServer`. These are typically installed as part of the respective server roles or via RSAT.
- **DNS synthetic queries** require correct record names (`[SERVER].[DOMAIN]`, `[ZONE NAME]`, `_ldap._tcp.dc._msdcs.[DOMAIN]`) configured via host- or template-level macros.
- **DHCP failover monitoring** only activates on servers that have failover relationships configured. Servers without failover produce `"No failover configured"` status, which does not trigger alerts.
- **Disk discovery** enumerates fixed local drives only (drive type 3). Network shares, removable media, and RAM disks are excluded.
- **Event Log items** check the most recent **24 hours** of events by default. If a server processes events infrequently, adjust the lookback window or tolerate gaps.
- **AD replication checks** assume default Active Directory site link intervals. If replication schedules are non-standard, adjust trigger timeouts accordingly.

---

## License

This project is open source under the [MIT License](LICENSE).