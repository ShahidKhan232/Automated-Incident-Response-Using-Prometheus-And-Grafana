@echo off
curl -X POST -H "Content-Type: application/json" -d "{\"alerts\": [{\"labels\": {\"alertname\": \"HighCPUUsage\"}}]}" http://localhost:5000/webhook
