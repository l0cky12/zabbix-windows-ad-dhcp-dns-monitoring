# Required Macros Reference

This document provides a complete reference for all macros used across the four Zabbix templates. Macros allow you to customise thresholds, timeouts, and other parameters without modifying the template or item definitions.

---

## Table of Contents

- [Macro Precedence](#macro-precedence)
- [Complete Macro Reference Table](#complete-macro-reference-table)
- [Template-Level Macros](#template-level-macros)
- [Host-Level Macros](#host-level-macros)
- [How to Customise Macros](#how-to-customise-macros)

---

## Macro Precedence

Zabbix applies macros in the following order (highest priority first):

1. **Host-level macros** — defined on the individual host
2. **Host group-level macros** — defined on a host group
3. **Template-level macros** — defined on the template
4. **Global macros** — defined at the Zabbix server level

When a macro value must differ from the template default for a specific server, define it at the **host level**.

---

## Complete Macro Reference Table

### AD DS Template (`template_windows_ad_ds.yaml`)

| Macro | Default | Unit | Description | Used In |
|---|---|---|---|---|
| `{$AD_SERVICE_DOWN_TIMEOUT}` | `2m` | Time | Maximum time AD service or dcdiag check can fail before trigger fires | Service health trigger |
| `{$AD_REPL_FAILURE_TIMEOUT}` | `15m` | Time | Maximum time replication failures can persist before trigger fires | Replication health trigger |
| `{$AD_DFSR_UNHEALTHY_TIMEOUT}` | `10m` | Time | Maximum time DFSR can be unhealthy before trigger fires | DFSR health trigger |
| `{$AD_TIME_OFFSET_WARN}` | `180` | Seconds | Clock offset warning threshold; value > this triggers a warning | Time sync warning trigger |
| `{$AD_TIME_OFFSET_CRIT}` | `300` | Seconds | Clock offset critical threshold; value > this triggers a critical alert | Time sync critical trigger |
| `{$AD_TIME_OFFSET_DURATION}` | `5m` | Time | Time window for sustained clock offset before trigger fires | Time sync duration |

### DHCP Template (`template_windows_dhcp.yaml`)

| Macro | Default | Unit | Description | Used In |
|---|---|---|---|---|
| `{$DHCP_SERVICE_DOWN_TIMEOUT}` | `2m` | Time | Maximum time DHCP service can be stopped before trigger fires | Service health trigger |
| `{$DHCP_FREE_PCT_WARN}` | `20` | Percent | Warning threshold for free addresses as percentage of scope total | Scope capacity warning trigger |
| `{$DHCP_FREE_PCT_CRIT}` | `10` | Percent | Critical threshold for free addresses as percentage of scope total | Scope capacity critical trigger |
| `{$DHCP_MIN_FREE_ADDR}` | `20` | Count | Minimum number of free addresses before a critical alert fires (even if percentage is above crit) | Scope capacity critical trigger |
| `{$DHCP_FAILOVER_TIMEOUT}` | `5m` | Time | Maximum time a failover relationship can be in a non-NORMAL state before trigger fires | Failover state trigger |

### DNS Template (`template_windows_dns.yaml`)

| Macro | Default | Unit | Description | Used In |
|---|---|---|---|---|
| `{$DNS_SERVICE_DOWN_TIMEOUT}` | `2m` | Time | Maximum time DNS service can be stopped before trigger fires | Service health trigger |
| `{$DNS_STARTUP_WARN_TIMEOUT}` | `15m` | Minutes | AD-integrated DNS startup delay warning threshold | Startup delay warning trigger |
| `{$DNS_STARTUP_CRIT_TIMEOUT}` | `20m` | Minutes | AD-integrated DNS startup delay critical threshold | Startup delay critical trigger |

### Role Health Template (`template_windows_role_health.yaml`)

| Macro | Default | Unit | Description | Used In |
|---|---|---|---|---|
| `{$ROLE_DISK_FREE_PCT_WARN}` | `15` | Percent | Warning threshold for free disk space on role-relevant volumes | Disk free space warning trigger |
| `{$ROLE_DISK_FREE_PCT_CRIT}` | `10` | Percent | Critical threshold for free disk space on role-relevant volumes | Disk free space critical trigger |
| `{$ROLE_DISK_FREE_GB_WARN}` | `25` | GB | Warning threshold for free disk space in absolute gigabytes | Disk free space warning trigger |
| `{$ROLE_DISK_FREE_GB_CRIT}` | `15` | GB | Critical threshold for free disk space in absolute gigabytes | Disk free space critical trigger |

---

## Template-Level Macros

Template-level macros define the default values that apply to all hosts linked to that template. They are defined in the template YAML files and imported automatically.

### Viewing Template-Level Macros

1. Navigate to **Configuration → Templates**.
2. Click on the template name (e.g., `template_windows_ad_ds`).
3. Select the **Macros** tab.

### Modifying Template-Level Macros

Modifying a template macro changes the default for **all hosts** linked to that template:

1. In the **Macros** tab, edit the macro value.
2. Click **Update**.

> **Caution**: Changing a template macro affects every host using that template. For server-specific adjustments, use a host-level override instead.

---

## Host-Level Macros

Host-level macros override template-level macros for a single host. Use host-level macros when a specific server needs different thresholds.

### Adding a Host-Level Macro

1. Navigate to **Configuration → Hosts**.
2. Click on the host name.
3. Select the **Macros** tab.
4. In the **Inherited and host macros** section, click **Add**.
5. Enter the macro name (e.g., `{$AD_TIME_OFFSET_WARN}`) and the desired value (e.g., `300`).
6. Click **Update** at the bottom of the host form.

### Example: Relaxing Time Sync Thresholds for a Remote DC

```yaml
Host: DC-REMOTE-BRANCH-01
Macros:
  - {$AD_TIME_OFFSET_WARN}: "300"
  - {$AD_TIME_OFFSET_CRIT}: "450"
  - {$AD_TIME_OFFSET_DURATION}: "10m"
```

### Example: Tightening DHCP Scope Thresholds for a High-Density Scope

```yaml
Host: DHCP-PROD-01
Macros:
  - {$DHCP_FREE_PCT_WARN}: "25"
  - {$DHCP_FREE_PCT_CRIT}: "15"
  - {$DHCP_MIN_FREE_ADDR}: "50"
```

---

## How to Customise Macros

### Step-by-Step: Customising at the Host Level

1. **Identify the macro** you want to override from the reference table above.
2. **Log in** to the Zabbix frontend.
3. Navigate to **Configuration → Hosts**.
4. Click on the target host.
5. Go to the **Macros** tab.
6. Click **Add** in the **Inherited and host macros** section.
7. Enter the **Macro** name exactly as written (e.g., `{$DHCP_FREE_PCT_WARN}`).
8. Enter the desired **Value** (e.g., `30`).
9. Click **Update**.

### Using Macros with Zabbix API

You can also set macros programmatically via the Zabbix API:

```bash
#!/bin/bash

ZABBIX_URL="http://[ZABBIX_SERVER]/api_jsonrpc.php"
TOKEN="[AUTH_TOKEN]"
HOST_ID="[HOST_ID]"  # Find via host.get API call

curl -s -X POST "$ZABBIX_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "host.update",
    "params": {
      "hostid": "'$HOST_ID'",
      "macros": [
        {
          "macro": "{$AD_TIME_OFFSET_WARN}",
          "value": "300"
        }
      ]
    },
    "auth": "'$TOKEN'",
    "id": 1
  }' | jq .
```

---

## Quick Reference: When to Override

| Scenario | Suggested Macros to Override |
|---|---|
| Remote site with unreliable WAN time sync | `{$AD_TIME_OFFSET_WARN}`, `{$AD_TIME_OFFSET_CRIT}`, `{$AD_TIME_OFFSET_DURATION}` |
| High-density DHCP scope (e.g., /22 subnet) | `{$DHCP_FREE_PCT_WARN}`, `{$DHCP_FREE_PCT_CRIT}`, `{$DHCP_MIN_FREE_ADDR}` |
| Low-traffic domain with few DCs | `{$AD_REPL_FAILURE_TIMEOUT}` (increase to 30m to reduce noise) |
| AD DNS in a large forest with slow startup | `{$DNS_STARTUP_WARN_TIMEOUT}`, `{$DNS_STARTUP_CRIT_TIMEOUT}` |
| Server with small OS volume (e.g., 60 GB) | `{$ROLE_DISK_FREE_GB_WARN}`, `{$ROLE_DISK_FREE_GB_CRIT}` (lower values) |
| Development/lab environment | All macros — relax thresholds to reduce alert fatigue |