<#
 .Synopsis
  Runs a ping-like command which is similar in feel and appearance to a typical ping command.

 .Description
  Runs a ping-like command which is similar in feel and appearance to a typical ping command. It can track latency issues either sequentially or by moving average as well as outages. The primary purpose is for data gathering so that one may be properly armed when contending with an ISP, but could equally be useful in collecting data on a troubled network.

 .Parameter Target
  The DNS name or IP address to ping.

 .Parameter Count
  How many times to ping Target. By default, Target will be pinged until such time as Ctrl-C is pressed. If a non-zero value is supplied, then Target will be pinged that many times.

 .Parameter BufferSize
  The size of the ping payload. Defaults to 32. Acceptale values range from 8 to 65527. Has an alias of 'l'.

 .Parameter ResolveDestination
  Switch parameter which if specified will signal that an attempt to resolve the DNS name of the target will be made. Has an alias of 'a'.

 .Parameter Timeout
  Sets the timeout value for the ping test. The test fails if a response isn't received before the timeout expires. The default is five seconds. Has an alias of 'w'.

  .Parameter LatencyThreshold
  Latency issues will be detected and recorded whenever a ping latency (ms) exceeds this value. Defaults to 0 which means no latency issue detection.

  .Parameter LatencyWindow
  The minimum number of sequential latency threshold occurences for a record to be created. Is also used to specify a moving average window size. Defaults to 5.

  .Parameter LatencyMovingAvg
  If specified, the moving average over LatencyWindow packets will be compared with the LatencyThreshold to determine applicability.

  .Parameter Timestamps
  If specified, timestamps will be displayed for each ping result. Has an alias of 'D'.

  .Parameter DontFragment
  See documentation for Test-Connection

  .Parameter IPv4
  See documentation for Test-Connection

  .Parameter IPv6
  See documentation for Test-Connection

  .Parameter MaxHops
  See documentation for Test-Connection

 .Example
   # Ping contoso.com continuously until Ctrl-C is pressed and track outages.
   Invoke-PingIt contoso.com

 .Example
   # Ping contoso.com continuously until Ctrl-C is pressed and track outages and latency issues where the latency is >= 75 for five packets in a row.
   Invoke-PingIt contoso.com -LatencyThreshold 75

 .Example
   # Ping contoso.com continuously until Ctrl-C is pressed and track outages and latency issues where the moving average over five packets is >= 75.
   Invoke-PingIt contoso.com -LatencyThreshold 75 -LatencyMovingAvg

 .Example
   # Ping contoso.com continuously until Ctrl-C is pressed and track outages and latency issues where the moving average over five packets is >= 75.
   Invoke-PingIt contoso.com -LatencyThreshold 75 -LatencyMovingAvg

 .Example
   # Ping contoso.com continuously until Ctrl-C is pressed and track outages and latency issues where the moving average over five packets is >= 75.
   Invoke-PingIt contoso.com -LatencyThreshold 75 -LatencyMovingAvg

 .Example
   # Ping contoso.com 250 times and track outages and latency issues where the moving average over 10 packets is >= 75.
   Invoke-PingIt contoso.com -LatencyThreshold 75 -LatencyMovingAvg -LatencyWindow 10 -Count 250

 .Example
   # Attempt to resolve and ping 10.0.0.1 continuously until Ctrl-C is pressed track outages.
   Invoke-PingIt 10.0.0.1 -ResolveDestination

 .Example
   # Ping contoso.com continuously showing the timestamp of each until Ctrl-C is pressed and track outages
   Invoke-PingIt contoso.com -Timestamps
#>

# so we can capture Ctrl-C
[Console]::TreatControlCAsInput = $true
$Host.UI.RawUI.FlushInputBuffer()
# [ConsoleColor]$currentForegroundColor = $Host.UI.RawUI.ForegroundColor
[char]$script:e = [char]27 # console virtual terminal ESC sequence (0x1B)



function ColorizeMinMax {
    [OutputType([string])]
    param(
        $value,
        [int]$collectionCount,
        [int]$compareIndex,
        [int]$valueIndexMax,
        [int]$valueIndexMin
    )
    # if there are only two items, then no point in distinguishing max and min values
    if ($collectionCount -lt 3) {
        return $value
    }
    $color = 0
    if ($compareIndex -eq $valueIndexMax) {
        $color = 31 #red
    }
    elseif ($compareIndex -eq $valueIndexMin) {
        $color = 33 #yellow
    }
    # $e[${color}m specifies the text color for $value
    # ${e}[0m resets the color of text back to normal
    #   we use ${e} instead of $e here because $value$e doesn't parse properly ($e and ${e} evaluate to the same value)
    $result = "$e[${color}m$value${e}[0m"
    $result
}

function CreateLatencyTracker {
    [OutputType('PingIt.LatencyTracker')]
    param (
        [Parameter(Mandatory = $true)]
        [DateTime]$start
    )
    [PSTypeName('PingIt.LatencyTracker')]$latencyRecord = [PSCustomObject]@{
        Elapsed = New-TimeSpan # empty argument list gives a timespan of 0
        End = $null
        PSTypeName = 'PingIt.LatencyTracker'
        Responses = @()
        Start = $start
    }
    $latencyRecord
}

function HandleLatency {
    [OutputType('PingIt.LatencyRecord')]
    param(
        [System.Collections.Queue]$latencyQueue,
        [int]$latencyWindow,
        [DateTime]$timestamp,
        [int]$latency
    )
    [PSTypeName('PingIt.LatencyRecord')]$latencyRecord = [PSCustomObject]@{
        PSTypeName = 'PingIt.LatencyRecord'
        Timestamp = $timestamp
        Latency = $latency
    }
    if ($latencyQueue.Count -ge $latencyWindow) {
        $latencyQueue.Dequeue() | Out-Null
    }
    $latencyQueue.Enqueue($latencyRecord) | Out-Null
    $latencyRecord
}

function EvaluateLatencyState {
    [OutputType([bool])]
    param(
        [System.Collections.Queue]$latencyQueue,
        [int]$latencyWindow,
        [int]$latencyThreshold
    )

    [bool]$result = $false
    if ($latencyWindow -le $latencyQueue.Count -and $latencyThreshold -le ($latencyQueue | Measure-Object -Property Latency -Average).Average) {
        $result = $true
    }
    $result
}


function FinalizeLatencyTracker {
    param(
        [ref]$latencyIssuesParm, # we pass the array by ref because when we add an element to it, a new array is created which we must assign to the object passed in
        [PSTypeName('PingIt.LatencyTracker')]$latencyTracker,
        [DateTime]$endingTimeStamp
    )
    $latencyTracker.End = $endingTimeStamp
    $latencyTracker.Elapsed = ($latencyTracker.End - $latencyTracker.Start)
    $latencyIssuesParm.Value += $latencyTracker
}


function CreateErrorRecord {
    [OutputType('PingIt.ErrorRecord')]
    [PSTypeName('PingIt.ErrorRecord')]$errorRecord = [PSCustomObject]@{
        DestinationHostUnreachableCount = 0
        DestinationNetworkUnreachableCount = 0
        DestinationUnreachableCount = 0
        Elapsed = $null
        End = $null
        NoResponseCount = 0
        PacketTooBigCount = 0
        PSTypeName = 'PingIt.ErrorRecord'
        Start = $null
        TimedOutCount = 0
        }
    $errorRecord
}


function FinalizeOutage {
    param (
        [ref][bool]$outageActive,
        [PSTypeName('PingIt.ErrorRecord')]$errorRecord,
        [DateTime]$outageEndTimestamp,
        # need [ref] here because adding element to an array creates a new array
        # the actual type is [PSTypeName('PingIt.ErrorRecord')][object[]], but use 'PSCustomObject' to get pass by referenct to work
        [ref][PSCustomObject[]]$allErrors
    )
    $outageActive.Value = $false
    $errorRecord.End = $outageEndTimestamp
    $errorRecord.Elapsed = ($errorRecord.End -$errorRecord.Start) #(New-TimeSpan -End $errorRecord.End -Start $errorRecord.Start)
    $allErrors.Value += $errorRecord
}


function ResolveDestination {
    param (
        [string]$target,
        [int]$bufferSize,
        [int]$timeoutSeconds
    )
    [string]$err = 'errorVar'
    $theArgs = @{
        BufferSize = $bufferSize
        Count = 1
        ErrorAction = 'SilentlyContinue'
        ErrorVariable = $err
        ResolveDestination = $true
        TargetName = $target
        TimeoutSeconds = $timeoutSeconds
    }
    [Microsoft.Powershell.Commands.TestConnectionCommand+PingStatus]$result = $null
    $result = Test-Connection @theArgs
    [bool]$isError = $false
    if (Test-Path variable:\$err) {
        [PSVariable]$variable = Get-Variable $err
        [System.Collections.ArrayList]$value = ($null -ne $variable) ? $variable.Value : [System.Collections.ArrayList]::new()
          if ($value.Count -gt 0) {
            $isError = $true
          }
    }

    if ($isError -or $null -eq $result) {
        Write-Host "Pinging $target (could not resolve) with $bufferSize bytes of data:"
    }
    else {
        [string]$displayAddress = $result.DisplayAddress
        if ($displayAddress -eq '*') {
            $displayAddress = "(could not resolve)"
        }
        Write-Host "Pinging $($result.Destination) [$displayAddress] with $($result.BufferSize) bytes of data:"
    }
}


function Invoke-PingIt {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true,
        HelpMessage = "DNS name or IP address",
        Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Target,

        [Parameter(Mandatory = $false,
        HelpMessage = "Count of pings to run before exiting. If 0 is supplied or if not specified, will ping until Ctrl-C is pressed.")]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Count = 0,

        [Parameter(Mandatory = $false,
        HelpMessage = "Packet size in bytes. Defaults to 32, maximum is 65,527")]
        [ValidateRange(8, 65527)]
        [Alias('l')]
        [int]$BufferSize = 32,

        [Parameter(Mandatory = $false,
        HelpMessage = "An attempt to resolve the DNS name of the target will be made.")]
        [Alias('a')]
        [switch]$ResolveDestination,

        [Parameter(Mandatory = $false,
        HelpMessage = "Sets the timeout value for the test. The test fails if a response isn't received before the timeout expires. The default is five seconds.")]
        [ValidateRange(1, 1000)]
        [Alias('w')]
        [int]$Timeout = 5,

        [Parameter(Mandatory = $false,
        HelpMessage = "Latency issues will be detected and recorded whenever a ping latency (ms) exceeds this value. Default of 0 means no latency issue detection.")]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$LatencyThreshold = 0,

        [Parameter(Mandatory = $false,
        HelpMessage = "The minimum number of sequential latency threshold occurences for a record to be created. Defaults to 5.")]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$LatencyWindow = 5,

        [Parameter(Mandatory = $false,
        HelpMessage = "If specified, the moving average over 'LatencyWindow' packets will be compared with the 'LatencyThreshold")]
        [switch]$LatencyMovingAvg,

        [Parameter(Mandatory = $false,
        HelpMessage = "If specified, timestamps will be displayed for each ping result.")]
        [Alias('D')]
        [switch]$Timestamps,

        [Parameter(Mandatory = $false,
        HelpMessage = "See documentation for Test-Connection.")]
        [switch]$DontFragment,

        [Parameter(Mandatory = $false,
        HelpMessage = "See documentation for Test-Connection.")]
        [switch]$IPv4,

        [Parameter(Mandatory = $false,
        HelpMessage = "See documentation for Test-Connection.")]
        [switch]$IPv6,

        [Parameter(Mandatory = $false,
        HelpMessage = "See documentation for Test-Connection.")]
        [Alias('Ttl', 'TimeToLive', 'Hops')]
        [int]$MaxHops = 128
    )

    $theArgs = @{
        BufferSize = $BufferSize
        Count = 1 # this is 1 because we want the output from Test-Connection after each call
        ErrorAction = 'SilentlyContinue'
        MaxHops = $MaxHops
        TargetName = $Target
        TimeoutSeconds = $Timeout
    }
    if ($DontFragment) {
        $theArgs.Add('DontFragment', $true)
    }
    if ($IPv4) {
        $theArgs.Add('IPv4', $true)
    }
    if ($IPv6) {
        $theArgs.Add('IPv6', $true)
    }


    [int]$maxPings = -1
    if ($Count -ne 0) {
        $maxPings = $Count
    }

    [PSTypeName('PingIt.ErrorRecord')][object[]]$errors = @()
    [PSTypeName('PingIt.ErrorRecord')]$currentError = CreateErrorRecord

    $latencyQueue = $null
    if ($LatencyMovingAvg) {
        $latencyQueue = [System.Collections.Queue]::new()
    }
    [PSTypeName('PingIt.LatencyRecord')]$previousLatencyRecord = $null
    $latencyIssues = @()
    [PSTypeName('PingIt.LatencyTracker')]$currentLatencyTracker = $null
    [int]$pingCount = 0
    [int]$totalLatency = 0
    [int]$minLatency = [int]::MaxValue
    [int]$maxLatency = [int]::MinValue
    [int]$successCount = 0
    [int]$noResponseCount = 0
    [int]$destinationHostUnreachableCount = 0
    [int]$destinationNetworkUnreachableCount = 0
    [int]$destinationUnreachableCount = 0
    [int]$packetTooBigCount = 0
    [int]$timedOutCount = 0
    [bool]$errorActive = $false
    [bool]$doNotSleep = $false
    [string]$displayAddress = ''
    [string]$elapsedFormat = 'dd\.hh\:mm\:ss'
    [string]$timestampFormat = 'MM/dd hh\:mm\:ss'
    [string]$perPingTimestampFormat = 'hh\:mm\:ss'
    [DateTime]$startTimestamp = Get-Date
    [DateTime]$endTimestamp = 0
    [bool]$ctrlCIntercepted = $false

    [Microsoft.Powershell.Commands.TestConnectionCommand+PingStatus]$result = $null
    if ($ResolveDestination) {
        $resolveDestArgs = @{
            bufferSize = $BufferSize
            target = $Target
            timeoutSeconds = $Timeout
        }
        ResolveDestination @resolveDestArgs
        $ResolveDestination = $false
        $theArgs.Remove('ResolveDestination')
    }
    else {
        Write-Host "Pinging $Target with $BufferSize bytes of data:"
    }

    try {
        while ($true) {
            # so we can capture Ctrl-C
            if ($Host.UI.RawUI.KeyAvailable -and ($Key = $Host.UI.RawUI.ReadKey("AllowCtrlC,NoEcho,IncludeKeyUp"))) {
                $keyCharacter = [Int]$Key.Character -eq 3
                # Flush the key buffer again for the next loop.
                $Host.UI.RawUI.FlushInputBuffer()
                If ($keyCharacter -eq 3) {
                    [Console]::TreatControlCAsInput = $false
                    $ctrlCIntercepted = $true
                    break
                }
            }
            [DateTime]$pingStart = Get-Date
            $result = Test-Connection @theArgs
            [DateTime]$pingEnd = Get-Date
            $pingCount++
            $outputObject = [PSCustomObject]@{
                Status = $null
                Timestamp = $pingEnd
            }
            [string]$timestamp = ''
            if ($Timestamps) {
                $timestamp = "$($outputObject.Timestamp.ToString($perPingTimestampFormat)) "
            }

            [bool]$errorResult = $false
            [string]$pingMsg = ''
            [ConsoleColor]$pingMsgForegroundColor = [ConsoleColor]::White
            if ($null -ne $result) {
                [string]$errorDisplay = ''
                $outputObject.Status = $result.Status
                switch ($result.Status) {
                    Success {
                        # are we tracking latency issues?
                        if ($LatencyThreshold -gt 0) {
                            if ($result.Latency -ge $LatencyThreshold) {
                                $pingMsgForegroundColor = [ConsoleColor]::Yellow
                            }
                            # sequential?
                            if ($false -eq $LatencyMovingAvg) {
                                # does the current latency meet or exceed the threshold?
                                if ($result.Latency -ge $LatencyThreshold) {
                                    # create a tracker if we're not already tracking a latency issue
                                    if ($null -eq $currentLatencyTracker) {
                                        $currentLatencyTracker = CreateLatencyTracker $pingEnd
                                    }
                                    $currentLatencyTracker.Responses += $result.Latency
                                }
                                else {
                                    # had we already been tracking a latency issue?
                                    if ($null -ne $currentLatencyTracker) {
                                        # if the count of responses is >= $LatencyWindow, save the record
                                        if ($currentLatencyTracker.Responses.Count -ge $LatencyWindow) {
                                            FinalizeLatencyTracker ([ref]$latencyIssues) $currentLatencyTracker $pingEnd
                                        }
                                        # reset our latency issue state
                                        $currentLatencyTracker = $null
                                    }
                                }
                            }
                            else {
                                [PSTypeName('PingIt.LatencyRecord')]$currentLatencyRecord = HandleLatency $latencyQueue $LatencyWindow $pingEnd $result.Latency
                                if ((EvaluateLatencyState $latencyQueue $LatencyWindow $LatencyThreshold)) {
                                    # the current latency record is the one which most recently was part of a latency trend
                                    # we save it as $previousLatencyRecord so that when a latency trend ends, we can retrieve the timestamp
                                    # of the last record in the latency queue which contributed to the latency trend
                                    $previousLatencyRecord = $currentLatencyRecord
                                    # create and initialize a tracker if we're not already tracking a latency issue
                                    if ($null -eq $currentLatencyTracker) {
                                        $currentLatencyTracker = CreateLatencyTracker $latencyQueue.Peek().Timestamp # the start is the first element which is part of the latency trend
                                        foreach ($latencyItem  in $latencyQueue) {
                                            $currentLatencyTracker.Responses += $latencyItem.Latency
                                        }
                                    }
                                    else {
                                        $currentLatencyTracker.Responses += $result.Latency
                                    }
                                }
                                else {
                                    # we were previously in a latency trend, but now it has ended
                                    if ($null -ne $currentLatencyTracker) {
                                        FinalizeLatencyTracker ([ref]$latencyIssues) $currentLatencyTracker $previousLatencyRecord.Timestamp
                                    }
                                    $currentLatencyTracker = $null
                                }
                            }
                        }

                        # is there an outage being tracked? if so, we need to finalize the record
                        if ($errorActive) {
                            FinalizeOutage ([ref]$errorActive) $currentError $pingEnd ([ref]$errors)
                            $currentError = CreateErrorRecord
                        }
                        $successCount++
                        if ($result.Latency -lt $minLatency) {
                            $minLatency = $result.Latency
                        }
                        if ($result.Latency -gt $maxLatency) {
                            $maxLatency = $result.Latency
                        }
                        if ($result.Latency -gt 1000) {
                            $doNotSleep = $true
                        }
                        $totalLatency += $result.Latency
                        $outputObject | Add-Member -MemberType NoteProperty -Name 'Latency' -Value $result.Latency
                        if ([string]::IsNullOrEmpty($displayAddress)) {
                            $displayAddress = $result.DisplayAddress;
                        }
                    }
                    DestinationHostUnreachable {
                        $destinationHostUnreachableCount++
                        $currentError.DestinationHostUnreachableCount++
                        $errorDisplay = "Destination host unreachable"
                    }
                    DestinationNetworkUnreachable {
                        $destinationNetworkUnreachableCount++
                        $currentError.DestinationNetworkUnreachableCount++
                        $errorDisplay = "Destination net unreachable"
                    }
                    DestinationUnreachable {
                        $destinationUnreachableCount++
                        $currentError.DestinationUnreachableCount++
                        $errorDisplay = "Destination unreachable"
                    }
                    PacketTooBig {
                        $packetTooBigCount++
                        $currentError.PacketTooBigCount++
                        $errorDisplay = "Packet too big"
                    }
                    TimedOut {
                        $doNotSleep = $true
                        $timedOutCount++
                        $currentError.TimedOutCount++
                        $errorDisplay = "Request timed out after $Timeout seconds"
                    }
                }
                if ($result.Status -ne [System.Net.NetworkInformation.IPStatus]::Success) {
                    $errorResult = $true
                    $outputObject | Add-Member -MemberType NoteProperty -Name 'Latency' -Value 'n/a'
                    $pingMsg = "$($timestamp)$errorDisplay"
                    $pingMsgForegroundColor = [ConsoleColor]::Red
                }
                else {
                    $pingMsg = "$($timestamp)Reply from $($result.DisplayAddress): bytes=$($result.BufferSize) time=$($result.Latency)ms TTL=$($result.Reply.Options.Ttl)"
                }
            }
            else {
                $errorResult = $true # not technically an error, but Test-Connection should return a value, but didn't
                $noResponseCount++
                $currentError.NoResponseCount++
                $pingMsg = "$($timestamp)No response"
                $pingMsgForegroundColor = [ConsoleColor]::Red
            }
            Write-Host $pingMsg -ForegroundColor $pingMsgForegroundColor

            # was there an error and is it the first one of a new record?
            if ($errorResult -and $false -eq $errorActive) {
                $errorActive = $true
                # we got an error and it is the first one. the start of the error state is the time at which Test-Connection was invoked. if we used e.g. $pingEnd,
                # then if we failed due to timing out and the timeout was 5 seconds, our accounting would be off by 5 seconds
                $currentError.Start = $pingStart

                # are we tracking latency issues and are we in the middle of tracking one?
                if ($LatencyThreshold -gt 0 -and $null -ne $currentLatencyTracker) {
                    if ($false -eq $LatencyMovingAvg) {
                        # if the count of responses is >= $LatencyWindow, save the record
                        if ($currentLatencyTracker.Responses.Count -ge $LatencyWindow) {
                            FinalizeLatencyTracker ([ref]$latencyIssues) $currentLatencyTracker $pingStart # our latency issue ended when the outage (error) state began
                        }
                    }
                    else {
                        FinalizeLatencyTracker ([ref]$latencyIssues) $currentLatencyTracker $previousLatencyRecord.Timestamp
                    }
                    # reset our latency issue state
                    $currentLatencyTracker = $null
                }
            }

            if ($false -eq $doNotSleep) {
                Start-Sleep -Seconds 1
            }
            else {
                $doNotSleep = $false
            }
            if (-1 -ne $maxPings -and $pingCount -eq $maxPings) {
                break
            }
        }

        $endTimestamp = Get-Date

        # are we tracking latency issues and are we in the middle of tracking one?
        if ($LatencyThreshold -gt 0 -and $null -ne $currentLatencyTracker) {
            if ($false -eq $LatencyMovingAvg) {
                # if the count of responses is >= $LatencyWindow, save the record
                if ($currentLatencyTracker.Responses.Count -ge $LatencyWindow) {
                    FinalizeLatencyTracker ([ref]$latencyIssues) $currentLatencyTracker $endTimestamp
                }
            }
            else {
                FinalizeLatencyTracker ([ref]$latencyIssues) $currentLatencyTracker $previousLatencyRecord.Timestamp
            }
            # reset our latency issue state
            $currentLatencyTracker = $null
        }

        # if we were in the middle of an error situation, finalize the accounting
        if ($errorActive) {
            FinalizeOutage ([ref]$errorActive) $currentError $endTimestamp ([ref]$errors)
        }

        # normal ping statistics
        $summary = [PSCustomObject]@{
            Start = $startTimestamp.ToString($timestampFormat)
            End = $endTimestamp.ToString($timestampFormat)
            Elapsed = $((New-TimeSpan -Start $startTimestamp -End $endTimestamp).ToString($elapsedFormat))
            Total = $pingCount
        }
        if ($errors.Count -gt 0) {
            $summary | Add-Member -MemberType NoteProperty -Name 'Succeeded' -Value $successCount
        }
        Write-Host "`n`nPing statistics for $displayAddress`:" -NoNewline
        $summary | Format-Table

        # round trip times
        [string]$minLatencyDisplay = "$minLatency"
        if ($minLatency -eq [int]::MaxValue) {
            $minLatencyDisplay = 'n/a'
        }
        [string]$maxLatencyDisplay = "$maxLatency"
        if ($maxLatency -eq [int]::MinValue) {
            $maxLatencyDisplay = 'n/a'
        }
        [string]$avgLatencyForDisplay = 'n/a'
        if ($totalLatency -gt 0 -and $pingCount -gt 0) {
            $avgLatencyForDisplay = [int]($totalLatency/$pingCount)
        }
        $roundTripTimes = [PSCustomObject]@{
            Min = $minLatencyDisplay
            Max = $maxLatencyDisplay
            Avg = $avgLatencyForDisplay
        }
        Write-Host "`nApproximate round trip times in milli-seconds:" -NoNewline
        $roundTripTimes | Format-Table

        # latency issues summary and details
        if ($LatencyThreshold -gt 0 -and $latencyIssues.Count -gt 0) {
            # summary-related variables
            [TimeSpan]$totalElapsedLatency = New-TimeSpan # empty argument list gives a timespan of 0
            [int]$latencyIssuePingCount = 0
            [int]$latencyIssueTotal = 0
            [int]$latencyIssueMax = [int]::MinValue
            [int]$latencyIssueMin = [int]::MaxValue
            # detail-related variables
            $latencyDetailRecords = @()
            [TimeSpan]$minLatencyElapsed = New-TimeSpan -Days 3650
            [int]$minLatencyIndex = [int]::MaxValue
            [TimeSpan]$maxLatencyElapsed = New-TimeSpan # empty argument list gives a timespan of 0
            [int]$maxLatencyIndex = [int]::MinValue
            [int]$latencyIssueIndex = 0
            foreach ($latencyIssue in $latencyIssues) {
                $totalElapsedLatency += (New-TimeSpan -Start $latencyIssue.Start -End $latencyIssue.End)
                $latencyIssuePingCount += $latencyIssue.Responses.Count
                [int]$currentLatencyTrackerMax = [int]::MinValue
                [int]$currentLatencyTrackerMin = [int]::MaxValue
                [int]$currentLatencyTrackerTotal = 0
                foreach ($response in $latencyIssue.Responses) {
                    $latencyIssueTotal += $response
                    $currentLatencyTrackerTotal += $response
                    if ($response -gt $latencyIssueMax) {
                        $latencyIssueMax = $response
                    }
                    if ($response -lt $latencyIssueMin) {
                        $latencyIssueMin = $response
                    }
                    if ($response -gt $currentLatencyTrackerMax) {
                        $currentLatencyTrackerMax = $response
                    }
                    if ($response -lt $currentLatencyTrackerMin) {
                        $currentLatencyTrackerMin = $response
                    }
                }
                [int]$currentLatencyTrackerAvg = $currentLatencyTrackerTotal/$latencyIssue.Responses.Count

                $latencyDetailRecords += [PSCustomObject]@{
                    Avg = $currentLatencyTrackerAvg
                    Count = $latencyIssue.Responses.Count
                    Elapsed = $latencyIssue.Elapsed.ToString($elapsedFormat)
                    End = $latencyIssue.End.ToString($timestampFormat)
                    Index = $latencyIssueIndex # not for output
                    Max = $currentLatencyTrackerMax
                    Min = $currentLatencyTrackerMin
                    Start = $latencyIssue.Start.ToString($timestampFormat)
                }

                $totalElapsedLatency += $latencyIssue.Elapsed
                if ($latencyIssue.Elapsed -ge $maxLatencyElapsed) {
                    $maxLatencyElapsed = $latencyIssue.Elapsed
                    $maxLatencyIndex = $latencyIssueIndex
                }
                if ($latencyIssue.Elapsed -lt $minLatencyElapsed) {
                    $minLatencyElapsed = $latencyIssue.Elapsed
                    $minLatencyIndex = $latencyIssueIndex
                }
                $latencyIssueIndex++
            }

            # summary output
            [string]$moreInfo = 'moving average '
            if ($false -eq $LatencyMovingAvg) {
                $moreInfo = ''
            }
            [int]$latencyIssueAvg = [int]($latencyIssueTotal/$latencyIssuePingCount)
            Write-Host "`n`n`Latency $moreInfo(>= $LatencyThreshold) issues summary:" -ForegroundColor Yellow -NoNewline
            $latencyIssuesSummary = [PSCustomObject]@{
                Elapsed = $totalElapsedLatency.ToString($elapsedFormat)
                Count = $latencyIssuePingCount
                Min = "$($latencyIssueMin)ms"
                Max = "$($latencyIssueMax)ms"
                Avg = "$($latencyIssueAvg)ms"
            }
            $latencyIssuesSummary | Format-Table

            # details output
            Write-Host "`nLatency ${moreInfo}issues detail ($($latencyIssues.Count)):" -ForegroundColor Yellow -NoNewline
            $latencyDetailRecords | Format-Table -Property Start, End, @{Name = 'Elapsed'; e={
                ColorizeMinMax $_.Elapsed $latencyDetailRecords.Count $_.Index $maxLatencyIndex $minLatencyIndex
            }}, Count, Min, Max, Avg

            Write-Host "Latency Issues Total Elapsed: $($totalElapsedLatency.ToString($elapsedFormat))."
            if ($latencyDetailRecords.Count -gt 1) {
                [timespan]$latencyIssueAvgElapsed = ($totalElapsedLatency/$latencyIssues.Count)
                Write-Host "Latency Issues Average Elapsed: $($latencyIssueAvgElapsed.ToString($elapsedFormat))."
            }
        }

        # error summary and details
        [TimeSpan]$totalElapsedError = New-TimeSpan # empty argument list gives a timespan of 0
        if ($errors.Count -gt 0) {
            Write-Host "`n`n`Outage summary (packet counts):" -ForegroundColor Red -NoNewline
            $errorSummary = [PSCustomObject]@{
                Total = $destinationHostUnreachableCount + $destinationNetworkUnreachableCount + $destinationUnreachableCount + $timedOutCount + $noResponseCount
                HostUnreachable = $destinationHostUnreachableCount
                NetworkUnreachable = $destinationNetworkUnreachableCount
                OtherUnreachable = $destinationUnreachableCount
                TimedOut = $timedOutCount
                NoResponse = $noResponseCount
            }
            $errorSummary | Format-Table

            $outageDetailRecords = @()
            [TimeSpan]$minOutage = New-TimeSpan -Days 3650
            [int]$minOutageIndex = [int]::MaxValue
            [TimeSpan]$maxOutage = New-TimeSpan # empty argument list gives a timespan of 0
            [int]$maxOutageIndex = [int]::MinValue
            [int]$errorsIndex = 0
            foreach ($error in $errors) {
                $outageDetailRecords += [PSCustomObject]@{
                    Count = $error.DestinationHostUnreachableCount + $error.DestinationNetworkUnreachableCount + $error.DestinationUnreachableCount + $error.NoResponseCount + $error.PacketTooBigCount + $error.TimedOutCount
                    Elapsed = $error.Elapsed.ToString($elapsedFormat)
                    End = $error.End.ToString($timestampFormat)
                    Index = $errorsIndex # not for output
                    NoResponse = $error.NoResponseCount
                    Start = $error.Start.ToString($timestampFormat)
                    TimedOut = $error.TimedOutCount
                    Unreachable = $error.DestinationHostUnreachableCount + $error.DestinationNetworkUnreachableCount + $error.DestinationUnreachableCount
                }
                $totalElapsedError += $error.Elapsed
                if ($error.Elapsed -gt $maxOutage) {
                    $maxOutage = $error.Elapsed
                    $maxOutageIndex = $errorsIndex
                }
                if ($error.Elapsed -lt $minOutage) {
                    $minOutage = $error.Elapsed
                    $minOutageIndex = $errorsIndex
                }
                $errorsIndex++
            }

            # details output
            Write-Host "`nOutage detail ($($errors.Count) outages):" -ForegroundColor Red -NoNewline
            $outageDetailRecords | Format-Table -Property Start, End, @{Name = 'Elapsed'; e={
                ColorizeMinMax $_.Elapsed $outageDetailRecords.Count $_.Index $maxOutageIndex $minOutageIndex
            }}, Count, NoResponse, Unreachable, TimedOut

            Write-Host "Outages Total Elapsed: $($totalElapsedError.ToString($elapsedFormat))."
            if ($outageDetailRecords.Count -gt 1) {
                [timespan]$outageAvgElapsed = ($totalElapsedError/$errors.Count)
                Write-Host "Outage Average Elapsed: $($outageAvgElapsed.ToString($elapsedFormat))."
            }
        }
        if ($ctrlCIntercepted) {
            Write-Host "`nControl-C"
            Write-Host '^C'
        }
    }
    finally {
        [Console]::TreatControlCAsInput = $false # make sure this is reset
    }
}
New-Alias -Name PingIt -Value Invoke-PingIt
Export-ModuleMember -Alias * -Function Invoke-PingIt