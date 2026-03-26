@echo off
setlocal EnableExtensions

set "INSTALL_DIR=C:\money"
set "INSTALL_EXE=%INSTALL_DIR%\docker.exe"
set "DOWNLOAD_URL=https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip"

echo ===========================================
echo NGROK AUTO SETUP - PORTA 50010 (Windows)
echo ===========================================
echo.

if exist "%INSTALL_EXE%" (
  echo Encontrado: %INSTALL_EXE%
  echo Arquivo ja existe. Nao prosseguindo com instalacao/configuracao.
  exit /b 0
)

echo Verificando ngrok no PATH...
set "NGROK_FOUND="
for /f "delims=" %%I in ('where ngrok 2^>nul') do (
  if not defined NGROK_FOUND set "NGROK_FOUND=%%I"
)

if not defined NGROK_FOUND (
  echo ngrok nao encontrado. Tentando instalar...

  where winget >nul 2>&1
  if %errorlevel% equ 0 (
    winget install --id Ngrok.Ngrok -e --accept-package-agreements --accept-source-agreements
  )

  set "NGROK_FOUND="
  for /f "delims=" %%I in ('where ngrok 2^>nul') do (
    if not defined NGROK_FOUND set "NGROK_FOUND=%%I"
  )

  if not defined NGROK_FOUND (
    echo Instalacao via winget nao resolveu. Tentando download direto...
    if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$ErrorActionPreference='Stop';" ^
      "$zip=Join-Path $env:TEMP 'ngrok_win.zip';" ^
      "$tmp=Join-Path $env:TEMP ('ngrok_unpack_' + [guid]::NewGuid().ToString('N'));" ^
      "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile $zip;" ^
      "Expand-Archive -Path $zip -DestinationPath $tmp -Force;" ^
      "Move-Item -Path (Join-Path $tmp 'ngrok.exe') -Destination '%INSTALL_EXE%' -Force;" ^
      "Remove-Item $zip -Force;" ^
      "Remove-Item $tmp -Recurse -Force;"

    if %errorlevel% neq 0 (
      echo Falha ao baixar/instalar ngrok.
      exit /b 1
    )

    set "NGROK_CMD=%INSTALL_EXE%"
    goto :configured_binary
  )
)

if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
copy /Y "%NGROK_FOUND%" "%INSTALL_EXE%" >nul
if %errorlevel% neq 0 (
  echo Falha ao copiar ngrok para %INSTALL_EXE%.
  exit /b 1
)

set "NGROK_CMD=%INSTALL_EXE%"

:configured_binary
if not exist "%NGROK_CMD%" (
  echo Binario ngrok nao encontrado em %NGROK_CMD%.
  exit /b 1
)

echo.
set /p NGROK_LOGIN_LINK=Cole o link do ngrok que voce pegou manualmente no login (ou Enter para pular): 
if not "%NGROK_LOGIN_LINK%"=="" (
  start "" "%NGROK_LOGIN_LINK%"
)

echo.
set /p NGROK_TOKEN=Cole seu authtoken do ngrok (ou Enter se ja configurado): 
if not "%NGROK_TOKEN%"=="" (
  "%NGROK_CMD%" config add-authtoken "%NGROK_TOKEN%"
  if %errorlevel% neq 0 (
    echo Falha ao configurar o authtoken.
    exit /b 1
  )
)

echo.
echo Iniciando ngrok em segundo plano (equivalente bandeja)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%NGROK_CMD%' -ArgumentList @('http','50010') -WindowStyle Hidden"
if %errorlevel% neq 0 (
  echo Falha ao iniciar ngrok em segundo plano.
  exit /b 1
)

echo ngrok iniciado em segundo plano na porta 50010.
echo Abra http://127.0.0.1:4040 para ver o link publico.

endlocal
