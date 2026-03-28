#!/bin/bash
# =============================================================
#  Auto-install: Docker + n8n + PostgreSQL
#  Tested on: Ubuntu 20.04 / 22.04 / 24.04, Debian 11/12
# =============================================================

set -e

# ─── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${GREEN}[✔]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
err()  { echo -e "${RED}[✘]${NC} $1"; exit 1; }

# ─── Banner ───────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════╗"
echo "║     Docker + n8n + PostgreSQL Setup      ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ─── Root check ───────────────────────────────────────────────
[[ $EUID -ne 0 ]] && err "Запустите скрипт от root: sudo bash install.sh"

# ─── Load config ──────────────────────────────────────────────
CONFIG_FILE="$(dirname "$0")/.env"
if [[ -f "$CONFIG_FILE" ]]; then
  info "Загружаю конфигурацию из .env"
  source "$CONFIG_FILE"
fi

# ─── Defaults (override via .env) ─────────────────────────────
POSTGRES_USER="${POSTGRES_USER:-n8n}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -base64 16)}"
POSTGRES_DB="${POSTGRES_DB:-n8n}"
N8N_PORT="${N8N_PORT:-5678}"
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-$(openssl rand -base64 32)}"
INSTALL_DIR="${INSTALL_DIR:-/opt/n8n}"
N8N_HOST="${N8N_HOST:-localhost}"
N8N_PROTOCOL="${N8N_PROTOCOL:-http}"

echo ""
info "Параметры установки:"
echo "  Директория:       $INSTALL_DIR"
echo "  n8n порт:         $N8N_PORT"
echo "  PostgreSQL DB:    $POSTGRES_DB"
echo "  PostgreSQL User:  $POSTGRES_USER"
echo ""
read -p "Продолжить? [y/N] " -n 1 -r
echo ""
[[ ! $REPLY =~ ^[Yy]$ ]] && err "Установка отменена."

# ─── 1. System update ─────────────────────────────────────────
info "Обновление системы..."
apt-get update -qq
apt-get install -y -qq curl wget gnupg2 ca-certificates lsb-release \
  apt-transport-https software-properties-common openssl

# ─── 2. Install Docker ────────────────────────────────────────
if command -v docker &>/dev/null; then
  warn "Docker уже установлен ($(docker --version | cut -d' ' -f3 | tr -d ','))"
else
  info "Установка Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
  log "Docker установлен"
fi

# ─── 3. Install Docker Compose ────────────────────────────────
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

# Определяем команду compose
if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
else
  COMPOSE_CMD="docker-compose"
fi

# ─── 4. Prepare directories ───────────────────────────────────
info "Создание директорий..."
mkdir -p "$INSTALL_DIR"/{n8n_data,postgres_data,backups}
chmod 700 "$INSTALL_DIR/postgres_data"
cd "$INSTALL_DIR"

# ─── 5. Write .env ────────────────────────────────────────────
info "Запись конфигурации..."
cat > "$INSTALL_DIR/.env" <<EOF
# Auto-generated — $(date)
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
N8N_PORT=${N8N_PORT}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_HOST=${N8N_HOST}
N8N_PROTOCOL=${N8N_PROTOCOL}
INSTALL_DIR=${INSTALL_DIR}
EOF
chmod 600 "$INSTALL_DIR/.env"
log ".env сохранён"

# ─── 6. Write docker-compose.yml ──────────────────────────────
info "Создание docker-compose.yml..."
cat > "$INSTALL_DIR/docker-compose.yml" <<'COMPOSE'
version: "3.8"

services:
  postgres:
    image: postgres:16-alpine
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
    image: n8nio/n8n:latest
    container_name: n8n_app
    restart: unless-stopped
    ports:
      - "${N8N_PORT}:5678"
    environment:
      # Database
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: ${POSTGRES_DB}
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      # n8n settings
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      N8N_HOST: ${N8N_HOST}
      N8N_PORT: 5678
      N8N_PROTOCOL: ${N8N_PROTOCOL}
      WEBHOOK_URL: ${N8N_PROTOCOL}://${N8N_HOST}:${N8N_PORT}/
      # Performance
      EXECUTIONS_DATA_PRUNE: "true"
      EXECUTIONS_DATA_MAX_AGE: 336
      # Timezone
      GENERIC_TIMEZONE: Europe/Moscow
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

log "docker-compose.yml создан"

# ─── 7. Start services ────────────────────────────────────────
info "Запуск контейнеров..."
cd "$INSTALL_DIR"
$COMPOSE_CMD up -d

# Wait for n8n
info "Ожидание готовности n8n (до 60 сек)..."
for i in $(seq 1 30); do
  if curl -s "http://localhost:${N8N_PORT}/healthz" | grep -q "ok" 2>/dev/null; then
    break
  fi
  sleep 2
done

# ─── 8. Install backup script ─────────────────────────────────
info "Установка скрипта резервного копирования..."
cat > "$INSTALL_DIR/backup.sh" <<BACKUP
#!/bin/bash
# PostgreSQL backup script
BACKUP_DIR="${INSTALL_DIR}/backups"
DATE=\$(date +%Y%m%d_%H%M%S)
FILE="\$BACKUP_DIR/n8n_pg_\$DATE.sql.gz"

docker exec n8n_postgres pg_dump -U ${POSTGRES_USER} ${POSTGRES_DB} | gzip > "\$FILE"

# Keep only last 7 backups
ls -t "\$BACKUP_DIR"/*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm
echo "Backup saved: \$FILE"
BACKUP
chmod +x "$INSTALL_DIR/backup.sh"

# Add daily cron job
(crontab -l 2>/dev/null; echo "0 2 * * * $INSTALL_DIR/backup.sh >> $INSTALL_DIR/backups/backup.log 2>&1") | crontab -
log "Ежедневный бэкап настроен (02:00)"

# ─── 9. UFW firewall (optional) ───────────────────────────────
if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
  info "Открытие порта $N8N_PORT в UFW..."
  ufw allow "$N8N_PORT/tcp" comment "n8n" >/dev/null
fi

# ─── Done ─────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║         Установка завершена успешно!         ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}n8n URL:${NC}        http://$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP'):${N8N_PORT}"
echo -e "  ${BOLD}Директория:${NC}     $INSTALL_DIR"
echo -e "  ${BOLD}Бэкап скрипт:${NC}   $INSTALL_DIR/backup.sh"
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
