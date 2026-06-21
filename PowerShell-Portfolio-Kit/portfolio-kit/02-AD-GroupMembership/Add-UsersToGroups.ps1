$groups = gc .\groups.txt #.\decSasGroups.txt
$users = gc .\users.txt

$users | %{
    $user = get-aduser -Properties * -Filter {name -like $_}

    $groups | %{
        $group = Get-ADGroup $_
        Write-Host "Adding User: $user to group $group"
        $group | Add-ADGroupMember -Members $user
    }
}