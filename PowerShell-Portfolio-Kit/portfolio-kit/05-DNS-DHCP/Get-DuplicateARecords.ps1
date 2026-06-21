<#
DNS Functions
#>

function Get-DNSip2{

    [cmdletbinding()]
    param(
      [parameter(
        Mandatory = $true,
        ValueFromPipeline = $true)]
        $ipAddress,
      [parameter(
        Mandatory = $false)]
        [int]$total
      
    )
    Begin {
        #if($ipAddress -eq $null){Read-Host "Enter IP: "}
        write-host "Initiating Variables: "
        $zoneName = "ad.example.com"
        $dnsServer = "phxiodc04"
        $ptrZone = "10.in-addr.arpa"
        $PtrRecord = Get-DnsServerResourceRecord -ZoneName $ptrZone -ComputerName $dnsServer
        $Arecord = Get-DnsServerResourceRecord -ZoneName $zoneName -ComputerName $dnsServer
        $count = 0
    }

    Process {
        $count++
        foreach ($ip in $ipAddress){
            #Write-Output "DNS information for " $ip
            $ptrHostname = $ip.Split(".")[3] + "." + $ip.Split(".")[2] + "."  + $ip.Split(".")[1]
            $hostrecord = $Arecord | ?{$_.RecordData.IPv4Address -like $ip}
            $pointerRecord = $PtrRecord | ?{$_.HostName -like $ptrHostname}
            
            $percent = $count/$total*100
            Write-Host "Percent Complete: " $count/$total
            Write-Progress -Activity "Gathering Duplicate Records" -Status "Searching: % $percent" -PercentComplete $percent;
            


             New-Object -TypeName psobject -Property @{
              aRecord            = $hostrecord
              ptrRecord          = $pointerRecord
              count              = $count
              
           } | select ptrRecord,aRecord

        }
        
    }

    End{}
}

<#   Accepts Pipline String#>

function Get-DNShost2{

    [cmdletbinding()]
    param(
      [parameter(
        Mandatory = $true,
        ValueFromPipeline = $true)]
      $hostName
    )
    Begin {
        #if($ipAddress -eq $null){Read-Host "Enter IP: "}
        $zoneName = "ad.example.com"
        $dnsServer = "phxiodc01"
        $ptrZone = "10.in-addr.arpa"
        $PtrRecord = Get-DnsServerResourceRecord -ZoneName $ptrZone -ComputerName $dnsServer
        $Arecord = Get-DnsServerResourceRecord -ZoneName $zoneName -ComputerName $dnsServer
    }

    Process {

        foreach ($name in $hostName){
            if($hostName.count -eq "1"){
                $wildCard = '*' + $name + '*' }
            else{
                $wildCard = '*' + $name.name + '*' }

            #Write-Output "DNS information for " $wildCard
            $pointerRecord = $PtrRecord | ?{$_.RecordData.PtrDomainName -like $wildCard}   # | Format-Table -AutoSize
            $hostrecord = $Arecord | ?{$_.HostName -like $wildCard}   # | Format-Table -AutoSize
            #if($pointerRecord.Count -gt 0){$pointerRecord}
            #if($hostrecord.Count -gt 0){$hostrecord}
            
            New-Object -TypeName psobject -Property @{
              aRecord            = $hostrecord
              ptrRecord          = $pointerRecord
              
           } | select ptrRecord,aRecord

        }
        
    }

    End{}
}

<#
    Start Script



#>

#initial variables
<#
$zoneName = "ad.example.com"
$dnsServer = "phxiodc03"
$Arecords = Get-DnsServerResourceRecord -ZoneName $zoneName -ComputerName $dnsServer -RRType A
$ipAddresses = $Arecords.recordData.ipv4address.ipaddresstostring
#>
<#
$dhcpServers = Get-DhcpServerInDC
$dhcpServers.dnsname.replace(".ad.example.com","") | %{
    $server = $_
    $scopes = try{Get-DhcpServerv4Scope -ComputerName $server -ErrorAction SilentlyContinue | ?{$_.Name -notlike "*voice*"}}catch{}
    $leases = $scopes | %{Get-DhcpServerv4Lease -ComputerName $server -ScopeId $_.ScopeId}
}
#>

$memberServers = Get-ADComputer -SearchBase "OU=MemberServers,OU=Systems,OU=example,DC=internal,DC=example,DC=com" -Filter * -Properties *

#$ipAddressesUnique = $ipAddresses | Sort-Object | Get-Unique
$ipAddressesUnique = $memberServers.ipv4address
$total = $ipAddressesUnique.Count

#loop through  and look for duplicate records

$ipAddressesUnique | Get-DNSip2 -total $total | ?{$_.aRecord.count -gt 1} | %{
  
  $ip = $_.aRecord.recordData.ipv4Address.ipaddresstostring | Get-Unique
  $i  = $_.aRecord.count
  $ptr = $_.ptrRecord.RecordData.PtrDomainName
  if($ptr.count -gt 1){$ptr = "duplicate pointer"}

  while($i -gt 0){
    Write-Host "I; " $i
    
    $i--
    $progress = $_.count
    $hostName = $_.aRecord[$i].Hostname
    $timeStamp = $_.aRecord[$i].timestamp
    if(!($timeStamp)){$timeStamp = "Static"}

    $percent = $progress / $total * 100 
    write-Host "IP Address: " $ip
    Write-Host "Hostname: " $hostname
    Write-Host "Time To Live: " $timeStamp.ToString()
    Write-Host ""

    New-Object -TypeName psobject -Property @{
    IPAddress = $ip
    Hostname  = $hostName
    TimeStamp = $timeStamp.ToString()
    Pointer   = $ptr
    } | select IPAddress,Hostname,TimeStamp,Pointer | Export-Csv memberserversDuplicates.csv -NoClobber -NoTypeInformation -Append
    
    $hostName = $timeStamp = $null
  }  
  
}