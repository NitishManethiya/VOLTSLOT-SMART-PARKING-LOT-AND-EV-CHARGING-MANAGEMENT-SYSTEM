@echo off
title VoltSlot DBMS Dashboard
echo ===================================================
echo   Starting VoltSlot Smart Parking & EV Dashboard
echo   Opening http://127.0.0.1:5000 in your browser...
echo ===================================================
cd /d "%~dp0"
start http://127.0.0.1:5000
python app.py
pause
