﻿$CwaUrl = $null
$CwaApiToken = $null
$CwaCredential = $null


#region *-CwaUrl
function Set-CwaUrl {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true)]
        [String]
        $Url = $null
    )

    # If the URL is not a FQDN, append the standard TLD.
    if( -not ( $Url.ToString().Contains('.') ) ) {
        Write-Verbose "URL does not seem to be a FQDN. Appending .hostedrmm.com"
        $Url = "$Url.hostedrmm.com"
    }

    # Auto-prepend https:// if there is no http:// or https:// at the beginning of the hostname.
    if( -not ($Url.ToString().ToLower().StartsWith( "http://" ) -or $Url.ToString().ToLower().StartsWith( "https://" ) ) ) {
        Write-Verbose "No http:// or https:// prefix, defaulting to https://"
        $Url = "https://$Url"
    }

    # Store the URL for later use.
    Write-Verbose "Setting `$CwaUrl to '$Url'"
    $Script:CwaUrl = $Url
    Write-Verbose "`$CwaHost = '$($Script:CwaUrl)'"
}

function Get-CwaUrl {
    [CmdletBinding()]
    Param (
    )

    if( $null -eq $Script:CwaUrl ){
        Load-CwaUrl
    }

    return $Script:CwaUrl
}

function Remove-CwaUrl {
    [CmdletBinding()]
    Param (
    )

    $Script:CwaUrl = $null
}

function Save-CwaUrl {
    [CmdletBinding()]
    Param (
        [String]
        $Path = "$env:USERPROFILE/.CwaUrl.txt"
    )

    $Script:CwaUrl | Out-File -FilePath $Path -NoNewline
}

function Load-CwaUrl {
    [CmdletBinding()]
    Param (
        [String]
        $Path = "$env:USERPROFILE/.CwaUrl.txt"
    )

    if( Test-Path -Path $Path ){
        $Script:Cwaurl = Get-Content -Path $Path -Raw
    }
}
#endregion *-CwaUrl

#region *-CwaCredential
function Set-CwaCredential {
    [CmdletBinding()]
    Param (
        [parameter(Mandatory=$true,ValueFromPipelineByPropertyName,ValueFromPipeline)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty  
    )

    # Store credential for later use.
    Write-Verbose "Credential username = '$($Credential.UserName)'"
    $Script:CwaCredential = $credential
}

function Get-CwaCredential {
    [CmdletBinding()]
    Param (
    )

    $Script:CwaCredential.UserName
}

function Remove-CwaCredential {
    [CmdletBinding()]
    Param (
    )

    $Script:CwaCredential = $null
}

function Save-CwaCredential {
    [CmdletBinding()]
    Param (
        [String]
        $Path = "$env:USERPROFILE/.CwaCredential.xml"
    )

    $Script:CwaCredential | Export-CliXml -Path $path
}

function Load-CwaCredential {
    [CmdletBinding()]
    Param (
        [String]
        $Path = "$env:USERPROFILE/.CwaCredential.xml"
    )

    if( Test-Path -Path $Path ){
        $Script:CwaCredential = Import-CliXml -Path $Path
    }
}



#endregion *-CwaCredential

#region *-CwaSession
function Start-CwaSession {
    [CmdletBinding()]
    Param (
        [parameter(Mandatory=$false)]
        [String]
        $Url = '',

        [parameter(Mandatory=$false,ValueFromPipelineByPropertyName,ValueFromPipeline)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty  
    )

    Process {
        # If a URL was passed, save it for later use.
        if( '' -ne $Url ){
            Set-CwaUrl $Url
        }

        # If credentials were passed, store them for later use.
        if( $Credential -ne [System.Management.Automation.PSCredential]::Empty ) {
            Set-CwaCredential $Credential
        }

        # If credentials haven't already been manually specified, attempt to load them.
        if( $null -eq $Script:CwaCredential ){
            Load-CwaCredential
        }

        # If credentials haven't already been manually specified, prompt now.
        if( $null -eq $Script:CwaCredential ){
            Get-CwaCredential
        }

        if( $null -eq $Script:CwaUrl ){
            Load-CwaUrl
        }
        # Connect to the URL, and attempt to create a session (get a session/API token).
        $plaintextPassword = $Script:CwaCredential.GetnetworkCredential().Password
        Write-Verbose "Using credentials for: '$($Script:CwaCredential.UserName)'"
        $loginPage= "$($Script:CwaUrl)/cwa/api/v1/apitoken"
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
}

function Stop-CwaSession(){
    # TODO: Would it be worth figuring out how to invalidate the API token?
    $script:CwaApiToken = $null
}

function Test-CwaSession(){
    [CmdletBinding()]
    Param (
    )

    $UserProfilesPage = "$($Script:CwaUrl)/cwa/api/v1/userprofiles"
    $headers = @{
        "Accept"="application/json, text/plain, */*"
        "Authorization"="bearer $($script:CwaApiToken.AccessToken)"
    }

    try{
        $requestResult = Invoke-WebRequest -Method GET -Uri $UserProfilesPage -Headers $headers
        return $true
    }
    catch{
        return $false
    }
}
#endregion *-CwaSession

#region *-CwaClient
function Get-CwaClient {
    [CmdletBinding()]
    Param (
        [parameter(Mandatory=$false)]
        [String]
        $Name = ''
    )

    if( -not ( Test-CwaSession ) ){ Start-CwaSession }

    $clientsListPage = "$($Script:CwaUrl)/cwa/api/v1/clients?pageSize=-1&includeFields='Name'&orderBy=Name asc"
    if( '' -ne $Name ) {
        $encodedClientName = [uri]::EscapeDataString( $Name )
        $clientsListPage = "$clientsListPage&condition=Name%20contains%20%27$encodedClientName%27"
    }
    $headers = @{
        "Accept"="application/json, text/plain, */*"
        "Authorization"="bearer $($script:CwaApiToken.AccessToken)"
    }
    $requestResult = Invoke-WebRequest -Method GET -Body ($payload | ConvertTo-Json -Compress) -Uri $clientsListPage -Headers $headers
    $clients = $requestResult | ConvertFrom-Json
    # TODO: Verify valid JSON is returned
    $clients
}

#endregion *-CwaClient

#region *-CwaLocation
function Get-CwaLocation {
    [CmdletBinding()]
    Param (
        [parameter(Mandatory=$false)]
        [String]
        $Name = ''
    )

    if( -not ( Test-CwaSession ) ){ Start-CwaSession }

    $clientsListPage = "$($Script:CwaUrl)/cwa/api/v1/locations?pageSize=-1&includeFields=Name&orderBy=Name asc"
<#
    if( '' -ne $Name ) {
        $encodedClientName = [uri]::EscapeDataString( $Name )
        $clientsListPage = "$clientsListPage&condition=Name%20contains%20%27$encodedClientName%27"
    }
#>
    $headers = @{
        "Accept"="application/json, text/plain, */*"
        "Authorization"="bearer $($script:CwaApiToken.AccessToken)"
    }
    $requestResult = Invoke-WebRequest -Method GET -Body ($payload | ConvertTo-Json -Compress) -Uri $clientsListPage -Headers $headers
    $locations = $requestResult | ConvertFrom-Json
    # TODO: Verify valid JSON is returned
    $locations
}

#endregion *-CwaLocation

#region *-CwaComputer
function Get-CwaComputer {
    [CmdletBinding()]
    Param (
        [parameter(Mandatory=$false)]
        [String]
        $ComputerName = '',

        [parameter(Mandatory=$false)]
        [String]
        $ClientName = '',

        [parameter(Mandatory=$false,
        ValueFromPipeline=$true)]
        $ClientObject,

        [parameter(Mandatory=$false)]
        [Int]
        $PageSize = 20,

        [parameter(Mandatory=$false)]
        [Int]
        $Page = 1
    )

    Process {
        if( -not ( Test-CwaSession ) ){ Start-CwaSession }

        $conditionString = "ComputerName contains '$ComputerName'"

        # If a CwaClient "object" was passed, use the information from that to filter computers.
        $clientInfo = $null
        if( $ClientObject.Count -ne 0 ){
            Write-Verbose "Using client info from pipeline: $($ClientObject.Name)($($ClientObject.Id))"
            $ClientName = $ClientObject.Name
            $clientInfo = $ClientObject
        }

        # If client information was passed along, use that information to filter computers.
        if ( '' -ne $ClientName ) {
            if( $null -eq $clientInfo ) {
                $clientInfo = Get-CwaClient( $ClientName )
            }
            Write-Verbose "Client Name: $($clientInfo.Name)"
            Write-Verbose "Client ID: $($clientInfo.Id)"
            $conditionString = "$conditionString and Client.Id = $($clientInfo.Id)"
        }
        $conditionString = [uri]::EscapeDataString( $conditionString )
        $computersPage = "$($Script:CwaUrl)/cwa/api/v1/computers?pageSize=$PageSize&page=$Page&condition=$conditionString&orderBy=computerName%20asc"
        $headers = @{
            "Accept"="application/json, text/plain, */*"
            "Authorization"="bearer $($script:CwaApiToken.AccessToken)"
        }
        $requestResult = Invoke-WebRequest -Method GET -Body ($payload | ConvertTo-Json -Compress) -Uri $computersPage -Headers $headers
        $computers = $requestResult | ConvertFrom-Json
        # TODO: Verify valid JSON is returned
        $computers
    }
}
#endregion

#region *-CwaScreenconnect
function Start-CwaScreenconnect {
    [CmdletBinding()]
    Param (
        [parameter(Mandatory=$true,
        Position=0,
        ParameterSetName="ComputerId")]
        [Int]
        $ComputerId,

        [parameter(Mandatory=$true,
        Position=0,
        ParameterSetName="ComputerName")]
        [String]
        $ComputerName,

        [parameter(Mandatory=$false,
        Position=1,
        ParameterSetName="ComputerName")]
        [String]
        $ClientName = '',

        [parameter(Mandatory=$true,
        ValueFromPipeline=$true,
        ParameterSetName="ComputerObject")]
        $ComputerObject
    )

    Process {
        if( -not ( Test-CwaSession ) ){ Start-CwaSession }

        # If Get-CwaComputer was piped through the pipeline, use that information.
        if( $ComputerObject.Count -ne 0 ){
            Write-Verbose "Using computer object"
            $ComputerId = $ComputerObject.Id
        }

        #TODO: Add a better way to handle if multiple computers match the name... An extra parameter or two, asking how to act when multiple matches are found? Default to out-gridview?
        # If the computer name (and optionally client name) was passed, get a computer ID from it.
        if( [bool]($MyInvocation.BoundParameters.Keys -match 'ComputerName') ) {
            if( [bool]($MyInvocation.BoundParameters.Keys -match 'ClientName') ) {
                $Computers = Get-CwaComputer -ComputerName $ComputerName -ClientName $ClientName
            } else {
                $Computers = Get-CwaComputer -ComputerName $ComputerName
            }
            if( 0 -eq $Computers.Count ){
                return # No matches found by filter.
            }
            if( 1 -lt $Computers.Count ){
                $Computers | Out-GridView -Title "Select computers to connect to" -OutputMode Multiple | Start-CwaScreenconnect
                return # We will simply loop through all of them individually, for now...
            }
            $ComputerId = $Computers.Id
        }

        $screenconnectPage = "$($Script:CwaUrl)/cwa/api/v1/extensionactions/control/$computerID"
        $headers = @{
            "Accept"="application/json, text/plain, */*"
            "Authorization"="bearer $($script:CwaApiToken.AccessToken)"
        }
        $requestResult = Invoke-WebRequest -Method GET -Body ($payload | ConvertTo-Json -Compress) -Uri $screenconnectPage -Headers $headers
        if( $null -eq $requestResult ){
            Write-Error "Unable to retrieve ScreenConnect URL. Try again or restart your session (start-cwasession)."
        }
        $screenconnectUrl = ($requestResult.content) -replace '"',''
        start "$screenconnectUrl"
    }
}
#endregion *-CwaScreenconnect
