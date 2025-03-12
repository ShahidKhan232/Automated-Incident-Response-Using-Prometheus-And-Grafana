from flask import Flask, request, jsonify
import subprocess
import logging
import os
from typing import Dict, Any, Optional
from dataclasses import dataclass
from enum import Enum
import yaml
from functools import lru_cache
import threading
from concurrent.futures import ThreadPoolExecutor
import time

# Alert severity levels
class Severity(Enum):
    CRITICAL = "critical"
    WARNING = "warning"
    INFO = "info"

# Alert status types
class AlertStatus(Enum):
    FIRING = "firing"
    RESOLVED = "resolved"

@dataclass
class AlertConfig:
    name: str
    playbook: str
    severity: Severity
    description: str

class AlertHandler:
    def __init__(self, config_path: str = "alert_config.yml", max_workers: int = 4):
        self.alert_configs = self._load_alert_configs(config_path)
        self.logger = logging.getLogger(__name__)
        self.executor = ThreadPoolExecutor(max_workers=max_workers)
        self.alert_lock = threading.Lock()
        self.last_execution = {}

    @lru_cache(maxsize=128)
    def _load_alert_configs(self, config_path: str) -> Dict[str, AlertConfig]:
        default_configs = {
            "HighCPUUsage": AlertConfig(
                name="HighCPUUsage",
                playbook="../scripts/cpu_mitigation.ps1",
                severity=Severity.WARNING,
                description="High CPU usage detected"
            ),
            "HighMemoryUsage": AlertConfig(
                name="HighMemoryUsage",
                playbook="../scripts/memory_cleanup.ps1",
                severity=Severity.WARNING,
                description="High memory usage detected"
            ),
            "LowDiskSpace": AlertConfig(
                name="LowDiskSpace",
                playbook="../scripts/disk_cleanup.ps1",
                severity=Severity.WARNING,
                description="Low disk space detected"
            ),
            "SystemDown": AlertConfig(
                name="SystemDown",
                playbook="../scripts/system_recovery.ps1",
                severity=Severity.CRITICAL,
                description="System is down"
            )
        }

        if os.path.exists(config_path):
            try:
                with open(config_path, 'r') as f:
                    custom_configs = yaml.safe_load(f)
                    for name, config in custom_configs.items():
                        default_configs[name] = AlertConfig(**config)
            except Exception as e:
                self.logger.error(f"Error loading config file: {e}")

        return default_configs

    def _should_execute_playbook(self, alert_name: str, instance: str) -> bool:
        """Rate limiting for playbook execution"""
        key = f"{alert_name}_{instance}"
        current_time = time.time()
        
        with self.alert_lock:
            last_time = self.last_execution.get(key, 0)
            if current_time - last_time < 300:  # 5 minutes cooldown
                return False
            self.last_execution[key] = current_time
            return True

    def handle_alert(self, alert_data: Dict[str, Any]) -> tuple[Dict[str, str], int]:
        try:
            alert_name = alert_data.get('labels', {}).get('alertname')
            severity = alert_data.get('labels', {}).get('severity')
            status = alert_data.get('status')
            instance = alert_data.get('labels', {}).get('instance', 'unknown')

            if not alert_name:
                return {"status": "error", "message": "Missing alert name"}, 400

            config = self.alert_configs.get(alert_name)
            if not config:
                self.logger.warning(f"No configuration found for alert: {alert_name}")
                return {"status": "warning", "message": f"Unhandled alert type: {alert_name}"}, 200

            self.logger.info(f"Processing {severity} alert: {alert_name} for instance {instance}")

            if status == AlertStatus.RESOLVED.value:
                self.logger.info(f"Alert {alert_name} resolved for instance {instance}")
                return {"status": "success", "message": "Alert resolved"}, 200

            if not self._should_execute_playbook(alert_name, instance):
                return {"status": "skipped", "message": "Rate limited"}, 200

            future = self.executor.submit(self._execute_playbook, config.playbook, instance)
            return {"status": "accepted", "message": "Remediation scheduled"}, 202

        except Exception as e:
            self.logger.error(f"Error processing alert: {str(e)}", exc_info=True)
            return {"status": "error", "message": str(e)}, 500

    def _execute_playbook(self, playbook: str, instance: str) -> tuple[Dict[str, str], int]:
        try:
            if not os.path.exists(playbook):
                return {"status": "error", "message": f"Script not found: {playbook}"}, 404

            result = subprocess.run(
                ["powershell", "-ExecutionPolicy", "Bypass", "-File", playbook, "-TargetHost", instance],
                capture_output=True,
                text=True,
                check=True
            )

            self.logger.info(f"Script execution successful: {result.stdout}")
            return {"status": "success", "message": "Remediation executed successfully"}, 200

        except subprocess.CalledProcessError as e:
            self.logger.error(f"Script execution failed: {e.stderr}")
            return {"status": "error", "message": f"Remediation failed: {e.stderr}"}, 500

# Initialize Flask app with production configuration
app = Flask(__name__)
app.config['JSON_SORT_KEYS'] = False
app.config['JSONIFY_PRETTYPRINT_REGULAR'] = False

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('webhook.log'),
        logging.StreamHandler()
    ]
)

# Initialize alert handler with 4 worker threads
alert_handler = AlertHandler(max_workers=4)

@app.route("/webhook", methods=["POST"])
def webhook():
    try:
        data = request.json
        if not data or 'alerts' not in data or not data['alerts']:
            return jsonify({"status": "error", "message": "Invalid alert data"}), 400

        responses = []
        for alert in data['alerts']:
            response, status_code = alert_handler.handle_alert(alert)
            responses.append({
                "alert": alert.get('labels', {}).get('alertname'),
                "instance": alert.get('labels', {}).get('instance', 'unknown'),
                "response": response
            })

        return jsonify({"status": "success", "responses": responses}), 200

    except Exception as e:
        logging.error(f"Error processing webhook: {str(e)}", exc_info=True)
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route("/health", methods=["GET"])
def health_check():
    return jsonify({
        "status": "healthy",
        "configured_alerts": list(alert_handler.alert_configs.keys()),
        "active_workers": len(alert_handler.executor._threads)
    }), 200

if __name__ == "__main__":
    logging.info("Starting webhook server on port 5000")
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
