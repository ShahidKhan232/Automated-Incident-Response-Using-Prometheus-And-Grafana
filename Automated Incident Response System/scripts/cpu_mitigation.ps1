param(
    [Parameter(Mandatory=$true)]
    [string]$TargetHost,
    [int]$CPUThreshold = 80,
    [int]$SampleCount = 3,
    [int]$SampleInterval = 2
)

# Import required modules
Import-Module Microsoft.PowerShell.Diagnostics
Import-Module Microsoft.PowerShell.Management

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
    Add-Content -Path "cpu_mitigation.log" -Value "[$timestamp] $Message"
}

function Get-HighCPUProcesses {
    param($threshold)
    $processes = Get-Process | Where-Object {$_.CPU -gt $threshold} | 
                Select-Object Name, Id, CPU, WorkingSet, Description |
                Sort-Object CPU -Descending
    return $processes
}

function Test-RemoteConnection {
    param($computerName)
    try {
        Test-Connection -ComputerName $computerName -Count 1 -Quiet
        return $true
    } catch {
        Write-Log "Failed to connect to $computerName : $_"
        return $false
    }
}

function Stop-HighCPUProcess {
    param($process)
    try {
        Stop-Process -Id $process.Id -Force
        Write-Log "Successfully stopped process $($process.Name) (PID: $($process.Id))"
        return $true
    } catch {
        Write-Log "Failed to stop process $($process.Name) : $_"
        return $false
    }
}

function Restart-CriticalService {
    param($serviceName)
    try {
        Restart-Service -Name $serviceName -Force
        Write-Log "Successfully restarted service $serviceName"
        return $true
    } catch {
        Write-Log "Failed to restart service $serviceName : $_"
        return $false
    }
}

# Main execution
Write-Log "Starting CPU mitigation script for host: $TargetHost"

# Check if target is accessible
if (-not (Test-RemoteConnection -computerName $TargetHost)) {
    Write-Log "Cannot connect to target host. Exiting."
    exit 1
}

# Monitor CPU usage over multiple samples
$highCPUDetected = 0
for ($i = 1; $i -le $SampleCount; $i++) {
    Write-Log "Taking CPU sample $i of $SampleCount"
    $processes = Get-HighCPUProcesses -threshold $CPUThreshold
    
    if ($processes.Count -gt 0) {
        $highCPUDetected++
        Write-Log "High CPU processes detected in sample $i:"
        $processes | ForEach-Object {
            Write-Log "Process: $($_.Name) (PID: $($_.Id)) - CPU: $($_.CPU)%"
        }
    }
    
    if ($i -lt $SampleCount) {
        Start-Sleep -Seconds $SampleInterval
    }
}

# Take action if high CPU is consistent
if ($highCPUDetected -ge [math]::Ceiling($SampleCount * 0.6)) {
    Write-Log "Consistent high CPU usage detected. Taking action..."
    
    # Get final list of high CPU processes
    $processes = Get-HighCPUProcesses -threshold $CPUThreshold
    
    foreach ($process in $processes) {
        # Skip system critical processes
        if ($process.Name -in @("System", "Idle", "svchost", "lsass", "csrss", "winlogon", "services")) {
            Write-Log "Skipping system critical process: $($process.Name)"
            continue
        }
        
        Stop-HighCPUProcess -process $process
    }
    
    # Check if CPU is still high after stopping processes
    Start-Sleep -Seconds 5
    $remainingHighCPU = Get-HighCPUProcesses -threshold $CPUThreshold
    
    if ($remainingHighCPU.Count -gt 0) {
        Write-Log "CPU still high after stopping processes. Restarting critical services..."
        $criticalServices = @("W3SVC", "wuauserv")
        
        foreach ($service in $criticalServices) {
            Restart-CriticalService -serviceName $service
        }
    }
} else {
    Write-Log "No consistent high CPU usage detected. No action needed."
}

Write-Log "CPU mitigation script completed." 