# parquet_export.py — Nightly export of OHLCV data to Hive-partitioned Parquet files.
#
# Output layout (matching the design in WB-12):
#   <parquet_dir>/ohlcv/market=ASX/interval=daily/<year>.parquet
#   <parquet_dir>/ohlcv/market=ASX/interval=10min/<YYYY-MM>.parquet
#   <parquet_dir>/ohlcv/market=US/interval=daily/<year>.parquet
#   ...
#
# Each export covers the previous calendar day (or the full previous month for
# the monthly 10-min files). Already-exported files are overwritten to ensure
# they are complete (handles re-runs after partial failures).
#
# The export does NOT delete or trim TimescaleDB data — retention policies in
# 06-retention.sql govern TSDB lifetime. Parquet on disk (and B2) is the
# permanent archive.

import logging
import os
from datetime import date, timedelta
from pathlib import Path

import asyncpg
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

from config import settings

log = logging.getLogger(__name__)

# ─── Arrow schema for OHLCV Parquet files ─────────────────────────────────
# Storing symbol ticker as a string column (denormalized) so Parquet files are
# self-contained and readable without joining the symbols table.
OHLCV_SCHEMA = pa.schema([
    pa.field("time",       pa.timestamp("us", tz="UTC")),
    pa.field("ticker",     pa.string()),
    pa.field("open",       pa.float64()),
    pa.field("high",       pa.float64()),
    pa.field("low",        pa.float64()),
    pa.field("close",      pa.float64()),
    pa.field("volume",     pa.int64()),
    pa.field("bar_count",  pa.int32()),
])


async def export_daily(
    pool: asyncpg.Pool,
    market: str,
    exchange_codes: list[str],
    for_year: int | None = None,
) -> Path | None:
    """Export ohlcv_daily to a Parquet file for `for_year` (default: previous calendar year).

    Returns the path written, or None if no data found.
    """
    if for_year is None:
        for_year = date.today().year - 1

    year_start = f"{for_year}-01-01"
    year_end   = f"{for_year}-12-31"

    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT d.time, s.ticker, d.open, d.high, d.low, d.close,
                   d.volume, d.bar_count
              FROM ohlcv_daily d
              JOIN symbols   s ON s.id = d.symbol_id
              JOIN exchanges e ON e.id = s.exchange_id
             WHERE e.code = ANY($1::text[])
               AND d.time >= $2::date
               AND d.time <= $3::date
             ORDER BY d.time, s.ticker
            """,
            exchange_codes, year_start, year_end,
        )

    if not rows:
        log.info("No daily data found for market=%s year=%d — skipping", market, for_year)
        return None

    df = pd.DataFrame(rows, columns=["time", "ticker", "open", "high", "low", "close", "volume", "bar_count"])
    df["time"] = pd.to_datetime(df["time"], utc=True)
    df["volume"] = df["volume"].astype("Int64")
    df["bar_count"] = df["bar_count"].astype("Int32")

    out_dir = Path(settings.parquet_dir) / "ohlcv" / f"market={market}" / "interval=daily"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{for_year}.parquet"

    table = pa.Table.from_pandas(df, schema=OHLCV_SCHEMA, preserve_index=False)
    pq.write_table(table, out_path, compression="snappy")
    log.info("Exported %d rows → %s", len(df), out_path)
    return out_path


async def export_current_year_daily(
    pool: asyncpg.Pool,
    market: str,
    exchange_codes: list[str],
) -> Path | None:
    """Export ohlcv_daily for the current calendar year (partial).

    Called nightly after market close to keep the current-year file up to date.
    Overwrites the existing file each time so it is always complete.
    """
    return await export_daily(pool, market, exchange_codes, for_year=date.today().year)


async def export_10min_month(
    pool: asyncpg.Pool,
    market: str,
    exchange_codes: list[str],
    year: int | None = None,
    month: int | None = None,
) -> Path | None:
    """Export ohlcv_10min for one calendar month to a Parquet file.

    Defaults to the previous calendar month (good for a monthly cron job).
    Returns the path written, or None if no data found.
    """
    today = date.today()
    if year is None or month is None:
        first_of_this_month = today.replace(day=1)
        last_month = first_of_this_month - timedelta(days=1)
        year  = last_month.year
        month = last_month.month

    month_start = f"{year}-{month:02d}-01"
    # Last day of the month: go to next month's first day minus 1
    next_month_first = date(year + (month // 12), (month % 12) + 1, 1)
    month_end = (next_month_first - timedelta(days=1)).isoformat()

    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT d.time, s.ticker, d.open, d.high, d.low, d.close,
                   d.volume, d.bar_count
              FROM ohlcv_10min d
              JOIN symbols   s ON s.id = d.symbol_id
              JOIN exchanges e ON e.id = s.exchange_id
             WHERE e.code = ANY($1::text[])
               AND d.time >= $2::timestamptz
               AND d.time <= ($3::date + INTERVAL '23:59:59')::timestamptz
             ORDER BY d.time, s.ticker
            """,
            exchange_codes, month_start, month_end,
        )

    if not rows:
        log.info("No 10min data for market=%s %d-%02d — skipping", market, year, month)
        return None

    df = pd.DataFrame(rows, columns=["time", "ticker", "open", "high", "low", "close", "volume", "bar_count"])
    df["time"] = pd.to_datetime(df["time"], utc=True)

    out_dir = Path(settings.parquet_dir) / "ohlcv" / f"market={market}" / "interval=10min"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{year}-{month:02d}.parquet"

    table = pa.Table.from_pandas(df, schema=OHLCV_SCHEMA, preserve_index=False)
    pq.write_table(table, out_path, compression="snappy")
    log.info("Exported %d rows → %s", len(df), out_path)
    return out_path


async def run_nightly_export(pool: asyncpg.Pool) -> None:
    """Run all nightly export jobs: current-year daily for ASX and US."""
    log.info("Starting nightly Parquet export")
    await export_current_year_daily(pool, market="ASX", exchange_codes=["ASX"])
    await export_current_year_daily(pool, market="US",  exchange_codes=["NYSE", "NASDAQ", "ARCA"])
    log.info("Nightly Parquet export complete")
