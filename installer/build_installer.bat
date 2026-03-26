@echo off
setlocal EnableExtensions

set "ROOT_DIR=%~dp0.."
for %%I in ("%ROOT_DIR%") do set "ROOT_DIR=%%~fI"
set "ISS_FILE=%~dp0money_setup.iss"
set "APP_BUILD_DIR_DEBUG=%ROOT_DIR%\build\windows\x64\runner\Debug"
set "APP_BUILD_DIR_RELEASE=%ROOT_DIR%\build\windows\x64\runner\Release"
set "ISCC_EXE="

if exist "%APP_BUILD_DIR_RELEASE%\money.exe" (
  set "APP_BUILD_DIR=%APP_BUILD_DIR_RELEASE%"
) else (
  set "APP_BUILD_DIR=%APP_BUILD_DIR_DEBUG%"
)

if not exist "%APP_BUILD_DIR%\money.exe" (
  echo [ERRO] Nao encontrei o executavel do app para empacotar.
  echo [ERRO] Caminho esperado: %APP_BUILD_DIR%\money.exe
  echo [ERRO] Gere o build Windows primeiro e rode novamente.
  exit /b 1
)

if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
  set "ISCC_EXE=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
) else if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
  set "ISCC_EXE=C:\Program Files\Inno Setup 6\ISCC.exe"
)

if not defined ISCC_EXE (
  echo [INFO] Inno Setup nao encontrado. Tentando instalar via winget...
  where winget >nul 2>&1
  if errorlevel 1 (
    echo [ERRO] winget nao encontrado. Instale Inno Setup 6 e tente novamente.
    exit /b 1
  )

  winget install -e --id JRSoftware.InnoSetup --accept-package-agreements --accept-source-agreements --silent
  if errorlevel 1 (
    echo [ERRO] Falha ao instalar Inno Setup via winget.
    exit /b 1
  )

  if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
    set "ISCC_EXE=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
  ) else if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
    set "ISCC_EXE=C:\Program Files\Inno Setup 6\ISCC.exe"
  )
)

if not defined ISCC_EXE (
  echo [ERRO] ISCC.exe nao encontrado mesmo apos tentativa de instalacao.
  exit /b 1
)

echo [INFO] Compilando instalador...
"%ISCC_EXE%" "/DAPP_BUILD_DIR=%APP_BUILD_DIR%" "%ISS_FILE%"
if errorlevel 1 (
  echo [ERRO] Falha ao compilar instalador.
  exit /b 1
)

echo [OK] Instalador gerado em: %ROOT_DIR%\dist
exit /b 0
