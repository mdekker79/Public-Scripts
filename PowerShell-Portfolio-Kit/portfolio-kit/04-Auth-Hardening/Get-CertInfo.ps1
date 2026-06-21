$certs = gci -Recurse cert:\localmachine | ?{($_.gettype()).Name -like "*certificate*"}

$certs.dnsnamelist.punycode
$certs.subject