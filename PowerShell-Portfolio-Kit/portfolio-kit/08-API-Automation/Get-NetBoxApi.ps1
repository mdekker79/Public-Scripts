
function Get-NetboxAPI{

    [CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]
    $requestURL,
    [Parameter(Mandatory = $true)]
    [string]
    $token
)

    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Accept", "application/json")
    $headers.Add("Authorization", "Token $token")

    $response = Invoke-RestMethod $requestURL -Method 'GET' -Headers $headers | ConvertTo-Json -Depth 5
    $response 

}

$token = "<NETBOX-API-TOKEN>" #| ConvertTo-SecureString -AsPlainText -Force
$requestURL = "https://netbox-dev.ad.example.com/api/ipam/ip-addresses/?address=<netbox-host-ip>"

Get-NetboxAPI -requestURL $requestURL -token $token