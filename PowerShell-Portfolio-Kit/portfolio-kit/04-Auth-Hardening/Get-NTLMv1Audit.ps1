$computers = Get-ADDomainController -filter * | Select-Object name
$keyServer = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0'
$keyLanMan = 'HKLM:\System\CurrentControlSet\Control\LSA'
$valuenameClient = 'NtlmMinClientSec'
$valuenameServer = 'NtlmMinServerSec'
$lanValue = 'LMCompatibilityLevel'
Write-Host "Script Shows the following in order, NtlmMinClient, NtlmMinServer,RestrictAnonymous and LMCompatibilityLevel"
foreach ($computer in $computers) {

        Write-Host "Hostname: " $computer.name
        
        Invoke-Command -ComputerName $computer.Name -ScriptBlock {

            <# ----------------------- Uncomment to Make Change ---------------------------#>
            #Set-ItemProperty -Path $args[0] -Name "NtlmMinClientSec" -Value 537395200
            #Set-ItemProperty -Path $args[0] -Name "NtlmMinServerSec" -Value 537395200
            #Set-ItemProperty -Path $args[0] -Name "RestrictAnonymous" -Value 1
            #Set-ItemProperty -Path $args[1] -Name "LMCompatibilityLevel" -Value 3

            (Get-ItemProperty -Path $args[0] -Name "NtlmMinClientSec").NtlmMinClientSec
            (Get-ItemProperty -Path $args[0] -Name "NtlmMinServerSec").NtlmMinServerSec
            (Get-ItemProperty -Path $args[0] -Name "RestrictAnonymous").RestrictAnonymous
            (Get-ItemProperty -Path $args[1] -Name "LMCompatibilityLevel").LMCompatibilityLevel
            

        } -ArgumentList $keyServer,$keyLanMan

}