<#

    Move Disabled Computer Object to Disabled OU

#>


$timeSpan = (Get-Date).Day - 14
$disabledOu = "disabledoupath"
$disabledComputers = Get-ADComputer -Properties * -Filter {(enabled -eq $false) -and (distinguishedname -notlike "*disabled*")}

$disabledComputers | %{
    $computer = $_.Name
    $lastWrite = $_.lastwritetime
    $ou = $_.distinguishedname
    $securityGroups = $_.memberof

    if($lastWrite -gt $timeSpan){
        $computer | Move-ADObject -TargetPath $disabledOU
    }

}