

<# 
    Written by Mathew Dekker
    05.14.2022
    Creates new groups in AD for new Tableau projects
    Uncomment below function to run the script in ISE or VSCode
#>

<#

This module has all the helper functions:
Get-Command -Module Example-AD-Module

CommandType     Name                                               Version    Source
-----------     ----                                               -------    ------
Function        Get-AdminCreds                                     0.0.1      Example-AD-Module
Function        Get-ADUserOpen                                     0.0.1      Example-AD-Module
Function        Get-ARecordsWildCard                               0.0.1      Example-AD-Module
Function        Get-NestedGroups                                   0.0.1      Example-AD-Module
Function        Set-LogFile                                        0.0.1      Example-AD-Module
#>


Import-Module Example-AD-Module

function New-TableauProject
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        #array of users with publish access
        [string[]]
        $publishUsers,
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        #array of users with read-only access
        [string[]]
        $readOnlyUsers,
        [Parameter(Mandatory = $true)]
        #[string] Project Name
        [string]
        $projectName,
        [Parameter(Mandatory = $true)]
        [bool]
        $restrictedData,
        #[bool] True if data is restricted
        [Parameter(Mandatory = $false)]
        [string]
        $emailAddress,
        #[string] emailAddress to send a confirmation email to (currently not in use)
        [Parameter(Mandatory = $false)]
        #[System.Management.Automation.PSCredential] Credentials to pass to the other functions if desired
        [System.Management.Automation.PSCredential]
        $credentialPass
    )
    <#
  .SYNOPSIS
   Creates needed Tableau AD security groups for new Tableau projects and adds the appropriate users to the appropriate groups
  .DESCRIPTION
    Creates needed Tableau AD security groups for new Tableau projects and adds the appropriate users to the appropriate groups
  .INPUTS
    can pipe in [string[]] of publish user accounts or read-only user accounts
  .OUTPUTS
    [Deserialized.Microsoft.ActiveDirectory.Management.ADUser]
  .EXAMPLE
    New-TableauProject -publishUsers "Mathew Dekker" -readOnlyUsers "John Smith" -projectName "Example Project" -restrictedData $true -credentialPass Get-Credential
    
    $pUsers = @("e72999","devin.roth@example.com","Josh Shea")
    #read users to be placed in read only group
    $roUsers = @()
    #basic parameters:
    $someParams = @{
        projectName = "Test Project4Script"
        restrictedData = $true
        credentialPass = Get-Credential
    }
    if(!$roUsers -and $pUsers){
    New-TableauProject @someParams -publishUsers $pUsers
    }
    if(!$roUsers -and !$pUsers){
        New-TableauProject @someParams
    }
    if($roUsers -and $pUsers){
        New-TableauProject @someParams -publishUsers $pUsers -readOnlyUsers $roUsers
    }
    if($roUsers -and $pUsers){
        New-TableauProject @someParams -publishUsers $pUsers
    }
#>
    
    

if(!$credentialPass){$credentials = Get-AdminCreds}
else{$credentials = Get-AdminCreds -Credential $credentialPass}
$groupNamePublish = "RG-Tableau-" + $projectName + "-Publish-R"
$groupNameRead = "RG-Tableau-" + $projectName + "-Read"
$groupScope = "Global"
$groupCategory = "Security"
$ou = "OU=Tableau,OU=Resource Groups,OU=Groups,DC=ad,DC=example,DC=com"
$description = "Tableau Project Permissions" 
#$notes = "Here we can enter notes such as primary/secondary contact, ticket number etc..."
#if we want to send emails upon completion to the primary/secondary approvers or person that requested project
<#
$body = "Hi $enterName, <br>"
	$body += "This is an Automated Notification that your Tableau Project $projectName has been generated. <br><br>"		
	$body += "Please feel free to contact the service desk with any questions.<br>"
    
#>
    #add publish group and users
    Write-Host "Creating: " $groupNamePublish
    Write-Host "In OU: $ou"
    New-ADGroup -Name $groupNamePublish -GroupScope $groupScope -GroupCategory $groupCategory -Description $description -Path $ou -Credential $credentials
    #Set-ADGroup -Identity $groupNamePublish -Replace @{Notes=$notes}
    Start-Sleep -Seconds 5
    Write-Host "Creating Group: " $groupNamePublish
    try{Get-ADGroup $groupNamePublish -Properties * -Credential $credentials | Select-Object distinguishedName,members}catch{}
    
    if($publishUsers.Count -gt 0){
    Write-Host "Adding the following users to the Publish Group: "
    $publishUsers | ForEach-Object{
        $member = try{Get-AduserOpen $_}catch{}
        if(!$member){break}
        Read-Host "Do you want to add the following user?"
        
        Write-Host "...Adding " $member.name -BackgroundColor Green -ForegroundColor White
        try{Add-ADGroupMember -Identity $groupNamePublish -Members $member.distinguishedName -Credential $credentials}catch{}
    }
    $group = try{Get-ADGroup $groupNamePublish -Properties * -Credential $credentials -Properties * | Select-Object distinguishedName,members}catch{}
    $group
    }

    #add read group and users
    Write-Host "Creating: " $groupNameRead
    Write-Host "In OU: $ou"
    New-ADGroup -Name $groupNameRead -GroupScope $groupScope -GroupCategory $groupCategory -Description $description -Path $ou -Credential $credentials
    #Set-ADGroup -Identity $groupNameRead -Replace @{Notes=$notes}
    Start-Sleep -Seconds 5
    Write-Host "Group Created: "
    $group = try{Get-ADGroup $groupNameRead -Properties * -Credential $credentials -Properties * | Select-Object distinguishedName,members}catch{}
    $group
    if($readOnlyUsers.Count -gt 0){
    Write-Host "Adding the following users to the Publish Group: "
    $readOnlyUsers | ForEach-Object{
        $member = try{Get-AduserOpen $_}catch{}
        if(!$member){break}
        Write-Host "...Adding " $member -BackgroundColor Green -ForegroundColor White
        try{Add-ADGroupMember -Identity $groupNameRead -Members $member.distinguishedName -Credential $credentials}catch{}
    }
    $group = try{Get-ADGroup $groupNamePublish -Properties * -Credential $credentials -Properties * | Select-Object distinguishedName,members}catch{}
    $group
    }
    #send email
    <#
    Send-MailMessage -To $emailAddress -From "TableauProjectCreation@example.com" `
	-Subject "Tableau Project Created" -SmtpServer "sp-gcp-smtp-01" -Body ($body | Out-String) -BodyAsHtml
    #>
}

#Uncomment the below to run the script 
<#
#publish users to be placed in publish group
$pUsers = @("e72999","devin.roth@example.com","Josh Shea")

#read users to be placed in read only group
$roUsers = @()

#basic parameters:
    $someParams = @{
        projectName = "Test Project4Script"
        restrictedData = $true
        credentialPass = Get-Credential
    }
    if(!$roUsers -and $pUsers){
    New-TableauProject @someParams -publishUsers $pUsers
    }
    if(!$roUsers -and !$pUsers){
        New-TableauProject @someParams
    }
    if($roUsers -and $pUsers){
        New-TableauProject @someParams -publishUsers $pUsers -readOnlyUsers $roUsers
    }
    if($roUsers -and $pUsers){
        New-TableauProject @someParams -publishUsers $pUsers
    }
#>
