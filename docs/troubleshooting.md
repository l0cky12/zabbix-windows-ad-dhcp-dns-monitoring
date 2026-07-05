# Troubleshooting Guide

This guide covers common issues encountered when deploying and using the Zabbix Windows AD DS, DHCP, and DNS monitoring templates, along with their resolutions.

---

## Table of Contents

- [Zabbix Agent Not Returning Data](#zabbix-agent-not-returning-data)
- [dcdiag / repadmin Access Denied](#dcdiag--repadmin-access-denied)
- [PowerShell Execution Policy Errors](#powershell-execution-policy-errors)
- [Event Log Access Denied](#event-log-access-denied)
- [LLD Not Discovering Anything](#lld-not-discovering-anything)
- [UserParameter Timeout](#userparameter-timeout)
- [Template Import Fails](#template-import-fails)
- [False Positives from Time Sync Checks](#false-positives-from-time-sync-checks)
- [DHCP Failover Checks on Non-Failover Servers](#dhcp-failover-checks-on-non-failover-servers)
- [General Debugging Workflow](#general-debugging-workflow)

---

## Zabbix Agent Not Returning Data

### Symptom

- Host ZBX icon is **red** (not green) in **Monitoring → Hosts**
- Items show **"Not supported"** in **Monitoring → Latest data**
- Zabbix agent test returns `ZBX_NOTSUPPORTED`

### Causes and Resolutions

| Cause | Check | Resolution |
|---|---|---|
| Agent service not running | `Get-Service ZabbixAgent*, ZabbixAgent2*` | `Start-Service ZabbixAgent` |
| Firewall blocking port 10050 | `Get-NetFirewallRule | Where-Object { $_.LocalPort -eq 10050 }` | Add firewall rule allowing inbound TCP 10050 from Zabbix server/proxy |
| UserParameter not loaded | `zabbix_agentd.exe -p | Select-String "ad.service.dcdiag"` | Verify `UserParameter` is present in config or included `.conf` file |
| Script path incorrect | Check the path in `UserParameter` definition | Ensure script exists at `C:\Scripts\<script-name>.ps1` |
| Zabbix server cannot reach agent | `Test-NetConnection -ComputerName [SERVER] -Port 10050` | Verify network routing, DNS resolution, and any intermediate firewalls |

### Resolution Steps

1. **Verify agent is running**:
   ```powershell
   Get-Service ZabbixAgent
   ```

2. **Test a UserParameter locally**:
   ```powershell
   cd "C:\Program Files\Zabbix Agent"
   .\zabbix_agentd.exe -t ad.service.dcdiag
   ```

3. **Check the agent log**:
   ```powershell
   Get-Content "C:\Program Files\Zabbix Agent\zabbix_agentd.log" -Tail 50
   ```

4. **Verify network connectivity** (from Zabbix server/proxy):
   ```bash
   nmap -p 10050 [WINDOWS_SERVER_IP]
   ```

---

## dcdiag / repadmin Access Denied

### Symptom

- `ad.service.dcdiag` item returns a non-zero value or access denied error message
- `ad.replication.summary` item shows 0 partner data or returns an error
- Running `dcdiag` or `repadmin` manually on the server shows "Access Denied"

### Cause

The Zabbix agent service account does not have sufficient Active Directory read permissions. The `LOCAL SYSTEM` account on a Domain Controller has these permissions by default, but a domain-joined non-DC or a custom service account may lack them.

### Resolution

**Option 1: Run agent as LOCAL SYSTEM on Domain Controllers**

This is the simplest approach if the Zabbix agent runs on DCs:

```powershell
# In Zabbix Agent service properties, set "Log On" to "Local System account"
Set-Service -Name ZabbixAgent -StartupType Automatic
sc.exe config ZabbixAgent obj="NT AUTHORITY\SYSTEM" type=own
Restart-Service ZabbixAgent
```

**Option 2: Grant delegated AD read permissions**

If the agent must run under a domain service account, delegate read access:

1. Open **Active Directory Users and Computers**.
2. Right-click the domain root → **Delegate Control**.
3. Add the agent's service account.
4. Delegate **Read** access to the following objects:
   - Domain DNS objects
   - Configuration naming context
   - Domain Controllers OU

Alternatively, use `dsacls`:

```cmd
dsacls "DC=[DOMAIN],DC=com" /G "[DOMAIN]\svc-zabbix:RP;user;user"
```

**Option 3: Add the account to the appropriate groups**

```powershell
Add-ADGroupMember -Identity "Domain Admins" -Members "svc-zabbix"  # Over-permissioned — use with caution
```

> **Note**: Adding the service account to Domain Admins grants full AD access but violates least-privilege principles. Use delegated read permissions instead.

---

## PowerShell Execution Policy Errors

### Symptom

- Items return `ZBX_NOTSUPPORTED` with an error message containing "Execution Policy" or "cannot be loaded because running scripts is disabled"
- Manually running the script produces: `File <script> cannot be loaded because running scripts is disabled on this system`

### Cause

PowerShell's execution policy is set to `Restricted` (default on Windows Server), which prevents script execution.

### Resolution

**Option 1: Change execution policy (permanent)**

```powershell
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
```

**Option 2: Bypass execution policy in UserParameter (no system change)**

Modify each `UserParameter` in `zabbix_agentd.conf` to include `-ExecutionPolicy Bypass`:

```
UserParameter=ad.service.dcdiag,powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Check-ServiceDCDiag.ps1"
```

**Option 3: Use Group Policy**

Set execution policy via Group Policy:
- **Computer Configuration → Administrative Templates → Windows Components → Windows PowerShell**
- Set **"Turn on Script Execution"** to **"Allow local scripts and remote signed scripts"**

---

## Event Log Access Denied

### Symptom

- Event Log items return no data or show "Access denied" in the item value
- Zabbix agent log shows errors accessing Event Log

### Cause

The Zabbix agent service account does not have read access to the Windows Event Log. The `LOCAL SYSTEM` account has this access built-in; custom accounts do not.

### Resolution

**Option 1: Run agent as LOCAL SYSTEM**

```powershell
sc.exe config ZabbixAgent obj="NT AUTHORITY\SYSTEM" type=own
Restart-Service ZabbixAgent
```

**Option 2: Add agent account to Event Log Readers group**

```powershell
Add-LocalGroupMember -Group "Event Log Readers" -Member "[DOMAIN]\svc-zabbix"
Restart-Service ZabbixAgent
```

---

## LLD Not Discovering Anything

### Symptom

- No DHCP scopes or no role-relevant volumes appear in Zabbix
- LLD rules show 0 discovered items

### Causes and Resolutions

| Cause | Check | Resolution |
|---|---|---|
| DHCP PowerShell module not installed | `Get-Module -ListAvailable DhcpServer` | Install DHCP Server role or RSAT:DHCP Server Tools |
| DNS PowerShell module not installed | `Get-Module -ListAvailable DnsServer` | Install DNS Server role or RSAT:DNS Server Tools |
| No DHCP scopes configured on server | `Get-DhcpServerv4Scope -ComputerName localhost` | Create at least one scope or exclude the server from DHCP template |
| No fixed local drives found | `Get-CimInstance Win32_LogicalDisk | Where-Object DriveType -eq 3` | Verify the server has at least one fixed drive |
| LLD script returns invalid JSON | Run the script manually to check output | Fix script output to return valid JSON. Ensure no extraneous Write-Host statements |
| Script timeout | Increase timeout (see [UserParameter Timeout](#userparameter-timeout)) | Set `Timeout=30` in agent config |

### Manually Testing LLD

```powershell
# Test DHCP scope discovery
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Check-DHCPScopeUtilization.ps1"

# Test disk discovery
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Check-DiskFreeSpace.ps1" "discover"
```

Each command should return a JSON array. If the output is empty or malformed, diagnose the script.

---

## UserParameter Timeout

### Symptom

- Items intermittently show "Not supported" or return `ZBX_NOTSUPPORTED`
- Zabbix agent log shows warnings about script execution time
- Scripts take longer than 3 seconds to complete

### Cause

The default Zabbix agent `Timeout` value is 3 seconds, which may be insufficient for PowerShell scripts that query AD DS or DHCP across slow links.

### Resolution

Increase the timeout value in `zabbix_agentd.conf`:

```conf
Timeout=30
```

Restart the agent:

```powershell
Restart-Service ZabbixAgent
```

> **Recommendation**: A timeout of 30 seconds is sufficient for most environments. Increase further if you have slow domain controllers or very large DHCP scope inventories.

---

## Template Import Fails

### Symptom

- Zabbix displays an **"Invalid YAML"** or **"version mismatch"** error when importing.
- Template does not appear in the template list after import.

### Causes and Resolutions

| Error | Cause | Resolution |
|---|---|---|
| "Invalid YAML" | File corruption or encoding issue | Re-download the template file. Validate with `python -c "import yaml; yaml.safe_load(open('template.yaml'))"` |
| "version mismatch" | Template exported from a different Zabbix version | Templates target Zabbix 6.0 LTS. If using an older version, manually adjust the `version:` field in the YAML, or re-export the template from a compatible server |
| "rule 'xxx' references non-existing template" | Template dependencies not imported | Import **all four templates** — they have no inter-dependencies, but ensure you import each one |
| Import succeeds but items are missing | Web UI cache | Log out of the Zabbix frontend and log back in |

### Checking Zabbix Version

```bash
# From the Zabbix server
zabbix_server --version
```

The templates require Zabbix **6.0 LTS or later**.

---

## False Positives from Time Sync Checks

### Symptom

- Time sync triggers fire repeatedly, especially on remote-site DCs or virtualised DCs
- Time offset values fluctuate within normal bounds but occasionally spike

### Cause

Default thresholds (`{$AD_TIME_OFFSET_WARN}=180`, `{$AD_TIME_OFFSET_CRIT}=300`, `{$AD_TIME_OFFSET_DURATION}=5m`) may be too tight for environments with:

- Virtualised domain controllers with imperfect time integration
- Remote branch offices with higher network latency
- Servers using external time sources with longer polling intervals

### Resolution

Relax the thresholds at the host level for affected servers:

```yaml
Host: DC-REMOTE-01
Macros:
  - {$AD_TIME_OFFSET_WARN}: "300"      # 5 minutes instead of 3
  - {$AD_TIME_OFFSET_CRIT}: "450"      # 7.5 minutes instead of 5
  - {$AD_TIME_OFFSET_DURATION}: "10m"  # Sustained for 10 minutes
```

Additionally, ensure the PDC emulator is synchronising with a reliable external time source:

```cmd
w32tm /config /manualpeerlist:"0.pool.ntp.org,1.pool.ntp.org" /syncfromflags:manual /reliable:yes /update
w32tm /resync
```

---

## DHCP Failover Checks on Non-Failover Servers

### Symptom

- DHCP failover items show a status indicating "No failover configured"
- No triggers fire, but the item is collecting data

### Explanation

This is **expected behaviour**. The DHCP failover monitoring items query the failover configuration on the server. If no failover relationships are configured, the script returns a non-ambiguous status such as `"No failover configured"`.

The template's triggers are designed to only fire when a failover relationship exists and enters a non-NORMAL state. Servers without failover will not produce alerts.

### No Action Required

No configuration change is needed. The items will show a consistent "No failover configured" value, and no triggers will fire. This is by design.

---

## General Debugging Workflow

Use this systematic workflow when diagnosing any issue:

### Step 1: Isolate the Problem Component

1. **Is the agent reachable?** → Check ZBX icon in **Monitoring → Hosts**
2. **Is the item collecting data?** → Check **Monitoring → Latest data**
3. **Is the script executable?** → Run the script manually on the server
4. **Is the output correct?** → Check the value returned by the item

### Step 2: Test Locally on the Target Server

```powershell
# Test agent connectivity
zabbix_agentd.exe -t ad.service.dcdiag

# Run the script directly
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Scripts\Check-ServiceDCDiag.ps1"
```

### Step 3: Check Logs

```powershell
# Zabbix agent log
Get-Content "$env:ProgramFiles\Zabbix Agent\zabbix_agentd.log" -Tail 100

# Windows Event Log (PowerShell script errors)
Get-WinEvent -LogName "Windows PowerShell" -MaxEvents 10 | Format-Table TimeCreated, Message -Wrap
```

### Step 4: Verify Configuration

```powershell
# Confirm UserParameters are loaded
zabbix_agentd.exe -p | Select-String "ad\.|dhcp\.|dns\.|role\."

# Verify script exists
Get-ChildItem C:\Scripts\

# Check PowerShell module availability
Get-Module -ListAvailable ActiveDirectory, DnsServer, DhcpServer
```

### Step 5: Escalate

If the issue persists after completing all steps above, check the **Zabbix server logs**:

```bash
# On the Zabbix server
tail -100 /var/log/zabbix/zabbix_server.log
```

Search for errors related to the host, item, or template in question. Common server-side errors include:

- `cannot connect to ... [10050]` — Agent unreachable
- `received value is not a valid JSON` — LLD or JSON-based item returned malformed data
- `preprocessing failed` — Data returned by agent failed preprocessing rules