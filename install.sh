#!/usr/bin/env bash
set -euo pipefail

APP_NAME="n8n + PostgreSQL"
INSTALLER_VERSION="1.3.1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_TEMPLATE="$SCRIPT_DIR/.env.example"
COMPOSE_TEMPLATE="$SCRIPT_DIR/docker-compose.yml.example"
BACKUP_TEMPLATE="$SCRIPT_DIR/backup-n8n.sh"

DEFAULT_STACK_VERSION="$INSTALLER_VERSION"
DEFAULT_N8N_IMAGE="n8nio/n8n:2.13.0"
DEFAULT_POSTGRES_IMAGE="postgres:16-alpine"
DEFAULT_POSTGRES_USER="n8n"
DEFAULT_POSTGRES_DB="n8n"
DEFAULT_N8N_PORT="5678"
DEFAULT_TIMEZONE="UTC"
DEFAULT_INSTALL_DIR="/opt/n8n"
DEFAULT_HOST="localhost"

log()  { echo "[i] $*"; }
ok()   { echo "[✔] $*"; }
warn() { echo "[!] $*"; }
err()  { echo "[x] $*" >&2; exit 1; }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Запусти так: sudo bash install.sh"
  fi
}

check_templates() {
  [[ -f "$COMPOSE_TEMPLATE" ]] || err "Не найден $COMPOSE_TEMPLATE"
  [[ -f "$BACKUP_TEMPLATE" ]] || err "Не найден $BACKUP_TEMPLATE"
}

random_hex() {
  openssl rand -hex 32
}

ask() {
  local prompt="$1" default="${2:-}" answer
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " answer || true
    answer="$(trim "$answer")"
    if [[ -z "$answer" ]]; then
      printf '%s' "$default"
    else
      printf '%s' "$answer"
    fi
  else
    read -r -p "$prompt: " answer || true
    answer="$(trim "$answer")"
    printf '%s' "$answer"
  fi
}

ask_secret() {
  local prompt="$1" default="${2:-}" answer
  if [[ -n "$default" ]]; then
    read -r -s -p "$prompt [$default]: " answer || true
  else
    read -r -s -p "$prompt: " answer || true
  fi
  echo
  answer="$(trim "$answer")"
  if [[ -z "$answer" ]]; then
    printf '%s' "$default"
  else
    printf '%s' "$answer"
  fi
}

ask_yes_no() {
  local prompt="$1" default="${2:-Y}" answer
  local shown
  if [[ "$default" == "Y" ]]; then
    shown="[Y/n]"
  else
    shown="[y/N]"
  fi

  read -r -p "$prompt $shown: " answer || true
  answer="$(trim "$answer")"
  answer="${answer:-$default}"

  case "${answer,,}" in
    y|yes) return 0 ;;
    n|no)  return 1 ;;
    *)     [[ "$default" == "Y" ]] && return 0 || return 1 ;;
  esac
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    ok "Docker уже установлен"
    return
  fi

  log "Обновление системы..."
  apt-get update
  apt-get install -y ca-certificates curl gnupg

  log "Установка Docker..."
  curl -fsSL https://get.docker.com | sh

  systemctl enable --now docker
  docker version >/dev/null
  ok "Docker установлен"
}

write_env_file() {
  cat > "$PROJECT_ENV" <<EOF
# Auto-generated — $(date -u '+%Y-%m-%d %H:%M:%S UTC')
STACK_VERSION=$STACK_VERSION
N8N_IMAGE=$N8N_IMAGE
POSTGRES_IMAGE=$POSTGRES_IMAGE
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB
N8N_PORT=$N8N_PORT
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
GENERIC_TIMEZONE=$GENERIC_TIMEZONE
N8N_HOST=$N8N_HOST
N8N_PROTOCOL=$N8N_PROTOCOL
WEBHOOK_URL=$WEBHOOK_URL
INSTALL_DIR=$INSTALL_DIR
EOF
  chmod 600 "$PROJECT_ENV"
}

validate_env_file() {
  local bad
  bad="$(grep -nEv '^[A-Z0-9_]+=.*$|^#|^$' "$PROJECT_ENV" || true)"
  if [[ -n "$bad" ]]; then
    echo "$bad"
    err ".env поврежден"
  fi
}

install_files() {
  log "Создание директорий..."
  mkdir -p "$INSTALL_DIR"/{postgres_data,n8n_data,backups}

  log "Копирование конфигурации..."
  cp "$COMPOSE_TEMPLATE" "$INSTALL_DIR/docker-compose.yml"
  cp "$BACKUP_TEMPLATE" "$INSTALL_DIR/backup-n8n.sh"
  cp "$PROJECT_ENV" "$INSTALL_DIR/.env"

  chmod 600 "$INSTALL_DIR/.env"
  chmod +x "$INSTALL_DIR/backup-n8n.sh"
}

install_cron() {
  local cron_line="0 3 * * * $INSTALL_DIR/backup-n8n.sh >> $INSTALL_DIR/backups/backup.log 2>&1"
  local current_cron
  current_cron="$(crontab -l 2>/dev/null || true)"

  if grep -Fq "$INSTALL_DIR/backup-n8n.sh" <<<"$current_cron"; then
    ok "Cron backup уже настроен"
    return
  fi

  printf '%s\n%s\n' "$current_cron" "$cron_line" | crontab -
  ok "Cron backup добавлен"
}

start_stack() {
  log "Запуск контейнеров..."
  cd "$INSTALL_DIR"
  docker compose pull
  docker compose up -d
}

show_summary() {
  echo
  log "Итоговые параметры:"
  echo "  n8n image:        $N8N_IMAGE"
  echo "  postgres image:   $POSTGRES_IMAGE"
  echo "  install dir:      $INSTALL_DIR"
  echo "  port:             $N8N_PORT"
  echo "  host:             $N8N_HOST"
  echo "  protocol:         $N8N_PROTOCOL"
  echo "  webhook url:      $WEBHOOK_URL"
  echo "  timezone:         $GENERIC_TIMEZONE"
  echo
}

show_final() {
  echo
  ok "Установка завершена"
  echo "  n8n:        $WEBHOOK_URL"
  echo "  install dir: $INSTALL_DIR"
  echo
  echo "Проверка:"
  echo "  cd $INSTALL_DIR && sudo docker compose ps"
  echo "  sudo docker logs -f n8n"
  echo
}

main() {
  require_root
  check_templates

  clear || true
  cat <<'EOF'
╔══════════════════════════════════════════════╗
║   n8n + PostgreSQL интерактивная установка  ║
╚══════════════════════════════════════════════╝
EOF
  echo
  echo "1) Внешний доступ:"
  echo "   1 - домен + reverse proxy + HTTPS"
  echo "   2 - прямой доступ по IP:порт"

  ACCESS_MODE="$(ask "Выберите режим" "1")"
  case "$ACCESS_MODE" in
    1)
      N8N_PROTOCOL="https"
      ;;
    2)
      N8N_PROTOCOL="http"
      ;;
    *)
      err "Неверный режим. Выбери 1 или 2."
      ;;
  esac

  STACK_VERSION="$DEFAULT_STACK_VERSION"
  N8N_IMAGE="$DEFAULT_N8N_IMAGE"
  POSTGRES_IMAGE="$DEFAULT_POSTGRES_IMAGE"

  POSTGRES_USER="$(ask "PostgreSQL user" "$DEFAULT_POSTGRES_USER")"
  POSTGRES_DB="$(ask "PostgreSQL database" "$DEFAULT_POSTGRES_DB")"
  POSTGRES_PASSWORD="$(ask_secret "PostgreSQL password" "$(random_hex)")"
  N8N_ENCRYPTION_KEY="$(ask_secret "N8N encryption key" "$(random_hex)")"
  N8N_PORT="$(ask "Порт n8n на сервере" "$DEFAULT_N8N_PORT")"
  GENERIC_TIMEZONE="$(ask "Timezone" "$DEFAULT_TIMEZONE")"
  INSTALL_DIR="$(ask "Папка установки" "$DEFAULT_INSTALL_DIR")"

  if [[ "$ACCESS_MODE" == "1" ]]; then
    N8N_HOST="$(ask "Домен n8n" "n8n.example.com")"
    WEBHOOK_URL="https://$N8N_HOST/"
  else
    N8N_HOST="$(ask "IP или hostname сервера" "$DEFAULT_HOST")"
    WEBHOOK_URL="http://$N8N_HOST:$N8N_PORT/"
  fi

  PROJECT_ENV="$SCRIPT_DIR/.env"

  show_summary
  ask_yes_no "Сохранить эти настройки в .env и продолжить?" "Y" || err "Отменено"

  write_env_file
  validate_env_file
  ok ".env сохранён: $PROJECT_ENV"

  echo
  log "Подтверждение перед установкой:"
  echo "  Версия инсталлятора: $INSTALLER_VERSION"
  echo "  n8n image:           $N8N_IMAGE"
  echo "  PostgreSQL image:    $POSTGRES_IMAGE"
  echo "  Директория:          $INSTALL_DIR"
  echo "  Внешний адрес:       $WEBHOOK_URL"
  echo "  Timezone:            $GENERIC_TIMEZONE"
  echo

  ask_yes_no "Начать установку?" "Y" || err "Отменено"

  ensure_docker
  install_files
  validate_env_file
  install_cron
  start_stack
  show_final
}

main "$@"