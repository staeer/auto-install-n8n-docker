#!/bin/bash
# =============================================================
#  Удаление: n8n + PostgreSQL контейнеров
# =============================================================

set -e
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'; BOLD='\033[1m'

[[ $EUID -ne 0 ]] && echo -e "${RED}Нужны права root!${NC}" && exit 1

INSTALL_DIR="${1:-/opt/n8n}"

echo -e "${RED}${BOLD}ВНИМАНИЕ: Это удалит n8n и все данные PostgreSQL!${NC}"
echo "Директория: $INSTALL_DIR"
echo ""
read -p "Введите 'yes' для подтверждения: " CONFIRM
[[ "$CONFIRM" != "yes" ]] && echo "Отменено." && exit 0

# Определяем compose команду
if docker compose version &>/dev/null 2>&1; then COMPOSE_CMD="docker compose"
else COMPOSE_CMD="docker-compose"; fi

# Останавливаем и удаляем контейнеры
if [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
  echo -e "${YELLOW}Остановка контейнеров...${NC}"
  cd "$INSTALL_DIR"
  $COMPOSE_CMD down -v --remove-orphans 2>/dev/null || true
fi

# Удаляем образы (опционально)
read -p "Удалить Docker образы n8n и postgres? [y/N] " -n 1 -r; echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  docker rmi n8nio/n8n:latest postgres:16-alpine 2>/dev/null || true
  echo -e "${GREEN}Образы удалены${NC}"
fi

# Удаляем данные (опционально)
read -p "Удалить данные в $INSTALL_DIR? [y/N] " -n 1 -r; echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
  rm -rf "$INSTALL_DIR"
  echo -e "${GREEN}Директория $INSTALL_DIR удалена${NC}"
fi

# Удаляем cron
(crontab -l 2>/dev/null | grep -v "backup.sh") | crontab - 2>/dev/null || true

echo -e "${GREEN}Готово! n8n и PostgreSQL удалены.${NC}"
