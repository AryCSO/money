@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM setup_money_env.bat
REM One-click setup for Docker Desktop + Docker Compose + Evolution API
REM Everything is created under C:\money\
REM ============================================================

set "RUN_MODE=%~1"
set "INPUT_MONEY_ROOT="
set "INPUT_NGROK_AUTHTOKEN="
set "INPUT_INSTALL_DOCKER="
set "INPUT_INSTALL_EVOLUTION="
set "INPUT_INSTALL_NGROK="
if /I "%RUN_MODE%"=="elevated" (
  set "INPUT_MONEY_ROOT=%~2"
  set "INPUT_NGROK_AUTHTOKEN=%~3"
  set "INPUT_INSTALL_DOCKER=%~4"
  set "INPUT_INSTALL_EVOLUTION=%~5"
  set "INPUT_INSTALL_NGROK=%~6"
) else (
  set "INPUT_MONEY_ROOT=%~1"
  set "INPUT_NGROK_AUTHTOKEN=%~2"
  set "INPUT_INSTALL_DOCKER=%~3"
  set "INPUT_INSTALL_EVOLUTION=%~4"
  set "INPUT_INSTALL_NGROK=%~5"
)

set "MONEY_ROOT=C:\money"
if defined INPUT_MONEY_ROOT set "MONEY_ROOT=%INPUT_MONEY_ROOT%"
set "MONEY_ROOT_DOCKER=%MONEY_ROOT:\=/%"

set "EVO_IMAGE=atendai/evolution-api:v2.2.3"
set "API_KEY=f0Y69k2b5yQWWtmLUs40UVtFWWBIhuWA"
set "API_URL=http://localhost:52062"

REM Cole aqui o token da sua conta ngrok:
REM https://dashboard.ngrok.com/get-started/your-authtoken
set "NGROK_AUTHTOKEN=COLE_SEU_TOKEN_NGROK_AQUI"
if defined INPUT_NGROK_AUTHTOKEN set "NGROK_AUTHTOKEN=%INPUT_NGROK_AUTHTOKEN%"

set "INSTALL_DOCKER=1"
set "INSTALL_EVOLUTION=1"
set "INSTALL_NGROK=1"
if defined INPUT_INSTALL_DOCKER set "INSTALL_DOCKER=%INPUT_INSTALL_DOCKER%"
if defined INPUT_INSTALL_EVOLUTION set "INSTALL_EVOLUTION=%INPUT_INSTALL_EVOLUTION%"
if defined INPUT_INSTALL_NGROK set "INSTALL_NGROK=%INPUT_INSTALL_NGROK%"

set "STACK_ROOT=%MONEY_ROOT%\evolution-api"
set "DATA_ROOT=%MONEY_ROOT%\evolution"
set "NGROK_ROOT=%MONEY_ROOT%\ngrok"
set "NGROK_BIN="
set "NGROK_CONFIG=%NGROK_ROOT%\ngrok.yml"
set "NGROK_TUNNEL_BAT=%MONEY_ROOT%\start_ngrok_50010.bat"
set "NGROK_HIDDEN_VBS=%MONEY_ROOT%\start_ngrok_hidden.vbs"
set "NGROK_LOG=%NGROK_ROOT%\ngrok.log"
set "NGROK_PUBLIC_URL="

echo.
echo [INFO] Iniciando setup do ambiente em %MONEY_ROOT%

REM ---- Elevation for install/start tasks ----
if /I not "%RUN_MODE%"=="elevated" (
  net session >nul 2>&1
  if errorlevel 1 (
    echo [INFO] Solicitando permissao de administrador...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -ArgumentList @('elevated','%MONEY_ROOT%','%NGROK_AUTHTOKEN%','%INSTALL_DOCKER%','%INSTALL_EVOLUTION%','%INSTALL_NGROK%') -Verb RunAs"
    exit /b
  )
)

REM ---- Create folder structure ----
if not exist "%MONEY_ROOT%" mkdir "%MONEY_ROOT%"
if not exist "%STACK_ROOT%" mkdir "%STACK_ROOT%"
if not exist "%DATA_ROOT%" mkdir "%DATA_ROOT%"
if not exist "%DATA_ROOT%\instances" mkdir "%DATA_ROOT%\instances"
if not exist "%DATA_ROOT%\store" mkdir "%DATA_ROOT%\store"
if not exist "%NGROK_ROOT%" mkdir "%NGROK_ROOT%"
copy /Y "%~f0" "%MONEY_ROOT%\setup_money_env.bat" >nul

echo [OK] Estrutura validada em %MONEY_ROOT%

if "%INSTALL_DOCKER%"=="1" (
  REM ---- Docker check / install ----
  where docker >nul 2>&1
  if errorlevel 1 (
    echo [WARN] Docker nao encontrado. Tentando instalar Docker Desktop via winget...
    where winget >nul 2>&1
    if errorlevel 1 (
      echo [ERRO] winget nao encontrado. Instale o Docker Desktop manualmente e execute novamente.
      goto :fail
    )

    winget install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements --silent
    if errorlevel 1 (
      echo [ERRO] Falha ao instalar Docker Desktop via winget.
      goto :fail
    )
    echo [OK] Docker Desktop instalado.
  ) else (
    echo [OK] Docker encontrado.
  )

  call :ensure_docker_running
  if errorlevel 1 goto :fail
) else (
  echo [INFO] Instalacao de Docker ignorada (opcional).
  if "%INSTALL_EVOLUTION%"=="1" (
    where docker >nul 2>&1
    if errorlevel 1 (
      echo [ERRO] Evolution foi selecionado, mas Docker nao esta instalado.
      echo [ERRO] Marque Docker no instalador ou instale Docker manualmente.
      goto :fail
    )
    call :ensure_docker_running
    if errorlevel 1 goto :fail
  )
)

if "%INSTALL_NGROK%"=="1" (
  REM ---- ngrok check / install ----
  call :ensure_ngrok_installed
  if errorlevel 1 (
    echo [WARN] Nao foi possivel instalar/configurar ngrok automaticamente.
  ) else (
    if /I not "%NGROK_AUTHTOKEN%"=="COLE_SEU_TOKEN_NGROK_AQUI" (
      call "%NGROK_BIN%" config add-authtoken "%NGROK_AUTHTOKEN%" >nul 2>&1
      if errorlevel 1 (
        echo [WARN] Falha ao aplicar o token do ngrok. Verifique NGROK_AUTHTOKEN no .bat.
      ) else (
        echo [OK] Token do ngrok aplicado.
      )
    ) else (
      echo [INFO] Preencha NGROK_AUTHTOKEN no setup_money_env.bat para autenticar no ngrok.
    )

    call :prepare_ngrok_scripts
  )
) else (
  echo [INFO] Instalacao de ngrok ignorada (opcional).
)

if "%INSTALL_EVOLUTION%"=="1" (
  REM ---- Docker Compose check ----
  set "COMPOSE_CMD="
  docker compose version >nul 2>&1
  if not errorlevel 1 set "COMPOSE_CMD=docker compose"

  if not defined COMPOSE_CMD (
    docker-compose version >nul 2>&1
    if not errorlevel 1 set "COMPOSE_CMD=docker-compose"
  )

  if not defined COMPOSE_CMD (
    echo [ERRO] Docker Compose nao encontrado.
    echo [ERRO] Atualize o Docker Desktop e tente novamente.
    goto :fail
  )

  echo [OK] Compose detectado: %COMPOSE_CMD%

  REM ---- Write .env if missing ----
  if not exist "%STACK_ROOT%\.env" (
    >"%STACK_ROOT%\.env" (
      echo AUTHENTICATION_TYPE=apikey
      echo AUTHENTICATION_API_KEY=%API_KEY%
      echo DEL_INSTANCE=false
    )
    echo [OK] Arquivo .env criado em %STACK_ROOT%
  ) else (
    echo [OK] Arquivo .env ja existe em %STACK_ROOT% (mantido sem alteracoes).
  )

  REM ---- Write docker-compose.yml if missing ----
  if not exist "%STACK_ROOT%\docker-compose.yml" (
    >"%STACK_ROOT%\docker-compose.yml" (
      echo services:
      echo   evolution-api:
      echo     container_name: evolution_api
      echo     image: %EVO_IMAGE%
      echo     restart: always
      echo     ports:
      echo       - "50010:8080"
      echo     env_file:
      echo       - .env
      echo     volumes:
      echo       - %MONEY_ROOT_DOCKER%/evolution/instances:/evolution/instances
      echo       - %MONEY_ROOT_DOCKER%/evolution/store:/evolution/store
    )
    echo [OK] docker-compose.yml criado em %STACK_ROOT%
  ) else (
    echo [OK] docker-compose.yml ja existe em %STACK_ROOT% (mantido sem alteracoes).
  )

  REM ---- Pull and start stack ----
  pushd "%STACK_ROOT%"
  echo [INFO] Subindo Evolution API...
  call %COMPOSE_CMD% up -d
  if errorlevel 1 (
    popd
    echo [ERRO] Falha ao subir os containers.
    goto :fail
  )
  popd

  REM ---- Basic health check ----
  echo [INFO] Verificando API em %API_URL% ...
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ok=$false; for($i=0; $i -lt 45; $i++){ try { $r=Invoke-RestMethod -Uri '%API_URL%/' -Headers @{ apikey='%API_KEY%' } -TimeoutSec 3; if($r.status -eq 200){$ok=$true; break} } catch {}; Start-Sleep -Seconds 2 }; if($ok){ exit 0 } else { exit 1 }"

  if errorlevel 1 (
    echo [WARN] A API pode ainda estar inicializando.
    echo [WARN] Confira os logs com:
    echo        cd /d "%STACK_ROOT%" ^&^& %COMPOSE_CMD% logs --tail=100
    goto :done
  )

  echo [OK] Evolution API pronta em %API_URL%
  echo [OK] Manager: %API_URL%/manager
  echo [OK] API Key configurada para seu app: %API_KEY%
) else (
  echo [INFO] Instalacao da Evolution API ignorada (opcional).
)

if "%INSTALL_NGROK%"=="1" if defined NGROK_BIN if /I not "%NGROK_AUTHTOKEN%"=="COLE_SEU_TOKEN_NGROK_AQUI" (
  call :start_ngrok_tunnel_hidden
)

:done
echo.
echo [INFO] Setup finalizado.
if defined NGROK_PUBLIC_URL (
  echo [OK] URL publica ngrok: %NGROK_PUBLIC_URL%
) else (
  echo [INFO] Para iniciar manualmente o tunnel: %NGROK_TUNNEL_BAT%
)
exit /b 0

:fail
echo.
echo [FALHA] Nao foi possivel concluir o setup.
echo [FALHA] Corrija o erro acima e execute novamente este .bat.
exit /b 1

:ensure_ngrok_installed
if exist "%NGROK_ROOT%\ngrok.exe" (
  set "NGROK_BIN=%NGROK_ROOT%\ngrok.exe"
  echo [OK] ngrok local encontrado em %NGROK_ROOT%.
  exit /b 0
)

where ngrok >nul 2>&1
if not errorlevel 1 (
  for /f "delims=" %%I in ('where ngrok') do (
    set "NGROK_BIN=%%I"
    goto :ngrok_ready
  )
)

echo [INFO] ngrok nao encontrado. Baixando para %NGROK_ROOT%...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Invoke-WebRequest -Uri 'https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip' -OutFile '%NGROK_ROOT%\ngrok.zip'"
if errorlevel 1 goto :ngrok_try_winget

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Expand-Archive -Path '%NGROK_ROOT%\ngrok.zip' -DestinationPath '%NGROK_ROOT%' -Force"
if errorlevel 1 goto :ngrok_try_winget

if exist "%NGROK_ROOT%\ngrok.exe" (
  set "NGROK_BIN=%NGROK_ROOT%\ngrok.exe"
  goto :ngrok_ready
)

:ngrok_try_winget
echo [INFO] Tentando instalar ngrok via winget...
where winget >nul 2>&1
if errorlevel 1 (
  echo [ERRO] winget nao encontrado para instalar ngrok.
  exit /b 1
)

winget install -e --id Ngrok.Ngrok --accept-package-agreements --accept-source-agreements --silent
if errorlevel 1 (
  echo [ERRO] Falha ao instalar ngrok via winget.
  exit /b 1
)

where ngrok >nul 2>&1
if errorlevel 1 (
  echo [ERRO] ngrok foi instalado, mas nao foi encontrado no PATH.
  exit /b 1
)

for /f "delims=" %%I in ('where ngrok') do (
  set "NGROK_BIN=%%I"
  goto :ngrok_ready
)

:ngrok_ready
echo [OK] ngrok pronto: !NGROK_BIN!
exit /b 0

:prepare_ngrok_scripts
>"%NGROK_CONFIG%" (
  echo version: "2"
  echo authtoken: %NGROK_AUTHTOKEN%
  echo web_addr: 127.0.0.1:4040
  echo tunnels:
  echo   money-api:
  echo     proto: http
  echo     addr: 50010
  echo     inspect: true
)

>"%NGROK_TUNNEL_BAT%" (
  echo @echo off
  echo setlocal
  echo taskkill /F /IM ngrok.exe ^>nul 2^>^&1
  echo timeout /t 1 /nobreak ^>nul
  echo "%NGROK_BIN%" start --all --config "%NGROK_CONFIG%" --log=stdout 1^>"%NGROK_LOG%" 2^>^&1
)

>"%NGROK_HIDDEN_VBS%" (
  echo Set WshShell = CreateObject("WScript.Shell"^)
  echo WshShell.Run """" ^& "%NGROK_TUNNEL_BAT%" ^& """", 0, False
)

echo [OK] Scripts do ngrok prontos:
echo      %NGROK_TUNNEL_BAT%
echo      %NGROK_HIDDEN_VBS%
exit /b 0

:start_ngrok_tunnel_hidden
echo [INFO] Iniciando tunnel ngrok em segundo plano...
wscript //nologo "%NGROK_HIDDEN_VBS%" >nul 2>&1
if errorlevel 1 (
  echo [WARN] Nao foi possivel iniciar o ngrok em modo oculto.
  exit /b 0
)

for /l %%A in (1,1,20) do (
  for /f "delims=" %%U in ('powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='SilentlyContinue'; $t=Invoke-RestMethod 'http://127.0.0.1:4040/api/tunnels'; if($t.tunnels.Count -gt 0){$t.tunnels[0].public_url}"') do (
      set "NGROK_PUBLIC_URL=%%U"
  )
  if defined NGROK_PUBLIC_URL goto :ngrok_started
  timeout /t 1 /nobreak >nul
)

echo [WARN] Tunnel iniciado, mas URL publica nao foi detectada ainda.
exit /b 0

:ngrok_started
echo [OK] Tunnel ngrok iniciado com sucesso.
exit /b 0

:ensure_docker_running
docker info >nul 2>&1
if not errorlevel 1 (
  echo [OK] Docker Engine ja esta ativo.
  exit /b 0
)

if exist "%ProgramFiles%\Docker\Docker\Docker Desktop.exe" (
  echo [INFO] Iniciando Docker Desktop...
  start "" "%ProgramFiles%\Docker\Docker\Docker Desktop.exe"
) else if exist "%ProgramFiles(x86)%\Docker\Docker\Docker Desktop.exe" (
  echo [INFO] Iniciando Docker Desktop...
  start "" "%ProgramFiles(x86)%\Docker\Docker\Docker Desktop.exe"
) else (
  echo [ERRO] Nao encontrei o executavel do Docker Desktop.
  exit /b 1
)

set /a WAIT_COUNT=0
:wait_docker
docker info >nul 2>&1
if not errorlevel 1 (
  echo [OK] Docker Engine ativo.
  exit /b 0
)

set /a WAIT_COUNT+=1
if !WAIT_COUNT! GEQ 90 (
  echo [ERRO] Docker Engine nao ficou pronto a tempo.
  echo [ERRO] Abra o Docker Desktop manualmente e execute novamente.
  exit /b 1
)

timeout /t 2 /nobreak >nul
goto :wait_docker
