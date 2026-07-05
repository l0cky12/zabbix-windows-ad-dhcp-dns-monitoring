# Zabbix Server Import Guide

This guide explains how to import the AD DS, DHCP, DNS, and Role Health templates into your Zabbix server, link them to hosts, and verify that monitoring is working correctly.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Importing Templates via Web UI](#importing-templates-via-web-ui)
- [Importing Templates via Zabbix API (CLI)](#importing-templates-via-zabbix-api-cli)
- [Linking Templates to Hosts](#linking-templates-to-hosts)
- [Overriding Macros](#overriding-macros)
- [Verification After Import](#verification-after-import)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

- Zabbix frontend access with **Admin** or **Super Admin** role privileges
- Template YAML files downloaded or cloned from the repository:
  - `templates/template_windows_ad_ds.yaml`
  - `templates/template_windows_dhcp.yaml`
  - `templates/template_windows_dns.yaml`
  - `templates/template_windows_role_health.yaml`
- Hosts already configured in Zabbix with Zabbix agent interface and agent running
- Windows servers prepared as described in [Windows Server Preparation](windows-server-preparation.md)

---

## Importing Templates via Web UI

### Step 1: Navigate to Template Import

1. Log in to the Zabbix frontend.
2. Go to **Configuration → Templates**.
3. Click the **Import** button in the upper-right corner.

### Step 2: Select and Import the Template File

1. Click **Choose File** and select one of the `.yaml` template files.
2. Leave all import rules set to their defaults:
   - **Rules**: All boxes checked (Create new, Update existing, Delete missing)
   - **Create new**: Selected
   - **Update existing**: Selected
3. Click **Import**.

### Step 3: Repeat for Each Template

Repeat the import process for all four template files:

| Template | File Name |
|---|---|
| AD DS | `template_windows_ad_ds.yaml` |
| DHCP | `template_windows_dhcp.yaml` |
| DNS | `template_windows_dns.yaml` |
| Role Health | `template_windows_role_health.yaml` |

### Step 4: Verify Import Success

After each import, Zabbix displays a green **Imported** banner at the top of the page. The template will appear in the **Configuration → Templates** list.

---

## Importing Templates via Zabbix API (CLI)

If you prefer to import templates programmatically, use the **Zabbix API** with `curl` or the Zabbix CLI tool.

### Using Zabbix CLI (zabbix-cli)

If `zabbix-cli` is installed and configured:

```bash
zabbix-cli template_import --file template_windows_ad_ds.yaml
zabbix-cli template_import --file template_windows_dhcp.yaml
zabbix-cli template_import --file template_windows_dns.yaml
zabbix-cli template_import --file template_windows_role_health.yaml
```

### Using Zabbix API with curl

```bash
#!/bin/bash

ZABBIX_URL="http://[ZABBIX_SERVER]/api_jsonrpc.php"
ZABBIX_USER="Admin"
ZABBIX_PASS="[PASSWORD]"

# Get authentication token
TOKEN=$(curl -s -X POST "$ZABBIX_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "user.login",
    "params": {"user": "'$ZABBIX_USER'", "password": "'$ZABBIX_PASS'"},
    "id": 1
  }' | jq -r '.result')

# Import template
for template in template_windows_ad_ds.yaml template_windows_dhcp.yaml \
                template_windows_dns.yaml template_windows_role_health.yaml; do

  SOURCE=$(cat "$template" | jq -Rs .)

  curl -s -X POST "$ZABBIX_URL" \
    -H "Content-Type: application/json" \
    -d '{
      "jsonrpc": "2.0",
      "method": "configuration.import",
      "params": {
        "format": "yaml",
        "rules": {
          "templates": {"createMissing": true, "updateExisting": true},
          "items": {"createMissing": true, "updateExisting": true, "deleteMissing": true},
          "triggers": {"createMissing": true, "updateExisting": true, "deleteMissing": true},
          "graphs": {"createMissing": true, "updateExisting": true, "deleteMissing": true},
          "discoveryRules": {"createMissing": true, "updateExisting": true, "deleteMissing": true},
          "valueMaps": {"createMissing": true, "updateExisting": true}
        },
        "source": '"$SOURCE"'
      },
      "auth": "'$TOKEN'",
      "id": 2
    }' | jq .

done
```

---

## Linking Templates to Hosts

### Step 1: Navigate to Host Configuration

1. Go to **Configuration → Hosts**.
2. Click on the host you want to link a template to.

### Step 2: Add Templates

1. In the **Templates** field, start typing the template name (e.g., "Windows AD DS").
2. Select the template from the autocomplete dropdown.
3. Repeat for each template that applies to this host.

| Host Role | Templates to Link |
|---|---|
| Domain Controller | `template_windows_ad_ds.yaml`, `template_windows_dns.yaml`, `template_windows_role_health.yaml` |
| DHCP Server (non-DC) | `template_windows_dhcp.yaml`, `template_windows_role_health.yaml` |
| DNS Server (non-DC) | `template_windows_dns.yaml`, `template_windows_role_health.yaml` |
| Multi-role server | Link all applicable templates |

### Step 3: Save

Click **Update** at the bottom of the host form. Zabbix begins collecting data for the newly linked items immediately.

---

## Overriding Macros

Macros can be customised at multiple levels. The order of precedence (lowest to highest) is:

1. **Template-level** macros (defaults shipped with the template)
2. **Host group-level** macros
3. **Host-level** macros (override template defaults for a specific server)

### Override at the Template Level

Modify macros for all hosts linked to a template:

1. Go to **Configuration → Templates**.
2. Click on the template name.
3. Go to the **Macros** tab.
4. Add or modify macro values.
5. Click **Update**.

### Override at the Host Level

Modify macros for a single host:

1. Go to **Configuration → Hosts**.
2. Click on the host name.
3. Go to the **Macros** tab.
4. Add the macro and set the desired value.
5. Click **Update**.

### Using Inherited vs Host-Specific Macros

Only define a macro at the host level when a specific server requires a different threshold than the template default. For example:

- A small office DC might keep the default `{$AD_TIME_OFFSET_WARN}=180`, while a DC in a remote branch with an unreliable WAN link might need `{$AD_TIME_OFFSET_WARN}=300`.

---

## Verification After Import

### 1. Check Template Import in Web UI

Navigate to **Configuration → Templates** and confirm all four templates appear in the list with the correct names.

### 2. Check Host-Template Association

For each host, navigate to **Configuration → Hosts → (host) → Templates** and confirm the expected templates are listed.

### 3. Check Latest Data

1. Go to **Monitoring → Latest data**.
2. Select the host from the filter.
3. Verify that items from the linked templates are collecting data (look for recent timestamps).

### 4. Check Zabbix Agent Availability

Navigate to **Monitoring → Hosts** and check that the host's **ZBX** icon is green, indicating successful communication with the Zabbix agent.

### 5. Verify Individual Items

Use the Zabbix agent test command on the target Windows server to confirm data is flowing:

```powershell
zabbix_agentd.exe -t ad.service.dcdiag
```

---

## Troubleshooting

| Problem | Likely Cause | Solution |
|---|---|---|
| Import fails with "Invalid YAML" | YAML file corrupt or incompatible | Validate the YAML with `python -c "import yaml; yaml.safe_load(open('template.yaml'))"` |
| Import fails with "version mismatch" | Template Zabbix version does not match server version | Templates are exported for Zabbix 6.0 LTS; if using a different version, re-export from a compatible server |
| Template imported but no items visible | Host not linked to template | Verify template is linked under **Configuration → Hosts → (host) → Templates** |
| Items show "Not supported" | Agent not configured or script not deployed | Follow the [Zabbix Agent Configuration](zabbix-agent-configuration.md) guide |
| Host ZBX icon red | Agent unreachable | Check agent service, firewall, and network connectivity on TCP 10050 |

---

## Import Checklist

- [ ] All four template YAML files imported
- [ ] Templates visible in **Configuration → Templates**
- [ ] Templates linked to appropriate hosts
- [ ] Macros reviewed and overridden where necessary
- [ ] Latest data showing for linked items
- [ ] ZBX icon green for all monitored hosts