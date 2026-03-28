#!/bin/bash
# =============================================================
#  Auto-install: Docker + n8n + PostgreSQL
#  Tested on: Ubuntu 20.04 / 22.04 / 24.04, Debian 11/12
#  Installer version: 1.1.0
# =============================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${GREEN}[✔]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
err()  { echo -e "${RED}[✘]${NC} $1"; exit 1; }

trim() {
  local var="$1"
  var="${var#${var%%[![:space:]]*}}"
  var="${var%${var##*[![:space:]]}}"
  printf '%s' "$var"
}

make_webhook_url() {
  local protocol="$1"
  local host="$2"
  local port="$3"
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

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║     Docker + n8n + PostgreSQL Setup      ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

[[ $EUID -ne 0 ]] && err "Запустите скрипт от root: sudo bash install.sh"

CONFIG_FILE="$(dirname "$0")/.env"
if [[ -f "$CONFIG_FILE" ]]; then
  info "Загружаю конфигурацию из .env"
  set -a
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  set +a
fi

STACK_VERSION="${STACK_VERSION:-1.1.0}"
N8N_IMAGE="${N8N_IMAGE:-n8nio/n8n:2.13.0}"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:16-alpine}"
POSTGRES_USER="$(trim "${POSTGRES_USER:-n8n}")"
POSTGRES_PASSWORD="$(trim "${POSTGRES_PASSWORD:-}")"
POSTGRES_DB="$(trim "${POSTGRES_DB:-n8n}")"
N8N_PORT="$(trim "${N8N_PORT:-5678}")"
N8N_ENCRYPTION_KEY="$(trim "${N8N_ENCRYPTION_KEY:-}")"
GENERIC_TIMEZONE="$(trim "${GENERIC_TIMEZONE:-UTC}")"
INSTALL_DIR="$(trim "${INSTALL_DIR:-/opt/n8n}")"
N8N_HOST="$(trim "${N8N_HOST:-localhost}")"
N8N_PROTOCOL="$(trim "${N8N_PROTOCOL:-http}")"
WEBHOOK_URL="$(trim "${WEBHOOK_URL:-}")"

[[ -z "$POSTGRES_PASSWORD" ]] && POSTGRES_PASSWORD="$(openssl rand -base64 16 | tr -d '\n')"
[[ -z "$N8N_ENCRYPTION_KEY" ]] && N8N_ENCRYPTION_KEY="$(openssl rand -base64 32 | tr -d '\n')"
[[ -z "$WEBHOOK_URL" ]] && WEBHOOK_URL="$(make_webhook_url "$N8N_PROTOCOL" "$N8N_HOST" "$N8N_PORT")"

case "$N8N_PROTOCOL" in
  http|https) ;;
  *) err "N8N_PROTOCOL должен быть http или https" ;;
esac

[[ "$WEBHOOK_URL" != */ ]] && WEBHOOK_URL="${WEBHOOK_URL}/"

echo ""
info "Параметры установки:"
echo "  Версия инсталлятора: $STACK_VERSION"
echo "  n8n image:           $N8N_IMAGE"
echo "  PostgreSQL image:    $POSTGRES_IMAGE"
echo "  Директория:          $INSTALL_DIR"
echo "  n8n порт:            $N8N_PORT"
echo "  Внешний адрес:       $WEBHOOK_URL"
echo "  Timezone:            $GENERIC_TIMEZONE"
echo ""
read -p "Продолжить? [y/N] " -n 1 -r
echo ""
[[ ! $REPLY =~ ^[Yy]$ ]] && err "Установка отменена."

info "Обновление системы..."
apt-get update -qq
apt-get install -y -qq curl wget gnupg2 ca-certificates lsb-release \
  apt-transport-https software-properties-common openssl

if command -v docker &>/dev/null; then
  warn "Docker уже установлен ($(docker --version | cut -d' ' -f3 | tr -d ','))"
else
  info "Установка Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
  log "Docker установлен"
fi

if command -v docker compose &>/dev/null 2>&1; then
  warn "Docker Compose plugin уже установлен"
elif command -v docker-compose &>/dev/null; then
  warn "docker-compose уже установлен"
else
  info "Установка Docker Compose plugin..."
  apt-get install -y -qq docker-compose-plugin 2>/dev/null || \
  curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
    -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose
  log "Docker Compose установлен"
fi

if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
else
  COMPOSE_CMD="docker-compose"
fi

info "Создание директорий..."
mkdir -p "$INSTALL_DIR"/{n8n_data,postgres_data,backups}
chmod 700 "$INSTALL_DIR/postgres_data"
cd "$INSTALL_DIR"

info "Запись конфигурации..."
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
N8N_HOST=${N8N_HOST}
N8N_PROTOCOL=${N8N_PROTOCOL}
WEBHOOK_URL=${WEBHOOK_URL}
INSTALL_DIR=${INSTALL_DIR}
ENVEOF
chmod 600 "$INSTALL_DIR/.env"
log ".env сохранён"

info "Создание docker-compose.yml..."
cat > "$INSTALL_DIR/docker-compose.yml" <<'COMPOSE'
version: "3.8"

services:
  postgres:
    image: ${POSTGRES_IMAGE}
    container_name: n8n_postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - ${INSTALL_DIR}/postgres_data:/var/lib/postgresql/data
      - ${INSTALL_DIR}/backups:/backups
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - n8n_net

  n8n:
    image: ${N8N_IMAGE}
    container_name: n8n_app
    restart: unless-stopped
    ports:
      - "${N8N_PORT}:5678"
    environment:
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: ${POSTGRES_DB}
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      N8N_HOST: ${N8N_HOST}
      N8N_PORT: 5678
      N8N_PROTOCOL: ${N8N_PROTOCOL}
      WEBHOOK_URL: ${WEBHOOK_URL}
      EXECUTIONS_DATA_PRUNE: "true"
      EXECUTIONS_DATA_MAX_AGE: 336
      GENERIC_TIMEZONE: ${GENERIC_TIMEZONE}
    volumes:
      - ${INSTALL_DIR}/n8n_data:/home/node/.n8n
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - n8n_net

networks:
  n8n_net:
    driver: bridge
COMPOSE

cat > "$INSTALL_DIR/VERSION" <<VEOF
STACK_VERSION=${STACK_VERSION}
N8N_IMAGE=${N8N_IMAGE}
POSTGRES_IMAGE=${POSTGRES_IMAGE}
VEOF

log "docker-compose.yml создан"

info "Запуск контейнеров..."
cd "$INSTALL_DIR"
$COMPOSE_CMD up -d

info "Ожидание готовности n8n (до 120 сек)..."
for i in $(seq 1 60); do
  if curl -fsS "http://localhost:${N8N_PORT}/healthz" 2>/dev/null | grep -q 'ok'; then
    log "n8n отвечает по /healthz"
    break
  fi
  sleep 2
  if [[ "$i" -eq 60 ]]; then
    warn "n8n не ответил по /healthz за 120 сек. Смотрите логи: cd $INSTALL_DIR && $COMPOSE_CMD logs -f"
  fi
done

info "Установка скрипта резервного копирования..."
cat > "$INSTALL_DIR/backup.sh" <<BACKUP
#!/bin/bash
BACKUP_DIR="${INSTALL_DIR}/backups"
DATE=\$(date +%Y%m%d_%H%M%S)
FILE="\$BACKUP_DIR/n8n_pg_\$DATE.sql.gz"

docker exec n8n_postgres pg_dump -U ${POSTGRES_USER} ${POSTGRES_DB} | gzip > "\$FILE"
ls -t "\$BACKUP_DIR"/*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm
echo "Backup saved: \$FILE"
BACKUP
chmod +x "$INSTALL_DIR/backup.sh"

(crontab -l 2>/dev/null; echo "0 2 * * * $INSTALL_DIR/backup.sh >> $INSTALL_DIR/backups/backup.log 2>&1") | crontab -
log "Ежедневный бэкап настроен (02:00)"

if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
  info "Открытие порта $N8N_PORT в UFW..."
  ufw allow "$N8N_PORT/tcp" comment "n8n" >/dev/null
fi

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║         Установка завершена успешно!         ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Внешний URL:${NC}    $WEBHOOK_URL"
echo -e "  ${BOLD}Локальный URL:${NC}  http://localhost:${N8N_PORT}"
echo -e "  ${BOLD}Директория:${NC}     $INSTALL_DIR"
echo -e "  ${BOLD}Версии:${NC}         $(tr '\n' ' ' < "$INSTALL_DIR/VERSION")"
echo ""
echo -e "  ${BOLD}PostgreSQL:${NC}"
echo -e "    DB:       $POSTGRES_DB"
echo -e "    User:     $POSTGRES_USER"
echo -e "    Password: $POSTGRES_PASSWORD"
echo ""
warn "Сохраните пароль! Он также записан в $INSTALL_DIR/.env"
echo ""
echo -e "  Полезные команды:"
echo -e "    Статус:   cd $INSTALL_DIR && $COMPOSE_CMD ps"
echo -e "    Логи:     cd $INSTALL_DIR && $COMPOSE_CMD logs -f"
echo -e "    Стоп:     cd $INSTALL_DIR && $COMPOSE_CMD down"
echo -e "    Бэкап:    $INSTALL_DIR/backup.sh"
echo ""
