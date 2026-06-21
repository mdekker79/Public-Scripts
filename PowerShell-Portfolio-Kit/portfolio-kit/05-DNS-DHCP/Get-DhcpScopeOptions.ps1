$dhcpServers = Get-ADComputer -Filter {name -like "*dhcp*"}

$dhcpServers | Get-DHCPServerScopeOptions | Export-Csv -Path C:\Users\mdekker\Documents\DHCPnDNSinfo\dhcpScopeOptions.csv -NoClobber -NoTypeInformation


function Get-DHCPServerScopeOptions{

    [cmdletbinding()]
        param(
          [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [Microsoft.ActiveDirectory.Management.ADComputer]$dhcpserver
        )

        Begin{
        # may add additional variables logging or error handling

        }


Process{

        $outPut = @()
        $dhcpName = $dhcpserver.Name
        
        $dhcpScopes = Get-DhcpServerv4Scope -ComputerName $dhcpName

        $dhcpScopes | % {

            $scopeId = $_.ScopeId.IPAddressToString
            $optionValues = Get-DhcpServerv4OptionValue -ComputerName $dhcpserver -ScopeId $scopeId
            $total = $optionValues.Count
            $count = 0

            $optionValues | %{

            
                [int]$count = 0


               while($count -lt $total){
               
                   $optionValuesObject = New-Object psobject
               
                   $OptionId           = $optionValues.OptionId[$count]
                   $optionName         = $optionValues.Name[$count]
                   $Value              = $optionValues.Value[$count]
                   
                   $optionValuesObject | Add-Member -NotePropertyName DHCPServer -NotePropertyValue $dhcpName
                   $optionValuesObject | Add-Member -NotePropertyName ScopeId -NotePropertyValue $scopeId
                   $optionValuesObject | Add-Member -NotePropertyName OptionId -NotePropertyValue $OptionId
                   $optionValuesObject | Add-Member -NotePropertyName OptionName -NotePropertyValue $optionName
                   $optionValuesObject | Add-Member -NotePropertyName OptionValue -NotePropertyValue $Value
                   $optionValuesObject | Add-Member -NotePropertyName Count -NotePropertyValue $count
               <#
                   Write-Host "DHCPServer: " $dhcpName
                   Write-Host "Scope ID" $scopeId
                   Write-Host "OptionID: " $OptionId
                   Write-Host "optionName: " $optionName
                   Write-Host "OptionValue: " $Value
                   Write-Host "Count: " $count
               #>
                   $count++
                   $outPut += $optionValuesObject 
               
             }#end While  
        }#end for each option

       }#end foreach dhcp scope
        
        $outPut
  }  
}
