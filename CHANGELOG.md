# Changelog

## 1.3.1
- Fixed broken `.env` writing for secret values entered during interactive install.
- Switched generated secrets from base64 to hex to avoid unsafe characters in `.env`.
- Added `.env` validation before sourcing and before `docker compose up -d`.
- Added `TZ` to generated env files.
