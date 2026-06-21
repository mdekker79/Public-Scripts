<#

    Update File Permissions (requires a passed ACL object)
    Import / Export File Permissions - for backup and restore

    Examples:

      Run Backup Only:
        Set-NTFS -backuponly $true -path <path to root folder for scanning>

      Include File Permissions for Backup:
        Set-NTFS -includeFiles $true -path <path to root folder for scanning> -backuponly $true

      Perform Restore From Saved Object:
        Set-NTFS -path <path to root folder for scanning> -restorefile <path to object file>

      Set NTFS Permissions Based on Template Folder/File:
        Get-ACL -path <Path To Template Object> | Set-NTFS -path <destination root to update permissions>


    Default Values:
        Will use current directory if path not specified
        Will only scan directories if -includeFiles is not set to $true
        Object saved to USERPROFILE\Backups\FILENAME.obj


    TO DO:
        Set depth variable for recursion depth
        Allow for Owner to be changed if requested

#>

<#  -- Get-NTFSOwner Function --  #>

function Get-NTFSOwner{
    [cmdletbinding()]
        param(
          [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string]$path = (Get-Location).path
        )
        
    Process{
        $newACL = Get-Acl $path
        $newACL.Owner.Replace("example\","")
    }
} #End Get-NTFSOwner

<#  -- Set-NTFSOwner Function --  #>

function Set-NTFSOwner{

    [cmdletbinding()]
        param(
          [parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string]$path,

          [parameter(Mandatory=$false)]
        [System.Security.Principal.NTAccount]$owner = (Get-ADDomain).NetBIOSName + "\" + $env:USERNAME
        )

        
    Process{

        $newACL = Get-Acl $path
        $newACL.SetOwner($owner)
        $newACL | Set-Acl -Path $path
    }
} #End Set-NTFSOwner

<#  -- Main Function --  #>

function Set-NTFS{

    [cmdletbinding()]
        param(
          [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string]$path,

          [parameter(Mandatory=$false)]
        [bool]$backupOnly = $false,

          [parameter(Mandatory=$false)]
        [bool]$includeFiles = $false,

          [parameter(Mandatory=$false)]
        [bool]$keepOwner = $false,

          [parameter(Mandatory=$false)]
        [string]$restoreFile = $null,

          [parameter(Mandatory=$false)]
        [System.Security.AccessControl.DirectorySecurity]$newACL = $null
        )
        
    Process{

        <#  -- Set Variables --  #>

        $NTFSBackupPath =  $env:USERPROFILE +"\NTFSBackups"
        $NTFSBackupName = "aclObject" + "-" + $path.Split("\")[$path.count-1] + "-" + (get-date).Day + "-" + (Get-Date).Month + "-" + (Get-Date).Year + ".obj"
        $i = 1
        Set-PSFLoggingProvider -Name logfile -Enabled $true -FilePath 'C:\Users\mdekker-a\NTFSBackups\logs'
        if(!(Test-Path $NTFSBackupPath)){New-Item -Path $NTFSBackupPath -ItemType Directory}

      
        <#  -- Create Object File --  #>

        $NTFSObjectOut = $NTFSBackupPath + "\" + $NTFSBackupName

        while(Test-Path $NTFSObjectOut){
             Write-Host "Backup File Exists, Renaming ..."
             $NTFSBackupName = $NTFSBackupName.Split('(')[0]
             Write-Host "File post split " $NTFSObjectOut 
             $NTFSBackupName = $NTFSBackupName.Replace(".obj","") + "(" + $i + ").obj"
             $NTFSObjectOut = $NTFSBackupPath + "\" + $NTFSBackupName
             $i++
        }

        Write-Host "Path: $path"
        if(!$path){$path = Get-Location}
        Write-Host "Path: $path"
        if($backupOnly -eq $true){
          if($includeFiles){
            Write-Host "Performing Backup Only (Include Files) to the following file: $NTFSObjectOut"
            $childItems = try{
                            Get-ChildItem -Recurse -Path $path -ErrorAction SilentlyContinue
                            Write-PSFMessage -Level Verbose -Message 'Success GCI - $path' -Tag 'Success'
                          }
                          catch{
                            Write-PSFMessage -Level Error -Message 'Error - GCI - $path' -Tag 'Failure'
                          }
            $currentPermissions = 
            $childItems | %{
                $parentPath = ($_.PSParentPath).replace("Microsoft.PowerShell.Core\FileSystem::","")
                $fullPath = $_.FullName
                Set-Location $parentPath
                
                $shortPath = $fullPath.Replace($parentPath,"")
                Write-Host "Shortpath: " $shortPath
                try{Get-Acl $shortPath
                    Write-PSFMessage -Level Verbose -Message 'Success Get-ACL - $fullpath' -Tag 'Success'
                }
                catch{Write-PSFMessage -Level Error -Message 'Error Get-ACL - $fullpath' -Tag 'Failure'
                }
            } 
            $currentPermissions | Export-Clixml $NTFSObjectOut #backup before restore
            Write-Host "Backed up NTFS permissions for $path to file $NTFSObjectOut"
            return
          }
          else{
            Write-Host "Performing Backup Only (Dir Only) to the following file: $NTFSObjectOut"
            $childItems = try{Get-ChildItem -Recurse -Directory -Path $path -ErrorAction SilentlyContinue}catch{Write-Host "Cannot gci " $_.FullName}
            $currentPermissions = 
            $childItems | %{
                $parentPath = ($_.PSParentPath).replace("Microsoft.PowerShell.Core\FileSystem::","")
                $fullPath = $_.FullName
                Set-Location $parentPath
                $shortPath = $fullPath.Replace($parentPath,"")
                try{Get-Acl $shortPath
                    Write-PSFMessage -Level Verbose -Message 'Success Get-ACL - $fullpath' -Tag 'Success'}
                    
                catch{Write-PSFMessage -Level Error -Message 'Error Get-ACL - $fullpath' -Tag 'Failure'}}
            } 
            $currentPermissions | Export-Clixml $NTFSObjectOut #backup before restore
            Write-Host "Backed up NTFS permissions for $path to file $NTFSObjectOut"
            return
          }
        

        if($restoreFile){
          if($includeFiles){
            $currentPermissions = try{Get-ChildItem -recurse $path -ErrorAction SilentlyContinue | Get-Acl} catch{Write-Host "Cannot Get: " $_.path} 
            $currentPermissions | Export-Clixml $NTFSObjectOut #backup before restore
            $permissions = Import-Clixml $restoreFile
            $permissions | %{
                try{
                    Set-Acl -Path $_.PSPath -AclObject $_
                    Write-PSFMessage -Level Verbose -Message 'Success Set-ACL - $fullpath' -Tag 'Success'
                }
                catch{
                    Write-PSFMessage -Level Verbose -Message 'Failure Set-ACL - $fullpath' -Tag 'Failure'
                }
            }
          }
          else{
            $currentPermissions = try{Get-ChildItem -Recurse -Directory -Path $path -ErrorAction SilentlyContinue | Get-Acl} catch{Write-Host "Cannot Get: " $_.path} 
            $currentPermissions | Export-Clixml $NTFSObjectOut #backup before restore
            $permissions = Import-Clixml $restoreFile
            $permissions | %{
                try{
                    Set-Acl -Path $_.PSPath -AclObject $_
                    Write-PSFMessage -Level Verbose -Message 'Success Set-ACL - $fullpath' -Tag 'Success'
                }
                catch{
                    Write-PSFMessage -Level Verbose -Message 'Failure Set-ACL - $fullpath' -Tag 'Failure'
                }
            }
          } 
                
        return
        } #End If      

        <#  -- Set File Permissions --#>
                    
        if(!$includeFiles -and $newACL){
            
            <# -- Backup Permissions -- #>
            $permissions = 
            try{
                Get-ChildItem -recurse $path -Directory | Get-Acl
                Write-PSFMessage -Level Verbose -Message 'Success Get-ACL - $_.PSPath' -Tag 'Success'
            } 
            catch{
                Write-PSFMessage -Level Error -Message 'Error Get-ACL $_.PSPath' -Tag 'Failure'}
            $permissions | Export-Clixml $NTFSObjectOut
            Write-Host "Backed up permissions to: " $NTFSObjectOut

            #  -- Update Permissions --  #>

            $paths = 
            try{
                Get-ChildItem -Directory -recurse $path
                Write-PSFMessage -Level Verbose -Message 'Success GCI - $path' -Tag 'Success'
            }
            catch{
                Write-PSFMessage -Level Error -Message 'Error Get-ACL $_.PSPath' -Tag 'Failure'
            }
            $paths | %{
                $oldOwner = Get-NTFSOwner -path $_.FullName
                try{
                    Set-NTFSOwner -path $_.FullName
                    Write-PSFMessage -Level Verbose -Message 'Success Set-Owner - $_.FullName' -Tag 'Success'
                }
                catch{
                    Write-PSFMessage -Level Error -Message 'Error Set-OwnerL $_.FullName' -Tag 'Failure'
                }
                Write-Host "Updated Owner from $oldOwner to self"
                Set-Acl -Path $_.FullName -AclObject $newACL  
                if($keepOwner){           
                    Set-NTFSOwner -path $_.FullName -owner $oldOwner
                    Write-Host "Updated Perms on $_ and set owner back to $oldOwner"
                }
                
            }
        }
   
     } #End Process
} #End Set-NTFS
  



  <#
        $shortbackupFileName = $path.ToString().Split("\")
        $backupFileName = (Get-Date).month.ToString() + "-" + (Get-Date).day.ToString() + "-" + (Get-Date).year.ToString() + "-" + $shortbackupFileName[$shortbackupFileName.count - 1]
        $NTFSObjectOut = "c:\temp\" + $backupFileName + ".obj"
        #>
        # $path = "\\ad.example.com\shares\IGI_Shares\Software"
        # $path = "\\ad.example.com\shares\applications\install files\Desktop Support Group"