@echo off
setlocal
chcp 65001 >nul
set "DOTNET_CLI_TELEMETRY_OPTOUT=1"

set "DOTNET_EXE=%USERPROFILE%\.dotnet\dotnet.exe"
if not exist "%DOTNET_EXE%" (
    set "DOTNET_EXE=dotnet"
)

echo Starting CurveNet Web...
start "" http://localhost:5000
"%DOTNET_EXE%" run --project "%~dp0web\CurveNet.Web\CurveNet.Web.csproj" --urls "http://0.0.0.0:5000"
pause
