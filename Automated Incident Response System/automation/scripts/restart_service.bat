@echo off
echo Restarting service...
net stop "ServiceName"
net start "ServiceName"
