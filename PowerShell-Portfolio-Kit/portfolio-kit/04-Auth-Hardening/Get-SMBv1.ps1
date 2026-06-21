<#   computers.txt will contain a list of computers without any leading or trailing spaces   #>

$servers =  gc .\computers.txt
#Get-ADComputer -Properties * -SearchBase "OU=MemberServers,OU=Systems,OU=example,DC=internal,DC=example,DC=com" -Filter *
$returnObject = @()

$servers | %{

#$serverName = $_.split(".")[0]
Write-Host "Server: " $_
$property =

   try{
    
    Invoke-Command -ComputerName $_ -ScriptBlock{
    
    #use the smb commandlet to set the needed values 
    
        Set-SmbServerConfiguration -EnableSecuritySignature $true -Force
        Set-SmbServerConfiguration -EnableSecuritySignature $true -Force
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
        Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force

        <#

            This should not be needed for Windows 10, but if R7 is scanning, you can set these registry values as well

            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" SMB1 -Type DWORD -Value 0 -Force
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" SMB2 -Type DWORD -Value 1 -Force
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" EnableSecuritySignature -Type DWORD -Value 1 -Force
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" RequireSecuritySignature -Type DWORD -Value 1 -Force
        
        #>
    
      $smb2 = Get-SmbServerConfiguration -ErrorAction SilentlyContinue

                if($smb2){
                  #Write-Host "SMB Installed: " $smb1.installState 
                  Write-Host "SMB2 Enabled: " $smb2.EnableSMB2Protocol
                  Write-Host "SMB1 Enabled: "$smb2.EnableSMB1Protocol
                  Write-Host "SMB Signed Required: " $smb2.RequireSecuritySignature
                  Write-Host "SMB Signed Enabled: " $smb2.EnableSecuritySignature
                  Write-Host "SMB Registry: " 
                  
                  
                  
                      $regSMB1    = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" SMB1 | select smb1
                      $regSMB2    = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" SMB2 | select smb2
                      $regEnable  = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" EnableSecuritySignature | select enablesecuritysignature
                      $regRequire = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" RequireSecuritySignature | select requiresecuritysignature

                  $properties = New-Object psobject -Property @{

                    Server = $serverName
                    smb2enabled = ($smb2.EnableSMB2Protocol).tostring()
                    Smb1enabled = ($smb2.EnableSMB1Protocol).tostring()
                    SignedReq = ($smb2.RequireSecuritySignature).tostring()
                    SignedEnable = ($smb2.EnableSecuritySignature).tostring()
                    regEnable = ($regEnable.EnableSecuritySignature).tostring()
                    regRequire = ($regRequire.RequireSecuritySignature).tostring()
                    regSMB1 = ($regSMB1.SMB1).tostring()
                    regSMB2 = ($regSMB2.SMB2).tostring()
                  }
                  $properties
                }

       }#invoke
  
   }#foreach
   catch{Write-Host "cannot connect: " $_}
   $returnObject += $property 
}

$returnObject | Export-Csv -NoTypeInformation smbReport1.csv