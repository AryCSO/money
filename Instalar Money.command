#!/usr/bin/env bash
# ============================================================
# Instalar Money.command
# Clique duas vezes neste arquivo no Finder para instalar o Money.
# ============================================================

cd "$(dirname "$0")" 2>/dev/null || true
clear

# ---- Cores ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}  [OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
erro()  { echo -e "${RED}[ERRO]${NC} $*"; }
fail()  { erro "$*"; echo; erro "Corrija o erro e execute novamente."; echo; read -rp "Pressione Enter para fechar..."; exit 1; }

divider() { echo -e "${DIM}────────────────────────────────────────────────${NC}"; }

# ============================================================
# TELA DE BOAS-VINDAS
# ============================================================
echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║                                          ║"
echo "  ║          MONEY - INSTALADOR macOS         ║"
echo "  ║                                          ║"
echo "  ║   Docker + Evolution API + Firebird       ║"
echo "  ║   + Aplicativo Money nativo               ║"
echo "  ║                                          ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
divider
echo

# ============================================================
# VERIFICAR macOS
# ============================================================
if [[ "$(uname)" != "Darwin" ]]; then
  fail "Este instalador e exclusivo para macOS. No Windows, use o setup_money_env.bat."
fi

# ============================================================
# PERGUNTAS INTERATIVAS
# ============================================================

MONEY_ROOT="$HOME/money"
echo -e "${BOLD}Pasta de instalacao:${NC} ${MONEY_ROOT}"
echo -e "${DIM}(Todos os dados, app e configs ficam aqui)${NC}"
echo
read -rp "Deseja alterar? (Enter para manter, ou digite o caminho): " custom_path
if [[ -n "${custom_path}" ]]; then
  MONEY_ROOT="${custom_path}"
  echo -e "  Usando: ${BOLD}${MONEY_ROOT}${NC}"
fi
echo
divider
echo

# ---- Componentes ----
echo -e "${BOLD}Selecione o que deseja instalar:${NC}"
echo

INSTALL_DOCKER="1"
INSTALL_EVOLUTION="1"
INSTALL_NGROK="1"
BUILD_APP="1"

read -rp "  Instalar Docker Desktop? (S/n): " ans
[[ "${ans,,}" == "n" ]] && INSTALL_DOCKER="0"

read -rp "  Instalar Evolution API? (S/n): " ans
[[ "${ans,,}" == "n" ]] && INSTALL_EVOLUTION="0"

read -rp "  Compilar aplicativo Money? (S/n): " ans
[[ "${ans,,}" == "n" ]] && BUILD_APP="0"

read -rp "  Instalar ngrok (acesso remoto)? (S/n): " ans
[[ "${ans,,}" == "n" ]] && INSTALL_NGROK="0"

echo
divider
echo

# ---- Token ngrok ----
NGROK_AUTHTOKEN=""
if [[ "${INSTALL_NGROK}" == "1" ]]; then
  echo -e "${BOLD}Configuracao do ngrok${NC}"
  echo -e "${DIM}O ngrok permite acessar a API de qualquer lugar.${NC}"
  echo -e "${DIM}Pegue seu token em: https://dashboard.ngrok.com/get-started/your-authtoken${NC}"
  echo
  read -rp "  Cole seu token ngrok (ou Enter para pular): " NGROK_AUTHTOKEN
  if [[ -z "${NGROK_AUTHTOKEN}" ]]; then
    NGROK_AUTHTOKEN="COLE_SEU_TOKEN_NGROK_AQUI"
    echo
    warn "ngrok sera instalado, mas sem autenticacao."
    warn "Voce pode configurar depois editando: ${MONEY_ROOT}/ngrok/ngrok.yml"
  else
    echo
    ok "Token ngrok configurado."
  fi
  echo
  divider
  echo
fi

# ---- Confirmacao ----
echo -e "${BOLD}Resumo da instalacao:${NC}"
echo
echo -e "  Pasta:           ${CYAN}${MONEY_ROOT}${NC}"
echo -e "  Docker:          $( [[ "${INSTALL_DOCKER}" == "1" ]] && echo -e "${GREEN}Sim${NC}" || echo -e "${DIM}Nao${NC}" )"
echo -e "  Evolution API:   $( [[ "${INSTALL_EVOLUTION}" == "1" ]] && echo -e "${GREEN}Sim${NC}" || echo -e "${DIM}Nao${NC}" )"
echo -e "  Compilar app:    $( [[ "${BUILD_APP}" == "1" ]] && echo -e "${GREEN}Sim${NC}" || echo -e "${DIM}Nao${NC}" )"
echo -e "  ngrok:           $( [[ "${INSTALL_NGROK}" == "1" ]] && echo -e "${GREEN}Sim${NC}" || echo -e "${DIM}Nao${NC}" )"
if [[ "${INSTALL_NGROK}" == "1" && "${NGROK_AUTHTOKEN}" != "COLE_SEU_TOKEN_NGROK_AQUI" ]]; then
  echo -e "  ngrok token:     ${GREEN}Configurado${NC}"
fi
echo
read -rp "Iniciar instalacao? (S/n): " confirm
if [[ "${confirm,,}" == "n" ]]; then
  echo
  info "Instalacao cancelada."
  read -rp "Pressione Enter para fechar..."
  exit 0
fi

echo
divider
echo -e "${BOLD}Iniciando instalacao...${NC}"
echo

# ============================================================
# CONFIGURACOES INTERNAS
# ============================================================
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

# ---- Criar pastas ----
mkdir -p "${MONEY_ROOT}"
mkdir -p "${STACK_ROOT}"
mkdir -p "${DATA_ROOT}/instances"
mkdir -p "${DATA_ROOT}/store"
mkdir -p "${NGROK_ROOT}"
ok "Estrutura de pastas criada"

# ============================================================
# FUNCOES DE INSTALACAO
# ============================================================

step_count=0
step_total=0
[[ "${INSTALL_DOCKER}" == "1" ]] && step_total=$((step_total + 1))
[[ "${INSTALL_NGROK}" == "1" ]] && step_total=$((step_total + 1))
[[ "${INSTALL_EVOLUTION}" == "1" ]] && step_total=$((step_total + 1))
[[ "${BUILD_APP}" == "1" ]] && step_total=$((step_total + 2)) # flutter + build
step() {
  step_count=$((step_count + 1))
  echo
  echo -e "${BOLD}[${step_count}/${step_total}] $*${NC}"
  divider
}

# ---- Homebrew ----
ensure_homebrew() {
  if command -v brew &>/dev/null; then
    ok "Homebrew encontrado."
    return 0
  fi
  info "Instalando Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  command -v brew &>/dev/null || fail "Homebrew nao encontrado. Feche e reabra o terminal."
  ok "Homebrew instalado."
}

# ---- Git ----
ensure_git() {
  if command -v git &>/dev/null; then return 0; fi
  info "Instalando Git via Xcode Command Line Tools..."
  xcode-select --install 2>/dev/null || true
  local w=0
  while ! command -v git &>/dev/null; do
    w=$((w + 1))
    [[ ${w} -ge 120 ]] && fail "Git nao instalado. Aceite o dialog do Xcode."
    sleep 2
  done
  ok "Git instalado."
}

# ---- Docker ----
ensure_docker_installed() {
  if command -v docker &>/dev/null; then
    ok "Docker encontrado."
    return 0
  fi
  info "Instalando Docker Desktop via Homebrew..."
  ensure_homebrew
  brew install --cask docker
  if [[ -d "/Applications/Docker.app" ]]; then
    info "Abrindo Docker Desktop pela primeira vez..."
    open -a Docker
    sleep 5
  fi
  command -v docker &>/dev/null || fail "Docker nao encontrado no PATH. Abra Docker Desktop manualmente."
  ok "Docker Desktop instalado."
}

ensure_docker_running() {
  if docker info &>/dev/null; then
    ok "Docker Engine ativo."
    return 0
  fi
  info "Iniciando Docker Desktop..."
  [[ -d "/Applications/Docker.app" ]] && open -a Docker || fail "Docker.app nao encontrado."
  local w=0
  while ! docker info &>/dev/null; do
    w=$((w + 1))
    [[ ${w} -ge 90 ]] && fail "Docker nao ficou pronto. Abra manualmente e tente de novo."
    sleep 2
  done
  ok "Docker Engine ativo."
}

# ---- ngrok ----
ensure_ngrok_installed() {
  if [[ -f "${NGROK_ROOT}/ngrok" ]]; then
    NGROK_BIN="${NGROK_ROOT}/ngrok"; ok "ngrok encontrado."; return 0
  fi
  if command -v ngrok &>/dev/null; then
    NGROK_BIN="$(command -v ngrok)"; ok "ngrok encontrado."; return 0
  fi
  ensure_homebrew
  brew install ngrok/ngrok/ngrok 2>/dev/null || brew install --cask ngrok 2>/dev/null || true
  if command -v ngrok &>/dev/null; then
    NGROK_BIN="$(command -v ngrok)"; ok "ngrok instalado."; return 0
  fi
  info "Download direto do ngrok..."
  local arch; arch="$(uname -m)"
  local url="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip"
  [[ "${arch}" == "arm64" ]] && url="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip"
  curl -fsSL "${url}" -o "${NGROK_ROOT}/ngrok.zip"
  unzip -o "${NGROK_ROOT}/ngrok.zip" -d "${NGROK_ROOT}" >/dev/null
  rm -f "${NGROK_ROOT}/ngrok.zip"
  chmod +x "${NGROK_ROOT}/ngrok"
  [[ -f "${NGROK_ROOT}/ngrok" ]] && { NGROK_BIN="${NGROK_ROOT}/ngrok"; ok "ngrok baixado."; return 0; }
  warn "Nao foi possivel instalar ngrok."
  return 1
}

# ---- Flutter ----
ensure_flutter() {
  if command -v flutter &>/dev/null; then
    ok "Flutter encontrado: $(flutter --version 2>/dev/null | head -1)"
    return 0
  fi
  if [[ -f "${MONEY_ROOT}/flutter/bin/flutter" ]]; then
    export PATH="${MONEY_ROOT}/flutter/bin:${PATH}"
    ok "Flutter encontrado em ${MONEY_ROOT}/flutter"
    return 0
  fi
  ensure_homebrew
  if brew install --cask flutter 2>/dev/null && command -v flutter &>/dev/null; then
    ok "Flutter instalado via Homebrew."
    return 0
  fi
  info "Clonando Flutter SDK..."
  ensure_git
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "${MONEY_ROOT}/flutter"
  export PATH="${MONEY_ROOT}/flutter/bin:${PATH}"
  command -v flutter &>/dev/null || fail "Flutter nao encontrado no PATH."
  ok "Flutter instalado em ${MONEY_ROOT}/flutter"
}

# ---- Firebird via Docker ----
ensure_firebird_docker() {
  info "Configurando Firebird 5 via Docker..."
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^money_firebird$"; then
    ok "Firebird ja esta rodando."; return 0
  fi
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^money_firebird$"; then
    docker start money_firebird; ok "Firebird iniciado."; return 0
  fi
  mkdir -p "${MONEY_ROOT}/firebird/data"
  docker run -d --name money_firebird --restart always \
    -p 9255:3050 \
    -e FIREBIRD_DATABASE=money.fdb \
    -e FIREBIRD_USER=money \
    -e "FIREBIRD_PASSWORD=101812Ar@" \
    -e ISC_PASSWORD=masterkey \
    -v "${MONEY_ROOT}/firebird/data:/firebird/data" \
    jacobalberty/firebird:v5 || fail "Falha ao criar container Firebird."
  info "Aguardando Firebird..."
  sleep 8
  ok "Firebird 5 rodando na porta 9255."
}

# ============================================================
# EXECUCAO
# ============================================================

# ---- 1. Docker ----
if [[ "${INSTALL_DOCKER}" == "1" ]]; then
  step "Instalando Docker Desktop"
  ensure_docker_installed
  ensure_docker_running
fi

# ---- 2. ngrok ----
if [[ "${INSTALL_NGROK}" == "1" ]]; then
  step "Instalando ngrok"
  if ensure_ngrok_installed; then
    if [[ "${NGROK_AUTHTOKEN}" != "COLE_SEU_TOKEN_NGROK_AQUI" ]]; then
      "${NGROK_BIN}" config add-authtoken "${NGROK_AUTHTOKEN}" 2>/dev/null && ok "Token aplicado." || warn "Falha ao aplicar token."
    fi
    # Config
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
    cat > "${MONEY_ROOT}/start_ngrok.sh" <<STARTEOF
#!/usr/bin/env bash
pkill -f ngrok 2>/dev/null || true; sleep 1
"${NGROK_BIN}" start --all --config "${NGROK_CONFIG}" --log=stdout > "${NGROK_LOG}" 2>&1 &
echo "ngrok iniciado. Log: ${NGROK_LOG}"
STARTEOF
    chmod +x "${MONEY_ROOT}/start_ngrok.sh"
    ok "Scripts do ngrok prontos."
  fi
fi

# ---- 3. Evolution API ----
if [[ "${INSTALL_EVOLUTION}" == "1" ]]; then
  step "Instalando Evolution API"
  if ! command -v docker &>/dev/null; then
    fail "Docker e necessario para a Evolution API."
  fi
  ensure_docker_running

  COMPOSE_CMD=""
  docker compose version &>/dev/null && COMPOSE_CMD="docker compose"
  [[ -z "${COMPOSE_CMD}" ]] && docker-compose version &>/dev/null && COMPOSE_CMD="docker-compose"
  [[ -z "${COMPOSE_CMD}" ]] && fail "Docker Compose nao encontrado."
  ok "Compose: ${COMPOSE_CMD}"

  if [[ ! -f "${STACK_ROOT}/.env" ]]; then
    cat > "${STACK_ROOT}/.env" <<ENVEOF
AUTHENTICATION_TYPE=apikey
AUTHENTICATION_API_KEY=${API_KEY}
DEL_INSTANCE=false
ENVEOF
    ok ".env criado"
  fi

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
    ok "docker-compose.yml criado"
  fi

  info "Subindo Evolution API..."
  (cd "${STACK_ROOT}" && ${COMPOSE_CMD} up -d) || fail "Falha ao subir containers."

  info "Verificando API..."
  api_ok=false
  for i in $(seq 1 45); do
    if curl -s -o /dev/null -w "%{http_code}" -H "apikey: ${API_KEY}" "${API_URL}/" 2>/dev/null | grep -q "200"; then
      api_ok=true; break
    fi
    sleep 2
  done
  [[ "${api_ok}" == "true" ]] && ok "Evolution API pronta em ${API_URL}" || warn "API pode estar inicializando ainda."

  # Firebird
  ensure_firebird_docker
fi

# ---- 4/5. Build do app ----
if [[ "${BUILD_APP}" == "1" ]]; then
  step "Instalando Flutter SDK"
  ensure_flutter

  step "Compilando aplicativo Money"
  ensure_git

  local_source="${MONEY_ROOT}/money-source"
  if [[ -d "${local_source}/.git" ]]; then
    info "Atualizando codigo-fonte..."
    (cd "${local_source}" && git pull --ff-only 2>/dev/null) || warn "Usando versao existente."
  else
    info "Clonando repositorio..."
    rm -rf "${local_source}"
    git clone "${MONEY_REPO}" "${local_source}" || fail "Falha ao clonar."
  fi
  ok "Codigo-fonte pronto"

  flutter config --enable-macos-desktop 2>/dev/null || true
  info "Baixando dependencias..."
  (cd "${local_source}" && flutter pub get) || fail "Falha nas dependencias."

  info "Compilando... (isso leva alguns minutos)"
  (cd "${local_source}" && flutter build macos --release) || fail "Falha na compilacao."

  built_app="${local_source}/build/macos/Build/Products/Release/money.app"
  if [[ ! -d "${built_app}" ]]; then
    built_app="$(find "${local_source}/build/macos" -name "*.app" -type d 2>/dev/null | head -1)"
  fi
  [[ -z "${built_app}" || ! -d "${built_app}" ]] && fail "Build concluido mas .app nao encontrado."

  # Instalar
  rm -rf "${MONEY_ROOT}/${MONEY_APP_NAME}.app"
  cp -R "${built_app}" "${MONEY_ROOT}/${MONEY_APP_NAME}.app"
  ok "App compilado: ${MONEY_ROOT}/${MONEY_APP_NAME}.app"

  if [[ -d "/Applications" ]]; then
    info "Copiando para /Applications..."
    rm -rf "/Applications/${MONEY_APP_NAME}.app" 2>/dev/null
    cp -R "${built_app}" "/Applications/${MONEY_APP_NAME}.app" 2>/dev/null && ok "Instalado em /Applications/${MONEY_APP_NAME}.app" || warn "Sem permissao para /Applications. Execute com sudo se desejar."
  fi

  # Atalho
  cat > "${MONEY_ROOT}/Abrir Money.command" <<'OPENEOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -d "/Applications/Money.app" ]]; then
  open -a "/Applications/Money.app"
elif [[ -d "${SCRIPT_DIR}/Money.app" ]]; then
  open "${SCRIPT_DIR}/Money.app"
else
  echo "Money.app nao encontrado."
  read -rp "Enter para fechar..."
  exit 1
fi
OPENEOF
  chmod +x "${MONEY_ROOT}/Abrir Money.command"
  ok "Atalho criado: ${MONEY_ROOT}/Abrir Money.command"
fi

# ---- ngrok tunnel ----
if [[ "${INSTALL_NGROK}" == "1" && -n "${NGROK_BIN}" && "${NGROK_AUTHTOKEN}" != "COLE_SEU_TOKEN_NGROK_AQUI" ]]; then
  info "Iniciando tunnel ngrok..."
  pkill -f ngrok 2>/dev/null || true; sleep 1
  nohup "${NGROK_BIN}" start --all --config "${NGROK_CONFIG}" --log=stdout > "${NGROK_LOG}" 2>&1 &
  for attempt in $(seq 1 20); do
    NGROK_PUBLIC_URL="$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | python3 -c "import sys,json; t=json.load(sys.stdin); print(t['tunnels'][0]['public_url'] if t.get('tunnels') else '')" 2>/dev/null || true)"
    [[ -n "${NGROK_PUBLIC_URL}" ]] && break
    sleep 1
  done
  [[ -n "${NGROK_PUBLIC_URL}" ]] && ok "ngrok: ${NGROK_PUBLIC_URL}" || warn "URL publica nao detectada ainda."
fi

# ============================================================
# RESULTADO FINAL
# ============================================================
echo
echo
echo -e "${BOLD}  ╔══════════════════════════════════════════╗"
echo -e "  ║                                          ║"
echo -e "  ║     ${GREEN}INSTALACAO CONCLUIDA COM SUCESSO${NC}${BOLD}     ║"
echo -e "  ║                                          ║"
echo -e "  ╚══════════════════════════════════════════╝${NC}"
echo
divider
echo

echo -e "${BOLD}  Resumo:${NC}"
echo
echo -e "    Pasta:             ${CYAN}${MONEY_ROOT}${NC}"
if [[ "${INSTALL_EVOLUTION}" == "1" ]]; then
  echo -e "    Evolution API:     ${CYAN}${API_URL}${NC}"
  echo -e "    API Manager:       ${CYAN}${API_URL}/manager${NC}"
  echo -e "    API Key:           ${CYAN}${API_KEY}${NC}"
fi
if [[ "${BUILD_APP}" == "1" ]]; then
  if [[ -d "/Applications/${MONEY_APP_NAME}.app" ]]; then
    echo -e "    App:               ${GREEN}/Applications/${MONEY_APP_NAME}.app${NC}"
  else
    echo -e "    App:               ${GREEN}${MONEY_ROOT}/${MONEY_APP_NAME}.app${NC}"
  fi
fi
if [[ -n "${NGROK_PUBLIC_URL}" ]]; then
  echo -e "    ngrok URL:         ${GREEN}${NGROK_PUBLIC_URL}${NC}"
fi
echo

if [[ "${BUILD_APP}" == "1" ]]; then
  divider
  echo
  echo -e "${BOLD}  Para abrir o Money:${NC}"
  echo
  if [[ -d "/Applications/${MONEY_APP_NAME}.app" ]]; then
    echo -e "    ${GREEN}Clique em 'Money' no Launchpad${NC}"
    echo -e "    ou execute: ${CYAN}open -a Money${NC}"
  else
    echo -e "    Clique duas vezes em: ${CYAN}${MONEY_ROOT}/Abrir Money.command${NC}"
  fi
  echo
fi

divider
echo
echo -e "${DIM}  Logs ngrok:     ${NGROK_ROOT}/ngrok.log${NC}"
echo -e "${DIM}  Reconfigurar:   Execute este instalador novamente${NC}"
echo -e "${DIM}  Codigo-fonte:   ${MONEY_ROOT}/money-source${NC}"
echo
read -rp "Pressione Enter para fechar..."
