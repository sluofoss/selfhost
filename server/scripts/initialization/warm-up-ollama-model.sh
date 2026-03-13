#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
STACK_DIR="$SERVER_DIR/devtools"

if [ ! -d "$STACK_DIR" ]; then
    echo "Devtools stack directory not found: $STACK_DIR" >&2
    exit 1
fi

cd "$STACK_DIR"

if [ ! -f .env ]; then
    echo "Missing $STACK_DIR/.env. Copy .env.example to .env and set the passwords first." >&2
    exit 1
fi

set -a
source ./.env
set +a

MODEL="${OLLAMA_MODEL:-qwen2.5-coder:3b}"

echo "Starting Ollama..."
docker compose up -d ollama

echo "Pulling model: $MODEL"
docker compose exec ollama ollama pull "$MODEL"

echo "Warming model into memory..."
docker compose exec ollama ollama run "$MODEL" "Reply with the single word ready."

echo "Current loaded models:"
docker compose exec ollama ollama ps
