@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
echo Atualizacao das quatro bases e publicacao no GitHub Pages
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0atualizar_dados_github.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
 echo FALHA: consulte erro_atualizacao.log nesta pasta.
) else (
 echo Processo finalizado.
)
pause
exit /b %RC%
