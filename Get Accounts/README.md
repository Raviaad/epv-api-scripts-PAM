# Get Accounts Scripts

This folder contains PowerShell scripts for managing and reporting CyberArk PAS accounts using REST API automation.

---

## Scripts

### Choosing the right script

If you're unsure which of the four scripts fits your task, use the guide below to
pick the best match for your workflow:

| When you need to... | Use this script | Why it's the best fit |
| --- | --- | --- |
| Report on or export accounts based on filters | `Get-Accounts.ps1` | Purpose-built for discovery and reporting, with CSV export support. |
| Update account properties in place | `Update-Account.ps1` | Accepts parameter/value pairs to modify attributes on existing accounts. |
| Trigger CPM actions (Verify/Change/Reconcile) in bulk | `Invoke-BulkAccountActions.ps1` | Wraps the bulk action REST endpoints with flexible filtering to target the right accounts. |
| Relocate an account to another safe | `Move-Account.ps1` | Validates safes and issues the move request, optionally renaming and retaining permissions. |

---

### 1. Get-Accounts.ps1
**Purpose:**
Enumerate, report, and export account information from CyberArk PAS.

**Usage:**
```powershell
Get-Accounts.ps1 -PVWAURL <string> -List [-Report] [-SafeName <string>] [-Keywords <string>] [-SortBy <string>] [-Limit <int>] [-AutoNextPage] [-CSVPath <string>] [<CommonParameters>]
Get-Accounts.ps1 -PVWAURL <string> -Details -AccountID <string> [-Report] [-CSVPath <string>] [<CommonParameters>]
```

**Examples:**
```powershell
# List all accounts in a safe
Get-Accounts.ps1 -PVWAURL https://mydomain.com/PasswordVault -List -SafeName "MySafe"

# Export a report of all accounts with keyword "production"
Get-Accounts.ps1 -PVWAURL https://mydomain.com/PasswordVault -List -Report -Keywords "production" -CSVPath "C:\\Temp\\accounts.csv"

# Get details for a specific account
Get-Accounts.ps1 -PVWAURL https://mydomain.com/PasswordVault -Details -AccountID "12_34"
```

---

### 2. Update-Account.ps1
**Purpose:**
Update one or more properties for a given account.

**Usage:**
```powershell
Update-Account.ps1 -PVWAURL <string> -AccountID <string> -ParameterNames <Comma separated names> -ParameterValues <Comma separated values> [<CommonParameters>]
```

**Examples:**
```powershell
# Update one property
Update-Account.ps1 -PVWAURL https://mydomain.com/PasswordVault -AccountID 12_34 -ParameterNames "Environment" -ParameterValues "Production"

# Update multiple properties
Update-Account.ps1 -PVWAURL https://mydomain.com/PasswordVault -AccountID 12_34 -ParameterNames "DataCenter","Building" -ParameterValues "Washington","B1"
```

---

### 3. Invoke-BulkAccountActions.ps1
**Purpose:**
Run bulk actions (Verify, Change, Reconcile) on accounts, with flexible filtering.

**Usage:**
```powershell
Invoke-BulkAccountActions.ps1 -PVWAURL <string> -AuthType <["cyberark","ldap","radius"]> [-DisableSSLVerify] -AccountsAction <["Verify","Change","Reconcile"]> [-SafeName <string>] [-PlatformID <string>] [-UserName <string>] [-Address <string>] [-Custom <string>] [-FailedOnly] [-CPMDisabled] [-logonToken <token>] [<CommonParameters>]
```

**Available Filters:**
- SafeName
- PlatformID
- UserName
- Address
- Custom (search by keyword)
- FailedOnly (only failed accounts)
- CPMDisabled (only CPM-disabled accounts)
- logonToken (use an existing authentication token)

**Examples:**
```powershell
# Use a logon token for authentication
Invoke-BulkAccountActions.ps1 -PVWAURL https://mydomain.com/PasswordVault -SafeName "MySafe" -AccountsAction "Verify" -logonToken $token

# Verify all root accounts from UnixSSH platform
Invoke-BulkAccountActions.ps1 -PVWAURL https://mydomain.com/PasswordVault -PlatformID "UnixSSH" -UserName "root" -AccountsAction "Verify"

# Change all accounts on a specific server
Invoke-BulkAccountActions.ps1 -PVWAURL https://mydomain.com/PasswordVault -Address "myserver.mydomain.com" -AccountsAction "Change"

# Reconcile all failed accounts in a safe
Invoke-BulkAccountActions.ps1 -PVWAURL https://mydomain.com/PasswordVault -SafeName "PRD-ATL-App01-Admin" -FailedOnly -AccountsAction "Reconcile"

# Reconcile all CPMDisabled accounts
Invoke-BulkAccountActions.ps1 -PVWAURL https://mydomain.com/PasswordVault -CPMDisabled -AccountsAction "Reconcile"

# Verify all accounts marked as CPMDisabled OR failed accounts
Invoke-BulkAccountActions.ps1 -PVWAURL https://mydomain.com/PasswordVault -CPMDisabled -FailedOnly -AccountsAction "Verify"
```

---

### 4. Move-Account.ps1
**Purpose:**
Relocate an existing account from its current Safe to another Safe via the REST API.

**Usage:**
```powershell
Move-Account.ps1 -PVWAURL <string> -ID <string> -DestinationSafeName <string> [-SourceSafeName <string>] [-DestinationFolder <string>] [-NewAccountName <string>] [-RetainCurrentOwners <bool>] [-RetainCurrentPermissions <bool>] [-DisableSSLVerify] [-logonToken <token>] [-PVWACredentials <PSCredential>]
```

**Examples:**
```powershell
# Move an account and retain its owners and permissions
Move-Account.ps1 -PVWAURL https://mydomain.com/PasswordVault -ID 12_34 -DestinationSafeName "TargetSafe"

# Move an account to a sub-folder and rename it
Move-Account.ps1 -PVWAURL https://mydomain.com/PasswordVault -ID 12_34 -DestinationSafeName "TargetSafe" -DestinationFolder "Unix Servers" -NewAccountName "svc-app-01"

# Use an existing logon token when moving the account
Move-Account.ps1 -PVWAURL https://mydomain.com/PasswordVault -ID 12_34 -DestinationSafeName "TargetSafe" -logonToken $token
```

---

## Notes
- All scripts require valid CyberArk PAS credentials and network access to the PVWA server.
- For full parameter documentation, use `Get-Help <script> -Full` in PowerShell.
