function Connect-CCHudu {
    [CmdletBinding()]
    param(
        [string]$BaseURL = $env:HUDU_BASE_URL
    )

    if (-not $BaseURL) {
        throw "Hudu base URL not provided. Set the HUDU_BASE_URL environment variable or pass -BaseURL."
    }

    $apiKey = Get-Secret -Name "Hudu" -AsPlainText
    New-HuduAPIKey -ApiKey $apiKey
    New-HuduBaseURL -BaseURL $BaseURL
    Write-Verbose "Connected to Hudu."
}
