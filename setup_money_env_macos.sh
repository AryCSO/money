#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# setup_money_env_macos.sh
# One-click setup for Docker Desktop + Evolution API on macOS
# Everything is created under ~/money/
# ============================================================

# ---- Configuracoes ----
MONEY_ROOT="${1:-$HOME/money}"
NGROK_AUTHTOKEN="${2:-COLE_SEU_TOKEN_NGROK_AQUI}"
INSTALL_DOCKER="${3:-1}"
INSTALL_EVOLUTION="${4:-1}"
INSTALL_NGROK="${5:-1}"
BUILD_APP="${6:-1}"

MONEY_REPO="https://github.com/AryCSO/money.git"
MONEY_APP_NAME="Money"

EVO_IMAGE="atendai/evolution-api:v2.2.3"
API_KEY="f0Y69k2b5yQWWtmLUs40UVtFWWBIhuWA"
API_PORT=50010
API_URL="http://localhost:${API_PORT}"

STACK_ROOT="${MONEY_ROOT}/evolution-api"
DATA_ROOT="${MONEY_ROOT}/evolution"
NGROK_ROOT="${MONEY_ROOT}/ngrok"
NGROK_BIN=""
NGROK_CONFIG="${NGROK_ROOT}/ngrok.yml"
NGROK_LOG="${NGROK_ROOT}/ngrok.log"
NGROK_PUBLIC_URL=""

# ---- Cores ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
erro()  { echo -e "${RED}[ERRO]${NC} $*"; }
fail()  { erro "$*"; echo; erro "Corrija o erro acima e execute novamente."; exit 1; }

# ---- Verificar macOS ----
if [[ "$(uname)" != "Darwin" ]]; then
  fail "Este script e exclusivo para macOS. No Windows, use setup_money_env.bat."
fi

echo
info "Iniciando setup do ambiente em ${MONEY_ROOT}"

# ---- Criar estrutura de pastas ----
mkdir -p "${MONEY_ROOT}"
mkdir -p "${STACK_ROOT}"
mkdir -p "${DATA_ROOT}/instances"
mkdir -p "${DATA_ROOT}/store"
mkdir -p "${NGROK_ROOT}"

ok "Estrutura de pastas criada em ${MONEY_ROOT}"

# ============================================================
# HOMEBREW (necessario para instalar Docker e ngrok)
# ============================================================
ensure_homebrew() {
  if command -v brew &>/dev/null; then
    ok "Homebrew encontrado."
    return 0
  fi

  info "Homebrew nao encontrado. Instalando..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Adicionar ao PATH da sessao atual (Apple Silicon vs Intel)
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  if ! command -v brew &>/dev/null; then
    fail "Homebrew foi instalado, mas nao foi encontrado no PATH. Feche e reabra o terminal e tente novamente."
  fi

  ok "Homebrew instalado com sucesso."
}

# ============================================================
# DOCKER
# ============================================================
ensure_docker_installed() {
  if command -v docker &>/dev/null; then
    ok "Docker encontrado."
    return 0
  fi

  info "Docker nao encontrado. Instalando Docker Desktop via Homebrew..."
  ensure_homebrew
  brew install --cask docker

  if ! command -v docker &>/dev/null; then
    # Docker Desktop instala em /usr/local/bin/docker via symlink
    # mas pode precisar abrir o app primeiro
    if [[ -d "/Applications/Docker.app" ]]; then
      info "Abrindo Docker Desktop pela primeira vez..."
      open -a Docker
      sleep 5
    fi
  fi

  if ! command -v docker &>/dev/null; then
    fail "Docker foi instalado, mas o comando 'docker' nao esta no PATH. Abra o Docker Desktop manualmente e tente novamente."
  fi

  ok "Docker Desktop instalado."
}

ensure_docker_running() {
  if docker info &>/dev/null; then
    ok "Docker Engine ativo."
    return 0
  fi

  info "Docker Engine nao esta rodando. Iniciando Docker Desktop..."

  if [[ -d "/Applications/Docker.app" ]]; then
    open -a Docker
  else
    fail "Docker Desktop nao encontrado em /Applications/Docker.app. Instale manualmente."
  fi

  local wait_count=0
  local max_wait=90
  while ! docker info &>/dev/null; do
    wait_count=$((wait_count + 1))
    if [[ ${wait_count} -ge ${max_wait} ]]; then
      fail "Docker Engine nao ficou pronto em ${max_wait} tentativas. Abra o Docker Desktop manualmente e execute novamente."
    fi
    sleep 2
  done

  ok "Docker Engine ativo."
}

# ============================================================
# NGROK
# ============================================================
ensure_ngrok_installed() {
  # Verificar ngrok local na pasta do Money
  if [[ -f "${NGROK_ROOT}/ngrok" ]]; then
    NGROK_BIN="${NGROK_ROOT}/ngrok"
    ok "ngrok local encontrado em ${NGROK_ROOT}."
    return 0
  fi

  # Verificar ngrok no PATH
  if command -v ngrok &>/dev/null; then
    NGROK_BIN="$(command -v ngrok)"
    ok "ngrok encontrado: ${NGROK_BIN}"
    return 0
  fi

  info "ngrok nao encontrado. Instalando via Homebrew..."
  ensure_homebrew
  brew install ngrok/ngrok/ngrok 2>/dev/null || brew install --cask ngrok 2>/dev/null || true

  if command -v ngrok &>/dev/null; then
    NGROK_BIN="$(command -v ngrok)"
    ok "ngrok instalado: ${NGROK_BIN}"
    return 0
  fi

  # Fallback: download direto
  info "Tentando download direto do ngrok..."
  local arch
  arch="$(uname -m)"
  local ngrok_url=""
  if [[ "${arch}" == "arm64" ]]; then
    ngrok_url="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip"
  else
    ngrok_url="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip"
  fi

  curl -fsSL "${ngrok_url}" -o "${NGROK_ROOT}/ngrok.zip"
  unzip -o "${NGROK_ROOT}/ngrok.zip" -d "${NGROK_ROOT}" >/dev/null
  rm -f "${NGROK_ROOT}/ngrok.zip"
  chmod +x "${NGROK_ROOT}/ngrok"

  if [[ -f "${NGROK_ROOT}/ngrok" ]]; then
    NGROK_BIN="${NGROK_ROOT}/ngrok"
    ok "ngrok baixado para ${NGROK_ROOT}"
    return 0
  fi

  warn "Nao foi possivel instalar o ngrok automaticamente."
  return 1
}

prepare_ngrok_scripts() {
  # ngrok config
  cat > "${NGROK_CONFIG}" <<NGROKEOF
version: "2"
authtoken: ${NGROK_AUTHTOKEN}
web_addr: 127.0.0.1:4040
tunnels:
  money-api:
    proto: http
    addr: ${API_PORT}
    inspect: true
NGROKEOF

  # Script para iniciar o tunnel
  cat > "${MONEY_ROOT}/start_ngrok.sh" <<STARTEOF
#!/usr/bin/env bash
# Mata qualquer ngrok rodando
pkill -f ngrok 2>/dev/null || true
sleep 1
"${NGROK_BIN}" start --all --config "${NGROK_CONFIG}" --log=stdout > "${NGROK_LOG}" 2>&1 &
echo "ngrok iniciado em segundo plano. Log em: ${NGROK_LOG}"
STARTEOF
  chmod +x "${MONEY_ROOT}/start_ngrok.sh"

  ok "Scripts do ngrok prontos:"
  info "  ${MONEY_ROOT}/start_ngrok.sh"
}

start_ngrok_tunnel() {
  info "Iniciando tunnel ngrok em segundo plano..."
  pkill -f ngrok 2>/dev/null || true
  sleep 1
  nohup "${NGROK_BIN}" start --all --config "${NGROK_CONFIG}" --log=stdout > "${NGROK_LOG}" 2>&1 &

  local attempt=0
  while [[ ${attempt} -lt 20 ]]; do
    NGROK_PUBLIC_URL="$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | python3 -c "import sys,json; t=json.load(sys.stdin); print(t['tunnels'][0]['public_url'] if t.get('tunnels') else '')" 2>/dev/null || true)"
    if [[ -n "${NGROK_PUBLIC_URL}" ]]; then
      ok "Tunnel ngrok iniciado."
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 1
  done

  warn "Tunnel iniciado, mas URL publica nao foi detectada ainda."
  return 0
}

# ============================================================
# GIT
# ============================================================
ensure_git() {
  if command -v git &>/dev/null; then
    ok "Git encontrado."
    return 0
  fi

  info "Git nao encontrado. Instalando via Xcode Command Line Tools..."
  xcode-select --install 2>/dev/null || true

  # Esperar ate o git aparecer (o usuario precisa aceitar o dialog do Xcode)
  local wait=0
  while ! command -v git &>/dev/null; do
    wait=$((wait + 1))
    if [[ ${wait} -ge 120 ]]; then
      fail "Git nao foi instalado. Aceite a instalacao do Xcode Command Line Tools e tente novamente."
    fi
    sleep 2
  done

  ok "Git instalado."
}

# ============================================================
# FLUTTER SDK
# ============================================================
ensure_flutter() {
  if command -v flutter &>/dev/null; then
    ok "Flutter encontrado: $(flutter --version 2>/dev/null | head -1)"
    return 0
  fi

  # Verificar se ja foi instalado pelo script anteriormente
  if [[ -f "${MONEY_ROOT}/flutter/bin/flutter" ]]; then
    export PATH="${MONEY_ROOT}/flutter/bin:${PATH}"
    ok "Flutter encontrado em ${MONEY_ROOT}/flutter"
    return 0
  fi

  info "Flutter nao encontrado. Instalando..."
  ensure_homebrew

  # Tentar via Homebrew primeiro (mais limpo)
  if brew install --cask flutter 2>/dev/null; then
    # Homebrew coloca em /opt/homebrew/Caskroom/flutter ou /usr/local/Caskroom/flutter
    # e cria symlinks automaticamente
    if command -v flutter &>/dev/null; then
      ok "Flutter instalado via Homebrew."
      return 0
    fi
  fi

  # Fallback: clone do repo oficial
  info "Instalando Flutter via clone direto..."
  ensure_git
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "${MONEY_ROOT}/flutter"
  export PATH="${MONEY_ROOT}/flutter/bin:${PATH}"

  if ! command -v flutter &>/dev/null; then
    fail "Flutter nao encontrado no PATH apos instalacao."
  fi

  ok "Flutter instalado em ${MONEY_ROOT}/flutter"
}

# ============================================================
# FIREBIRD (macOS — via Docker)
# ============================================================
ensure_firebird_docker() {
  info "Configurando Firebird 5 via Docker..."

  # Verificar se o container ja existe e esta rodando
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^money_firebird$"; then
    ok "Container Firebird ja esta rodando."
    return 0
  fi

  # Se existe mas parado, iniciar
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^money_firebird$"; then
    info "Container Firebird existe mas esta parado. Iniciando..."
    docker start money_firebird
    ok "Container Firebird iniciado."
    return 0
  fi

  # Criar o container
  info "Criando container Firebird 5..."
  mkdir -p "${MONEY_ROOT}/firebird/data"

  docker run -d \
    --name money_firebird \
    --restart always \
    -p 9255:3050 \
    -e FIREBIRD_DATABASE=money.fdb \
    -e FIREBIRD_USER=money \
    -e "FIREBIRD_PASSWORD=101812Ar@" \
    -e ISC_PASSWORD=masterkey \
    -v "${MONEY_ROOT}/firebird/data:/firebird/data" \
    jacobalberty/firebird:v5 \
    || fail "Falha ao criar container Firebird."

  # Esperar o Firebird ficar pronto
  info "Esperando Firebird inicializar..."
  local wait=0
  while ! docker exec money_firebird isql-fb -q -i /dev/null localhost:money.fdb -u money -p '101812Ar@' &>/dev/null; do
    wait=$((wait + 1))
    if [[ ${wait} -ge 30 ]]; then
      warn "Firebird pode nao estar pronto ainda. O app vai tentar conectar na primeira execucao."
      return 0
    fi
    sleep 2
  done

  ok "Firebird 5 rodando na porta 9255."
}

# ============================================================
# BUILD DO APP MONEY (macOS nativo .app)
# ============================================================
build_money_app() {
  ensure_git
  ensure_flutter

  local source_dir="${MONEY_ROOT}/money-source"
  local app_bundle="${MONEY_ROOT}/${MONEY_APP_NAME}.app"

  # Clonar ou atualizar o repositorio
  if [[ -d "${source_dir}/.git" ]]; then
    info "Atualizando codigo-fonte do Money..."
    (cd "${source_dir}" && git pull --ff-only 2>/dev/null) || warn "Nao foi possivel atualizar. Usando versao existente."
  else
    info "Clonando repositorio do Money..."
    rm -rf "${source_dir}"
    git clone "${MONEY_REPO}" "${source_dir}" || fail "Falha ao clonar repositorio."
  fi

  ok "Codigo-fonte pronto em ${source_dir}"

  # Verificar pre-requisitos do Flutter para macOS
  info "Verificando ambiente Flutter..."
  flutter config --enable-macos-desktop 2>/dev/null || true
  (cd "${source_dir}" && flutter pub get) || fail "Falha ao baixar dependencias Flutter."

  # Copiar fbclient (Firebird) se disponivel
  # No macOS via Docker, o fbclient nao e necessario localmente —
  # a conexao ao Firebird e via TCP (container Docker na porta 9255)

  # Build release
  info "Compilando Money para macOS (isso pode levar alguns minutos)..."
  (cd "${source_dir}" && flutter build macos --release) || fail "Falha ao compilar o app."

  # O build gera em build/macos/Build/Products/Release/money.app
  local built_app="${source_dir}/build/macos/Build/Products/Release/money.app"
  if [[ ! -d "${built_app}" ]]; then
    # Tentar path alternativo (varia com versao do Flutter)
    built_app="$(find "${source_dir}/build/macos" -name "*.app" -type d 2>/dev/null | head -1)"
  fi

  if [[ -z "${built_app}" || ! -d "${built_app}" ]]; then
    fail "Build concluido mas o .app nao foi encontrado em ${source_dir}/build/macos/"
  fi

  # Copiar para ~/money/Money.app
  info "Instalando app..."
  rm -rf "${app_bundle}"
  cp -R "${built_app}" "${app_bundle}"

  # Tambem copiar para /Applications se o usuario quiser
  if [[ -d "/Applications" ]]; then
    info "Copiando para /Applications/${MONEY_APP_NAME}.app..."
    rm -rf "/Applications/${MONEY_APP_NAME}.app"
    cp -R "${built_app}" "/Applications/${MONEY_APP_NAME}.app" 2>/dev/null || warn "Sem permissao para copiar para /Applications. Use sudo se desejar."
  fi

  ok "App compilado: ${app_bundle}"
  if [[ -d "/Applications/${MONEY_APP_NAME}.app" ]]; then
    ok "Tambem instalado em /Applications/${MONEY_APP_NAME}.app"
  fi

  # Criar script de atalho para abrir
  cat > "${MONEY_ROOT}/abrir_money.sh" <<'OPENEOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -d "/Applications/Money.app" ]]; then
  open -a "/Applications/Money.app"
elif [[ -d "${SCRIPT_DIR}/Money.app" ]]; then
  open "${SCRIPT_DIR}/Money.app"
else
  echo "Money.app nao encontrado."
  exit 1
fi
OPENEOF
  chmod +x "${MONEY_ROOT}/abrir_money.sh"

  ok "Atalho criado: ${MONEY_ROOT}/abrir_money.sh"
}

# ============================================================
# EXECUCAO PRINCIPAL
# ============================================================

# ---- Docker ----
if [[ "${INSTALL_DOCKER}" == "1" ]]; then
  ensure_docker_installed
  ensure_docker_running
else
  info "Instalacao de Docker ignorada (opcional)."
  if [[ "${INSTALL_EVOLUTION}" == "1" ]]; then
    if ! command -v docker &>/dev/null; then
      fail "Evolution foi selecionado, mas Docker nao esta instalado."
    fi
    ensure_docker_running
  fi
fi

# ---- ngrok ----
if [[ "${INSTALL_NGROK}" == "1" ]]; then
  if ensure_ngrok_installed; then
    if [[ "${NGROK_AUTHTOKEN}" != "COLE_SEU_TOKEN_NGROK_AQUI" ]]; then
      "${NGROK_BIN}" config add-authtoken "${NGROK_AUTHTOKEN}" 2>/dev/null && ok "Token do ngrok aplicado." || warn "Falha ao aplicar o token do ngrok."
    else
      info "Preencha NGROK_AUTHTOKEN para autenticar no ngrok."
    fi
    prepare_ngrok_scripts
  fi
else
  info "Instalacao de ngrok ignorada (opcional)."
fi

# ---- Evolution API ----
if [[ "${INSTALL_EVOLUTION}" == "1" ]]; then
  # Detectar docker compose
  COMPOSE_CMD=""
  if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
  elif docker-compose version &>/dev/null; then
    COMPOSE_CMD="docker-compose"
  fi

  if [[ -z "${COMPOSE_CMD}" ]]; then
    fail "Docker Compose nao encontrado. Atualize o Docker Desktop e tente novamente."
  fi

  ok "Compose detectado: ${COMPOSE_CMD}"

  # .env
  if [[ ! -f "${STACK_ROOT}/.env" ]]; then
    cat > "${STACK_ROOT}/.env" <<ENVEOF
AUTHENTICATION_TYPE=apikey
AUTHENTICATION_API_KEY=${API_KEY}
DEL_INSTANCE=false
ENVEOF
    ok "Arquivo .env criado em ${STACK_ROOT}"
  else
    ok "Arquivo .env ja existe em ${STACK_ROOT} (mantido)."
  fi

  # docker-compose.yml
  if [[ ! -f "${STACK_ROOT}/docker-compose.yml" ]]; then
    cat > "${STACK_ROOT}/docker-compose.yml" <<COMPOSEEOF
services:
  evolution-api:
    container_name: evolution_api
    image: ${EVO_IMAGE}
    restart: always
    ports:
      - "${API_PORT}:8080"
    env_file:
      - .env
    volumes:
      - ${DATA_ROOT}/instances:/evolution/instances
      - ${DATA_ROOT}/store:/evolution/store
COMPOSEEOF
    ok "docker-compose.yml criado em ${STACK_ROOT}"
  else
    ok "docker-compose.yml ja existe em ${STACK_ROOT} (mantido)."
  fi

  # Subir stack
  info "Subindo Evolution API..."
  (cd "${STACK_ROOT}" && ${COMPOSE_CMD} up -d) || fail "Falha ao subir os containers."

  # Health check
  info "Verificando API em ${API_URL} ..."
  local api_ok=false
  for i in $(seq 1 45); do
    if curl -s -o /dev/null -w "%{http_code}" -H "apikey: ${API_KEY}" "${API_URL}/" 2>/dev/null | grep -q "200"; then
      api_ok=true
      break
    fi
    sleep 2
  done

  if [[ "${api_ok}" == "true" ]]; then
    ok "Evolution API pronta em ${API_URL}"
    ok "Manager: ${API_URL}/manager"
    ok "API Key: ${API_KEY}"
  else
    warn "A API pode ainda estar inicializando."
    warn "Confira os logs com:"
    info "  cd \"${STACK_ROOT}\" && ${COMPOSE_CMD} logs --tail=100"
  fi
else
  info "Instalacao da Evolution API ignorada (opcional)."
fi

# ---- Firebird (via Docker, necessario para o app) ----
if [[ "${BUILD_APP}" == "1" || "${INSTALL_EVOLUTION}" == "1" ]]; then
  # Firebird precisa de Docker
  if command -v docker &>/dev/null && docker info &>/dev/null; then
    ensure_firebird_docker
  else
    warn "Docker nao esta ativo. Firebird sera configurado quando o Docker estiver pronto."
  fi
fi

# ---- Build do app Money ----
if [[ "${BUILD_APP}" == "1" ]]; then
  echo
  info "=========================================="
  info "  COMPILANDO APLICATIVO MONEY (macOS)"
  info "=========================================="
  build_money_app
fi

# ---- Iniciar ngrok se tudo configurado ----
if [[ "${INSTALL_NGROK}" == "1" && -n "${NGROK_BIN}" && "${NGROK_AUTHTOKEN}" != "COLE_SEU_TOKEN_NGROK_AQUI" ]]; then
  start_ngrok_tunnel
fi

# ---- Resultado final ----
echo
info "============================================"
info "  SETUP FINALIZADO"
info "============================================"
echo
if [[ -n "${NGROK_PUBLIC_URL}" ]]; then
  ok "URL publica ngrok: ${NGROK_PUBLIC_URL}"
else
  if [[ "${INSTALL_NGROK}" == "1" ]]; then
    info "Para iniciar o tunnel manualmente: ${MONEY_ROOT}/start_ngrok.sh"
  fi
fi

echo
info "Resumo:"
info "  Raiz:             ${MONEY_ROOT}"
if [[ "${INSTALL_EVOLUTION}" == "1" ]]; then
  info "  Evolution API:    ${API_URL}"
  info "  Evolution Manager: ${API_URL}/manager"
  info "  API Key:          ${API_KEY}"
fi
if [[ "${BUILD_APP}" == "1" ]]; then
  if [[ -d "/Applications/${MONEY_APP_NAME}.app" ]]; then
    info "  App:              /Applications/${MONEY_APP_NAME}.app"
  else
    info "  App:              ${MONEY_ROOT}/${MONEY_APP_NAME}.app"
  fi
  info "  Abrir:            ${MONEY_ROOT}/abrir_money.sh"
  info "  Codigo-fonte:     ${MONEY_ROOT}/money-source"
fi
info "  Dados Firebird:   ${MONEY_ROOT}/firebird/data"
info "  Dados Evolution:  ${DATA_ROOT}"
if [[ "${INSTALL_NGROK}" == "1" ]]; then
  info "  ngrok:            ${NGROK_ROOT}"
fi

echo
ok "Para abrir o Money:"
if [[ -d "/Applications/${MONEY_APP_NAME}.app" ]]; then
  ok "  Clique duas vezes em '${MONEY_APP_NAME}' no Launchpad/Applications"
  ok "  Ou execute: open -a ${MONEY_APP_NAME}"
else
  ok "  Execute: ${MONEY_ROOT}/abrir_money.sh"
fi
echo
