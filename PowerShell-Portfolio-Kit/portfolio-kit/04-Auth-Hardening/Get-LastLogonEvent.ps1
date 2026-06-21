<#

Written By Mathew Dekker 09/29/2020
Parses EventLog Security Logs for user login date/time and source IP
Currently only supports timespan in days
Can be adjusted to pull all login information if the sourceIp condition in if statement is removed
Can export to csv if returnObject is piped to Export-Csv

To Do: fine tune timespan options, turn into funtion so that it can process multiple servers in one go

#>

#Set up intial variables - recent day = 0 means from now, last day indicates how many days back
$recentDay = 0
$lastDay = 3
$computerName = "phxiodocp01"

$xmlQuery = 
@'
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">*[System[Provider[@Name='Microsoft-Windows-Security-Auditing'] and EventID = 4624] ]
</Select>
    <Suppress Path="Security">*[EventData[Data[@Name='TargetUserName'] and (Data='SYSTEM' or Data = 'svc_ldap_palo' or Data = 'PHXIOUTIL10$')]]
</Suppress>
  </Query>
</QueryList>
'@

$returnObject  = @()
$timeSpanStart = New-TimeSpan -Days $lastDay
$timeSpanEnd   = New-TimeSpan -Days $recentDay
$dateStart     = (Get-Date)  - $timeSpanStart
$dateEnd       = (Get-Date)  - $timeSpanEnd
$events        = Get-WinEvent -ComputerName $computerName -FilterXml $xmlQuery | ?{$_.TimeCreated -le $dateEnd -and $_.TimeCreated -ge $dateStart}

$events | %{
    $timeCreated = $_.TimeCreated
    $message = ($_.message).Split([Environment]::NewLine)
    $user = $message | Select-String -pattern 'ACCOUNT NAME:\s*\w' | Select-String -SimpleMatch "svc" -NotMatch | Select-String -SimpleMatch "$" -NotMatch
    $sourceIp = $message | Select-String -pattern 'Source Network Address:\s*\w'
    
    if($user -and $sourceIp){
        
        $logon = New-Object psobject -Property @{
        
            Date     = $timeCreated
            User     = $user.line -Replace '.*:\s*',''
            SourceIp = $sourceIp -Replace '.*:\s*',''
        }
        $returnObject += $logon

    }

}

$returnObject | sort Date -Descending
