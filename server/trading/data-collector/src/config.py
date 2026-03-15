# config.py — typed settings loaded from environment variables.
# All values are required unless a default is provided.
# The .env file is mounted at /app/.env in production; pass --env-file to docker run.

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # ─── TWS connection ─────────────────────────────────────────────────────
    tws_host: str = "tws"           # Docker service name in the trading network
    tws_port: int = 7497            # 7497 = paper; 7496 = live
    tws_client_id: int = 1          # Client ID for data-collector (must be unique per connection)

    # ─── Database ────────────────────────────────────────────────────────────
    db_host: str = "timescaledb"
    db_port: int = 5432
    db_name: str = "trading"
    db_user: str = "trading"
    db_password: str              # Required; no default

    # ─── Data collection behaviour ───────────────────────────────────────────
    # Comma-separated list of extra individual tickers to always collect
    # (beyond index constituents).  e.g. "STW,BTC"
    extra_tickers: str = "STW"

    # How many years of history to backfill on first run for a new symbol
    daily_backfill_years: int = 20
    # 10-min backfill is limited by IBKR to ~180 calendar days
    intraday_backfill_days: int = 179

    # ASX trading session end (Sydney local time HH:MM) — used for scheduling
    asx_close_time: str = "16:10"   # slight buffer after 16:00 AEST/AEDT close

    # ─── Parquet export ──────────────────────────────────────────────────────
    parquet_dir: str = "/data/trading/parquet"

    # ─── IBKR pacing ─────────────────────────────────────────────────────────
    # Seconds to sleep between consecutive reqHistoricalData calls
    ibkr_request_interval: float = 2.0
    # Extra pause (seconds) every N requests to avoid pacing violations
    ibkr_batch_pause: float = 10.0
    ibkr_batch_size: int = 50

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )


# Singleton loaded once at import time
settings = Settings()
