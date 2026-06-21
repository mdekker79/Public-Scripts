Set-Location ad:
$OUs = Get-ADOrganizationalUnit -SearchBase "OU=example,DC=internal,DC=example,DC=com" -Filter *
$ACL = $OUs | %{Get-Acl -Path $_.DistinguishedName} 

$ACL | %{
    $path = $_.Path
    $access = $_.access
}
