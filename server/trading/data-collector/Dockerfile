FROM python:3.12-slim

# Install system deps for asyncpg and PDF parsing
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app

# Copy dependency files first for layer caching
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY src/ ./src/
COPY scripts/ ./scripts/

ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONPATH="/app/src"
ENV PYTHONUNBUFFERED=1

# Health check: verify ib_insync and asyncpg import cleanly
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python -c "import ib_insync, asyncpg; print('ok')" || exit 1

CMD ["python", "-m", "main"]
