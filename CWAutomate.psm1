$CwaUrl = $null
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

    return $Script:CwaUrl
}

function Remove-CwaUrl {
    [CmdletBinding()]
    Param (
    )

    $Script:CwaUrl = $null
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

        # If credentials haven't already been manually specified, prompt now.
        if( $null -eq $Script:CwaCredential ){
            Get-CwaCredential
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
#endregion *-CwaSession

#region *-CwaClient
function Get-CwaClient {
    [CmdletBinding()]
    Param (
        [parameter(Mandatory=$false)]
        [String]
        $Name = ''
    )

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
        ParameterSetName="ComputerId")]
        [Int]
        $ComputerId,


        [parameter(Mandatory=$true,
        ParameterSetName="ComputerName")]
        [String]
        $ComputerName,

        [parameter(Mandatory=$false,
        ParameterSetName="ComputerName")]
        [String]
        $ClientName = '',

        [parameter(Mandatory=$true,
        ValueFromPipeline=$true,
        ParameterSetName="ComputerObject")]
        $ComputerObject
    )

    Process {
        # If Get-CwaComputer was piped through the pipeline, use that information.
        if( $ComputerObject.Count -ne 0 ){
            Write-Verbose "Using computer object"
            $ComputerId = $ComputerObject.Id
        }

        # If the computer name (and optionally client name) was passed, get a computer ID from it.
        if( [bool]($MyInvocation.BoundParameters.Keys -match 'ComputerName') ) {
            if( [bool]($MyInvocation.BoundParameters.Keys -match 'ClientName') ) {
                $ComputerId = Get-CwaComputer -ComputerName $ComputerName -ClientName $ClientName
            } else {
                $ComputerId = Get-CwaComputer -ComputerName $ComputerName
            }
        }

        # TODO: If using set ComputerName, get $computerID via Get-CwaComputer
        # TODO: Allow passing CwaComputer "objects" via pipeline
        $screenconnectPage = "$($Script:CwaUrl)/cwa/api/v1/extensionactions/control/$computerID"
        $headers = @{
            "Accept"="application/json, text/plain, */*"
            "Authorization"="bearer $($script:CwaApiToken.AccessToken)"
        }
        $requestResult = Invoke-WebRequest -Method GET -Body ($payload | ConvertTo-Json -Compress) -Uri $screenconnectPage -Headers $headers
        $screenconnectUrl = ($requestResult.content) -replace '"',''
        start "$screenconnectUrl"
    }
}
#endregion *-CwaScreenconnect
