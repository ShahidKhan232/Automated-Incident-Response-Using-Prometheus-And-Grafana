param(
    [Parameter(Mandatory=$true)]
    [string]$TargetHost,
    [int]$MemoryThreshold = 90,
    [int]$ProcessMemoryThreshold = 2GB
)

# Import required modules
Import-Module Microsoft.PowerShell.Diagnostics
Import-Module Microsoft.PowerShell.Management

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
    Add-Content -Path "memory_cleanup.log" -Value "[$timestamp] $Message"
}

function Get-MemoryUsage {
    $os = Get-WmiObject -Class Win32_OperatingSystem
    $totalMemory = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeMemory = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedMemory = [math]::Round(($totalMemory - $freeMemory), 2)
    $memoryUsagePercent = [math]::Round(($usedMemory / $totalMemory) * 100, 2)

    return @{
        TotalGB = $totalMemory
        FreeGB = $freeMemory
        UsedGB = $usedMemory
        UsagePercent = $memoryUsagePercent
    }
}

function Get-HighMemoryProcesses {
    param($thresholdBytes)
    $processes = Get-Process | Where-Object {$_.WorkingSet64 -gt $thresholdBytes} |
                Select-Object Name, Id, CPU, @{Name="MemoryGB";Expression={[math]::Round($_.WorkingSet64 / 1GB, 2)}}, Description |
                Sort-Object MemoryGB -Descending
    return $processes
}

function Clear-SystemCache {
    try {
        # Clear file system cache
        Write-Log "Clearing file system cache..."
        [System.Diagnostics.Process]::Start("rundll32.exe", "advapi32.dll,ProcessIdleTasks")
        
        # Clear system working set
        Write-Log "Clearing system working set..."
        $signature = @"
        [DllImport("psapi.dll")]
        public static extern int EmptyWorkingSet(IntPtr hwProc);
"@
        $type = Add-Type -MemberDefinition $signature -Name PSApiType -Namespace PSApi -PassThru
        $processes = Get-Process
        foreach ($process in $processes) {
            $type::EmptyWorkingSet($process.Handle)
        }
        
        return $true
    } catch {
        Write-Log "Failed to clear system cache: $_"
        return $false
    }
}

function Stop-HighMemoryProcess {
    param($process)
    try {
        Stop-Process -Id $process.Id -Force
        Write-Log "Successfully stopped process $($process.Name) (PID: $($process.Id)) - Memory: $($process.MemoryGB)GB"
        return $true
    } catch {
        Write-Log "Failed to stop process $($process.Name): $_"
        return $false
    }
}

function Test-RemoteConnection {
    param($computerName)
    try {
        Test-Connection -ComputerName $computerName -Count 1 -Quiet
        return $true
    } catch {
        Write-Log "Failed to connect to $computerName: $_"
        return $false
    }
}

# Main execution
Write-Log "Starting memory cleanup script for host: $TargetHost"

# Check if target is accessible
if (-not (Test-RemoteConnection -computerName $TargetHost)) {
    Write-Log "Cannot connect to target host. Exiting."
    exit 1
}

# Get initial memory usage
$initialMemory = Get-MemoryUsage
Write-Log "Initial memory state:"
Write-Log "Total: $($initialMemory.TotalGB)GB"
Write-Log "Used: $($initialMemory.UsedGB)GB ($($initialMemory.UsagePercent)%)"
Write-Log "Free: $($initialMemory.FreeGB)GB"

if ($initialMemory.UsagePercent -ge $MemoryThreshold) {
    Write-Log "Memory usage is above threshold. Starting cleanup..."
    
    # Clear system cache first
    Clear-SystemCache
    Start-Sleep -Seconds 5
    
    # Get high memory processes
    $processes = Get-HighMemoryProcesses -thresholdBytes $ProcessMemoryThreshold
    
    if ($processes.Count -gt 0) {
        Write-Log "Found $($processes.Count) processes consuming high memory:"
        foreach ($process in $processes) {
            Write-Log "Process: $($process.Name) (PID: $($process.Id)) - Memory: $($process.MemoryGB)GB"
            
            # Skip system critical processes
            if ($process.Name -in @("System", "Idle", "svchost", "lsass", "csrss", "winlogon", "services")) {
                Write-Log "Skipping system critical process: $($process.Name)"
                continue
            }
            
            Stop-HighMemoryProcess -process $process
        }
    }
    
    # Get final memory usage
    Start-Sleep -Seconds 5
    $finalMemory = Get-MemoryUsage
    Write-Log "`nFinal memory state:"
    Write-Log "Total: $($finalMemory.TotalGB)GB"
    Write-Log "Used: $($finalMemory.UsedGB)GB ($($finalMemory.UsagePercent)%)"
    Write-Log "Free: $($finalMemory.FreeGB)GB"
    
    $memoryFreed = $initialMemory.UsedGB - $finalMemory.UsedGB
    Write-Log "Memory freed: $([math]::Round($memoryFreed, 2))GB"
} else {
    Write-Log "Memory usage is within acceptable limits. No action needed."
}

Write-Log "Memory cleanup script completed." 