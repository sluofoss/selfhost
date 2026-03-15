# db.py — asyncpg connection pool and all database write helpers.
#
# Design rules:
#   - All writes are upsert-on-conflict (idempotent) so restarts and re-runs
#     never create duplicates.
#   - Symbol lookup uses get_or_create_symbol() which caches results in memory
#     to avoid per-bar round trips.
#   - Bulk inserts use executemany with a VALUES list, not row-by-row INSERT.

import asyncio
import logging
from datetime import date, datetime, timezone
from typing import Optional

import asyncpg
from ib_insync import BarData

from config import settings

log = logging.getLogger(__name__)

# ─── Module-level cache: ticker+exchange → symbol_id ──────────────────────
_symbol_cache: dict[tuple[str, str, str], int] = {}
_cache_lock = asyncio.Lock()


async def create_pool() -> asyncpg.Pool:
    dsn = (
        f"postgresql://{settings.db_user}:{settings.db_password}"
        f"@{settings.db_host}:{settings.db_port}/{settings.db_name}"
    )
    pool = await asyncpg.create_pool(dsn, min_size=2, max_size=8)
    log.info("DB pool connected to %s:%s/%s", settings.db_host, settings.db_port, settings.db_name)
    return pool


async def get_or_create_symbol(
    pool: asyncpg.Pool,
    ticker: str,
    exchange_code: str,
    sec_type: str,
    currency: str,
    con_id: Optional[int] = None,
) -> int:
    """Return the symbol.id for (ticker, exchange, sec_type), creating it if absent."""
    cache_key = (ticker, exchange_code, sec_type)
    async with _cache_lock:
        if cache_key in _symbol_cache:
            return _symbol_cache[cache_key]

    async with pool.acquire() as conn:
        # Get or insert exchange
        exchange_id: int = await conn.fetchval(
            "SELECT id FROM exchanges WHERE code = $1", exchange_code
        )
        if exchange_id is None:
            raise ValueError(f"Unknown exchange code: {exchange_code!r}. Add it to 02-lookup-tables.sql.")

        # Upsert symbol — con_id update handled by DO UPDATE
        symbol_id: int = await conn.fetchval(
            """
            INSERT INTO symbols (ticker, exchange_id, sec_type, currency, con_id)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (ticker, exchange_id, sec_type) DO UPDATE
                SET con_id   = COALESCE(EXCLUDED.con_id, symbols.con_id),
                    active   = TRUE
            RETURNING id
            """,
            ticker, exchange_id, sec_type, currency, con_id,
        )

    async with _cache_lock:
        _symbol_cache[cache_key] = symbol_id

    return symbol_id


async def upsert_ohlcv_daily(
    pool: asyncpg.Pool,
    symbol_id: int,
    bars: list[BarData],
) -> int:
    """Bulk upsert daily OHLCV bars. Returns number of rows written."""
    if not bars:
        return 0

    rows = [
        (
            _bar_time_utc(b.date),  # TIMESTAMPTZ: midnight UTC for the exchange date
            symbol_id,
            b.open,
            b.high,
            b.low,
            b.close,
            int(b.volume) if b.volume is not None else None,
            int(b.barCount) if b.barCount is not None else None,
        )
        for b in bars
        if b.open is not None  # IBKR sometimes returns empty bars at end of range
    ]

    async with pool.acquire() as conn:
        await conn.executemany(
            """
            INSERT INTO ohlcv_daily
                (time, symbol_id, open, high, low, close, volume, bar_count)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            ON CONFLICT DO NOTHING
            """,
            rows,
        )
    return len(rows)


async def upsert_ohlcv_10min(
    pool: asyncpg.Pool,
    symbol_id: int,
    bars: list[BarData],
) -> int:
    """Bulk upsert 10-minute OHLCV bars. Returns number of rows written."""
    if not bars:
        return 0

    rows = [
        (
            _bar_time_utc(b.date),
            symbol_id,
            b.open,
            b.high,
            b.low,
            b.close,
            int(b.volume) if b.volume is not None else None,
            int(b.barCount) if b.barCount is not None else None,
        )
        for b in bars
        if b.open is not None
    ]

    async with pool.acquire() as conn:
        await conn.executemany(
            """
            INSERT INTO ohlcv_10min
                (time, symbol_id, open, high, low, close, volume, bar_count)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            ON CONFLICT DO NOTHING
            """,
            rows,
        )
    return len(rows)


async def get_last_bar_date(
    pool: asyncpg.Pool,
    table: str,
    symbol_id: int,
) -> Optional[datetime]:
    """Return the most recent bar timestamp for a symbol, or None if no data exists."""
    assert table in ("ohlcv_daily", "ohlcv_10min"), f"Unknown table: {table}"
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            f"SELECT MAX(time) AS last_time FROM {table} WHERE symbol_id = $1",
            symbol_id,
        )
    return row["last_time"] if row else None


async def upsert_constituent(
    pool: asyncpg.Pool,
    index_code: str,
    symbol_id: int,
    entry_date: date,
    exit_date: Optional[date] = None,
    source: str = "ibkr_scanner",
    notes: Optional[str] = None,
) -> None:
    """Insert or update a constituent record. No-op if exact record already exists."""
    async with pool.acquire() as conn:
        index_id: int = await conn.fetchval(
            "SELECT id FROM indices WHERE code = $1", index_code
        )
        if index_id is None:
            raise ValueError(f"Unknown index code: {index_code!r}")

        await conn.execute(
            """
            INSERT INTO index_constituents
                (index_id, symbol_id, entry_date, exit_date, source, notes)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (index_id, symbol_id, entry_date) DO UPDATE
                SET exit_date = EXCLUDED.exit_date,
                    source    = EXCLUDED.source,
                    notes     = COALESCE(EXCLUDED.notes, index_constituents.notes)
            """,
            index_id, symbol_id, entry_date, exit_date, source, notes,
        )


async def close_constituent(
    pool: asyncpg.Pool,
    index_code: str,
    symbol_id: int,
    exit_date: date,
) -> None:
    """Set exit_date on the currently-open constituent record for a symbol."""
    async with pool.acquire() as conn:
        index_id: int = await conn.fetchval(
            "SELECT id FROM indices WHERE code = $1", index_code
        )
        await conn.execute(
            """
            UPDATE index_constituents
               SET exit_date = $3
             WHERE index_id  = $1
               AND symbol_id = $2
               AND exit_date IS NULL
            """,
            index_id, symbol_id, exit_date,
        )


async def get_current_constituents(
    pool: asyncpg.Pool,
    index_code: str,
) -> set[int]:
    """Return the set of symbol_ids currently in the index (exit_date IS NULL)."""
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT ic.symbol_id
              FROM index_constituents ic
              JOIN indices i ON i.id = ic.index_id
             WHERE i.code = $1 AND ic.exit_date IS NULL
            """,
            index_code,
        )
    return {r["symbol_id"] for r in rows}


async def get_ever_constituents(
    pool: asyncpg.Pool,
    index_code: str,
) -> list[dict]:
    """Return all distinct symbols that were ever in the index (for history bootstrap)."""
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT DISTINCT s.ticker, s.id AS symbol_id, s.currency, s.con_id,
                   e.code  AS exchange_code
              FROM index_constituents ic
              JOIN indices i ON i.id = ic.index_id
              JOIN symbols s ON s.id = ic.symbol_id
              JOIN exchanges e ON e.id = s.exchange_id
             WHERE i.code = $1
            """,
            index_code,
        )
    return [dict(r) for r in rows]


# ─── Internal helpers ──────────────────────────────────────────────────────

def _bar_time_utc(bar_date) -> datetime:
    """Convert an ib_insync bar.date to a UTC-aware datetime.

    For daily bars, IBKR returns a string like '20240115' (YYYYMMDD).
    For intraday bars, IBKR returns a Unix timestamp integer or a datetime.
    We store daily bars as midnight UTC on that calendar date. Strategy code
    must apply the exchange's UTC offset when computing 'what was the last
    closed bar' — but for daily backtesting this is handled by the data loader
    which works in exchange-local dates.
    """
    if isinstance(bar_date, datetime):
        if bar_date.tzinfo is None:
            return bar_date.replace(tzinfo=timezone.utc)
        return bar_date.astimezone(timezone.utc)
    if isinstance(bar_date, str):
        # IBKR daily bar date: 'YYYYMMDD' or 'YYYY-MM-DD'
        d = bar_date.replace("-", "")
        return datetime(int(d[:4]), int(d[4:6]), int(d[6:8]), tzinfo=timezone.utc)
    # IBKR intraday bar date: Unix timestamp
    return datetime.fromtimestamp(int(bar_date), tz=timezone.utc)
