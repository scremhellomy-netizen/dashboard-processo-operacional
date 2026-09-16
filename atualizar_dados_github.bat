@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0atualizar_dados_github.ps1" %*
pause
