# Zabbix Agent Configuration

This guide explains how to configure the Zabbix agent on Windows Server targets to support the AD DS, DHCP, DNS, and Role Health monitoring templates.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Configuration Methods](#configuration-methods)
- [Full UserParameter Reference](#full-userparameter-reference)
- [Include Directory Configuration](#include-directory-configuration)
- [Verifying UserParameters](#verifying-userparameters)
- [Restarting the Zabbix Agent](#restarting-the-zabbix-agent)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

- Zabbix agent (1.x) or Zabbix agent 2 installed on the target Windows Server
- PowerShell scripts deployed to `C:\Scripts\` (see [Installation Steps](../README.md#installation-steps))
- PowerShell execution policy set to `RemoteSigned` or configured with `-ExecutionPolicy Bypass` (see [PowerShell Execution Policy](../README.md#powershell-execution-policy))
- Required Windows roles and PowerShell modules installed (see [Windows Server Preparation](windows-server-preparation.md))

---

## Configuration Methods

### Method 1: Automated Configuration (Recommended)

Run the `configure-zabbix-agent.ps1` script provided in the `scripts/` directory. This script automatically appends all required `UserParameter` entries to the Zabbix agent configuration file.

```powershell
.\configure-zabbix-agent.ps1
```

By default, the script targets `C:\Program Files\Zabbix Agent\zabbix_agentd.conf`. If your agent is installed elsewhere or you use agent 2, specify the custom path:

```powershell
.\configure-zabbix-agent.ps1 -ConfigPath "C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf"
```

### Method 2: Manual Configuration

If you prefer to manage configurations manually, merge the `UserParameter` entries from the [reference table](#full-userparameter-reference) into your agent configuration file, or place them in an included `.conf` file (see [Include Directory Configuration](#include-directory-configuration)).

---

## Full UserParameter Reference

Each `UserParameter` defined below corresponds to a specific item in one of the templates. The key naming convention is:

- `ad.*` — AD DS template items
- `dhcp.*` — DHCP template items
- `dns.*` — DNS template items
- `role.*` — Role Health template items

### AD DS UserParameters

| Key | Script | Description |
|---|---|---|
| `ad.service.dcdiag` | `Check-ServiceDCDiag.ps1` | Runs `dcdiag /test:Services /test:Advertising`; returns 0 on success, non-zero on failure |
| `ad.replication.summary` | `Check-ADReplication.ps1` | Runs `repadmin /replsummary`; returns number of failed replication partners |
| `ad.dfsr.state` | `Check-DFSRServices.ps1` | Checks DFSR service state and SYSVOL/NETLOGON share availability; returns 0=healthy, 1=unhealthy |
| `ad.time.offset` | `Check-TimeSyncKerberos.ps1` | Returns the system clock offset from the PDC emulator in seconds |
| `ad.event.replication.2042` | — (Event Log item) | Searches the Directory Service log for Event ID 2042 (USN rollback) |
| `ad.event.replication.8614` | — (Event Log item) | Searches the Directory Service log for Event ID 8614 (replication failure) |
| `ad.event.dfsr.4012` | — (Event Log item) | Searches the DFS Replication log for Event ID 4012 (service unhealthy) |

### DHCP UserParameters

| Key | Script | Description |
|---|---|---|
| `dhcp.service.status` | — (Service check) | Checks the DHCPServer service status |
| `dhcp.scope.utilization` | `Check-DHCPScopeUtilization.ps1` | Returns JSON with scope ID, total addresses, used addresses, free addresses, and free percentage for each DHCP scope |
| `dhcp.authorization.status` | `Check-DHCPFailoverStatus.ps1` | Checks whether the DHCP server is authorised in AD |
| `dhcp.failover.status` | `Check-DHCPFailoverStatus.ps1` | Returns JSON with failover relationship name, partner, and state (NORMAL, CommDown, PARTNER_DOWN) |
| `dhcp.event.auth.1046` | — (Event Log item) | Searches the DHCP Server log for Event ID 1046 (server unauthorised) |
| `dhcp.event.auth.1051` | — (Event Log item) | Searches the DHCP Server log for Event ID 1051 (server authorised) |

### DNS UserParameters

| Key | Script | Description |
|---|---|---|
| `dns.service.status` | — (Service check) | Checks the DNS service status |
| `dns.query.a` | `Test-DNSQuery.ps1` | Resolves a configured A record; returns resolution time in ms |
| `dns.query.soa` | `Test-DNSQuery.ps1` | Queries the SOA record for the configured zone |
| `dns.query.srv_ldap` | `Test-DNSQuery.ps1` | Resolves `_ldap._tcp.dc._msdcs.[DOMAIN]` SRV record |
| `dns.event.startup.4013` | `Check-DNSStartupEvent.ps1` | Checks the DNS Server log for Event ID 4013 within the configured time window |

### Role Health UserParameters

| Key | Script | Description |
|---|---|---|
| `role.discovery.volumes` | `Check-DiskFreeSpace.ps1` | LLD rule: returns JSON array of fixed local volumes (drive letter, label, type) relevant to AD/DNS/DHCP roles |
| `role.disk.free.pct[{#VOLUME}]` | `Check-DiskFreeSpace.ps1` | Returns free space percentage for a specific volume discovered by LLD |
| `role.disk.free.gb[{#VOLUME}]` | `Check-DiskFreeSpace.ps1` | Returns free space in GB for a specific volume discovered by LLD |

---

## Include Directory Configuration

To keep the main configuration file clean, place all `UserParameter` definitions in a dedicated `.conf` file inside the Zabbix agent include directory.

### Steps

1. **Locate the include directory** in your agent configuration:
   ```conf
   # Default is:
   Include=C:\Program Files\Zabbis Agent\zabbis_agentd.d\
   ```

2. **Create the include directory** if it does not exist:
   ```powershell
   New-Item -ItemType Directory -Path "C:\Program Files\Zabbix Agent\zabbix_agentd.d\" -Force
   ```

3. **Create a file named `ad-dhcp-dns-monitoring.conf`** in the include directory with all required `UserParameter` entries:
   ```
   UserParameter=ad.service.dcdiag,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Check-ServiceDCDiag.ps1"
   UserParameter=ad.replication.summary,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Check-ADReplication.ps1"
   UserParameter=ad.dfsr.state,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Check-DFSRServices.ps1"
   UserParameter=ad.time.offset,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Check-TimeSyncKerberos.ps1"
   UserParameter=dhcp.scope.utilization,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Check-DHCPScopeUtilization.ps1"
   UserParameter=dhcp.authorization.status,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Check-DHCPFailoverStatus.ps1"
   UserParameter=dhcp.failover.status,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Check-DHCPFailoverStatus.ps1"
   UserParameter=dns.query.a[*],powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Test-DNSQuery.ps1" "a" "$1"
   UserParameter=dns.query.soa[*],powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Test-DNSQuery.ps1" "soa" "$1"
   UserParameter=dns.query.srv_ldap,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Test-DNSQuery.ps1" "srv"
   UserParameter=dns.event.startup.4013[*],powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Check-DNSStartupEvent.ps1" "$1"
   UserParameter=role.discovery.volumes,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Check-DiskFreeSpace.ps1" "discover"
   UserParameter=role.disk.free.pct[*],powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Check-DiskFreeSpace.ps1" "pct" "$1"
   UserParameter=role.disk.free.gb[*],powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Check-DiskFreeSpace.ps1" "gb" "$1"
   ```

4. **Restart the Zabbix agent** (see below).

---

## Verifying UserParameters

After configuration, verify that each `UserParameter` is correctly loaded and returns data.

### Using Zabbix Agent 1.x

```powershell
# Test a single parameter
zabbix_agentd.exe -t ad.service.dcdiag

# Expected output:
# ad.service.dcdiag                                  [s|0]
# (s = string type, the value is the check result)
```

### Using Zabbix Agent 2

```powershell
zabbix_agent2.exe -t ad.service.dcdiag
```

### Testing All Parameters

```powershell
# List all loaded UserParameters
zabbix_agentd.exe -p | Select-String "^ad\.|^dhcp\.|^dns\.|^role\."
```

Common responses:

| Response | Meaning |
|---|---|
| `[s|0]` | Success — script returned exit code 0 |
| `[s|1]` | Non-zero exit — check or script encountered an issue |
| `[s|{"data":[...]}]` | JSON output from LLD rule or multi-value check |
| `ZBX_NOTSUPPORTED` | `UserParameter` not found or script failed to execute |

---

## Restarting the Zabbix Agent

After modifying the configuration, restart the agent service:

```powershell
# Zabbix Agent 1.x
Restart-Service ZabbixAgent

# Zabbix Agent 2
Restart-Service ZabbixAgent2
```

Verify the service is running:

```powershell
Get-Service ZabbixAgent, ZabbixAgent2 | Select-Object Name, Status
```

---

## Troubleshooting

| Problem | Likely Cause | Solution |
|---|---|---|
| `ZBX_NOTSUPPORTED` for all keys | Include directory misconfigured or conf file has wrong extension | Verify conf files use `.conf` extension and are in the correct include directory |
| `ZBX_NOTSUPPORTED` for a single key | Script path incorrect or script missing | Verify script exists at `C:\Scripts\<name>.ps1` |
| Script runs slowly and causes agent timeouts | Default `Timeout=3` is too low | Increase `Timeout=30` in `zabbix_agentd.conf` |
| JSON-based keys return garbled output | Newlines in script output | Ensure scripts use `Write-Host` (not `Write-Output` or `echo`) for their last output line, and suppress all other output |
| Event Log items return no data | Agent account lacks event log read access | Ensure agent runs as LOCAL SYSTEM or a member of Event Log Readers |
| `-t` test works but Zabbix server gets no data | Firewall blocking port 10050 | Verify inbound TCP 10050 is allowed from Zabbix server/proxy IPs |

---

## Agent Configuration File Locations

| Agent | Default Config Path |
|---|---|
| Zabbix Agent 1.x | `C:\Program Files\Zabbix Agent\zabbix_agentd.conf` |
| Zabbix Agent 2 | `C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf` |