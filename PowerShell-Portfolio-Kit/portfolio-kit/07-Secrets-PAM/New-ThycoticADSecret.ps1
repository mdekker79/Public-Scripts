# Helper Function

function GetFieldId($template, [string]$name) {
    Return ($template.Fields | Where {$_.DisplayName -eq $name}).Id
}
function GetFolderId($name) {
    Return ($template.Fields | where {$_.DisplayName -eq $name}).Id
}

# Define the function of creating a Secret
function CreateNewSecret {

    param($accountUserName)

    # Define the proxy
    $url = "https://phxiossrv01.ad.example.com//webservices/sswebservice.asmx"
    $proxy = New-WebServiceProxy -uri $url -UseDefaultCredential -Namespace "ss"

    # Define the user credentials
    $credentials = Get-Credential
    $username = $credentials.UserName
    $password = $credentials.GetNetworkCredential().password
    #$username = "ssadmin"
    #$password = "<password>"
    $domain = "ad.example.com"

    # Get a auth token
    echo "------------------------"
    echo "----- Authenticate -----"
    echo "------------------------"

    $tokenResult = $proxy.Authenticate($username, $password, '', $domain)
    if($tokenResult.Errors.Count -gt 0)
    {
        echo "Authentication Error: " +  $tokenResult.Errors[0]
        Return
    }
    $token = $tokenResult.Token

    echo $token

    # Define the Secret Template
    $templateName = "Active Directory"
    $template = $proxy.GetSecretTemplates($token).SecretTemplates | Where {$_.Name -eq $templateName}
    if($template.id -eq $null)
    {
        echo "Error: Unable to find Secret Template " +  $templateName
        Return
    }

    # Define the secrets domain
    $domain = "ad.example.com"

    # Show that the Secret is in process of cfreation
    echo "Creating Active Directory Account: " + $domain + "\" + $accountUserName;

    # Password is set to null so will generate a new one based on settings on template
    $newPass = $credentials.GetNetworkCredential().Password
    if($newPass -eq $null)
    {
        echo "Generating New Password for account"
        $secretFieldIdForPassword = (GetFieldId $template "Password")
        $newPass = $proxy.GeneratePassword($token, $secretFieldIdForPassword).GeneratedPassword
    }

    # Define the Secret's name format ($machine and $accountUserName)
    $secretName = $accountUserName

    # Load and set values on the Secret
    $secretItemFields = ((GetFieldId $template "Domain"), (GetFieldId $template "Username"), (GetFieldId $template "Password"), (GetFieldId $template "Notes"), (GetFieldID $template "SNOW Ticket"))
    $secretItemValues=($domain,$accountUserName,$newPass,$description,$task)

    # Define the folder where the Secret is created
    $folderId = GetFolderId -name "Temporary drop for transfers ONLY";

    # Shows whether Secret was successfully created
    $addResult = $proxy.AddSecret($token, $template.Id, $secretName, $secretItemFields, $secretItemValues, $folderId)
    if($addResult.Errors.Count -gt 0)
    {
        $msg = "Add Secret Error: " +  $addResult.Errors[0]
        echo $msg
        Return
    }
    else
    {
        $msg = "Successfully added Secret: " +  $addResult.Secret.Name + " (Secret Id:" + $addResult.Secret.Id + ")"
        echo $msg
        Return
    }
}

# Define the username on the Secret and name of the Secret after $machine\
CreateNewSecret $accountName