
$search = "sp-im-admin*"
$dnsServer = "<dns-server-ip>"


$pointerZones = Get-DnsServerZone -ComputerName $dnsServer | ?{$_.zonename -like "*.in-addr.arpa"}
$pointerRecords = $pointerZones | %{

    Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $_.ZoneName -RRType Ptr

}

$ptrMatches = $pointerRecords | ?{$_.recordData.PtrDomainName -like $search}

$otherZones =  Get-DnsServerZone -ComputerName $dnsServer | ?{$_.zonename -notlike "*.in-addr.arpa" -and $_.ZoneName -notlike "_msdcs.ad.example.com"}

$otherRecords =
$otherZones | %{
    Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $_.ZoneName -RRType A
    Get-DnsServerResourceRecord -ComputerName $dnsServer -ZoneName $_.ZoneName -RRType CName
}

$otherMatches = $otherRecords | ?{$_.HostName -like $search}

Write-Host "PTR Records: "
$ptrMatches | %{$_}
Write-Host "Other Records: "
$otherMatches | %{$_}


<#

PS C:\Windows\system32> $ptr.RecordData | select *


PtrDomainName         : hqwinlt01825.ad.example.com.
PSComputerName        : 
CimClass              : root/Microsoft/Windows/DNS:DnsServerResourceRecordPtr
CimInstanceProperties : {PtrDomainName}
CimSystemProperties   : Microsoft.Management.Infrastructure.CimSystemProperties




PS C:\Windows\system32> $ptr.DistinguishedName
DC=164.10,DC=100.10.in-addr.arpa,cn=MicrosoftDNS,DC=DomainDnsZones,DC=ad,DC=example,DC=com

PS C:\Windows\system32> Resolve-DnsName <dns-server-ip>

Name                           Type   TTL   Section    NameHost                                                                                                                               
----                           ----   ---   -------    --------                                                                                                                               
<reverse-zone-ip>.in-addr.arpa     PTR    1200  Answer     hqwinlt01825.ad.example.com                                                                                                            



PS C:\Windows\system32> $ptr.DistinguishedName.Split(".")
DC=164
10,DC=100
10
in-addr
arpa,cn=MicrosoftDNS,DC=DomainDnsZones,DC=ad,DC=example,DC=com

#>
