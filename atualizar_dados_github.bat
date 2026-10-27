@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
echo ============================================================
echo  DASHBOARD DE PROCESSO OPERACIONAL - PUBLICACAO DAS BASES
echo ============================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0atualizar_dados_github.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
    echo FALHA: verifique erro_atualizacao.log nesta pasta.
) else (
    echo Processo finalizado. Aguarde a propagacao do GitHub Pages.
)
echo.
pause
exit /b %RC%
