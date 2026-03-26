param(
  [switch]$ForceReinstall,
  [string]$SourceRoot = 'C:\money\firebird5_x64_source'
)

$ErrorActionPreference = 'Stop'

$sourceCandidates = @($SourceRoot)
$targetRoot = 'C:\money\firebird5'
$moneyRoot = 'C:\money'
$serviceInstance = 'Money'
$serviceName = "FirebirdServer$serviceInstance"
$firebirdPort = 9255
$appUser = 'money'
$appPassword = '101812Ar@'
$moneyDbPath = 'C:\money\money.fdb'
$tempSqlRoot = 'C:\money\.firebird_setup'

function Require-Administrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    throw 'Execute este script como Administrador.'
  }
}

function Write-MoneyFirebirdConfig {
  param([string]$Path, [int]$Port)

  @"
RootDirectory = .
RemoteBindAddress = 127.0.0.1
RemoteServicePort = $Port
DataTypeCompatibility = 3.0
WireCompression = false
DefaultDbCachePages = 8192
ConnectionIdleTimeout = 0
AuthServer = Srp, Srp256
AuthClient = Srp, Srp256
UserManager = Srp
DatabaseAccess = Restrict C:\money
UDFAccess = None
RemoteFileOpenAbility = None
ServerMode = Super
"@ | Set-Content -LiteralPath $Path -Encoding ASCII
}

function Get-PeMachineType {
  param([Parameter(Mandatory = $true)][string]$Path)

  $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
  try {
    $reader = [System.IO.BinaryReader]::new($stream)
    $stream.Seek(0x3C, [System.IO.SeekOrigin]::Begin) | Out-Null
    $peHeaderOffset = $reader.ReadInt32()
    $stream.Seek($peHeaderOffset + 4, [System.IO.SeekOrigin]::Begin) | Out-Null
    return $reader.ReadUInt16()
  } finally {
    $reader.Close()
    $stream.Close()
  }
}

function Test-IsX64FirebirdClient {
  param([Parameter(Mandatory = $true)][string]$Root)

  $clientPath = Join-Path $Root 'fbclient.dll'
  if (-not (Test-Path -LiteralPath $clientPath)) {
    return $false
  }

  return (Get-PeMachineType -Path $clientPath) -eq 0x8664
}

function Invoke-IsqlScript {
  param(
    [Parameter(Mandatory = $true)][string]$Sql,
    [string[]]$Arguments = @()
  )

  New-Item -ItemType Directory -Path $tempSqlRoot -Force | Out-Null
  $scriptPath = Join-Path $tempSqlRoot "$([Guid]::NewGuid().ToString('N')).sql"

  try {
    $Sql | Set-Content -LiteralPath $scriptPath -Encoding ASCII
    & (Join-Path $targetRoot 'isql.exe') @Arguments -i $scriptPath
    if ($LASTEXITCODE -ne 0) {
      throw "isql.exe retornou codigo $LASTEXITCODE."
    }
  } finally {
    Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue
  }
}

Require-Administrator

$sourceRoot = $null
foreach ($candidate in $sourceCandidates) {
  if (Test-IsX64FirebirdClient -Root $candidate) {
    $sourceRoot = $candidate
    break
  }
}

if (-not $sourceRoot) {
  throw "Nenhuma base x64 do Firebird 5 foi encontrada em $($sourceCandidates -join ', ')."
}

New-Item -ItemType Directory -Path $moneyRoot -Force | Out-Null

$serviceExists = [bool](Get-Service -Name $serviceName -ErrorAction SilentlyContinue)
if ($ForceReinstall -and $serviceExists) {
  Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath (Join-Path $targetRoot 'instsvc.exe')) {
    & (Join-Path $targetRoot 'instsvc.exe') remove -n $serviceInstance | Out-Null
  }
  $serviceExists = $false
}

if ($ForceReinstall -and (Test-Path -LiteralPath $targetRoot)) {
  Remove-Item -LiteralPath $targetRoot -Recurse -Force
}

if ($ForceReinstall -and (Test-Path -LiteralPath $moneyDbPath)) {
  Remove-Item -LiteralPath $moneyDbPath -Force
}

$targetWasMissing = -not (Test-Path -LiteralPath $targetRoot)
if ($targetWasMissing) {
  Copy-Item -LiteralPath $sourceRoot -Destination $targetRoot -Recurse
}

$securityDbSource = Join-Path $sourceRoot 'SECURITY5.FDB'
if (-not (Test-Path -LiteralPath $securityDbSource)) {
  throw "Arquivo SECURITY5.FDB nao encontrado em $sourceRoot."
}
Copy-Item -LiteralPath $securityDbSource -Destination (Join-Path $targetRoot 'security5.fdb') -Force

Write-MoneyFirebirdConfig -Path (Join-Path $targetRoot 'firebird.conf') -Port $firebirdPort

if ($serviceExists) {
  Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
} else {
  & (Join-Path $targetRoot 'instreg.exe') install -n $serviceInstance | Out-Null
  & (Join-Path $targetRoot 'instsvc.exe') install -n $serviceInstance | Out-Null
}

Invoke-IsqlScript `
  -Sql @"
CREATE OR ALTER USER SYSDBA PASSWORD 'masterkey';
QUIT;
"@ `
  -Arguments @('-user', 'SYSDBA', 'employee')

if (-not (Test-Path -LiteralPath $moneyDbPath)) {
  Invoke-IsqlScript -Sql @"
CREATE DATABASE 'C:/money/money.fdb' USER 'SYSDBA' PASSWORD 'masterkey';
QUIT;
"@ -Arguments @('-user', 'SYSDBA')
}

& (Join-Path $targetRoot 'instsvc.exe') start -n $serviceInstance | Out-Null
Start-Sleep -Seconds 2

Invoke-IsqlScript -Sql @"
CONNECT 'localhost/$firebirdPort:C:/money/money.fdb' USER SYSDBA PASSWORD 'masterkey';
CREATE OR ALTER USER $appUser PASSWORD '$appPassword';
GRANT DEFAULT RDB`$ADMIN TO USER $appUser;
COMMIT;
QUIT;
"@

Write-Output "Firebird Money configurado em $targetRoot"
Write-Output "Servico: $serviceName"
Write-Output "Porta: $firebirdPort"
Write-Output "Usuario do app: $appUser"
