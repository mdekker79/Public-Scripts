<# needs to be fixed do not use#>




$groupName = "SyS_njiodockerp01_Remote Desktop Users"
$groupScope = "DomainLocal"
$groupCategory = "Security"
$task = "SCTASK0467436 `n"
$ou = "OU=Security Groups,OU=Shared_Site_Accounts,OU=example,DC=internal,DC=example,DC=com"
$description = "Local access to Njiodockerp01. " 

    
    Write-Host "Creating: " $groupName
    Write-Host "In OU: $ou"
    New-ADGroup -Name $groupName -GroupScope $groupScope -GroupCategory $groupCategory -Description $description
    #Set-ADGroup -Identity $groupName -Replace @{Info=$info}
    Start-Sleep -Seconds 5
    $group = Get-ADGroup $groupName -Properties * 

    <#
    $body = "Hi $enterName, <br>"
	$body += "This is an Automated Notification that your Service Account: $groupName has been generated. <br><br>"		
	$body += "Please feel free to contact Me (Mathew.Dekker@example.com) or anyone in the MS Services team to discuss the location of this account in Thycotic and any additional security requirements.	<br>"

    Send-MailMessage -To "$emailAddress" -From "Mathew.Dekker@example.com" `
	-Subject "AD Admin Account Created" -SmtpServer "smtp-san.ad.example.com" -Body ($body | Out-String) -BodyAsHtml
    #>