# Devtools Stack

## Overview

The devtools stack groups:

- **code-server** for browser-based VS Code
- **Ollama** for a local coding model

The stack lives in `server/devtools/`.

## Authentication model

- **code-server** uses its own password from `server/devtools/.env`
- **Ollama** is internal-only by default and is not exposed through Traefik
- Authelia can be layered on later if admin surfaces are centralized

## Persistence

The stack stores data under `/data/devtools/`:

- `projects/`
- `code-server/`
- `ollama/`

These directories are created by `server/scripts/setup/install.sh`.

## Resource notes

This stack uses standalone Docker Compose memory controls:

- `mem_limit`
- `mem_reservation`

It does **not** rely on Swarm-only `deploy.resources.reservations`.

## First-time setup

1. Copy `server/devtools/.env.example` to `server/devtools/.env`
2. Set `DOMAIN`
3. Set `CODE_SERVER_PASSWORD`
4. Review or adjust `OLLAMA_MODEL`, `OLLAMA_NUM_PARALLEL`, and `OLLAMA_KEEP_ALIVE`
5. Start the stack:
   ```bash
   cd server/devtools
   docker compose up -d
   ```
6. Warm the Ollama model:
   ```bash
   cd ..
   ./scripts/initialization/warm-up-ollama-model.sh
   ```

## URLs

- `https://vscode.<your-domain>`

Ollama stays on the internal Docker network unless you intentionally add a public route later.
