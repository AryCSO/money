#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/money"
INSTALL_BIN="$INSTALL_DIR/docker"
LOG_FILE="$HOME/Library/Logs/ngrok_50010.log"

echo "==========================================="
echo "NGROK AUTO SETUP - PORTA 50010 (macOS)"
echo "==========================================="
echo

if [[ -x "$INSTALL_BIN" ]]; then
  echo "Encontrado: $INSTALL_BIN"
  echo "Arquivo ja existe. Nao prosseguindo com instalacao/configuracao."
  exit 0
fi

mkdir -p "$INSTALL_DIR"

if command -v ngrok >/dev/null 2>&1; then
  cp "$(command -v ngrok)" "$INSTALL_BIN"
  chmod +x "$INSTALL_BIN"
else
  if command -v brew >/dev/null 2>&1; then
    echo "Instalando ngrok via Homebrew..."
    brew install ngrok/ngrok/ngrok || brew install ngrok
  fi

  if command -v ngrok >/dev/null 2>&1; then
    cp "$(command -v ngrok)" "$INSTALL_BIN"
    chmod +x "$INSTALL_BIN"
  else
    echo "Homebrew indisponivel ou sem ngrok. Tentando download direto..."

    arch_name="$(uname -m)"
    if [[ "$arch_name" == "arm64" ]]; then
      download_url="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-arm64.zip"
    else
      download_url="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-darwin-amd64.zip"
    fi

    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    curl -fsSL "$download_url" -o "$tmp_dir/ngrok.zip"
    unzip -q "$tmp_dir/ngrok.zip" -d "$tmp_dir"
    mv "$tmp_dir/ngrok" "$INSTALL_BIN"
    chmod +x "$INSTALL_BIN"
  fi
fi

if [[ ! -x "$INSTALL_BIN" ]]; then
  echo "Falha ao instalar ngrok em: $INSTALL_BIN"
  exit 1
fi

echo
read -r -p "Cole o link do ngrok que voce pegou manualmente no login (ou Enter para pular): " NGROK_LOGIN_LINK
if [[ -n "${NGROK_LOGIN_LINK}" ]]; then
  open "${NGROK_LOGIN_LINK}" || true
fi

echo
read -r -p "Cole seu authtoken do ngrok (ou Enter se ja configurado): " NGROK_TOKEN
if [[ -n "${NGROK_TOKEN}" ]]; then
  "$INSTALL_BIN" config add-authtoken "${NGROK_TOKEN}"
fi

mkdir -p "$(dirname "$LOG_FILE")"

echo
echo "Iniciando ngrok em segundo plano (equivalente bandeja no macOS)..."
nohup "$INSTALL_BIN" http 50010 >"$LOG_FILE" 2>&1 &
ngrok_pid=$!
sleep 1

if kill -0 "$ngrok_pid" >/dev/null 2>&1; then
  echo "ngrok iniciado em segundo plano. PID: $ngrok_pid"
  echo "Log: $LOG_FILE"
  echo "Abra http://127.0.0.1:4040 para ver o link publico."
else
  echo "Falha ao iniciar ngrok em segundo plano."
  exit 1
fi
