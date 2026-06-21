<#

--------------------   Get-FolderAudit   ----------------------

written by Mathew Dekker 03/26/2020

Will return an object containing the following properties:

path         : full path the the folder
owner        : account with ownership of folder
ownerEnabled : if the account is enabled in Active Directory
ownerLastLog : last logon date in Active Directory for Owner
user         : if the "UserFolder" switch is set to $true, this returns the DN of the user whose folder this is - for use in UserData scenarios where folder name is username
userEnabled  : if the "UserFolder" switch is set to $true, this returns the status of the AD user account
userLastLog  : if the "UserFolder" switch is set to $true, this returns the Last Logon Date of the user
size         : if the "IncludeSize" switch is set to $true, this returns the size of the folder - currently extremely slow, work in progress

Accepts pipeline input of type [System.IO.DirectoryInfo]
Default value for get size is set to false
Default value for is user folder is set to true

example: gci C:\users | Get-FolderAudit -includeSize $true

#>


#set up variables:
$timeSpan = (Get-Date).AddDays(-365)


function Get-FolderAudit{

    [cmdletbinding()]
        param(
          [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [System.IO.DirectoryInfo]$directories,
          [parameter(Mandatory=$true)]
        [bool]$includeSize = $false,
          [parameter(Mandatory=$true)]
        [bool]$userFolder = $true
        )

        Begin{
        # may add additional variables or processes here such as logging or email setup
        }

        Process{


        foreach($directory in $directories){
            $dir          = $directory.fullname
            $acl          = try{Get-Acl $dir}catch{}
            $owner        = $acl.Owner
            $ownerAD      = try{Get-ADUser $owner.Split("\")[1] -properties Enabled,Name,LastLogonDate} catch{}

            if(!$ownerAD){$ownerEnable = $ownerLastLog="User Not in AD"}
            
            else{
              $ownerEnable  = $ownerAD.Enabled
              $ownerLastLog = $ownerAD.LastLogonDate
            }

            $lastAccess   = $directory.LastAccessTime
            $lastModifiedCount = $directory.LastWriteTime.count
            if($lastModifiedCount -gt 1) {$lastModified = $directory.LastWriteTime[$lastModifiedCount - 1]}
            else{$lastModified = $directory.LastWriteTime}
         if($userFolder){
             $user = $directory.name

             #to deal with folders that are appended with .examplev2 or .examplev3
               $user = $user.replace(".exampleV2","")
               $user = $user.replace(".V2","")

             $adUser = try{Get-ADUser $user -Properties Enabled,Name,LastLogonDate}catch{}
           if($adUser){
               $UserEnabled   = $adUser.Enabled
               $userLastLogon = $adUser.LastLogonDate
               $userName = $adUser.Name
            }
            else{
               $userName = $user
               $userLastLogon = "User Not Found in AD"
               $UserEnabled = "User Not Found in AD"
            }
        }#End If User Folder
            
        if($includeSize){
            $sizeB4 = (gci -Recurse $directory -File -ErrorAction Stop | Measure-Object -Property Length -Sum).Sum /1MB
            $size = [math]::Round($sizeB4,3)

        }#End Include Size

        

            New-Object -TypeName psobject -Property @{
              path           = $directory.fullname
              owner          = $owner
              ownerEnabled   = $ownerEnable 
              ownerLastLog   = $ownerLastLog
              user           = if($adUser){$adUser}else{$user}
              userEnabled    = $UserEnabled
              userLastLog    = $userLastLogon
              size           = $size
              lastAccess     = $lastAccess
              lastModify     = $lastModified
              
           } | select path, owner, ownerEnabled, ownerLastLog, user, userEnabled, userLastLog,lastModify, lastAccess, size

     }

    } 

}

$path = \\fileserver01\f$

$directories = gci -Recurse -Depth 2 -Directory $path

$directories | %{

    $files = gci -File $_.FullName
    if($files | ?{$_.LastAccessTime -gt $timeSpan}){$old = $false}
    else{$old = $true}

    if($old -eq $true){
    
        $users = (Get-Acl $_.FullName).Access.identityreference
        Write-Host "Directory: " $_.FullName
        Write-Host "Access List: " $users    
    }

}

