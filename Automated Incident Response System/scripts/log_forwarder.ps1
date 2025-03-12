param(
    [string]$LokiUrl = "http://localhost:3100",
    [string[]]$LogPaths = @(
        "$PSScriptRoot\*.log"
    ),
    [int]$BatchSize = 1000,
    [int]$SendInterval = 10
)

# Create a log file for the forwarder itself
$LogForwarderLog = Join-Path $PSScriptRoot "log_forwarder.log"
function Write-ForwarderLog {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "{`"timestamp`":`"$timestamp`",`"level`":`"$Level`",`"message`":`"$Message`"}"
    Add-Content -Path $LogForwarderLog -Value $logMessage
    Write-Host $logMessage
}

function Get-UnixTimestampMillis {
    return [long]([datetime]::UtcNow - [datetime]"1970-01-01").TotalMilliseconds * 1000000
}

function Send-LogsToLoki {
    param(
        [string]$LokiUrl,
        [array]$LogEntries
    )
    
    $streams = @(
        @{
            stream = @{
                source = "powershell_scripts"
                job = "log_forwarder"
            }
            values = $LogEntries
        }
    )

    $body = @{
        streams = $streams
    } | ConvertTo-Json -Depth 10 -Compress

    try {
        $response = Invoke-RestMethod -Uri "$LokiUrl/loki/api/v1/push" -Method Post -Body $body -ContentType "application/json"
        Write-ForwarderLog -Message "Successfully sent $($LogEntries.Count) log entries to Loki"
        return $true
    }
    catch {
        Write-ForwarderLog -Message "Failed to send logs to Loki: $_" -Level "ERROR"
        return $false
    }
}

function Get-FormattedEventLogEntry {
    param($Event)
    
    $timestamp = Get-UnixTimestampMillis
    $message = "{`"level`":`"$($Event.EntryType)`",`"source`":`"EventLog`",`"message`":`"$($Event.Message -replace '"','\"')`"}"
    
    return @(
        "$timestamp",
        $message
    )
}

function Get-FormattedFileLogEntry {
    param($Line)
    
    try {
        if ($Line -match '^\[([\d\-: ]+)\]') {
            $timestamp = Get-UnixTimestampMillis
        }
        else {
            $timestamp = Get-UnixTimestampMillis
        }
        
        # Try to parse as JSON first
        try {
            $json = $Line | ConvertFrom-Json
            return @(
                "$timestamp",
                $Line
            )
        }
        catch {
            # If not JSON, create a JSON structure
            $message = "{`"message`":`"$($Line -replace '"','\"')`"}"
            return @(
                "$timestamp",
                $message
            )
        }
    }
    catch {
        $timestamp = Get-UnixTimestampMillis
        $message = "{`"message`":`"$($Line -replace '"','\"')`"}"
        return @(
            "$timestamp",
            $message
        )
    }
}

Write-ForwarderLog -Message "Starting log forwarder..."

# Main loop
$lastCheck = @{}
$logEntries = [System.Collections.ArrayList]::new()

# Get initial event log timestamps
$lastEventLogCheck = (Get-Date).AddMinutes(-5)

while ($true) {
    # Process file logs
    foreach ($path in $LogPaths) {
        if ($path -like "*.log") {
            Get-Item $path -ErrorAction SilentlyContinue | ForEach-Object {
                $file = $_
                Write-ForwarderLog -Message "Processing log file: $($file.FullName)"
                $lastPosition = $lastCheck[$file.FullName]
                
                if (-not $lastPosition) {
                    $lastPosition = 0
                }
                
                if ($file.Length -gt $lastPosition) {
                    $reader = [System.IO.File]::OpenText($file.FullName)
                    $reader.BaseStream.Position = $lastPosition
                    
                    while (-not $reader.EndOfStream) {
                        $line = $reader.ReadLine()
                        $entry = Get-FormattedFileLogEntry -Line $line
                        [void]$logEntries.Add($entry)
                    }
                    
                    $lastCheck[$file.FullName] = $reader.BaseStream.Position
                    $reader.Close()
                }
            }
        }
    }

    # Process Windows Event Logs
    try {
        $events = Get-EventLog -LogName System -After $lastEventLogCheck -ErrorAction SilentlyContinue |
            Where-Object { $_.EntryType -in 'Error','Warning' }
        foreach ($event in $events) {
            $entry = Get-FormattedEventLogEntry -Event $event
            [void]$logEntries.Add($entry)
        }

        $events = Get-EventLog -LogName Application -After $lastEventLogCheck -ErrorAction SilentlyContinue |
            Where-Object { $_.EntryType -in 'Error','Warning' }
        foreach ($event in $events) {
            $entry = Get-FormattedEventLogEntry -Event $event
            [void]$logEntries.Add($entry)
        }
    }
    catch {
        Write-ForwarderLog -Message "Error accessing event logs: $_" -Level "ERROR"
    }

    $lastEventLogCheck = Get-Date
    
    # Send logs in batches
    while ($logEntries.Count -ge $BatchSize) {
        $batch = $logEntries.GetRange(0, $BatchSize)
        if (Send-LogsToLoki -LokiUrl $LokiUrl -LogEntries $batch) {
            $logEntries.RemoveRange(0, $BatchSize)
        }
        else {
            Start-Sleep -Seconds 5
        }
    }
    
    if ($logEntries.Count -gt 0) {
        if (Send-LogsToLoki -LokiUrl $LokiUrl -LogEntries $logEntries) {
            $logEntries.Clear()
        }
    }
    
    Start-Sleep -Seconds $SendInterval
} 
} 