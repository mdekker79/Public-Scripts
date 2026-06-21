function Get-NestedGroups
{

    [cmdletbinding()]
        param(
          [parameter(Mandatory=$true,ValueFromPipeline=$true)]
        $group
        )

<#    Variables   #>

    Begin {
             
     } #End Begin


<#   Begin Process, to be ran for each input   #>

    Process {
        #Write-Host "Parent Group: " $group
        $memberOf = Get-ADGroup $group -Properties * | Select-Object memberof -ExpandProperty memberof 
        if($memberOf.Count -gt 0){
            #Write-Host ""
            #Write-Host "Group: " $group " is a member of the following: "
            $memberOf | ForEach-Object{
                [string]$group = $_
                $groupShort = $group.split(",")[0].Replace("CN=","")
                $groupShort
                Get-NestedGroups $groupShort
                
            }
        
        }
        else{}

        
    }
}

<#
#$adminCreds = Get-AdminCreds
Get-ADGroup -Credential $adminCreds -Filter {name -like "RG-Tableau*"} | %{
    $parent = $null
    $group = $_.name
    $parent = Get-NestedGroups $_.name

    if($parent -ne $null){
        Write-Host "Group: " $group
        Write-Host "Parent: " $parent
    }


}

#>