$CwaHost = $null
$CwaApiToken = $null
$CwaCredential = $null


#region *-CwaHost
function Set-CwaHost ( [String] $host ) {
    if( -not ( $host.ToString().Contains('.') ) ) {
        Write-Verbose "Host does not seem to be a FQDN. Appending .hostedrmm.com"
        $host = "$host.hostedrmm.com"
    }
    # Auto-prepend https:// if there is no http:// or https:// at the beginning of the hostname.
    if( -not ($host.ToString().ToLower().StartsWith( "http://" ) -or $host.ToString().ToLower().StartsWith( "https://" ) ) ) {
        Write-Verbose "No http:// or https:// prefix, defaulting to https://"
        $host = "https://$host"
    }
    Write-Verbose "Setting `$CwaHost to '$host'"
    $Script:CwaHost = $host
    Write-Verbose "`$CwaHost = '$($Script:CwaHost)'"
}

function Get-CwaHost () {
    Write-Verbose "`$CwaHost = '$($Script:CwaHost)'"
    return $Script:CwaHost
}
#endregion *-CwaHost

#region *-CwaCredential
function Set-CwaCredential ($credential) {
    $Script:CwaCredential = $credential
}

function Get-CwaCredential () {
    return $Script:CwaCredential.UserName
}
#endregion *-CwaCredential

#region *-CwaServer
function Connect-CwaServer (){
    $plaintextPassword = $Script:CwaCredential.GetnetworkCredential().Password
    Write-Verbose "Using credentials for: '$($Script:CwaCredential.UserName)'"
Write-Verbose "Using password: '$plaintextPassword'"
    $loginPage= "$($Script:CwaHost)/cwa/api/v1/apitoken"
    Write-Verbose "Using login page '$loginPage'"
    $headers = @{
        'Accept'='application/json, text/plain, */*'
    }
    $payload = @{
        UserName=$($Script:CwaCredential.UserName)
        Password=$plaintextPassword
        TwoFactorPasscode=''
    }
    $requestResult = Invoke-RestMethod -Uri $loginPage -Method POST -Headers $headers -Body ($payload | ConvertTo-Json -Compress) -WebSession $Script:CwaWebRequestSession -ContentType "application/json;charset=UTF-8"
    # TODO: Add error checking on return value    
    $script:CwaApiToken = $requestResult
}
function Disconnect-CwaServer(){
    $script:CwaApiToken = $null
}
#endregion *-CwaServer

#region *-CwaClient
function Get-CwaClient( $clientName = '' ){
    $clientsListPage = "$($Script:CwaHost)/cwa/api/v1/clients?pageSize=-1&includeFields='Name'&orderBy=Name asc"
    if( '' -ne $clientName ) {
        $encodedClientName = [uri]::EscapeDataString( $clientName )
        $clientsListPage = "$clientsListPage&condition=Name%20contains%20%27$encodedClientName%27"
    }
    $headers = @{
        "Accept"="application/json, text/plain, */*"
        "Authorization"="bearer $($script:CwaApiToken.AccessToken)"
    }
    $requestResult = Invoke-WebRequest -Method GET -Body ($payload | ConvertTo-Json -Compress) -Uri $clientsListPage -Headers $headers
    $clients = $requestResult | ConvertFrom-Json
    # TODO: Verify valid JSON is returned
    return $clients
}
#endregion *-CwaClient

#region *-CwaComputer
function Get-CwaComputer ( $computerName, $clientName = '' ) {
    $conditionString = "ComputerName contains '$computerName'"
    if ( '' -ne $clientName ) {
        $clientInfo = Get-CwaClient( $clientName );
        $conditionString = "$conditionString and Client.Id = $($clientInfo.Id)"
    }
    $conditionString = [uri]::EscapeDataString( $conditionString )
    $computersPage = "$($Script:CwaHost)/cwa/api/v1/computers?pageSize=20&page=1&condition=$conditionString&orderBy=computerName%20asc"
    $headers = @{
        "Accept"="application/json, text/plain, */*"
        "Authorization"="bearer $($script:CwaApiToken.AccessToken)"
    }
    $requestResult = Invoke-WebRequest -Method GET -Body ($payload | ConvertTo-Json -Compress) -Uri $computersPage -Headers $headers
    $computers = $requestResult | ConvertFrom-Json
    # TODO: Verify valid JSON is returned
    return $computers
}
#endregion

#region *-CwaScreenconnect
function Start-CwaScreenconnect( $computerID ){
    $screenconnectPage = "$($Script:CwaHost)/cwa/api/v1/extensionactions/control/$computerID"
    $headers = @{
        "Accept"="application/json, text/plain, */*"
        "Authorization"="bearer $($script:CwaApiToken.AccessToken)"
    }
    $requestResult = Invoke-WebRequest -Method GET -Body ($payload | ConvertTo-Json -Compress) -Uri $screenconnectPage -Headers $headers
    $requestResult | gm
    $screenconnectUrl = ($requestResult.content) -replace '"',''
    start "$screenconnectUrl"
#    $requestResult = Invoke-WebRequest -Method GET -Body ($payload | ConvertTo-Json -Compress) -Uri $screenconnectPage -Headers $headers
}
#endregion *-CwaScreenconnect
