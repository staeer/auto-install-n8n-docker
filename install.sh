#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'
log()  { echo -e "${GREEN}[✔]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
err()  { echo -e "${RED}[✘]${NC} $1" >&2; exit 1; }

trim() {
  local var="${1:-}"
  var="${var#${var%%[![:space:]]*}}"
  var="${var%${var##*[![:space:]]}}"
  printf '%s' "$var"
}

ask_default() {
  local prompt="$1" default="$2" answer
  read -r -p "$prompt [$default]: " answer || true
  answer="$(trim "$answer")"
  if [[ -z "$answer" ]]; then
    printf '%s' "$default"
  else
    printf '%s' "$answer"
  fi
}

ask_secret_default() {
  local prompt="$1" default="$2" answer
  read -r -s -p "$prompt [$default]: " answer || true
  echo >&2
  answer="$(trim "$answer")"
  if [[ -z "$answer" ]]; then
    printf '%s' "$default"
  else
    printf '%s' "$answer"
  fi
}

ask_yes_no() {
  local prompt="$1" default="${2:-y}" answer
  local suffix="[Y/n]"
  [[ "$default" == "n" ]] && suffix="[y/N]"
  read -r -p "$prompt $suffix: " answer || true
  answer="$(trim "$answer")"
  if [[ -z "$answer" ]]; then
    answer="$default"
  fi
  [[ "$answer" =~ ^[Yy]$ ]]
}

random_hex() {
  openssl rand -hex "$1"
}

make_webhook_url() {
  local protocol="$1" host="$2" port="$3"
  if [[ "$protocol" == "https" ]]; then
    printf '%s://%s/' "$protocol" "$host"
  else
    if [[ "$port" == "80" ]]; then
      printf '%s://%s/' "$protocol" "$host"
    else
      printf '%s://%s:%s/' "$protocol" "$host" "$port"
    fi
  fi
}

validate_env_file() {
  local env_file="$1"
  local bad
  bad="$(grep -nEv '^[A-Z0-9_]+=.*$|^#|^$' "$env_file" || true)"
  if [[ -n "$bad" ]]; then
    echo "$bad" >&2
    err "Файл $env_file поврежден"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ENV="$SCRIPT_DIR/.env"
COMPOSE_TEMPLATE="$SCRIPT_DIR/docker-compose.yml.example"
BACKUP_TEMPLATE="$SCRIPT_DIR/backup-n8n.sh"
VERSION_FILE="$SCRIPT_DIR/VERSION"

[[ -f "$COMPOSE_TEMPLATE" ]] || err "Не найден $COMPOSE_TEMPLATE"
[[ -f "$BACKUP_TEMPLATE" ]] || err "Не найден $BACKUP_TEMPLATE"
[[ $EUID -ne 0 ]] && err "Запустите: sudo bash install.sh"

DEFAULT_STACK_VERSION="1.3.5"
DEFAULT_N8N_IMAGE="n8nio/n8n:2.13.0"
DEFAULT_POSTGRES_IMAGE="postgres:16-alpine"
DEFAULT_POSTGRES_USER="n8n"
DEFAULT_POSTGRES_DB="n8n"
DEFAULT_N8N_PORT="5678"
DEFAULT_GENERIC_TIMEZONE="UTC"
DEFAULT_INSTALL_DIR="/opt/n8n"
DEFAULT_N8N_HOST="localhost"
DEFAULT_N8N_SECURE_COOKIE="true"

load_env_values() {
  if [[ -f "$PROJECT_ENV" ]]; then
    validate_env_file "$PROJECT_ENV"
    set -a
    # shellcheck disable=SC1090
    source "$PROJECT_ENV"
    set +a
  fi

  STACK_VERSION="$(trim "${STACK_VERSION:-$DEFAULT_STACK_VERSION}")"
  N8N_IMAGE="$(trim "${N8N_IMAGE:-$DEFAULT_N8N_IMAGE}")"
  POSTGRES_IMAGE="$(trim "${POSTGRES_IMAGE:-$DEFAULT_POSTGRES_IMAGE}")"
  POSTGRES_USER="$(trim "${POSTGRES_USER:-$DEFAULT_POSTGRES_USER}")"
  POSTGRES_PASSWORD="$(trim "${POSTGRES_PASSWORD:-}")"
  POSTGRES_DB="$(trim "${POSTGRES_DB:-$DEFAULT_POSTGRES_DB}")"
  N8N_PORT="$(trim "${N8N_PORT:-$DEFAULT_N8N_PORT}")"
  N8N_ENCRYPTION_KEY="$(trim "${N8N_ENCRYPTION_KEY:-}")"
  GENERIC_TIMEZONE="$(trim "${GENERIC_TIMEZONE:-$DEFAULT_GENERIC_TIMEZONE}")"
  INSTALL_DIR="$(trim "${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}")"
  N8N_HOST="$(trim "${N8N_HOST:-$DEFAULT_N8N_HOST}")"
  N8N_PROTOCOL="$(trim "${N8N_PROTOCOL:-http}")"
  WEBHOOK_URL="$(trim "${WEBHOOK_URL:-}")"
  N8N_SECURE_COOKIE="$(trim "${N8N_SECURE_COOKIE:-$DEFAULT_N8N_SECURE_COOKIE}")"
}

write_env_file() {
  cat > "$PROJECT_ENV" <<ENVEOF
# Auto-generated — $(date -u +'%Y-%m-%d %H:%M:%S UTC')
STACK_VERSION=${STACK_VERSION}
N8N_IMAGE=${N8N_IMAGE}
POSTGRES_IMAGE=${POSTGRES_IMAGE}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
N8N_PORT=${N8N_PORT}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
TZ=${GENERIC_TIMEZONE}
INSTALL_DIR=${INSTALL_DIR}
N8N_HOST=${N8N_HOST}
N8N_PROTOCOL=${N8N_PROTOCOL}
WEBHOOK_URL=${WEBHOOK_URL}
N8N_SECURE_COOKIE=${N8N_SECURE_COOKIE}
ENVEOF
  chmod 600 "$PROJECT_ENV"
  validate_env_file "$PROJECT_ENV"
}

interactive_config() {
  echo -e "${BOLD}${CYAN}"
  echo "╔══════════════════════════════════════════════╗"
  echo "║   n8n + PostgreSQL интерактивная установка  ║"
  echo "╚══════════════════════════════════════════════╝"
  echo -e "${NC}"

  STACK_VERSION="$DEFAULT_STACK_VERSION"
  N8N_IMAGE="$DEFAULT_N8N_IMAGE"
  POSTGRES_IMAGE="$DEFAULT_POSTGRES_IMAGE"

  echo "1) Внешний доступ:"
  echo "   1 - домен + reverse proxy + HTTPS"
  echo "   2 - прямой доступ по IP:порт"
  ACCESS_MODE="$(ask_default 'Выберите режим' '1')"

  POSTGRES_USER="$(ask_default 'PostgreSQL user' "${POSTGRES_USER:-$DEFAULT_POSTGRES_USER}")"
  POSTGRES_DB="$(ask_default 'PostgreSQL database' "${POSTGRES_DB:-$DEFAULT_POSTGRES_DB}")"

  local generated_pg generated_key
  generated_pg="$(random_hex 16)"
  generated_key="$(random_hex 32)"

  POSTGRES_PASSWORD="$(ask_secret_default 'PostgreSQL password' "${POSTGRES_PASSWORD:-$generated_pg}")"
  N8N_ENCRYPTION_KEY="$(ask_secret_default 'N8N encryption key' "${N8N_ENCRYPTION_KEY:-$generated_key}")"

  N8N_PORT="$(ask_default 'Порт n8n на сервере' "${N8N_PORT:-$DEFAULT_N8N_PORT}")"
  GENERIC_TIMEZONE="$(ask_default 'Timezone' "${GENERIC_TIMEZONE:-$DEFAULT_GENERIC_TIMEZONE}")"
  INSTALL_DIR="$(ask_default 'Папка установки' "${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}")"

  case "$ACCESS_MODE" in
    1)
      N8N_HOST="$(ask_default 'Домен n8n' "${N8N_HOST:-n8n.example.com}")"
      N8N_PROTOCOL="https"
      WEBHOOK_URL="https://${N8N_HOST}/"
      N8N_SECURE_COOKIE="true"
      ;;
    2)
      N8N_HOST="$(ask_default 'IP или hostname сервера' "${N8N_HOST:-127.0.0.1}")"
      N8N_PROTOCOL="http"
      WEBHOOK_URL="$(make_webhook_url "$N8N_PROTOCOL" "$N8N_HOST" "$N8N_PORT")"
      N8N_SECURE_COOKIE="$(ask_default 'N8N_SECURE_COOKIE (true/false)' "${N8N_SECURE_COOKIE:-$DEFAULT_N8N_SECURE_COOKIE}")"
      ;;
    *) err "Неверный режим. Нужен 1 или 2" ;;
  esac

  echo
  info "Итоговые параметры:"
  echo "  n8n image:        $N8N_IMAGE"
  echo "  postgres image:   $POSTGRES_IMAGE"
  echo "  install dir:      $INSTALL_DIR"
  echo "  port:             $N8N_PORT"
  echo "  host:             $N8N_HOST"
  echo "  protocol:         $N8N_PROTOCOL"
  echo "  webhook url:      $WEBHOOK_URL"
  echo "  timezone:         $GENERIC_TIMEZONE"
  echo "  secure cookie:    $N8N_SECURE_COOKIE"
  echo

  ask_yes_no 'Сохранить эти настройки в .env и продолжить?' y || err 'Установка отменена.'
  write_env_file
  log ".env сохранён: $PROJECT_ENV"
}

load_env_values

if [[ -f "$PROJECT_ENV" ]]; then
  info "Найден .env"
  if ask_yes_no 'Использовать существующий .env без вопросов?' y; then
    [[ -z "$POSTGRES_PASSWORD" ]] && POSTGRES_PASSWORD="$(random_hex 16)"
    [[ -z "$N8N_ENCRYPTION_KEY" ]] && N8N_ENCRYPTION_KEY="$(random_hex 32)"
    [[ -z "$WEBHOOK_URL" ]] && WEBHOOK_URL="$(make_webhook_url "$N8N_PROTOCOL" "$N8N_HOST" "$N8N_PORT")"
    write_env_file
  else
    interactive_config
  fi
else
  interactive_config
fi

case "$N8N_PROTOCOL" in
  http|https) ;;
  *) err "N8N_PROTOCOL должен быть http или https" ;;
esac
[[ "$WEBHOOK_URL" != */ ]] && WEBHOOK_URL="${WEBHOOK_URL}/"
case "${N8N_SECURE_COOKIE,,}" in
  true|false) N8N_SECURE_COOKIE="${N8N_SECURE_COOKIE,,}" ;;
  *) err "N8N_SECURE_COOKIE должен быть true или false" ;;
esac

info "Подтверждение перед установкой:"
echo "  Версия инсталлятора: $STACK_VERSION"
echo "  n8n image:           $N8N_IMAGE"
echo "  PostgreSQL image:    $POSTGRES_IMAGE"
echo "  Директория:          $INSTALL_DIR"
echo "  Внешний адрес:       $WEBHOOK_URL"
echo "  Timezone:            $GENERIC_TIMEZONE"
echo "  Secure cookie:       $N8N_SECURE_COOKIE"
echo
ask_yes_no 'Начать установку?' y || err 'Установка отменена.'

info "Обновление системы..."
apt-get update -qq
apt-get install -y -qq curl wget gnupg2 ca-certificates lsb-release apt-transport-https software-properties-common openssl

if command -v docker &>/dev/null; then
  warn "Docker уже установлен ($(docker --version | cut -d' ' -f3 | tr -d ','))"
else
  info "Установка Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
  log "Docker установлен"
fi

if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
else
  info "Установка Docker Compose plugin..."
  apt-get install -y -qq docker-compose-plugin 2>/dev/null || err "Не удалось установить docker compose plugin"
  COMPOSE_CMD="docker compose"
  log "Docker Compose установлен"
fi

info "Создание директорий..."
mkdir -p "$INSTALL_DIR"/{n8n_data,postgres_data,backups}
chown -R 999:999 "$INSTALL_DIR/postgres_data"
chown -R 1000:1000 "$INSTALL_DIR/n8n_data"
chmod 700 "$INSTALL_DIR/postgres_data"
chmod 755 "$INSTALL_DIR/n8n_data"

info "Копирование конфигурации..."
cat > "$INSTALL_DIR/.env" <<ENVEOF
# Auto-generated — $(date -u +'%Y-%m-%d %H:%M:%S UTC')
STACK_VERSION=${STACK_VERSION}
N8N_IMAGE=${N8N_IMAGE}
POSTGRES_IMAGE=${POSTGRES_IMAGE}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
N8N_PORT=${N8N_PORT}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
TZ=${GENERIC_TIMEZONE}
N8N_HOST=${N8N_HOST}
N8N_PROTOCOL=${N8N_PROTOCOL}
WEBHOOK_URL=${WEBHOOK_URL}
N8N_SECURE_COOKIE=${N8N_SECURE_COOKIE}
INSTALL_DIR=${INSTALL_DIR}
ENVEOF
chmod 600 "$INSTALL_DIR/.env"
validate_env_file "$INSTALL_DIR/.env"
install -m 644 "$COMPOSE_TEMPLATE" "$INSTALL_DIR/docker-compose.yml"
install -m 755 "$BACKUP_TEMPLATE" "$INSTALL_DIR/backup.sh"

cat > "$INSTALL_DIR/VERSION" <<VEOF
STACK_VERSION=${STACK_VERSION}
N8N_IMAGE=${N8N_IMAGE}
POSTGRES_IMAGE=${POSTGRES_IMAGE}
VEOF
[[ -f "$VERSION_FILE" ]] && install -m 644 "$VERSION_FILE" "$INSTALL_DIR/PROJECT_VERSION"

info "Запуск контейнеров..."
cd "$INSTALL_DIR"
$COMPOSE_CMD up -d

info "Ожидание готовности n8n (до 120 сек)..."
for i in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${N8N_PORT}" >/dev/null 2>&1; then
    log "n8n доступен: $WEBHOOK_URL"
    break
  fi
  sleep 2
  if [[ "$i" -eq 60 ]]; then
    warn "n8n не ответил за 120 сек. Логи: cd $INSTALL_DIR && $COMPOSE_CMD logs -f"
  fi
done

(crontab -l 2>/dev/null | grep -v "$INSTALL_DIR/backup.sh"; echo "0 2 * * * $INSTALL_DIR/backup.sh >> $INSTALL_DIR/backups/backup.log 2>&1") | crontab -
log "Ежедневный бэкап настроен (02:00)"

if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
  info "Открытие порта $N8N_PORT в UFW..."
  ufw allow "$N8N_PORT/tcp" comment "n8n" >/dev/null
fi

echo
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║         Установка завершена успешно!         ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo
echo -e "  ${BOLD}Внешний URL:${NC}    $WEBHOOK_URL"
echo -e "  ${BOLD}Локальный URL:${NC}  http://localhost:${N8N_PORT}"
echo -e "  ${BOLD}Директория:${NC}     $INSTALL_DIR"
echo -e "  ${BOLD}Версии:${NC}         $(tr '\n' ' ' < "$INSTALL_DIR/VERSION")"
echo
echo -e "  ${BOLD}PostgreSQL:${NC}"
echo -e "    DB:       $POSTGRES_DB"
echo -e "    User:     $POSTGRES_USER"
echo -e "    Password: $POSTGRES_PASSWORD"
warn "Сохраните пароль. Он записан в $INSTALL_DIR/.env и $PROJECT_ENV"
