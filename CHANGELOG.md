# Changelog

## 1.3.3
- Added interactive `N8N_SECURE_COOKIE` prompt for direct IP/http installs.
- Default for `N8N_SECURE_COOKIE` stays `true`; HTTPS mode forces `true`.
- Added `N8N_SECURE_COOKIE` to generated `.env`, `.env.example`, and container environment.

## 1.3.2
- Fixed ownership and permissions for `n8n_data` and `postgres_data` during install.
- Removed obsolete `version:` from `docker-compose.yml.example`.
- Replaced fragile `/healthz` readiness check with a direct HTTP check on the n8n port.
- Added `TZ` to n8n container environment.

## 1.3.1
- Fixed broken `.env` writing for secret values entered during interactive install.
- Switched generated secrets from base64 to hex to avoid unsafe characters in `.env`.
- Added `.env` validation before sourcing and before `docker compose up -d`.
- Added `TZ` to generated env files.
