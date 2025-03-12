# Automated Incident Response System Using Prometheus and Grafana

This project implements an automated incident response system using Prometheus for monitoring, Grafana for visualization, and PowerShell scripts for automated remediation.

## Features

- Real-time system monitoring using Windows Exporter
- Automated alert generation with Prometheus
- Beautiful visualization with Grafana dashboards
- Automated incident response using PowerShell scripts
- Log aggregation with Loki
- Alert management with AlertManager

## Components

- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **Windows Exporter**: Windows system metrics collection
- **Loki**: Log aggregation
- **AlertManager**: Alert routing and management
- **PowerShell Scripts**: Automated remediation

## Prerequisites

- Windows 10/11 or Windows Server
- PowerShell 5.1 or later
- Administrator privileges

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/ShahidKhan232/Automated-Incident-Response-Using-Prometheus-And-Grafana.git
   cd Automated-Incident-Response-Using-Prometheus-And-Grafana
   ```

2. Download and install required components:

   a. Prometheus:
   ```powershell
   # Download Prometheus
   Invoke-WebRequest -Uri "https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.windows-amd64.zip" -OutFile "prometheus.zip"
   Expand-Archive -Path "prometheus.zip" -DestinationPath "prometheus"
   ```

   b. Windows Exporter:
   ```powershell
   # Download Windows Exporter
   Invoke-WebRequest -Uri "https://github.com/prometheus-community/windows_exporter/releases/download/v0.25.1/windows_exporter-0.25.1-amd64.exe" -OutFile "windows_exporter.exe"
   ```

   c. Grafana:
   ```powershell
   # Download and install Grafana
   Invoke-WebRequest -Uri "https://dl.grafana.com/enterprise/release/grafana-enterprise-10.0.3.windows-amd64.msi" -OutFile "grafana.msi"
   Start-Process msiexec.exe -ArgumentList "/i grafana.msi /quiet" -Wait
   ```

   d. Loki:
   ```powershell
   # Download Loki
   Invoke-WebRequest -Uri "https://github.com/grafana/loki/releases/download/v2.9.0/loki-windows-amd64.exe" -OutFile "loki/loki.exe"
   ```

3. Start the components:
   ```powershell
   # Start Prometheus
   Start-Process -FilePath ".\prometheus\prometheus.exe" -NoNewWindow

   # Start Windows Exporter
   Start-Process -FilePath ".\windows_exporter.exe" -ArgumentList "--web.listen-address=:9182" -NoNewWindow

   # Start Loki
   Start-Process -FilePath ".\loki\loki.exe" -ArgumentList "--config.file=loki/loki-config.yml" -NoNewWindow

   # Start Log Forwarder
   Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File scripts/log_forwarder.ps1" -NoNewWindow
   ```

4. Access the interfaces:
   - Prometheus: http://localhost:9090
   - Grafana: http://localhost:3000
   - AlertManager: http://localhost:9093
   - Windows Exporter Metrics: http://localhost:9182/metrics

## Configuration

### Alert Rules

Alert rules are defined in `prometheus/alert.rules.yml` and include:
- High CPU Usage (>80%)
- High Memory Usage (>85%)
- Critical Memory Usage (>95%)
- Low Disk Space (>85%)
- Critical Disk Space (>95%)
- System Down
- Network Errors
- Service Status

### Automated Response

The system automatically responds to alerts by executing appropriate PowerShell scripts:
- CPU mitigation
- Memory cleanup
- Disk space cleanup
- System recovery
- Service restoration

### Dashboards

The Grafana dashboards provide visualization for:
- System metrics (CPU, Memory, Disk, Network)
- Alert status
- Log aggregation
- Service health

## Testing

Use the test script to simulate various alert conditions:
```powershell
.\scripts\test_alerts.ps1
```

This provides options to test:
1. High CPU Usage
2. High Memory Usage
3. Disk Space Issues
4. Network Errors
5. Service Down Scenarios



## Contributing

Contributions are welcome! Please feel free to submit pull requests.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 
