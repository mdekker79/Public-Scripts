<#
    11/20/2020
    Access Audit global
    Writen By Mathew Dekker

    Returns CSV to UserProfile Documents Folder

#>


function Get-GroupMemberUserInformation{

     [cmdletbinding()]
        param(
          [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string]$ADgroup,
          [parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$domain = "example",
          [parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$server,
          [parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [System.Management.Automation.PSCredential]$credentials
        )

    Begin {}
    Process {
        $returnInformation = @()
        $userInfo = try{Get-ADUser -Server $server -Credential $credentials -Identity $ADgroup -Properties * -ErrorAction SilentlyContinue}catch{Write-Host "Cannot Get AD User Information in Function (Most Likely do to Group)"}
        $domainName = $domain
        $returnInformation +=
            New-Object -TypeName psobject -Property @{
                group       = "No Group"
                domain      = $domainName
                user        = $userInfo.Name
                first       = $userInfo.GivenName
                last        = $userInfo.SurName
                email       = $userInfo.EmailAddress
                title       = $userInfo.Title
                department  = $userInfo.Department
                deglobalion = $userInfo.Deglobalion
                office      = $userInfo.Office
                enabled     = $userInfo.Enabled
            }
                   
        if(!$userInfo){
        
            $users = try{Get-ADGroupMember -Recursive -Server $server -Credential $credentials -Identity $ADgroup -ErrorAction SilentlyContinue}catch{Write-Host "Cannot Get Users from Within Function"}
            Write-Host "Processing Users: " $users.SamAccountName

            $users | %{
                $samAccount = $_.SamAccountName
                $Name = $_.Name
                Write-Host "SAM: $samAccount"
                Write-Host "Name: $name" 
                if($_.DistinguishedName -like "*DC=example,DC=local"){
                    $userInfo = try{Get-ADUser -server $global:exampleServer -Identity $samAccount -credentials $global:exampleCreds -Properties *}catch{Write-Host "Cannot Get example User Info from Within Function For User: " $name}
                    $domainName = "example"
                }
                elseif($_.DistinguishedName -like "*DC=example-inc,DC=com"){
                    $userInfo = try{Get-ADUser -server $global:exampleServer -Identity $samAccount -credentials $global:exampleCreds -Properties *}catch{Write-Host "Cannot Get example User Info from Within Function For User: " $name
                    $global:exampleServer
                    ($global:exampleCreds).UserName
                    ($global:exampleCreds).Password
                    Write-Host "SamAccount - $samAccount"
                    }
                    $domainName = "example"
                }
                elseif($_.DistinguishedName -like "*DC=example,DC=local"){
                    $userInfo = try{Get-ADUser -server $global:exampleServer -Identity $samAccount -credentials $global:exampleServer -Properties *}catch{Write-Host "Cannot Get example User Info from Within Function For User: " $name}
                    $domainName = "example"
                }
                else{
                    $userInfo = try{Get-ADUser -server $global:exampleServer -Identity $samAccount -credentials $global:exampleCreds -Properties *}catch{Write-Host "Cannot Get example User Info from Within Function For User: " $name
                    $global:exampleServer
                    ($global:exampleCreds).UserName
                    ($global:exampleCreds).Password
                    Write-Host "SamAccount - $samAccount"
                    }
                    $domainName = "example"
                }

            $information =
                New-Object -TypeName psobject -Property @{
                    group       = $ADgroup
                    domain      = $domainName
                    user        = $userInfo.Name
                    first       = $userInfo.GivenName
                    last        = $userInfo.SurName
                    email       = $userInfo.EmailAddress
                    title       = $userInfo.Title
                    department  = $userInfo.Department
                    deglobalion = $userInfo.Deglobalion
                    office      = $userInfo.Office
                    enabled     = $userInfo.Enabled
                }

            $returnInformation += $information

            }
         }
 
         $returnInformation
    }
    End{}
}


$DefaultVariables = $(Get-Variable).Name
$pathOfShare = Read-Host "Enter Path to Share for Access Report"
$domainOfShare = Read-Host "Enter Domain for Share (example, example, example or example)"
if($domainOfShare -notlike "example" -and $domainOfShare -notlike "example" -and $domainOfShare -notlike "example" -and $domainOfShare -notlike "example"){Write-Host "Bad Domain";return}
$fileName = ($pathOfShare.Replace("\\","")).replace("\","-")
$exportFileName = $env:USERPROFILE + "\Documents\" + $fileName + ".csv"

$returnObject = @()

Write-Host "Enter example Creds"
$global:exampleCreds = Get-Credential -Message "Enter example Creds"
$global:exampleServer = "phxioexampledc01"

Write-Host "Enter example Creds"
$global:exampleCreds = Get-Credential -Message "Enter example Creds"
$global:exampleServer = "phxiodc01"

Write-Host "Enter example Creds"
$global:exampleCreds = Get-Credential -Message "Enter example Creds"
$global:exampleServer = "phxioexampledc01"

Write-Host "Enter example Creds"
$global:exampleCreds = Get-Credential -Message "Enter example Creds"
$global:exampleServer = "njioexampledc01"

$accessInformation = 
Switch($domainOfShare)
{
    example {Invoke-Command -ComputerName $global:exampleServer -Credential $global:exampleCreds -ScriptBlock {(Get-Acl -Path $args[0]).Access} -ArgumentList $pathOfShare}
    example {Invoke-Command -ComputerName $global:exampleServer -Credential $global:exampleCreds -ScriptBlock {(Get-Acl -Path $args[0]).Access} -ArgumentList $pathOfShare}
    example {Invoke-Command -ComputerName $global:exampleServer -ScriptBlock {(Get-Acl -Path $args[0]).Access} -ArgumentList $pathOfShare}
    example {Invoke-Command -ComputerName $global:exampleServer -Credential $global:exampleCreds -ScriptBlock {(Get-Acl -Path $args[0]).Access} -ArgumentList $pathOfShare}
}

Write-Host "ACL Information to be reported on:" 
$accessInformation

Write-Host "Current global Variables:"
$global:exampleServer
$global:exampleServer
$global:exampleServer
$global:exampleServer




$accessInformation | %{
    if($_.IdentityReference -like "*\*"){
        $identity   = (($_.IdentityReference).tostring()).split("\")[1]
        $domain     = (($_.IdentityReference).tostring()).split("\")[0]
    }
    else{
        $identity = ($_.IdentityReference).toString()
        $domain   = "No Domain"
    }
    $access     = $_.FileSystemRights
    $accessType = $_.AccessControlType
    $userInfo = $null

    if($domain -like "*example*"){
        $userInformation = try{Get-GroupMemberUserInformation -domain $domain -server $global:exampleServer -ADgroup $identity -credentials $global:exampleCreds -ErrorAction SilentlyContinue}catch{}
    }
    if($domain -like "*example*"){
        $userInformation = try{Get-GroupMemberUserInformation -domain $domain -server $global:exampleServer -ADgroup $identity -credentials $global:exampleCreds -ErrorAction SilentlyContinue}catch{}
    }
    if($domain -like "*example*"){
        $userInformation = try{Get-GroupMemberUserInformation -domain $domain -server $global:exampleServer -ADgroup $identity -credentials $global:exampleServer -ErrorAction SilentlyContinue}catch{}
    }
    if($domain -like "*ac&f*"){
        $userInformation = try{Get-GroupMemberUserInformation -domain $domain -server $global:exampleServer -ADgroup $identity -credentials $global:exampleCreds -ErrorAction SilentlyContinue}catch{}
    }
    if($domain -like "No Domain"){
        $userInformationDetails =
            New-Object -TypeName psobject -Property @{
                group       = "No Group"
                domain      = $domain
                user        = $identity
                first       = $null
                last        = $null
                email       = $null
                title       = $null
                department  = $null
                deglobalion = $null
                office      = $null
                enabled     = $null
                accessType  = $accessType
                access      = $access
            }
    }
    else{
        $userInformationDetails =
            New-Object -TypeName psobject -Property @{
                group       = $userInformation.Group
                domain      = $userInformation.Domain
                user        = $userInformation.Name
                first       = $userInformation.GivenName
                last        = $userInformation.SurName
                email       = $userInformation.EmailAddress
                title       = $userInformation.Title
                department  = $userInformation.Department
                deglobalion = $userInformation.Deglobalion
                office      = $userInformation.Office
                enabled     = $userInformation.Enabled
                accessType  = $accessType
                access      = $access
            }
    }
    $returnObject += $userInformationDetails
    
        
}

$returnObject | select group,domain,user,first,last,email,title,department,deglobalion,office,enabled,accessType,access | Export-Csv -NoTypeInformation $exportFileName