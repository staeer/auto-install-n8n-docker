# auto-install-n8n-docker

Интерактивный установщик Docker + PostgreSQL + n8n.

## Как запускать

```bash
git clone https://github.com/staeer/auto-install-n8n-docker.git
cd auto-install-n8n-docker
sudo bash install.sh
```

## Что делает install.sh

Скрипт сам по шагам спросит:
- домен или IP
- режим доступа: reverse proxy/https или прямой доступ по IP:порт
- порт n8n
- имя БД
- логин БД
- пароль БД
- N8N_ENCRYPTION_KEY
- timezone
- папку установки

Потом сам:
- создаст `.env`
- установит Docker
- поднимет PostgreSQL и n8n
- настроит backup cron
- покажет итоговые параметры

## Повторный запуск

Если `.env` уже есть, скрипт спросит:
- использовать существующий `.env`
- или пройти мастер вопросов заново


## Как запускать uninstall.sh

```bash
git clone https://github.com/staeer/auto-install-n8n-docker.git
cd auto-install-n8n-docker
sudo bash uninstall.sh
``
или для другого пути:

```bash
git clone https://github.com/staeer/auto-install-n8n-docker.git
cd auto-install-n8n-docker
sudo bash uninstall.sh /opt/n8n
``

