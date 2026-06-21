$nameservers = (Get-DnsServerResourceRecord -RRType Ns -ComputerName phxiodc01 -ZoneName example.com).recorddata

$nameservers | %{
    $nameserver = $_.NameServer

    Get-DnsServerScavenging -ComputerName $nameserver | %{
        $ScavengingState = $_.ScavengingState
        $NoRefreshInterval = $_.NoRefreshInterval
        $RefreshInterval = $_.RefreshInterval
        $ScavengingInterval = $_.ScavengingInterval
        $LastScavengeTime = $_.LastScavengeTime
    }

    New-Object -TypeName psobject -Property @{
             NameServer = $NameServer
             ScavengingState = $ScavengingState
             NoRefreshInterval = $NoRefreshInterval
             RefreshInterval = $RefreshInterval
             ScavengingInterval = $ScavengingInterval
             LastScavengeTime = $LastScavengeTime

           } | select NameServer,ScavengingState,NoRefreshInterval,RefreshInterval,ScavengingInterval,LastScavengeTime
} | export-csv -Path C:\Users\mdekker\Documents\DHCPnDNSinfo\dnsScavengingNS.csv