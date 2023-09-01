################################
# Start: Internal use functions
################################

$Success = "Success"

function Get-AccessTokenFromSessionData() {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [System.Management.Automation.SessionState]
    $SessionState
  )

  $token = Get-MSCommerceConnectionInfo -SessionState $SessionState

  $token
}

function Get-MSCommerceConnectionInfo {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [System.Management.Automation.SessionState]
    $SessionState
  )

  if ($null -eq $sessionState.PSVariable) {
    throw "unable to access SessionState. PSVariable, Please call Connect-MSCommerce before calling any other Powershell CmdLet for the MSCommerce Module"
  }

  $token = $sessionState.PSVariable.GetValue("token");

  if ($null -eq $token) {
    throw "You must call the Connect-MSCommerce cmdlet before calling any other cmdlets"
  }

  return $token
}

function HandleError() {
  param(
    [Parameter(Mandatory = $true)]
    $ErrorContext,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $CustomErrorMessage
  )

  $errorMessage = $ErrorContext.Exception.Message
  $errorDetails = $ErrorContext.ErrorDetails.Message

  if ($_.Exception.Response.StatusCode -eq 401) {
    Write-Error "Your credentials have expired. Please, call Connect-MSCommerce again to regain access to MSCommerce Module."

    return
  }

  write-error "$CustomErrorMessage, ErrorMessage - $errorMessage ErrorDetails - $errorDetails"
}

################################
# End: Internal use functions
################################


################################
# Start: Exported functions
################################

<#
    .SYNOPSIS
    Method to connect to MSCommerce with the credentials specified
#>
function Connect-MSCommerce() {
  [CmdletBinding()]
  param(
    [string]
    $ClientId = "3d5cffa9-04da-4657-8cab-c7f074657cad",

    [Uri]
    $RedirectUri = [uri] "http://localhost/m365/commerce",

    [string]
    $Resource = "aeb86249-8ea3-49e2-900b-54cc8e308f85", #LicenseManager App Id

    [PSCredential]
    $AdminAccount
  )

  if ($PSVersionTable.PSVersion.Major -gt 5) {
    Write-Output "Your PowerShell version is $($PSVersionTable.PSVersion.Major). Please use version 5 or below"
    return
  }
  $authorityUrl = "https://login.windows.net/common"

  $authCtx = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" $authorityUrl
  if ($PSBoundParameters.ContainsKey("AdminAccount")) {
    $credential = [Microsoft.IdentityModel.Clients.ActiveDirectory.UserPasswordCredential]::new($AdminAccount.Username, $AdminAccount.Password)
    $token = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContextIntegratedAuthExtensions]::AcquireTokenAsync($authCtx, $Resource, $ClientId, $credential).Result
  }
  else {
    $platformParams = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters" ([Microsoft.IdentityModel.Clients.ActiveDirectory.PromptBehavior]::Always)

    $token = $authCtx.AcquireTokenAsync($Resource, $ClientId, $RedirectUri, $platformParams).Result
  }
  if ($null -eq $token) {
    Write-Error "Unable to establish connection"

    return
  }

  $sessionState = $PSCmdlet.SessionState

  $sessionState.PSVariable.Set("token", $token)

  Write-Output "Connection established successfully"
}

<#
    .SYNOPSIS
    Method to retrieve configurable policies
#>
function Get-MSCommercePolicies() {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $false)]
    [string] $Token
  )

  if (!$Token) {
    $Token = (Get-AccessTokenFromSessionData -SessionState $PSCmdlet.SessionState).AccessToken
  }
  $correlationId = New-Guid
  $baseUri = "https://licensing.m365.microsoft.com"

  $restPath = "$baseUri/v1.0/policies"

  try {
    $response = Invoke-RestMethod `
      -Method GET `
      -Uri $restPath `
      -Headers @{
      "x-ms-correlation-id" = $correlationId
      "Authorization"       = "Bearer $($Token)"
    }

    foreach ($policy in $response.items) {
      New-Object PSObject -Property @{
        PolicyId     = $policy.id
        Description  = $policy.description
        DefaultValue = $policy.defaultValue
      }
    }
    return $Success
  }
  catch {
    HandleError -ErrorContext $_ -CustomErrorMessage "Failed to retrieve policies"
  }
}

<#
    .SYNOPSIS
    Method to retrieve a description of the specified policy
#>
function Get-MSCommercePolicy() {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $PolicyId,
    [Parameter(Mandatory = $false)]
    [string] $Token
  )

  if (!$Token) {
    $Token = (Get-AccessTokenFromSessionData -SessionState $PSCmdlet.SessionState).AccessToken
  }

  $correlationId = New-Guid
  $baseUri = "https://licensing.m365.microsoft.com"

  $restPath = "$baseUri/v1.0/policies/$PolicyId"

  try {
    $response = Invoke-RestMethod `
      -Method GET `
      -Uri $restPath `
      -Headers @{
      "x-ms-correlation-id" = $correlationId
      "Authorization"       = "Bearer $($Token)"
    }

    New-Object PSObject -Property @{
      PolicyId     = $response.id
      Description  = $response.description
      DefaultValue = $response.defaultValue
    }
    return $Success
  }
  catch {
    HandleError -ErrorContext $_ -CustomErrorMessage "Failed to retrieve policy with PolicyId '$PolicyId'"
  }
}

<#
    .SYNOPSIS
    Method to retrieve applicable products for the specified policy and their current settings
#>
function Get-MSCommerceProductPolicies() {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $PolicyId,
    [Parameter(Mandatory = $false)]
    [string] $Token
  )

  if (!$Token) {
    $Token = (Get-AccessTokenFromSessionData -SessionState $PSCmdlet.SessionState).AccessToken
  }
  $correlationId = New-Guid
  $baseUri = "https://licensing.m365.microsoft.com"

  $restPath = "$baseUri/v1.0/policies/$PolicyId/products"

  try {
    $response = Invoke-RestMethod `
      -Method GET `
      -Uri $restPath `
      -Headers @{
      "x-ms-correlation-id" = $correlationId
      "Authorization"       = "Bearer $($Token)"
    }

    foreach ($product in $response.items) {
      New-Object PSObject -Property @{
        PolicyId    = $product.policyId
        ProductName = $product.productName
        ProductId   = $product.productId
        PolicyValue = $product.policyValue
      }
    }
    return $Success
  }
  catch {
    HandleError -ErrorContext $_ -CustomErrorMessage "Failed to retrieve product policy with PolicyId '$PolicyId'"
  }
}

<#
    .SYNOPSIS
    Method to retrieve the current setting for the policy for the specified product
#>
function Get-MSCommerceProductPolicy() {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $PolicyId,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ProductId,
    [Parameter(Mandatory = $false)]
    [string] $Token
  )

  if (!$Token) {
    $Token = (Get-AccessTokenFromSessionData -SessionState $PSCmdlet.SessionState).AccessToken
  }
  $correlationId = New-Guid
  $baseUri = "https://licensing.m365.microsoft.com"

  $restPath = "$baseUri/v1.0/policies/$PolicyId/products/$ProductId"

  try {
    $response = Invoke-RestMethod `
      -Method GET `
      -Uri $restPath `
      -Headers @{
      "x-ms-correlation-id" = $correlationId
      "Authorization"       = "Bearer $($Token)"
    }

    New-Object PSObject -Property @{
      PolicyId    = $response.policyId
      ProductName = $response.productName
      ProductId   = $response.productId
      PolicyValue = $response.policyValue
    }
    return $Success
  }
  catch {
    HandleError -ErrorContext $_ -CustomErrorMessage "Failed to retrieve product policy with PolicyId '$PolicyId' ProductId '$ProductId'"
  }
}

<#
    .SYNOPSIS
    Method to modify the current setting for the policy for the specified product
#>
function Update-MSCommerceProductPolicy() {
  [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = "Enum")]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $PolicyId,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $ProductId,
    [Parameter(Mandatory = $true, ParameterSetName = "Toggle")]
    [ValidateNotNullOrEmpty()]
    [string] $Enabled,
    [Parameter(Mandatory = $true, ParameterSetName = "Enum")]
    [ValidateSet("Enabled", "Disabled", "OnlyTrialsWithoutPaymentMethod")]
    [string] $Value,
    [Parameter(Mandatory = $false)]
    [string] $Token
  )

  if ($PSBoundParameters.ContainsKey("Enabled")) {
    if ("True" -ne $Enabled -and "False" -ne $Enabled) {
      Write-Error "Value of `$Enabled must be one of the following: `$True, `$true, `$False, `$false"
      return
    }
  }

  if (!$Token) {
    $Token = (Get-AccessTokenFromSessionData -SessionState $PSCmdlet.SessionState).AccessToken
  }
  $correlationId = New-Guid
  $baseUri = "https://licensing.m365.microsoft.com"

  $restPath = "$baseUri/v1.0/policies/$PolicyId/products/$ProductId"
  
  if ($PSBoundParameters.ContainsKey("Enabled")) {
    $policyValue = if ("True" -eq $Enabled -or "true" -eq $Enabled) { "Enabled" } else { "Disabled" }
  }
  else {
    $policyValue = $Value
  }

  $body = @{
    policyValue = $policyValue
  }

  if ($False -eq $PSCmdlet.ShouldProcess("ShouldProcess?")) {
    Write-Output "Updating product policy aborted"

    return
  }

  try {
    $response = Invoke-RestMethod `
      -Method PUT `
      -Uri $restPath `
      -Body ($body | ConvertTo-Json)`
      -ContentType 'application/json' `
      -Headers @{
      "x-ms-correlation-id" = $correlationId
      "Authorization"       = "Bearer $($Token)"
    }

    write-output "Update policy product success"
    New-Object PSObject -Property @{
      PolicyId    = $response.policyId
      ProductName = $response.productName
      ProductId   = $response.productId
      PolicyValue = $response.policyValue
    }
    return $Success
  }
  catch {
    HandleError -ErrorContext $_ -CustomErrorMessage "Failed to update product policy"
  }
}

################################
# End: Exported functions
################################

Write-Output "MSCommerce module loaded"

# SIG # Begin signature block
# MIInugYJKoZIhvcNAQcCoIInqzCCJ6cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBDJz4QEXRozYJN
# u7nCtsj+7pOw4zVayWIms0XWm2mqbqCCDYEwggX/MIID56ADAgECAhMzAAACUosz
# qviV8znbAAAAAAJSMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjEwOTAyMTgzMjU5WhcNMjIwOTAxMTgzMjU5WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDQ5M+Ps/X7BNuv5B/0I6uoDwj0NJOo1KrVQqO7ggRXccklyTrWL4xMShjIou2I
# sbYnF67wXzVAq5Om4oe+LfzSDOzjcb6ms00gBo0OQaqwQ1BijyJ7NvDf80I1fW9O
# L76Kt0Wpc2zrGhzcHdb7upPrvxvSNNUvxK3sgw7YTt31410vpEp8yfBEl/hd8ZzA
# v47DCgJ5j1zm295s1RVZHNp6MoiQFVOECm4AwK2l28i+YER1JO4IplTH44uvzX9o
# RnJHaMvWzZEpozPy4jNO2DDqbcNs4zh7AWMhE1PWFVA+CHI/En5nASvCvLmuR/t8
# q4bc8XR8QIZJQSp+2U6m2ldNAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUNZJaEUGL2Guwt7ZOAu4efEYXedEw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDY3NTk3MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAFkk3
# uSxkTEBh1NtAl7BivIEsAWdgX1qZ+EdZMYbQKasY6IhSLXRMxF1B3OKdR9K/kccp
# kvNcGl8D7YyYS4mhCUMBR+VLrg3f8PUj38A9V5aiY2/Jok7WZFOAmjPRNNGnyeg7
# l0lTiThFqE+2aOs6+heegqAdelGgNJKRHLWRuhGKuLIw5lkgx9Ky+QvZrn/Ddi8u
# TIgWKp+MGG8xY6PBvvjgt9jQShlnPrZ3UY8Bvwy6rynhXBaV0V0TTL0gEx7eh/K1
# o8Miaru6s/7FyqOLeUS4vTHh9TgBL5DtxCYurXbSBVtL1Fj44+Od/6cmC9mmvrti
# yG709Y3Rd3YdJj2f3GJq7Y7KdWq0QYhatKhBeg4fxjhg0yut2g6aM1mxjNPrE48z
# 6HWCNGu9gMK5ZudldRw4a45Z06Aoktof0CqOyTErvq0YjoE4Xpa0+87T/PVUXNqf
# 7Y+qSU7+9LtLQuMYR4w3cSPjuNusvLf9gBnch5RqM7kaDtYWDgLyB42EfsxeMqwK
# WwA+TVi0HrWRqfSx2olbE56hJcEkMjOSKz3sRuupFCX3UroyYf52L+2iVTrda8XW
# esPG62Mnn3T8AuLfzeJFuAbfOSERx7IFZO92UPoXE1uEjL5skl1yTZB3MubgOA4F
# 8KoRNhviFAEST+nG8c8uIsbZeb08SeYQMqjVEmkwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZjzCCGYsCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAlKLM6r4lfM52wAAAAACUjAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgvv0OUsIh
# v2pPO7l7tvZFAD+uP8IY1MkSCrnOLp/MaFAwQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQBhwTk1AdOPK03JKdcj/8WRQM3QMWYw6wi80jDVIaKS
# RnY7DljJYb5IaBlLbWbuUcb/LmCWHosWbHs4lKkKm7Wu2Nl1EweyTaENbJFeEhyp
# H42d2TodiZYS+kJYOvqaB65PSJt89fJtGRb7ItZsAwwwLBChzWycY1j4Q/YHk6wc
# oXkTcogLhnnj9y6+qmrozI1485revb2WSq8mi06Fvj/8caSjXc57dJdUHydj4xXP
# viCzz9XHi5SU4uFm0I6QHl4Jco0wgUGJpOIQyP5drfIqIU0eMD+paFZNfYyM4eVr
# xXdtRVZVWTdgH4sGDjnJ2ddZ+O4E8rgJwZ/EAplaVLl4oYIXGTCCFxUGCisGAQQB
# gjcDAwExghcFMIIXAQYJKoZIhvcNAQcCoIIW8jCCFu4CAQMxDzANBglghkgBZQME
# AgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEIKXY+tbp+UEQcYD/L2lfW6/AAi9qnVrP6517jh34
# h1KuAgZingL2sYwYEzIwMjIwNjE1MjAzODU5LjY2OFowBIACAfSggdikgdUwgdIx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhh
# bGVzIFRTUyBFU046QTI0MC00QjgyLTEzMEUxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghFoMIIHFDCCBPygAwIBAgITMwAAAY16VS54dJkq
# twABAAABjTANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yMTEwMjgxOTI3NDVaFw0yMzAxMjYxOTI3NDVaMIHSMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQg
# SXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOkEyNDAtNEI4Mi0xMzBFMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA2jRILZg+
# O6U7dLcuwBPMB+0tJUz0wHLqJ5f7KJXQsTzWToADUMYV4xVZnp9mPTWojUJ/l3O4
# XqegLDNduFAObcitrLyY5HDsxAfUG1/2YilcSkSP6CcMqWfsSwULGX5zlsVKHJ7t
# vwg26y6eLklUdFMpiq294T4uJQdXd5O7mFy0vVkaGPGxNWLbZxKNzqKtFnWQ7jMt
# Z05XvafkIWZrNTFv8GGpAlHtRsZ1A8KDo6IDSGVNZZXbQs+fOwMOGp/Bzod8f1YI
# 8Gb2oN/mx2ccvdGr9la55QZeVsM7LfTaEPQxbgAcLgWDlIPcmTzcBksEzLOQsSpB
# zsqPaWI9ykVw5ofmrkFKMbpQT5EMki2suJoVM5xGgdZWnt/tz00xubPSKFi4B4IM
# FUB9mcANUq9cHaLsHbDJ+AUsVO0qnVjwzXPYJeR7C/B8X0Ul6UkIdplZmncQZSBK
# 3yZQy+oGsuJKXFAq3BlxT6kDuhYYvO7itLrPeY0knut1rKkxom+ui6vCdthCfnAi
# yknyRC2lknqzz8x1mDkQ5Q6Ox9p6/lduFupSJMtgsCPN9fIvrfppMDFIvRoULsHO
# dLJjrRli8co5M+vZmf20oTxYuXzM0tbRurEJycB5ZMbwznsFHymOkgyx8OeFnXV3
# car45uejI1B1iqUDbeSNxnvczuOhcpzwackCAwEAAaOCATYwggEyMB0GA1UdDgQW
# BBR4zJFuh59GwpTuSju4STcflihmkzAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoG
# CCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUAA4ICAQA1r3Oz0lEq3VvpdFlh3YBxc4hn
# YkALyYPDa9FO4XgqwkBm8Lsb+lK3tbGGgpi6QJbK3iM3BK0ObBcwRaJVCxGLGtr6
# Jz9hRumRyF8o4n2y3YiKv4olBxNjFShSGc9E29JmVjBmLgmfjRqPc/2rD25q4ow4
# uA3rc9ekiaufgGhcSAdek/l+kASbzohOt/5z2+IlgT4e3auSUzt2GAKfKZB02ZDG
# WKKeCY3pELj1tuh6yfrOJPPInO4ZZLW3vgKavtL8e6FJZyJoDFMewJ59oEL+AK3e
# 2M2I4IFE9n6LVS8bS9UbMUMvrAlXN5ZM2I8GdHB9TbfI17Wm/9Uf4qu588PJN7vC
# Jj9s+KxZqXc5sGScLgqiPqIbbNTE+/AEZ/eTixc9YLgTyMqakZI59wGqjrONQSY7
# u0VEDkEE6ikz+FSFRKKzpySb0WTgMvWxsLvbnN8ACmISPnBHYZoGssPAL7foGGKF
# LdABTQC2PX19WjrfyrshHdiqSlCspqIGBTxRaHtyPMro3B/26gPfCl3MC3rC3NGq
# 4xGnIHDZGSizUmGg8TkQAloVdU5dJ1v910gjxaxaUraGhP8IttE0RWnU5XRp/sGa
# NmDcMwbyHuSpaFsn3Q21OzitP4BnN5tprHangAC7joe4zmLnmRnAiUc9sRqQ2bms
# MAvUpsO8nlOFmiM1LzCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUw
# DQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhv
# cml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg
# 4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aO
# RmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41
# JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5
# LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL
# 64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9
# QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj
# 0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqE
# UUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0
# kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435
# UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB
# 3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTE
# mr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwG
# A1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNV
# HSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNV
# HQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo
# 0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29m
# dC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5j
# cmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDAN
# BgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4
# sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th54
# 2DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRX
# ud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBew
# VIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0
# DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+Cljd
# QDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFr
# DZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFh
# bHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7n
# tdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+
# oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6Fw
# ZvKhggLXMIICQAIBATCCAQChgdikgdUwgdIxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046QTI0MC00Qjgy
# LTEzMEUxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoB
# ATAHBgUrDgMCGgMVAIBzlZM9TRND4PgtpLWQZkSPYVcJoIGDMIGApH4wfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQEFBQACBQDmVF5WMCIY
# DzIwMjIwNjE1MjEzNDE0WhgPMjAyMjA2MTYyMTM0MTRaMHcwPQYKKwYBBAGEWQoE
# ATEvMC0wCgIFAOZUXlYCAQAwCgIBAAICG98CAf8wBwIBAAICIK4wCgIFAOZVr9YC
# AQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEK
# MAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQBgTOPTPb/MdO206Z7XzL9nQFhd
# yiAtdQJd31suG9P3Y4cMzlhvJAOYoNCn4hP1FI8x0p+QcWCCchY3jzMx8AYY9R2C
# 8ITkTZDG9fZVaa4/E0avML3LXcSgJN2PYC92GOxPKkehsyfuTQnua16Ocd/143EV
# ZtD8I5AGubHAUeuO7TGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwAhMzAAABjXpVLnh0mSq3AAEAAAGNMA0GCWCGSAFlAwQCAQUAoIIB
# SjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIMtP
# O86/y/Yo94fcZGyQAo7WW8QP1dIVWtFpGofcie3uMIH6BgsqhkiG9w0BCRACLzGB
# 6jCB5zCB5DCBvQQgnpYRM/odXkDAnzf2udL569W8cfGTgwVuenQ8ttIYzX8wgZgw
# gYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAY16VS54dJkq
# twABAAABjTAiBCB7CF//NOuHqaMbuvTFKbWjvec1WkRdofJqYtHXCNlXOzANBgkq
# hkiG9w0BAQsFAASCAgDUEWobPPfxLTZRUM2GWvS0g3s9a5YIpGm79W0EBCdhVjsS
# 4nPetWtlJpsUKW1OEBkZZx0kXFws7acn2XrL2BwqfccOBIkXDBwlYWoTQl/2AMCN
# Whe0sZtIgqiLu4HuunBRM5gvOw+Vqv/PTfe/6XtjCI+hn0ofMWkzmuxAe99kXvXX
# /kHRf4qv5lcvSI90GBB8FcYA0O5WzqptZTdvHnZ1UxqlQD0ACmOTaIjGqz7taqD3
# eLBr67vizDq0/0VRCXsi1BcnsDPrypgUeX5QyQErVvl/PiCA7ia/fweJxyOKeIDN
# E8L/RhfkQ5NP1bpnCypropxUvv/CW4TL9570VXUh5jOIO3d0v0AZ5OueFEPV+8Hj
# nQEdKHUmqaNJwErwue0ava5nm7COoIsJp4A6yDPgDLoTCLSRvmSwR0olRmOk4UXg
# /MC29moQ5NNLkjWH/yessXT9CWdKdZEOA0CU5OuGcQc0niyQmKjwWkBJhYe3dx5W
# WXhv2CuenCSyeyOeX/Khn8C053egc98EC7VJN1mPUwgb7aswmCO6u0z3zjORGRfi
# 1mXvI4fr921dtYc7kVsCmkPmCHQLWgVLZcuJzShdt+PmC+1awJVqV+efELnbHAfQ
# Cwy7YQd/eTUnLsh0VS7u0JRxA8tU3Z3cnaEiGu7IeKWRxMJMnmYxOZA+hWCq4g==
# SIG # End signature block
