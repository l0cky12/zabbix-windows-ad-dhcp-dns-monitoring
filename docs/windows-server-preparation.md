# Windows Server Preparation Guide

This guide covers the prerequisites required on each target Windows Server before deploying the Zabbix AD DS, DHCP, and DNS monitoring templates.

---

## Table of Contents

- [Required Windows Roles and Features](#required-windows-roles-and-features)
- [Required Permissions](#required-permissions)
- [Required PowerShell Modules](#required-powershell-modules)
- [Installing RSAT on Server Core vs Desktop Experience](#installing-rsat-on-server-core-vs-desktop-experience)
- [Validation Commands](#validation-commands)

---

## Required Windows Roles and Features

The monitoring templates rely on PowerShell cmdlets and diagnostic tools that are part of specific Windows Server roles or Remote Server Administration Tools (RSAT). Install the roles corresponding to the services running on each server.

| Role / Feature | Required For | Installed With |
|---|---|---|
| **Active Directory Domain Services** | `dcdiag`, `repadmin`, ActiveDirectory module | AD DS role on Domain Controllers |
| **DNS Server** | `DnsServer` PowerShell module | DNS Server role |
| **DHCP Server** | `DhcpServer` PowerShell module | DHCP Server role |
| **RSAT: AD DS and AD LDS Tools** | ActiveDirectory module on non-DCs | RSAT feature |
| **RSAT: DNS Server Tools** | `DnsServer` module on non-DNS-servers | RSAT feature |
| **RSAT: DHCP Server Tools** | `DhcpServer` module on non-DHCP-servers | RSAT feature |

> **Note**: Domain Controllers automatically include the necessary AD DS and DNS tools. DHCP Servers automatically include the `DhcpServer` module when the role is installed.

---

## Required Permissions

### Zabbix Agent Service Account

The Zabbix agent service runs the PowerShell scripts that perform monitoring checks. The account under which the agent runs must have:

| Permission | Scope | Reason |
|---|---|---|
| **Event Log Read** | Local machine | Read Windows Event Logs (DS, DNS, DHCP) |
| **Active Directory Read** | Domain NC, Configuration NC | Execute `dcdiag`, `repadmin`, and Active Directory module cmdlets |
| **Local Administrator** | _(optional, installation only)_ | Deploy scripts and configure the Zabbix agent |

**Recommendations:**

- For **Event Log monitoring**: The built-in `LOCAL SYSTEM` account has sufficient event log read access on all Windows versions. No additional configuration is required.
- For **AD DS monitoring**: If the Zabbix agent runs as `LOCAL SYSTEM` on a Domain Controller, it automatically has sufficient AD read permissions. If the agent runs on a non-DC or under a different account, delegate read access to the Domain and Configuration naming contexts, or add the account to the **Event Log Readers** group and grant the necessary AD permissions.
- For **DHCP authorisation checks**: The DHCP server's computer account or the agent's domain account must be able to read the `dhcpClass` objects in the AD Configuration NC.

### Event Log Readers Group

If the Zabbix agent does **not** run as `LOCAL SYSTEM`, add its service account to the local **Event Log Readers** group:

```powershell
Add-LocalGroupMember -Group "Event Log Readers" -Member "DOMAIN\svc-zabbix"
```

---

## Required PowerShell Modules

The following PowerShell modules must be available on each target server. They are typically installed as part of the respective server role or via RSAT.

| Module | Provides Cmdlets For | Availability |
|---|---|---|
| **ActiveDirectory** | `Get-ADDomainController`, `Get-ADReplication*`, AD-related queries | AD DS role or RSAT |
| **DnsServer** | `Get-DnsServerZone`, `Resolve-DnsName`, `Get-DnsServerResourceRecord` | DNS Server role or RSAT |
| **DhcpServer** | `Get-DhcpServerv4Scope`, `Get-DhcpServerv4ScopeStatistics`, `Get-DhcpServerv4Failover` | DHCP Server role or RSAT |

### Checking Installed Modules

```powershell
Get-Module -ListAvailable ActiveDirectory, DnsServer, DhcpServer
```

A module that is not listed must be installed via Server Manager, `Install-WindowsFeature`, or RSAT.

---

## Installing RSAT on Server Core vs Desktop Experience

### Server with Desktop Experience (GUI)

Use **Server Manager** or PowerShell:

```powershell
# Install AD DS and LDS Tools
Install-WindowsFeature -Name RSAT-ADDS-Tools

# Install DNS Server Tools
Install-WindowsFeature -Name RSAT-DNS-Server

# Install DHCP Server Tools
Install-WindowsFeature -Name RSAT-DHCP
```

Or install all RSAT tools relevant to this project at once:

```powershell
Install-WindowsFeature -Name RSAT-ADDS-Tools, RSAT-DNS-Server, RSAT-DHCP
```

### Server Core (No GUI)

RSAT tools can be installed on Server Core using `Install-WindowsFeature`:

```powershell
# Same commands as above — they work on Server Core
Install-WindowsFeature -Name RSAT-ADDS-Tools, RSAT-DNS-Server, RSAT-DHCP
```

> **Note**: On Server Core, there is no graphical Server Manager. All management must be performed via PowerShell or remotely using RSAT from a management workstation.

### Server 2012 R2 Considerations

Windows Server 2012 R2 uses `Add-WindowsFeature` instead of `Install-WindowsFeature`. RSAT packages may need to be downloaded separately if not included in the base image:

```powershell
Add-WindowsFeature RSAT-ADDS-Tools
Add-WindowsFeature RSAT-DNS-Server
Add-WindowsFeature RSAT-DHCP
```

If RSAT features are not available in the offline image, download the appropriate RSAT package from the Microsoft Download Center.

---

## Validation Commands

Run the following commands on each target server to confirm prerequisites are in place before deploying the Zabbix agent configuration.

### 1. Verify PowerShell Module Availability

```powershell
Write-Host "ActiveDirectory: " -NoNewline
if (Get-Module -ListAvailable ActiveDirectory) { Write-Host "OK" -ForegroundColor Green }
else { Write-Host "MISSING" -ForegroundColor Red }

Write-Host "DnsServer:      " -NoNewline
if (Get-Module -ListAvailable DnsServer) { Write-Host "OK" -ForegroundColor Green }
else { Write-Host "MISSING" -ForegroundColor Red }

Write-Host "DhcpServer:     " -NoNewline
if (Get-Module -ListAvailable DhcpServer) { Write-Host "OK" -ForegroundColor Green }
else { Write-Host "MISSING" -ForegroundColor Red }
```

### 2. Verify Diagnostic Tools (AD DS)

```powershell
# dcdiag should return a summary (may show failures — that's fine)
dcdiag /test:Services /test:Advertising /s:[SERVER]

# repadmin should be available
repadmin /replsummary
```

### 3. Verify DHCP Server Module (DHCP Servers)

```powershell
Get-DhcpServerv4Scope -ComputerName localhost
```

If no scopes are configured, this returns an empty list — the module is still available.

### 4. Verify DNS Server Module (DNS Servers)

```powershell
Get-DnsServerZone -ComputerName localhost | Format-Table ZoneName, ZoneType
```

### 5. Verify Scripts Directory

```powershell
Test-Path C:\Scripts\
```

### 6. Verify PowerShell Execution Policy

```powershell
Get-ExecutionPolicy
```

Must be `RemoteSigned` or less restrictive (see [PowerShell Execution Policy](../README.md#powershell-execution-policy) in the main README).

### 7. Verify Zabbix Agent Status

```powershell
Get-Service ZabbixAgent -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType
Get-Service ZabbixAgent2 -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType
```

---

## Summary Checklist

Before proceeding to agent configuration, confirm:

- [ ] Required Windows roles installed (AD DS, DNS Server, DHCP Server as applicable)
- [ ] RSAT tools installed where roles are not present
- [ ] Required PowerShell modules listed by `Get-Module -ListAvailable`
- [ ] Zabbix agent service account has appropriate permissions
- [ ] PowerShell execution policy set to `RemoteSigned`
- [ ] Script deployment path `C:\Scripts\` exists
- [ ] Inbound firewall rule for TCP 10050 configured
- [ ] Zabbix agent (or agent2) installed and running