# Changelog

## 1.1.0
- n8n image pinned to `n8nio/n8n:2.13.0`
- PostgreSQL image moved to configurable variable `POSTGRES_IMAGE`
- default timezone set to `UTC`
- fixed `WEBHOOK_URL` logic for direct access and reverse proxy
- added `STACK_VERSION`, `N8N_IMAGE`, `POSTGRES_IMAGE`, `VERSION`
- cleaned `.env.example` comments and empty values handling
- `uninstall.sh` now removes pinned images from installed `.env`
