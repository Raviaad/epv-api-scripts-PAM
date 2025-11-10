<#
.SYNOPSIS
    Move an account from one CyberArk safe to another using the REST API.

.DESCRIPTION
    Retrieves an existing account, validates the destination safe, and calls the
    CyberArk PVWA REST API to move the account. Optional switches let you retain
    the account owners and permissions, rename the account, or target a specific
    folder in the destination safe. Existing authentication tokens can be reused
    and SSL certificate validation can be bypassed for lab scenarios.

.NOTES
    Author: OpenAI ChatGPT (based on CyberArk sample conventions)
    Requires: CyberArk PVWA v11.7+
    Version: 1.1 (2024-04-12)

.EXAMPLE
    .\Move-Account.ps1 -PVWAURL https://pvwa.example.com/PasswordVault -ID 12_34 \
        -DestinationSafeName TargetSafe

    Moves account 12_34 to the TargetSafe safe while retaining owners and permissions.

.EXAMPLE
    $token = .\Get-LogonToken.ps1
    .\Move-Account.ps1 -PVWAURL https://pvwa.example.com/PasswordVault -ID 12_34 \
        -DestinationSafeName TargetSafe -DestinationFolder "Unix Servers" \
        -NewAccountName "svc-app-01" -logonToken $token -WhatIf

    Previews the move request for account 12_34 into a sub-folder with a new name using
    an existing authentication token.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param
(
    [Parameter(Mandatory = $true, HelpMessage = "Enter the PVWA URL")]
    [ValidateScript( { Invoke-WebRequest -UseBasicParsing -DisableKeepAlive -Uri $_ -Method 'Head' -ErrorAction 'stop' -TimeoutSec 30 })]
    [Alias("url")]
    [String]$PVWAURL,

    [Parameter(Mandatory = $false, HelpMessage = "Enter the Authentication type (Default:CyberArk)")]
    [ValidateSet("cyberark", "ldap", "radius")]
    [String]$AuthType = "cyberark",

    [Parameter(Mandatory = $true, HelpMessage = "The required Account ID")]
    [ValidateScript( { $_ -match "\d{1,}_\d{1,}" })]
    [Alias("AccountID")]
    [string]$ID,

    [Parameter(Mandatory = $false, HelpMessage = "Validate the account is currently stored in this Safe")]
    [Alias("SourceSafe")]
    [string]$SourceSafeName,

    [Parameter(Mandatory = $true, HelpMessage = "Destination Safe name")]
    [Alias("DestinationSafe")]
    [string]$DestinationSafeName,

    [Parameter(Mandatory = $false, HelpMessage = "Destination folder name (default: Root)")]
    [string]$DestinationFolder = "Root",

    [Parameter(Mandatory = $false, HelpMessage = "Optional new account name after move")]
    [string]$NewAccountName,

    [Parameter(Mandatory = $false, HelpMessage = "Retain the existing account owners in the destination Safe")]
    [bool]$RetainCurrentOwners = $true,

    [Parameter(Mandatory = $false, HelpMessage = "Retain the existing account permissions in the destination Safe")]
    [bool]$RetainCurrentPermissions = $true,

    [Parameter(Mandatory = $false, HelpMessage = "Provide pre-authenticated logon token")]
    $logonToken,

    [Parameter(Mandatory = $false, HelpMessage = "Do not logoff session on completion")]
    [switch]$DisableLogoff,

    [Parameter(Mandatory = $false, HelpMessage = "Disable certificate validation (self-signed certificates)")]
    [switch]$DisableSSLVerify,

    [Parameter(Mandatory = $false, HelpMessage = "Provide credentials via parameter instead of prompt")]
    [System.Management.Automation.PSCredential]$PVWACredentials
)

# Script defaults
$ErrorActionPreference = "Stop"
$ScriptVersion = "1.1"
$UsingProvidedToken = $PSBoundParameters.ContainsKey('logonToken') -and $null -ne $logonToken -and $logonToken -ne ""

# Prepare base URLs
if ($PVWAURL.EndsWith("/")) {
    $PVWAURL = $PVWAURL.TrimEnd("/")
}

$URL_PVWAAPI = $PVWAURL + "/api"
$URL_Authentication = $URL_PVWAAPI + "/auth"
$URL_Logon = $URL_Authentication + "/$AuthType/Logon"
$URL_Logoff = $URL_Authentication + "/Logoff"
$URL_Accounts = $URL_PVWAAPI + "/Accounts"
$URL_AccountDetails = $URL_Accounts + "/{0}"
$URL_AccountMove = $URL_Accounts + "/{0}/Move"
$URL_Safes = $URL_PVWAAPI + "/Safes"
$URL_SafeDetails = $URL_Safes + "/{0}"

# region Helper Functions
function Disable-SSLVerification {
    <#
    .SYNOPSIS
        Bypass SSL certificate validations
    .DESCRIPTION
        Disables the SSL verification (bypass self-signed SSL certificates)
    #>
    [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    if (-not('DisableCertValidationCallback' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public static class DisableCertValidationCallback {
    public static bool ReturnTrue(object sender,
        X509Certificate certificate,
        X509Chain chain,
        SslPolicyErrors sslPolicyErrors) { return true; }

    public static RemoteCertificateValidationCallback GetDelegate() {
        return new RemoteCertificateValidationCallback(DisableCertValidationCallback.ReturnTrue);
    }
}
'@
    }
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = [DisableCertValidationCallback]::GetDelegate()
}

function Get-LogonHeader {
    param(
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$Credentials
    )

    if ($DisableSSLVerify) {
        Disable-SSLVerification
    }

    if ($script:UsingProvidedToken) {
        return @{ Authorization = $logonToken }
    }

    if (-not $Credentials) {
        $caption = "CyberArk Logon"
        $msg = "Enter your CyberArk user name and password"
        $Credentials = $Host.UI.PromptForCredential($caption, $msg, "", "")
    }

    if (-not $Credentials) {
        throw "No credentials supplied"
    }

    $body = @{ username = $Credentials.UserName.Replace('\\', ''); password = $Credentials.GetNetworkCredential().Password } | ConvertTo-Json
    try {
        $token = Invoke-RestMethod -Method Post -Uri $URL_Logon -Body $body -ContentType "application/json" -TimeoutSec 2700
    }
    catch {
        throw "Logon failed: $($_.Exception.Message)"
    }

    if ([string]::IsNullOrEmpty($token)) {
        throw "Logon token is empty"
    }

    return @{ Authorization = $token }
}

function Invoke-Logoff {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Header
    )

    if ($DisableLogoff) {
        return
    }

    if ($script:UsingProvidedToken) {
        return
    }

    try {
        Invoke-RestMethod -Method Post -Uri $URL_Logoff -Headers $Header -ContentType "application/json" -TimeoutSec 2700 | Out-Null
    }
    catch {
        Write-Warning "Failed to logoff session: $($_.Exception.Message)"
    }
}

function Invoke-ApiRequest {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [hashtable]$Headers,

        [Parameter(Mandatory = $false)]
        $Body
    )

    $params = @{ Method = $Method; Uri = $Uri; Headers = $Headers; TimeoutSec = 2700 }
    if ($null -ne $Body) {
        $params.Body = $Body
        $params.ContentType = "application/json"
    }

    try {
        return Invoke-RestMethod @params
    }
    catch {
        throw "Request to '$Uri' failed: $($_.Exception.Message)"
    }
}
# endregion

$logonHeader = $null
$acquiredToken = -not $UsingProvidedToken

try {
    $logonHeader = Get-LogonHeader -Credentials $PVWACredentials

    # Retrieve account details
    $accountUri = $URL_AccountDetails -f $ID
    Write-Verbose "Retrieving account details from $accountUri"
    $account = Invoke-ApiRequest -Method 'GET' -Uri $accountUri -Headers $logonHeader

    if ($null -eq $account) {
        throw "Account '$ID' was not found"
    }

    $currentSafe = $account.safeName
    if ([string]::IsNullOrEmpty($currentSafe)) {
        $currentSafe = $account.safe
    }

    if ($SourceSafeName -and ($currentSafe -ne $SourceSafeName)) {
        throw "Account '$ID' is stored in Safe '$currentSafe', not in '$SourceSafeName'"
    }

    if ($currentSafe -eq $DestinationSafeName) {
        throw "Destination Safe '$DestinationSafeName' is the same as the current Safe"
    }

    # Validate destination safe exists
    $encodedSafeName = [System.Uri]::EscapeDataString($DestinationSafeName)
    $safeUri = $URL_SafeDetails -f $encodedSafeName
    Write-Verbose "Validating destination safe via $safeUri"
    $null = Invoke-ApiRequest -Method 'GET' -Uri $safeUri -Headers $logonHeader

    # Build move request body
    $moveBody = @{
        safeName = $DestinationSafeName
        folderName = $DestinationFolder
        retainCurrentOwners = $RetainCurrentOwners
        retainCurrentPermissions = $RetainCurrentPermissions
    }

    if ($PSBoundParameters.ContainsKey('NewAccountName') -and -not [string]::IsNullOrEmpty($NewAccountName)) {
        $moveBody.name = $NewAccountName
    }

    $jsonBody = $moveBody | ConvertTo-Json -Depth 4

    $moveUri = $URL_AccountMove -f $ID
    $targetDescription = "Safe '$DestinationSafeName'"
    if (-not [string]::IsNullOrEmpty($DestinationFolder) -and $DestinationFolder -ne 'Root') {
        $targetDescription += "/Folder '$DestinationFolder'"
    }

    if ($PSCmdlet.ShouldProcess("Account '$ID'", "Move to $targetDescription")) {
        Write-Verbose "Moving account via $moveUri"
        Invoke-ApiRequest -Method 'POST' -Uri $moveUri -Headers $logonHeader -Body $jsonBody | Out-Null
        Write-Host -ForegroundColor Green "Account '$ID' moved from Safe '$currentSafe' to $targetDescription."
    }
}
catch {
    Write-Error $_
}
finally {
    if ($acquiredToken -and $null -ne $logonHeader) {
        Invoke-Logoff -Header $logonHeader
    }
}
