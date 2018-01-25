function Invoke-Method {
    <#
    .SYNOPSIS
        Extracted invokation of the REST method to own function.

    .PARAMETER IncludeTotalCount
        NOTE: Not yet implemented.
        Causes an extra output of the total count at the beginning.
        Note this is actually a uInt64, but with a custom string representation.

    .PARAMETER Skip
        Controls how many things will be skipped before starting output.
        Defaults to 0.

    .PARAMETER First
        NOTE: Not yet implemented.
        Indicates how many items to return.
    #>
    [CmdletBinding( SupportsPaging )]
    # [OutputType(
    #     [PSObject],
    #     [BitbucketPS.Repository]
    # )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute( "PSAvoidUsingEmptyCatchBlock", "" )]
    param (
        # REST API to invoke
        [Parameter( Mandatory )]
        [String] # Is a [String] instead of [Uri] to support relative paths; such as "/resource"
        $Uri,

        # Name of the Server registered in $script.Configuration.Server
        [String]
        $ServerName,

        # Method of the invokation
        [Microsoft.PowerShell.Commands.WebRequestMethod]
        $Method = "GET",

        # Body of the request
        [ValidateNotNullOrEmpty()]
        [String]
        $Body,

        # Do not encode the body
        [Switch]
        $RawBody,

        # Additional headers
        [Hashtable]
        $Headers,

        # GET Parameters
        [Hashtable]
        $GetParameters = @{},

        # Type of object to which the output will be casted to
        # [ValidateSet(
        #     [BitbucketPS.Repository]
        # )]
        [System.Type]$OutputType,

        # Name of the variable in which to save the session
        [String]
        $SessionVariable,

        # Authentication credentials
        [PSCredential]
        $Credential,

        # Parameter that defines the original caller of this function
        # This is used so that errors can be thrown on the level the user called it
        # instead of showing cryptic lines of code of the guts of functions
        #
        # Please do not use this parameter unless you know what you are doing.
        $Caller = $PSCmdlet
    )

    begin {
        Write-Verbose "[$($MyInvocation.MyCommand.Name)] Function started"

        if ($ServerName) {
            $server = Get-Configuration -ServerName $ServerName -ErrorAction Stop
            if ($server.IsCloudServer) {
                $Uri = "2.0{0}" -f $Uri
            }
            else {
                $Uri = "rest/api/latest{0}" -f $Uri
            }
            [Uri]$Uri = "{0}/{1}" -f $server.Uri, $Uri
        }

        # pass input to local variable
        # this allows to use the PSBoundParameters for recursion
        $_headers = @{   # Set any default headers
            "Accept"         = "application/json"
            "Accept-Charset" = "utf-8"
        }
        $Headers.Keys.foreach( { $_headers[$_] = $Headers[$_] })
    }

    process {
        Write-DebugMessage "[$($MyInvocation.MyCommand.Name)] ParameterSetName: $($PsCmdlet.ParameterSetName)"
        Write-DebugMessage "[$($MyInvocation.MyCommand.Name)] PSBoundParameters: $($PSBoundParameters | Out-String)"

        # load DefaultParameters for Invoke-WebRequest
        # as the global PSDefaultParameterValues is not used
        $PSDefaultParameterValues = $global:PSDefaultParameterValues

        # Append GET parameters to URi
        if (($PSCmdlet.PagingParameters) -and ($PSCmdlet.PagingParameters.Skip)) {
            $GetParameters["start"] = $PSCmdlet.PagingParameters.Skip
        }
        if ($GetParameters -and ($URi -notlike "*\?*")) {
            Write-Debug "[$($MyInvocation.MyCommand.Name)] Using `$GetParameters: $($GetParameters | Out-String)"
            [Uri]$URI = "$Uri$(ConvertTo-GetParameter $GetParameters)"
            # Prevent recursive appends
            $GetParameters = @{}
        }

        # set mandatory parameters
        $splatParameters = @{
            Uri             = $Uri
            Method          = $Method
            Headers         = $_headers
            ContentType     = "application/json; charset=utf-8"
            UseBasicParsing = $true
            Credential      = $Credential
            ErrorAction     = "Stop"
            Verbose         = $false     # Overwrites verbose output
        }

        # Overwrite default `ContentType` in $splatParameters in case `Content-Type` was provided in $Headers
        if ($_headers.ContainsKey("Content-Type")) {
            $splatParameters["ContentType"] = $_headers["Content-Type"]
            $_headers.Remove("Content-Type")
            $splatParameters["Headers"] = $_headers
        }
        # Add parameter to get the Session return in variable
        if ($SessionVariable) {
            $splatParameters["SessionVariable"] = $SessionVariable
        }
        # Use saved Session in case it is available and no Credentials have been provided
        if (($server.Session) -and (-not $Credential)) {
            Write-Verbose "[$($MyInvocation.MyCommand.Name)] Using saved WebSession"
            $splatParameters["WebSession"] = $server.Session
        }

        if ($Body) {
            if ($RawBody) {
                $splatParameters["Body"] = $Body
            }
            else {
                # Encode Body to preserve special chars
                # http://stackoverflow.com/questions/15290185/invoke-webrequest-issue-with-special-characters-in-json
                $splatParameters["Body"] = [System.Text.Encoding]::UTF8.GetBytes($Body)
            }
        }

        # Invoke the API
        Write-Verbose "[$($MyInvocation.MyCommand.Name)] Invoking method $Method to URI $URi"
        Write-Verbose "[$($MyInvocation.MyCommand.Name)] Invoke-WebRequest with: $(([PSCustomObject]$splatParameters) | Out-String)"
        try {
            $webResponse = Invoke-WebRequest @splatParameters
            if ($SessionVariable) {
                Set-Variable -Name $SessionVariable -Value (Get-Variable $SessionVariable).Value -Scope 1
            }
        }
        catch {
            Write-Verbose "[$($MyInvocation.MyCommand.Name)] Failed to get an answer from the server"
            $webResponse = $_
            if ($webResponse.ErrorDetails) {
                # In PowerShellCore (v6+), the response body is available as string
                $responseBody = $webResponse.ErrorDetails.Message
            }
            else {
                $webResponse = $webResponse.Exception.Response
            }
        }

        # Test response Headers if Confluence requires a CAPTCHA
        # Test-Captcha -InputObject $webResponse
        Write-Debug "[$($MyInvocation.MyCommand.Name)] Executed WebRequest. Access `$webResponse to see details"

        if ($webResponse) {
            Write-Verbose "[$($MyInvocation.MyCommand.Name)] Status code: $($webResponse.StatusCode)"

            if ($webResponse.StatusCode.value__ -ge 400) {
                Write-Warning "Confluence returned HTTP error $($webResponse.StatusCode.value__) - $($webResponse.StatusCode)"

                if ((!($responseBody)) -and ($webResponse | Get-Member -Name "GetResponseStream")) {
                    # Retrieve body of HTTP response - this contains more useful information about exactly why the error occurred
                    $readStream = New-Object -TypeName System.IO.StreamReader -ArgumentList ($webResponse.GetResponseStream())
                    $responseBody = $readStream.ReadToEnd()
                    $readStream.Close()
                }

                Write-Verbose "[$($MyInvocation.MyCommand.Name)] Retrieved body of HTTP response for more information about the error (`$responseBody)"
                Write-Debug "[$($MyInvocation.MyCommand.Name)] Got the following error as `$responseBody"

                $errorItem = [System.Management.Automation.ErrorRecord]::new(
                    ([System.ArgumentException]"Invalid Server Response"),
                    "InvalidResponse.Status$($webResponse.StatusCode.value__)",
                    [System.Management.Automation.ErrorCategory]::InvalidResult,
                    $responseBody
                )

                try {
                    $responseObject = ConvertFrom-Json -InputObject $responseBody -ErrorAction Stop
                    if ($responseObject.message) {
                        $errorItem.ErrorDetails = $responseObject.message
                    }
                    else {
                        $errorItem.ErrorDetails = "An unknown error ocurred."
                    }

                }
                catch {
                    $errorItem.ErrorDetails = "An unknown error ocurred."
                }

                $Caller.WriteError($errorItem)
            }
            else {
                if ($webResponse.Content) {
                    try {
                        # API returned a Content: lets work with it
                        $response = ConvertFrom-Json ([Text.Encoding]::UTF8.GetString($webResponse.RawContentStream.ToArray()))

                        if ($null -ne $response.errors) {
                            Write-Verbose "[$($MyInvocation.MyCommand.Name)] An error response was received from; resolving"
                            # This could be handled nicely in an function such as:
                            # ResolveError $response -WriteError
                            Write-Error $($response.errors | Out-String)
                        }
                        else {
                            if ($PSCmdlet.PagingParameters.IncludeTotalCount) {
                                [double]$Accuracy = 0.0
                                $PSCmdlet.PagingParameters.NewTotalCount($response.size, $Accuracy)
                            }
                            # None paginated results / first page of pagination
                            $result = $response
                            if (($response) -and ($response | Get-Member -Name values)) {
                                $result = $response.values
                            }
                            if ($OutputType) {
                                # Results shall be casted to custom objects (see ValidateSet)
                                Write-Verbose "[$($MyInvocation.MyCommand.Name)] Outputting results as $($OutputType.FullName)"
                                $converter = "ConvertTo-$($OutputType.Name)"
                                Write-Output $result | & $converter
                            }
                            else {
                                Write-Output $result
                            }

                            # Detect if result is paginated
                            if (-not($response.isLastPage)) {
                                Write-Verbose "[$($MyInvocation.MyCommand.Name)] Invoking pagination"

                                # Remove Parameters that don't need propagation
                                # $script:PSDefaultParameterValues.Remove("$($MyInvocation.MyCommand.Name):GetParameters")
                                $script:PSDefaultParameterValues.Remove("$($MyInvocation.MyCommand.Name):IncludeTotalCount")

                                # Self-Invoke function for recursion
                                if ($response.nextPageStart) {
                                    Write-Debug "ahoi!"
                                    $GetParameters["start"] = $response.nextPageStart
                                }
                                $parameters = @{
                                    Uri           = $Uri
                                    Method        = $Method
                                    GetParameters = $GetParameters
                                    Credential    = $Credential
                                }
                                if ($Body) {$parameters["Body"] = $Body}
                                if ($Headers) {$parameters["Headers"] = $Headers}
                                if ($OutputType) {$parameters["OutputType"] = $OutputType}

                                Write-Verbose "NEXT PAGE: $($parameters["Uri"])"

                                Invoke-Method @parameters
                            }
                        }
                    }
                    catch {
                        throw $_
                    }
                }
                else {
                    # No content, although statusCode < 400
                    # This could be wanted behavior of the API
                    Write-Verbose "[$($MyInvocation.MyCommand.Name)] No content was returned from."
                }
            }
        }
        else {
            Write-Verbose "[$($MyInvocation.MyCommand.Name)] No Web result object was returned from. This is unusual!"
        }
    }

    end {
        Write-Verbose "[$($MyInvocation.MyCommand.Name)] Function ended"
    }
}