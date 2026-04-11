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

# ---- Iniciar ngrok se tudo configurado ----
if [[ "${INSTALL_NGROK}" == "1" && -n "${NGROK_BIN}" && "${NGROK_AUTHTOKEN}" != "COLE_SEU_TOKEN_NGROK_AQUI" ]]; then
  start_ngrok_tunnel
fi

# ---- Resultado final ----
echo
info "Setup finalizado."
if [[ -n "${NGROK_PUBLIC_URL}" ]]; then
  ok "URL publica ngrok: ${NGROK_PUBLIC_URL}"
else
  info "Para iniciar o tunnel manualmente: ${MONEY_ROOT}/start_ngrok.sh"
fi

echo
info "Resumo dos caminhos:"
info "  Raiz:           ${MONEY_ROOT}"
info "  Evolution API:  ${STACK_ROOT}"
info "  Dados:          ${DATA_ROOT}"
info "  ngrok:          ${NGROK_ROOT}"
echo
ok "Tudo pronto. Abra o app Money e conecte ao WhatsApp."
