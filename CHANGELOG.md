# Changelog

## 1.2.0
- Git-friendly project structure
- `docker-compose.yml` moved to standalone template file
- `backup-n8n.sh` moved to standalone script file
- `install.sh` now copies project files instead of generating compose inline
- Fixed image versioning kept in `.env.example`
- Default timezone remains `UTC`
- `WEBHOOK_URL` logic kept corrected for reverse proxy and direct access
