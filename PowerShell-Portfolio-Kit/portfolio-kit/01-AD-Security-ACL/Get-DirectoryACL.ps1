$userDirPath = "\\ad.example.com\userdata\Users"
Get-DirectoryACL -rootFolder $userDirPath -userFolders $true
#$test | Export-Csv testCSVOut.csv -NoTypeInformation -NoClobber

function Get-DirectoryACL{

[cmdletbinding()]
        param(
          [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string]$rootFolder,
          [parameter(Mandatory=$true, ParameterSetName='IncludeSize')]
        [bool]$includeSize = $false,
          [parameter(Mandatory=$true, ParameterSetName='UserFolder')]
        [bool]$userFolders = $true
        )

    
    Process{  
    
    #$outputObject =
    gci $rootFolder
        gci $rootFolder | %{
            Write-Host "root folder: " $rootFolder
            $dirPath = $_.FullName
            $lastAccess = $_.LastAccessTime
            $name = $_.Name
            

          if($userFolders){
            $user = $null
            Write-Host "inside userFolders, with name: " $name
            $user = try{Get-ADUser $name -Properties * | select name,enabled,lastlogondate} catch{}
                if(!$user){$userName=$enabled=$laslogondate=$user="Not in AD"}
                else{
                    $enabled = $user.enabled
                    $lastlogondate = $user.lastlogondate
                    $userName = $user.name
                }
          }#end if

          if($includeSize){
          Write-Host "inside Size with dirPath: " $dirPath
            $size1 = (gci -Recurse $dirPath -File | Measure-Object -Property Length -Sum).Sum /1GB
            $size = [math]::Round($size1,3)

          }#Endif

          $acl = Get-Acl $dirPath
          $owner = $acl.Owner.Split("\")[1]
          Write-Host "Owner is : " $owner
          $ownerEnabled = try{Get-ADUser $owner | select name,enabled}catch{}
        if(!$ownerEnabled){$ownerEnabled="Not in AD"}
            else{
                $ownerIsEnabled = $ownerEnabled.enabled
                #$ownerName = $ownerEnabled.name
            }

         New-Object -TypeName psobject -Property @{
              path           =     $dirPath
              user           =     $userName
              userEnabled    =     $enabled
              userLastLogOn  =     $lastlogondate
              lastAccessed   =     $lastAccess
              size           =     $size
              ownerName      =     $owner
              ownerEnabled   =     $ownerIsEnabled
           } | select path,user,userEnabled,userLastLogOn,lastAccessed,size,ownerName,ownerEnabled

        }#End ForEach
    
    #Write-Output $outputObject
    
    }#End Process 
    
}#End Function

