# Function to consume CPU
function Test-HighCPU {
    Write-Host "Starting CPU stress test..."
    $cores = (Get-WmiObject Win32_Processor).NumberOfLogicalProcessors
    1..$cores | ForEach-Object {
        Start-Job -ScriptBlock {
            $result = 1
            while ($true) {
                $result *= 1.000001
            }
        }
    }
    Write-Host "CPU stress test running. This should trigger the HighCPUUsage alert in about 1 minute."
}

# Function to consume Memory
function Test-HighMemory {
    Write-Host "Starting memory stress test..."
    $list = New-Object System.Collections.ArrayList
    while ($true) {
        $list.Add("A" * 1MB)
        Start-Sleep -Milliseconds 100
    }
}

# Function to fill disk space
function Test-DiskSpace {
    param(
        [string]$Path = "C:\temp\test",
        [int]$SizeInGB = 10
    )
    
    Write-Host "Creating large file to test disk space alerts..."
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force
    }
    
    $file = Join-Path $Path "large_file.dat"
    $buffer = New-Object byte[] (1GB)
    $stream = [System.IO.File]::OpenWrite($file)
    
    for ($i = 0; $i -lt $SizeInGB; $i++) {
        Write-Host "Writing GB $($i+1) of $SizeInGB..."
        $stream.Write($buffer, 0, $buffer.Length)
    }
    
    $stream.Close()
    Write-Host "Finished creating large file at $file"
}

# Function to simulate network errors
function Test-NetworkErrors {
    Write-Host "Simulating network errors..."
    # This will create some failed network requests
    1..1000 | ForEach-Object {
        try {
            $null = Invoke-WebRequest "http://localhost:1" -TimeoutSec 1
        } catch {
            # Expected error
        }
        Start-Sleep -Milliseconds 10
    }
}

# Function to stop a Windows service
function Test-ServiceDown {
    param(
        [string]$ServiceName = "Print Spooler"
    )
    Write-Host "Stopping service $ServiceName to test ServiceDown alert..."
    Stop-Service -Name "Spooler" -Force
    Write-Host "Service stopped. This should trigger the ServiceDown alert."
}

# Function to clean up tests
function Stop-StressTests {
    Write-Host "Cleaning up stress tests..."
    Get-Job | Stop-Job
    Get-Job | Remove-Job
    [System.GC]::Collect()
    Start-Service -Name "Spooler"
    Write-Host "Cleanup complete."
}

# Menu to select test
function Show-Menu {
    Write-Host "`n=== Alert Testing Menu ===" -ForegroundColor Cyan
    Write-Host "1: Test High CPU Alert"
    Write-Host "2: Test High Memory Alert"
    Write-Host "3: Test Disk Space Alert"
    Write-Host "4: Test Network Errors Alert"
    Write-Host "5: Test Service Down Alert"
    Write-Host "6: Stop All Tests"
    Write-Host "Q: Quit"
    Write-Host "=========================" -ForegroundColor Cyan
}

# Main loop
do {
    Show-Menu
    $choice = Read-Host "`nEnter your choice"
    
    switch ($choice) {
        "1" {
            Test-HighCPU
        }
        "2" {
            Test-HighMemory
        }
        "3" {
            $path = Read-Host "Enter path for test file (default: C:\temp\test)"
            if ([string]::IsNullOrWhiteSpace($path)) {
                $path = "C:\temp\test"
            }
            $size = Read-Host "Enter size in GB (default: 10)"
            if ([string]::IsNullOrWhiteSpace($size)) {
                $size = 10
            }
            Test-DiskSpace -Path $path -SizeInGB ([int]$size)
        }
        "4" {
            Test-NetworkErrors
        }
        "5" {
            Test-ServiceDown
        }
        "6" {
            Stop-StressTests
        }
        "Q" {
            Write-Host "Exiting..."
            Stop-StressTests
        }
        default {
            Write-Host "Invalid choice. Please try again." -ForegroundColor Red
        }
    }
} while ($choice -ne "Q") 