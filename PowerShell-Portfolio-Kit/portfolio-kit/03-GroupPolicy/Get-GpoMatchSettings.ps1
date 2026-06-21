pin

$gpos          = Get-GPO -All  
$setting       = "Windows Components/Internet Explorer/Internet Control Panel/Security Page"
$output = @()

$gpos | %{
    $gpoName = $_.DisplayName
    $reportXml = Get-GPOReport -Guid $_.Id -ReportType Xml
    [xml]$xml  = Get-GPOReport -Guid $_.Id -ReportType Xml
    $match = ($reportXml | Select-String -Pattern $setting).Matches.Success
    Write-Host "GPO: " $gpoName
    if($match){Write-Host "Matches!"}
    Else{Write-Host "Does Not Match."}

    if($match){
    [array]$links = $xml.GPO.LinksTo.SOMPath
    [array]$data = $xml.GPO.User.ExtensionData.Extension.ChildNodes.ListBox.Value.Element.Name
    Write-Host "Matched GPO: " $gpoName
    Write-Host "Matched Data: " $data
    $i=$data.Count
    
     while($i -ge 1){
        $i--
        $j = $links.count
        while($j -ge 1){
         $j--
         $gpo = New-Object psobject
         $gpo | Add-Member -NotePropertyName GPOName -NotePropertyValue $gpoName
         $gpo | Add-Member -NotePropertyName Data -NotePropertyValue $data[$i]
         $gpo | Add-Member -NotePropertyName Linked -NotePropertyValue $links[$j]
         $output += $gpo
        }
     }

    }
}

$output | select gpoName,Data,Linked | Export-Csv -NoTypeInformation iesecurityGPOsettings.csv

