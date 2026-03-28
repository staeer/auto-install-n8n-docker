#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'
BOLD='\033[1m'

log()  { echo -e "[i] $*"; }
ok()   { echo -e "${GREEN}[✔] $*${NC}"; }
warn() { echo -e "${YELLOW}[!] $*${NC}"; }
err()  { echo -e "${RED}[x] $*${NC}" >&2; exit 1; }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

ask_yes_no() {
  local prompt="$1" default="${2:-N}" answer shown
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

require_root() {
  [[ "${EUID}" -eq 0 ]] || err "Запусти так: sudo bash uninstall.sh"
}

detect_compose() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
  else
    err "Docker Compose не найден"
  fi
}

load_env_if_exists() {
  if [[ -f "$INSTALL_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$INSTALL_DIR/.env"
    set +a
  fi
}

validate_install_dir() {
  [[ -n "${INSTALL_DIR:-}" ]] || err "INSTALL_DIR пустой"
  [[ "$INSTALL_DIR" != "/" ]] || err "Нельзя удалять /"
  [[ "$INSTALL_DIR" == /opt/* || "$INSTALL_DIR" == /srv/* || "$INSTALL_DIR" == /home/* ]] || \
    warn "Нестандартный путь: $INSTALL_DIR"
}

remove_stack() {
  if [[ -f "$INSTALL_DIR/docker-compose.yml" ]]; then
    log "Остановка и удаление контейнеров..."
    cd "$INSTALL_DIR"
    $COMPOSE_CMD down -v --remove-orphans || true
  else
    warn "docker-compose.yml не найден, пропускаю compose down"
  fi
}

remove_project_network_if_exists() {
  if docker network inspect n8n_n8n_net >/dev/null 2>&1; then
    log "Удаление сети n8n_n8n_net..."
    docker network rm n8n_n8n_net >/dev/null 2>&1 || true
  fi
}

remove_images() {
  local images=()
  [[ -n "${N8N_IMAGE:-}" ]] && images+=("$N8N_IMAGE")
  [[ -n "${POSTGRES_IMAGE:-}" ]] && images+=("$POSTGRES_IMAGE")

  if [[ "${#images[@]}" -eq 0 ]]; then
    warn "Список образов пустой, пропускаю"
    return
  fi

  log "Удаление образов..."
  docker rmi "${images[@]}" >/dev/null 2>&1 || true
  ok "Образы удалены"
}

remove_install_dir() {
  log "Удаление директории $INSTALL_DIR ..."
  rm -rf "$INSTALL_DIR"
  ok "Директория удалена"
}

remove_backup_cron() {
  local current_cron
  current_cron="$(crontab -l 2>/dev/null || true)"
  if [[ -z "$current_cron" ]]; then
    return
  fi

  printf '%s\n' "$current_cron" \
    | grep -vF "$INSTALL_DIR/backup-n8n.sh" \
    | crontab - || true

  ok "Cron backup очищен"
}

main() {
  require_root

  INSTALL_DIR="${1:-/opt/n8n}"
  N8N_IMAGE="n8nio/n8n:2.13.0"
  POSTGRES_IMAGE="postgres:16-alpine"

  validate_install_dir
  load_env_if_exists
  detect_compose

  echo -e "${RED}${BOLD}ВНИМАНИЕ${NC}"
  echo "Будет остановлен и удалён стек n8n + PostgreSQL."
  echo "Директория установки: $INSTALL_DIR"
  echo "n8n image: ${N8N_IMAGE:-неизвестно}"
  echo "postgres image: ${POSTGRES_IMAGE:-неизвестно}"
  echo

  ask_yes_no "Продолжить удаление контейнеров и volumes?" "N" || {
    echo "Отменено."
    exit 0
  }

  remove_stack
  remove_project_network_if_exists
  remove_backup_cron

  if ask_yes_no "Удалить Docker-образы?" "N"; then
    remove_images
  fi

  if ask_yes_no "Удалить директорию с данными ($INSTALL_DIR)?" "N"; then
    remove_install_dir
  fi

  echo
  ok "Удаление завершено"
}

main "$@"