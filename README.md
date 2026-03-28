# auto-install-n8n-docker

Git-friendly installer for Docker + n8n + PostgreSQL.

## Files
- `install.sh` — installs Docker if needed, prepares `.env`, copies project files, starts stack
- `docker-compose.yml.example` — compose template stored in Git
- `backup-n8n.sh` — PostgreSQL backup script stored in Git
- `.env.example` — editable configuration with fixed image versions
- `VERSION` — project version file
- `CHANGELOG.md` — change log

## Install
```bash
git clone https://github.com/staeer/auto-install-n8n-docker.git
cd auto-install-n8n-docker
cp .env.example .env
nano .env
sudo bash install.sh
```

## Update
```bash
cd auto-install-n8n-docker
git pull
sudo bash install.sh
```

## Notes
- For reverse proxy use `N8N_PROTOCOL=https` and external domain in `N8N_HOST`
- For direct IP access leave `http`
- If `POSTGRES_PASSWORD` or `N8N_ENCRYPTION_KEY` are empty, installer generates them
