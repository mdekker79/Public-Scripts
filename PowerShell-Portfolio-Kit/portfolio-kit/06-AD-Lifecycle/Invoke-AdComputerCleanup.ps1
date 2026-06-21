<#
    Date: 03.04.2020
    Author: Mathew Dekker
    Purpose: Remove old AD computer Objects
#>

<#Variables#>

$date = Get-Date
$timeSpan = $date.AddDays(-90)
$disabledOU = "OU=Disabled_Computers,DC=internal,DC=example,DC=com"
 
$computersInDisabledOU = Get-ADObject -SearchBase $disabledOu -Properties *  -filter {LastLogonDate -lt $timeSpan} 

#delete it
$computersInDisabledOU | %{
    $success = "False"
    $object = $_.name
    $lastlogon = $_.lastlogondate
    if(Write-Host $object){
      $success = "true"
    }

    New-Object -TypeName psobject -Property @{
              success = $success
              object = $object
              lastlogon = $lastlogon.Date.ToString()              
           } | select object,lastlogon,success
    
    } | Export-Csv deletedComputerObject3.csv -NoTypeInformation -NoClobber
    

 