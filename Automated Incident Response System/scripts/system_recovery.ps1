param(
    [Parameter(Mandatory=$true)]
    [string]$TargetHost,
    [int]$MaxRetries = 3,
    [int]$RetryInterval = 30
)

# Import required modules
Import-Module Microsoft.PowerShell.Diagnostics
Import-Module Microsoft.PowerShell.Management

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
    Add-Content -Path "system_recovery.log" -Value "[$timestamp] $Message"
}

function Test-SystemAvailability {
    param($computerName)
    try {
        $result = Test-Connection -ComputerName $computerName -Count 1 -Quiet
        return $result
    } catch {
        Write-Log "Error testing connection to $computerName : $_"
        return $false
    }
}

function Get-SystemUptime {
    param($computerName)
    try {
        $os = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $computerName
        $uptime = (Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)
        return $uptime
    } catch {
        Write-Log "Error getting system uptime: $_"
        return $null
    }
}

function Get-CriticalServices {
    param($computerName)
    $criticalServices = @(
        "wuauserv",      # Windows Update
        "W3SVC",         # IIS
        "MSSQLSERVER",   # SQL Server
        "Schedule",      # Task Scheduler
        "EventLog",      # Event Log
        "Dnscache",      # DNS Client
        "LanmanServer",  # Server
        "LanmanWorkstation", # Workstation
        "RpcSs"         # Remote Procedure Call
    )

    try {
        $services = Get-Service -ComputerName $computerName -Name $criticalServices -ErrorAction SilentlyContinue |
                   Where-Object {$_.Status -ne 'Running'}
        return $services
    } catch {
        Write-Log "Error getting services: $_"
        return $null
    }
}

function Restart-CriticalService {
    param(
        $computerName,
        $serviceName
    )
    try {
        $service = Get-Service -ComputerName $computerName -Name $serviceName
        if ($service.Status -ne 'Running') {
            Write-Log "Attempting to restart service: $serviceName"
            Restart-Service -InputObject $service -Force
            Start-Sleep -Seconds 5
            $service.Refresh()
            
            if ($service.Status -eq 'Running') {
                Write-Log "Successfully restarted service: $serviceName"
                return $true
            } else {
                Write-Log "Service failed to start: $serviceName"
                return $false
            }
        }
        return $true
    } catch {
        Write-Log "Error restarting service $serviceName : $_"
        return $false
    }
}

function Restart-RemoteSystem {
    param($computerName)
    try {
        Write-Log "Initiating system restart for $computerName"
        Restart-Computer -ComputerName $computerName -Force -Wait
        return $true
    } catch {
        Write-Log "Failed to restart system: $_"
        return $false
    }
}

# Main execution
Write-Log "Starting system recovery script for host: $TargetHost"

# Initial system check
$isAvailable = Test-SystemAvailability -computerName $TargetHost
if ($isAvailable) {
    Write-Log "System is responding to ping. Checking services..."
    
    # Check system uptime
    $uptime = Get-SystemUptime -computerName $TargetHost
    if ($uptime) {
        Write-Log "System uptime: $($uptime.Days) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes"
    }
    
    # Check and restart critical services
    $failedServices = Get-CriticalServices -computerName $TargetHost
    if ($failedServices) {
        Write-Log "Found $($failedServices.Count) stopped critical services"
        foreach ($service in $failedServices) {
            Restart-CriticalService -computerName $TargetHost -serviceName $service.Name
        }
    } else {
        Write-Log "All critical services are running"
    }
    
    # Final service check
    $remainingFailedServices = Get-CriticalServices -computerName $TargetHost
    if ($remainingFailedServices) {
        Write-Log "Some services still not running. Initiating system restart..."
        Restart-RemoteSystem -computerName $TargetHost
    }
} else {
    Write-Log "System is not responding. Starting recovery process..."
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        Write-Log "Recovery attempt $i of $MaxRetries"
        
        # Try to restart the system
        $restartResult = Restart-RemoteSystem -computerName $TargetHost
        
        # Wait for the specified interval
        Write-Log "Waiting $RetryInterval seconds for system to recover..."
        Start-Sleep -Seconds $RetryInterval
        
        # Check if system is back online
        if (Test-SystemAvailability -computerName $TargetHost) {
            Write-Log "System recovered successfully"
            
            # Wait additional time for services to start
            Start-Sleep -Seconds 30
            
            # Check and restart any remaining stopped services
            $failedServices = Get-CriticalServices -computerName $TargetHost
            if ($failedServices) {
                foreach ($service in $failedServices) {
                    Restart-CriticalService -computerName $TargetHost -serviceName $service.Name
                }
            }
            
            exit 0
        }
    }
    
    Write-Log "System recovery failed after $MaxRetries attempts"
    exit 1
}

Write-Log "System recovery script completed" 