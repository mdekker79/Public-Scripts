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


$rootPath = try{gci '\\ad.example.com\userdata\IGI_Users' -Directory -ErrorAction SilentlyContinue} catch{}
$paths1 = $rootPath | %{try {gci $_.FullName -Directory -ErrorAction SilentlyContinue}catch{}}
$paths2 = try{gci "\\ad.example.com\userdata\Profiles\v2$" -Directory -ErrorAction SilentlyContinue} catch{}
$paths3 = try{gci "\\ad.example.com\userdata\Profiles\v3$" -Directory -ErrorAction SilentlyContinue} catch{}


$paths1 | Get-FolderAudit -includeSize $false | Export-Csv userdirectoryAudit.csv -NoClobber -NoTypeInformation
#$paths2 | Get-FolderAudit -includeSize $false | Export-Csv userdirectoryAudit.csv -NoClobber -NoTypeInformation -Append
#$paths3 | Get-FolderAudit -includeSize $false | Export-Csv userdirectoryAudit.csv -NoClobber -NoTypeInformation -Append



function Get-FolderAudit{

    [cmdletbinding()]
        param(
          [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [System.IO.DirectoryInfo]$directories,
          [parameter(Mandatory=$true, ParameterSetName='IncludeSize')]
        [bool]$includeSize = $false,
          [parameter(Mandatory=$true, ParameterSetName='UserFolder')]
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
            $lastModified = $directory.LastWriteTimes

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
            $sizeB4 = (gci -Recurse $directory -File -ErrorAction Stop | Measure-Object -Property Length -Sum).Sum /1GB
            $size = [math]::Round($sizeB4,3)

        }#End Include Size

        

            New-Object -TypeName psobject -Property @{
              path           = $directory.fullname
              owner          = $owner
              ownerEnabled   = $ownerEnable 
              ownerLastLog   = $ownerLastLog
              user           = $adUser
              userEnabled    = $UserEnabled
              userLastLog    = $userLastLogon
              size           = $size
              lastAccess     = $lastAccess
              lastModify     = $lastModified
              
           } | select path, owner, ownerEnabled, ownerLastLog, user, userEnabled, userLastLog,lastMofiy, lastAccess, size

     }

    } 

}


