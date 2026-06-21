<#
    11/20/2020
    Access Audit 
    Written By Mathew Dekker

    Returns CSV to UserProfile Documents Folder

#>

function Get-GroupMemberUserInformation{

     [cmdletbinding()]
        param(
          [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string]$ADgroup,
          [parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$domain,
          [parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$server,
          [parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$accessType,
          [parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [string]$access,
          [parameter(Mandatory=$true,ValueFromPipeline=$false)]
        [System.Management.Automation.PSCredential]$credentials
        )

    Begin {}
    Process {
        $userInfo = $null
        $information = $null
        $userInfo = try{Get-ADUser -Server $server -Credential $credentials -Identity $ADgroup -Properties * -ErrorAction SilentlyContinue}catch{Write-Host "Cannot Get AD User Information in Function (Most Likely do to Group Name): " $ADgroup}
        $domainName = $domain

        if($userInfo){
          $information =
            New-Object -TypeName psobject -Property @{
                group       = "No Group"
                domain      = $domainName
                user        = $userInfo.SamAccountName
                first       = $userInfo.GivenName
                last        = $userInfo.SurName
                email       = $userInfo.EmailAddress
                title       = $userInfo.Title
                department  = $userInfo.Department
                displayName = $userInfo.DisplayName
                description = $userInfo.Description
                office      = $userInfo.Office
                enabled     = $userInfo.Enabled
                accessType  = $accessType
                access      = $access
            }
        $global:returnObject += $information
        
        }           
        elseif(!$userInfo){
        
            $users = try{Get-ADGroupMember -Identity $ADgroup -Recursive -Credential $credentials -Server $server -ErrorAction SilentlyContinue}catch{Write-Host "Cannot Get Users from Within Function"}
            Write-Host "Processing Users: " $users.SamAccountName

            $users | %{
                $samAccount = $_.SamAccountName
                $Name = $_.Name
                Write-Host "SAM: $samAccount"
                Write-Host "Name: $name" 
                if($_.DistinguishedName -like "*DC=example,DC=local"){
                    $userInfo = try{Get-ADUser -server $global:exampleServer -Identity $samAccount -Credential $global:exampleCreds -Properties *}catch{Write-Host "Cannot Get example User Info from Within Function For User: " $name}
                    $domainName = "example"
                }
                elseif($_.DistinguishedName -like "*DC=example-inc,DC=com"){
                    $userInfo = try{Get-ADUser -server $global:exampleServer -Identity $samAccount -Credential $global:exampleCreds -Properties *}catch{Write-Host "Cannot Get example User Info from Within Function For User: " $name}
                    $domainName = "example"
                }
                elseif($_.DistinguishedName -like "*DC=example,DC=local"){
                    $userInfo = try{Get-ADUser -server $global:exampleServer -Identity $samAccount -Credential $global:exampleServer -Properties *}catch{Write-Host "Cannot Get example User Info from Within Function For User: " $name}
                    $domainName = "example"
                }
                else{
                    $userInfo = try{Get-ADUser -Server $global:exampleServer -Credential $global:exampleCreds -Properties * -filter{(SamAccountName -like $samAccount) -or (Name -like $name) -or (DistinguishedName -like $_.DistinguishedName)}}catch{}
                    $domainName = "example"
                }

            $information =
                New-Object -TypeName psobject -Property @{
                    group       = $ADgroup
                    groupDomain = $domain
                    userDomain  = $domainName
                    user        = $userInfo.SamAccountName
                    first       = $userInfo.GivenName
                    last        = $userInfo.SurName
                    displayName = $userInfo.DisplayName
                    email       = $userInfo.EmailAddress
                    title       = $userInfo.Title
                    department  = $userInfo.Department
                    description = $userInfo.Description
                    office      = $userInfo.Office
                    enabled     = $userInfo.Enabled
                    accessType  = $accessType
                    access      = $access
                }

            $global:returnObject += $information
          }
        }
    }
    End{}
}

<#
----------------------------------- Start Script --------------------------------------------------
#>

$pathOfShare = Read-Host "Enter Path to Share for Access Report"
$domainOfShare = Read-Host "Enter Domain for Share (example, example, example or example)"
if($domainOfShare -notlike "example" -and $domainOfShare -notlike "example" -and $domainOfShare -notlike "example" -and $domainOfShare -notlike "example"){Write-Host "Bad Domain";return}
$fileName = ($pathOfShare.Replace("\\","")).replace("\","-")
$exportFileName = $env:USERPROFILE + "\Documents\" + $fileName + ".csv"

if(Test-Path $exportFileName){
    $delete = Read-Host "File Exists, Enter 1 to Delete $exportFileName"
    if($delete -eq 1){rm $exportFileName}
    else{return}
}
$userInformationDetails = $null
$global:returnObject = @()


Write-Host "Enter example Creds"
$global:exampleCreds = Get-Credential -Message "Enter example Creds"
$global:exampleServer = "phxioexampledc01"

Write-Host "Enter example Creds"
$global:exampleCreds = Get-Credential -Message "Enter example Creds"
$global:exampleServer = "phxiodc04"

Write-Host "Enter example Creds"
$global:exampleCreds = Get-Credential -Message "Enter example Creds"
$global:exampleServer = "phxioexampledc01"

Write-Host "Enter example Creds"
$global:exampleCreds = Get-Credential -Message "Enter example Creds"
$global:exampleServer = "njioexampledc01.example-inc.com"


$accessInformation = 

Switch($domainOfShare.ToUpper())
{
    example {
        $drive = New-PSDrive -Name "temp" -Root $pathOfShare -PSProvider "FileSystem" -Credential $global:exampleCreds
        (Get-Acl $drive.root).Access
        Get-PSDrive -Name temp | Remove-PSDrive
        #Invoke-Command -ComputerName $global:exampleServer -Credential $global:exampleCreds -ScriptBlock {(Get-Acl -Path $args[0]).Access} -ArgumentList $pathOfShare
    }
    example {
        $drive = New-PSDrive -Name "temp" -Root $pathOfShare -PSProvider "FileSystem" -Credential $global:exampleCreds
        (Get-Acl $drive.root).Access
        Get-PSDrive -Name temp | Remove-PSDrive
        #Invoke-Command -ComputerName $global:exampleServer -Credential $global:exampleCreds -ScriptBlock {(Get-Acl -Path $args[0]).Access} -ArgumentList $pathOfShare
    }
    example {
        $drive = New-PSDrive -Name "temp" -Root $pathOfShare -PSProvider "FileSystem" -Credential $global:exampleCreds
        (Get-Acl $drive.root).Access
        Get-PSDrive -Name temp | Remove-PSDrive
        #Invoke-Command -ComputerName $global:exampleServer -Credential $global:exampleCreds -ScriptBlock {(Get-Acl -Path $args[0]).Access} -ArgumentList $pathOfShare
    }
    example {
        $drive = New-PSDrive -Name "temp" -Root $pathOfShare -PSProvider "FileSystem" -Credential $global:exampleCreds
        (Get-Acl $drive.root).Access
        Get-PSDrive -Name temp | Remove-PSDrive
        #Invoke-Command -Credential $global:exampleCreds -ScriptBlock {(Get-Acl -Path $args[0]).Access} -ArgumentList $pathOfShare
    }
}

Write-Host "ACL Information to be reported on:" 
$accessInformation

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

    if($domain -like "*example*"){
        try{Get-GroupMemberUserInformation -accessType $accessType -access $access -domain $domain -server $global:exampleServer -ADgroup $identity -credentials $global:exampleCreds -ErrorAction SilentlyContinue}catch{}
        
    }
    if($domain -like "*example*"){
        try{Get-GroupMemberUserInformation -accessType $accessType -access $access -domain $domain -server $global:exampleServer -ADgroup $identity -credentials $global:exampleCreds -ErrorAction SilentlyContinue}catch{}
        
    }
    if($domain -like "*example*"){
        try{Get-GroupMemberUserInformation -accessType $accessType -access $access -domain $domain -server $global:exampleServer -ADgroup $identity -credentials $global:exampleServer -ErrorAction SilentlyContinue}catch{}
        
    }
    if($domain -like "*ac&f*"){
        try{Get-GroupMemberUserInformation -accessType $accessType -access $access -domain $domain -server $global:exampleServer -ADgroup $identity -credentials $global:exampleCreds -ErrorAction SilentlyContinue}catch{}
        
    }
    if($domain -like "No Domain"){
        $userInformationDetails =
            New-Object -TypeName psobject -Property @{
                group       = "No Group"
                groupDomain = "No Group"
                userDomain  = $domain
                user        = $identity
                first       = "No AD Info"
                last        = "No AD Info"
                displayName = "No AD Info"
                email       = "No AD Info"
                title       = "No AD Info"
                department  = "No AD Info"
                description = "No AD Info"
                office      = "No AD Info"
                enabled     = "No AD Info"
                accessType  = $accessType
                access      = $access
            }
        $global:returnObject += $userInformationDetails
    }
 
}

$global:returnObject | select group,groupDomain,userDomain,user,first,last,displayName,email,title,department,description,office,enabled,accessType,access | Export-Csv -NoTypeInformation $exportFileName