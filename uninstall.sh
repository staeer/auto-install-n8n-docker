#!/bin/bash
set -e
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'; BOLD='\033[1m'

[[ $EUID -ne 0 ]] && echo -e "${RED}Нужны права root!${NC}" && exit 1

INSTALL_DIR="${1:-/opt/n8n}"
N8N_IMAGE="n8nio/n8n:2.13.0"
POSTGRES_IMAGE="postgres:16-alpine"

if [[ -f "$INSTALL_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$INSTALL_DIR/.env"
  set +a
fi

echo -e "${RED}${BOLD}ВНИМАНИЕ: Это удалит n8n и все данные PostgreSQL!${NC}"
echo "Директория: $INSTALL_DIR"
echo ""
read -p "Введите 'yes' для подтверждения: " CONFIRM
[[ "$CONFIRM" != "yes" ]] && echo "Отменено." && exit 0

if docker compose version &>/dev/null 2>&1; then COMPOSE_CMD="docker compose"
else COMPOSE_CMD="docker-compose"; fi

if [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
  echo -e "${YELLOW}Остановка контейнеров...${NC}"
  cd "$INSTALL_DIR"
  $COMPOSE_CMD down -v --remove-orphans 2>/dev/null || true
fi

read -p "Удалить Docker образы n8n и postgres? [y/N] " -n 1 -r; echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  docker rmi "$N8N_IMAGE" "$POSTGRES_IMAGE" 2>/dev/null || true
  echo -e "${GREEN}Образы удалены${NC}"
fi

read -p "Удалить данные в $INSTALL_DIR? [y/N] " -n 1 -r; echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  rm -rf "$INSTALL_DIR"
  echo -e "${GREEN}Директория $INSTALL_DIR удалена${NC}"
fi

(crontab -l 2>/dev/null | grep -v "backup.sh") | crontab - 2>/dev/null || true

echo -e "${GREEN}Готово! n8n и PostgreSQL удалены.${NC}"
