<#
10.09.2020
Written by Mathew Dekker
To Do:  turn into function, import data from failed logon report to include source IP information
        possibly change the format of the body of the email to present it more concisely and add data as csv attachment to email
#>

#set initial variables for email recipients
    $bccRecipients = "mathew.dekker@example.com"
    $ccRecipients = "Fiorela.Salazar@example.COM","ali@phobos.io","gary@phobos.io"
    $noEmailAddressRecipient = "mathew.dekker@example.com"
    $contactemail = "mathew.dekker@example.com"
    $failedLogonDL = "Group_Failed_Logons_Notification@example.com"
    $date = Get-Date

    #set location of failed logon file
    $failedLogFile = Read-Host "Please Enter Full Path To Failed Logons File: "
    if(!(Test-Path $failedLogFile)){Write-Host "Invalid Path!"; return}
    #initialize the wildcard criteria for Domain Controllers to be queried
    $domainControllers = Get-ADComputer -Filter {enabled -eq $true -and name -like "*DC0*"} | select name

#prompt user to enter the account names to be queried (this may be automated as well - set to pull top x numbers from csv etc...)
$user = Read-Host - "Enter User Name(s) of top offenders (Seperated by Comma):"

#email body to be sent to Failed Logon DL
    $body2  = "Hi All, <br>"
	$body2 += "This is an Automated Notification for the failed logons this week: $date <br><br>"		
	$body2 += "Below you will see the Active Directory information for the top offending accounts on each Domain Controller <br>"
    $body2 += "Feel free to reach out to mathew.dekker@example.com with any questions. Thank you. <br>"
    $body2 += "<br><br>"

#get active directory information for user to be used in outgoing email
$user.Split(",") | %{
    $userName = $_
    $userInfo = try{Get-ADUser $userName  -Properties * | select name,givenName,SurName,UserPrincipalName,emailAddress -ErrorAction SilentlyContinue}finally{$userInfo = $null}
    $userMailInfo = $userInfo

#if this is an admin account, pull user data from their regular account
    if($userInfo.name -like "*-a*"){
        $dashA = $userName.Replace("-a","")
        $userMailInfo = try{Get-ADUser $dashA  -Properties * | select name,givenName,SurName,UserPrincipalName,emailAddress -ErrorAction SilentlyContinue}finally{$userInfo = $null}
    }
#attempt to pull user's email address, if address is not found - email $noEmailAddressRecipient
#this section can use additional email verification - if service accounts are updated with contact email addresses in comment section, that could be pulled in the future to contact the proper team for service accounts
    if($userMailInfo){
        if($userMailInfo.emailAddress){$email = $userMailInfo.emailAddress} 
        else{$email = $userMailInfo.userPrncipalName}           
        
        if($userMailInfo.givenName -or $userMailInfo.surName){$fullName = $userMailInfo.givenName + " " + $userMailInfo.surName}
        else{$fullName = $userName}
    }
    else{
        $email = $noEmailAddressRecipient
        $fullName = "No User Email"
    }
    
#set up body of email to be sent to end user
    $body  = "Hi $fullName, <br>"
	$body += "This is an Automated Notification informing you that the below account has had a very large number of failed logons this week.  <br><br>"		
	$body += "If you have recently changed your password, please contact the service desk and/or be sure to update your password in all locations where it may be saved (laptops, servers, phones, applications etc...). <br>"
    $body += "Below is information regarding your account status on all of the Domain Controllers (This information may be helpful for the service desk to assist you with any account/lockout issues) <br>"
    $body += "Feel free to reach out to $contactEmail with any questions. <br>"
    $body += "<br><br>"    
   
#html formatting can use additionl work
    $domainControllers.name | %{
       $body += "`r`n"
       $body += Write-Output "<span style='font-family:Ariel;font-size:14pt;font-style:bold;font-weight: 900;'>Domain Controller: $_  `r`n</span>" 
       $body += Write-Output "<span style='font-family:Ariel;font-size:14pt;font-style:bold;font-weight: 900;'>Account Name: $userName `r`n</span>"
       #$body += Write-Output "`r`n"

       $body2 += "`r`n"
       $body2 += Write-Output "<span style='font-family:Ariel;font-size:14pt;font-style:bold;font-weight: 900;font-weight: 900;'>Domain Controller: $_ `r`n</span>"
       $body2 += Write-Output "<span style='font-family:Ariel;font-size:14pt;font-style:bold;font-weight: 900;'>Account Name: $userName `r`n</span>"
       #$body2 += Write-Output "`r`n"

#query each domain controller for pertinent user account information
       $info = try{Get-ADUser -Server $_ -Identity $userName  -Properties * | select PasswordLastSet,LastLogonDate,LastBadPasswordAttempt,badPwdCount,Enabled,LockedOut,PasswordExpired -ErrorAction SilentlyContinue}catch{}
       
       if($info){
        $body += $info | ConvertTo-Html -As List
        $body2 += $info | ConvertTo-Html -As List

       }
       else{
        $body += "<br>"
        $body += Write-Output "Unable to query this DC `r`n"
        $body2 += Write-Output "Unable to query this DC `r`n"
       }
    }

#send mail to end user containing only their AD infotmation
    Send-MailMessage -To "$email" -From "FailedLogonNotification@example.com" -Bcc $bccRecipients `
	-Subject "Failed Logon Notice" -SmtpServer "smtp-san.ad.example.com" -Body $body -BodyAsHtml
  
}
#send email to failed logon DL
    Send-MailMessage -To "$failedLogonDL" -Cc $ccRecipients -From "FailedLogonNotification@example.com" -Bcc $bccRecipients `
	-Subject "Failed Logon Notice" -Attachments $failedLogFile -SmtpServer "smtp-san.ad.example.com" -Body $body2 -BodyAsHtml

#end script
