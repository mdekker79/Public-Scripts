function Connect-SecretServer(){
    <#
        .SYNOPSIS
        Connects to Secret Server.
        .DESCRIPTION
        Establishes a connection the the Secret Server to do API calls for GET,
        SET, PUT, and DELETE https calls
        .PARAMETER Server
        Specifies the secret server used
        .PARAMETER User
        Specifies the user name for the secret server access
        .PARAMETER Password
        Specifies the password required for the user to access the secret server
        .PARAMETER GrantType
        Specifies the type of token to establish.
        .INPUTS
        None. You cannot pipe objects to Add-Extension.
        .OUTPUTS
        returns the connection.
        .EXAMPLE
        Connect-SecretServer -Server '<servername>' -User '<username>' -Password '<password>'
        .EXAMPLE
        Connect-SecretServer -Server '<servername>' -User '<username>' -Password '<password>' -GrantType 'refresh_token'
    #>
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string]$Server,
        [string]$User,
        [string]$Password,
        [Parameter(Mandatory=$false)]
        [string]$GrantType = 'password'
    )
    $creds = @{
            username = "example\$User"
            password = $Password
            grant_type = 'password'#$GrantType
    }
    $tokenRoute = "https://$Server/oauth2/token";
    try{
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $response = Invoke-RestMethod $tokenRoute -Method Post -Body $creds
        $token = $response.access_token;
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", "Bearer $token")
        return New-Object -TypeName psobject -Property @{
        header = $headers
        api = $api
    }
    }catch [System.Net.WebException]{
        Write-Host "----- Exception -----"
        Write-Host  $_.Exception
        Write-Host  $_.Exception.Response.StatusCode
        Write-Host  $_.Exception.Response.StatusDescription
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $responseBody = $reader.ReadToEnd()
        Write-Host $responseBody
    }
}
Connect-SecretServer -User 'username' -Password 'password' -Server 'secrets.ad.example.com'