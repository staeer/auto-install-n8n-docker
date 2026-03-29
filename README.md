# auto-install-n8n-docker для Ubuntu

Интерактивный установщик `Docker + PostgreSQL + n8n` для Ubuntu.

README ниже приведён по фактическому поведению файлов репозитория: `install.sh`, `docker-compose.yml.example`, `backup-n8n.sh`, `.env.example`, `VERSION`, `CHANGELOG.md`, `uninstall.sh`.

## Что ставится

Стек поднимает:

- `n8nio/n8n:2.13.0`
- `postgres:16-alpine`

Сервисы запускаются через Docker Compose.

## Что делает install.sh

Скрипт:

1. Проверяет и при необходимости устанавливает Docker.
2. Использует `docker compose`, а если его нет — ставит `docker-compose-plugin`.
3. Спрашивает параметры установки.
4. Создаёт `.env` в каталоге репозитория.
5. Создаёт каталог установки и копирует туда конфиги.
6. Поднимает контейнеры `postgres` и `n8n`.
7. Настраивает ежедневный backup PostgreSQL через cron.
8. Показывает итоговые параметры установки.

## Что спросит установщик

Скрипт спрашивает:

- режим доступа:
  - `1` — домен + reverse proxy + HTTPS
  - `2` — прямой доступ по IP:порт
- `POSTGRES_USER`
- `POSTGRES_DB`
- `POSTGRES_PASSWORD`
- `N8N_ENCRYPTION_KEY`
- `N8N_PORT`
- `GENERIC_TIMEZONE`
- `INSTALL_DIR`
- для режима `1`: домен `N8N_HOST`
- для режима `2`: IP/hostname `N8N_HOST`
- для режима `2`: `N8N_SECURE_COOKIE` (`true/false`)

Если пароль БД и `N8N_ENCRYPTION_KEY` не заданы, скрипт генерирует их автоматически.

## Быстрый запуск

```bash
git clone https://github.com/staeer/auto-install-n8n-docker.git
cd auto-install-n8n-docker
sudo bash install.sh
```

## Повторный запуск

Если рядом со скриптом уже есть файл `.env`, установщик спросит:

- использовать существующий `.env` без повторных вопросов;
- или пройти интерактивную настройку заново.

Если в существующем `.env` пустые `POSTGRES_PASSWORD`, `N8N_ENCRYPTION_KEY` или `WEBHOOK_URL`, скрипт их дозаполнит.

## Куда ставится

По умолчанию установка идёт в:

```bash
/opt/n8n
```

В каталоге установки создаются:

```text
/opt/n8n/
├── .env
├── docker-compose.yml
├── backup-n8n.sh
├── VERSION
├── PROJECT_VERSION
├── backups/
├── n8n_data/
└── postgres_data/
```

## Где лежат данные после установки

### Доступ к PostgreSQL

После установки данные БД лежат в двух местах:

1. в `.env` рядом с `install.sh`
2. в `.env` внутри каталога установки

Ищи здесь:

```bash
./.env
```

и здесь:

```bash
/opt/n8n/.env
```

Нужные поля:

```bash
POSTGRES_USER=
POSTGRES_PASSWORD=
POSTGRES_DB=
```

### Папки с данными

```bash
/opt/n8n/postgres_data
/opt/n8n/n8n_data
/opt/n8n/backups
```

## Параметры окружения, которые реально используются

```bash
STACK_VERSION
N8N_IMAGE
POSTGRES_IMAGE
POSTGRES_USER
POSTGRES_PASSWORD
POSTGRES_DB
N8N_PORT
N8N_ENCRYPTION_KEY
GENERIC_TIMEZONE
TZ
INSTALL_DIR
N8N_HOST
N8N_PROTOCOL
WEBHOOK_URL
N8N_SECURE_COOKIE
```

## Как формируется доступ к n8n

### Режим 1 — домен + reverse proxy + HTTPS

Скрипт выставляет:

```bash
N8N_PROTOCOL=https
WEBHOOK_URL=https://<ваш-домен>/
N8N_SECURE_COOKIE=true
```

В этом режиме предполагается, что HTTPS и внешний reverse proxy уже есть снаружи.

### Режим 2 — прямой доступ по IP:порт

Скрипт выставляет:

```bash
N8N_PROTOCOL=http
WEBHOOK_URL=http://<ip-или-host>:<порт>/
```

`N8N_SECURE_COOKIE` в этом режиме спрашивается отдельно.

## Какие порты и контейнеры используются

Контейнеры:

- `n8n_app`
- `n8n_postgres`

Публикуется наружу порт:

```bash
<N8N_PORT>:5678
```

Внутри Compose n8n ходит в PostgreSQL по хосту:

```bash
postgres:5432
```

## Автозапуск после перезагрузки сервера

Да, автозапуск предусмотрен.

Почему сервисы поднимаются после reboot:

- `install.sh` включает Docker через `systemctl enable docker` и сразу запускает его через `systemctl start docker`;
- в `docker-compose.yml` у `postgres` стоит `restart: unless-stopped`;
- в `docker-compose.yml` у `n8n` тоже стоит `restart: unless-stopped`.

Это значит:

- после перезагрузки стартует сам Docker;
- Docker поднимает контейнеры `n8n_postgres` и `n8n_app`, если их не останавливали вручную через `docker stop` или `docker compose stop`.

Проверка после reboot:

```bash
cd /opt/n8n
docker compose ps
```

## Backup

После установки добавляется cron-задача:

```bash
0 2 * * * /opt/n8n/backup-n8n.sh >> /opt/n8n/backups/backup.log 2>&1
```

Что делает backup:

- запускает `pg_dump` из контейнера `n8n_postgres`;
- складывает архивы в `INSTALL_DIR/backups`;
- имя файла:

```bash
n8n_pg_YYYYMMDD_HHMMSS.sql.gz
```

- хранит последние 7 backup-файлов, более старые удаляет.

### Ручной запуск backup

```bash
sudo bash /opt/n8n/backup-n8n.sh
```

## Полезные команды после установки

### Проверить контейнеры

```bash
cd /opt/n8n
docker compose ps
```

### Посмотреть логи n8n

```bash
cd /opt/n8n
docker compose logs -f n8n
```

### Посмотреть логи PostgreSQL

```bash
cd /opt/n8n
docker compose logs -f postgres
```

### Открыть установленный `.env`

```bash
sudo nano /opt/n8n/.env
```

### Перезапустить стек

```bash
cd /opt/n8n
docker compose restart
```

### Полностью пересоздать контейнеры

```bash
cd /opt/n8n
docker compose up -d
```

## Удаление

Удаление по умолчанию:

```bash
git clone https://github.com/staeer/auto-install-n8n-docker.git
cd auto-install-n8n-docker
sudo bash uninstall.sh
```

Удаление для кастомного пути:

```bash
git clone https://github.com/staeer/auto-install-n8n-docker.git
cd auto-install-n8n-docker
sudo bash uninstall.sh /opt/n8n
```

## Что делает uninstall.sh

Скрипт:

1. Берёт путь установки из аргумента, по умолчанию `/opt/n8n`.
2. Если есть `/opt/n8n/.env`, подгружает оттуда параметры.
3. Выполняет `docker compose down -v --remove-orphans`.
4. Пытается удалить сеть `n8n_n8n_net`.
5. Удаляет cron backup для `backup-n8n.sh`.
6. По подтверждению удаляет Docker-образы.
7. По подтверждению удаляет каталог установки.

## Важные нюансы

### 1. Текущая версия

В `install.sh` используется версия стека `1.3.5`. Если версия в `VERSION`, `.env.example` и `CHANGELOG.md` совпадает, это и есть текущая релизная версия репозитория.

### 2. Локальная проверка готовности

После `docker compose up -d` скрипт проверяет доступность web-интерфейса n8n локально, через `127.0.0.1` и выбранный `N8N_PORT`.

## Минимальный сценарий восстановления доступа к базе

Если после установки нужно подключиться к PostgreSQL из клиента, бери значения из:

```bash
cat /opt/n8n/.env
```

Дальше используй:

- host: IP сервера
- port: тот порт, который ты сам пробросишь наружу, если решишь публиковать PostgreSQL отдельно
- database: `POSTGRES_DB`
- user: `POSTGRES_USER`
- password: `POSTGRES_PASSWORD`

По умолчанию PostgreSQL наружу не публикуется, он доступен только внутри docker-сети проекта.
