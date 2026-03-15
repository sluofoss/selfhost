# bar_history.py — Fetch and store OHLCV bars from IBKR TWS.
#
# Two modes:
#   1. Full-history backfill: called once for a new symbol. Fetches as much
#      history as IBKR allows (daily: up to 20 Y; 10-min: ~179 days).
#   2. Incremental update: fetches bars since the last stored timestamp.
#      Runs on a schedule after each market close.
#
# IBKR pacing rules (to avoid error 162):
#   - No more than 60 historical data requests in any rolling 10-minute window.
#   - Wait settings.ibkr_request_interval seconds between requests.
#   - After every ibkr_batch_size requests, pause ibkr_batch_pause seconds.
#
# All fetches are synchronous with respect to the asyncio event loop because
# ib_insync's reqHistoricalDataAsync is awaitable and yields control properly.

import asyncio
import logging
from datetime import datetime, timezone
from typing import Optional

from ib_insync import IB, Contract, Stock
from ib_insync.objects import BarDataList

from config import settings
from db import (
    asyncpg,
    get_last_bar_date,
    get_or_create_symbol,
    upsert_ohlcv_10min,
    upsert_ohlcv_daily,
)

log = logging.getLogger(__name__)


def asx_stock(ticker: str) -> Contract:
    """Return an ib_insync Contract for an ASX-listed stock."""
    return Stock(ticker, "ASX", "AUD")


def asx_etf(ticker: str) -> Contract:
    """STW and similar ETFs also use Stock contract type on ASX."""
    return Stock(ticker, "ASX", "AUD")


async def backfill_daily(
    ib: IB,
    pool: asyncpg.Pool,
    ticker: str,
    exchange_code: str = "ASX",
    sec_type: str = "STK",
    currency: str = "AUD",
    con_id: Optional[int] = None,
) -> int:
    """Fetch the full available daily bar history for a symbol and store it.

    Returns the number of bars written.
    """
    contract = Stock(ticker, exchange_code, currency)
    if con_id:
        contract.conId = con_id

    symbol_id = await get_or_create_symbol(
        pool, ticker, exchange_code, sec_type, currency, con_id
    )

    last = await get_last_bar_date(pool, "ohlcv_daily", symbol_id)
    if last is not None:
        # Already have data — use incremental instead
        log.debug("%s daily: already has data up to %s, skipping backfill", ticker, last.date())
        return 0

    log.info("%s daily: requesting up to %d-year history", ticker, settings.daily_backfill_years)
    try:
        bars: BarDataList = await ib.reqHistoricalDataAsync(
            contract=contract,
            endDateTime="",          # '' = up to the present
            durationStr=f"{settings.daily_backfill_years} Y",
            barSizeSetting="1 day",
            whatToShow="ADJUSTED_LAST",
            useRTH=True,
            formatDate=1,
            keepUpToDate=False,
        )
    except Exception as exc:
        log.error("%s daily backfill failed: %s", ticker, exc)
        return 0

    n = await upsert_ohlcv_daily(pool, symbol_id, bars)
    log.info("%s daily: backfilled %d bars", ticker, n)
    return n


async def incremental_daily(
    ib: IB,
    pool: asyncpg.Pool,
    ticker: str,
    exchange_code: str = "ASX",
    sec_type: str = "STK",
    currency: str = "AUD",
    con_id: Optional[int] = None,
) -> int:
    """Fetch daily bars since the last stored bar for a symbol.

    Returns the number of new bars written.
    """
    contract = Stock(ticker, exchange_code, currency)
    if con_id:
        contract.conId = con_id

    symbol_id = await get_or_create_symbol(
        pool, ticker, exchange_code, sec_type, currency, con_id
    )

    last = await get_last_bar_date(pool, "ohlcv_daily", symbol_id)
    if last is None:
        # No data at all — hand off to full backfill
        return await backfill_daily(ib, pool, ticker, exchange_code, sec_type, currency, con_id)

    # Request only enough history to cover since last stored bar.
    # Add a 5-day buffer to handle weekends and holidays at the boundary.
    days_since = max((datetime.now(tz=timezone.utc) - last).days + 5, 7)
    duration = f"{days_since} D"

    log.debug("%s daily incremental: requesting %s", ticker, duration)
    try:
        bars: BarDataList = await ib.reqHistoricalDataAsync(
            contract=contract,
            endDateTime="",
            durationStr=duration,
            barSizeSetting="1 day",
            whatToShow="ADJUSTED_LAST",
            useRTH=True,
            formatDate=1,
            keepUpToDate=False,
        )
    except Exception as exc:
        log.error("%s daily incremental failed: %s", ticker, exc)
        return 0

    n = await upsert_ohlcv_daily(pool, symbol_id, bars)
    log.debug("%s daily incremental: wrote %d bars", ticker, n)
    return n


async def backfill_10min(
    ib: IB,
    pool: asyncpg.Pool,
    ticker: str,
    exchange_code: str = "ASX",
    sec_type: str = "STK",
    currency: str = "AUD",
    con_id: Optional[int] = None,
) -> int:
    """Fetch the full available 10-minute history for a symbol (~179 calendar days).

    IBKR limits intraday data to 180 calendar days for most instruments.
    Returns number of bars written.
    """
    contract = Stock(ticker, exchange_code, currency)
    if con_id:
        contract.conId = con_id

    symbol_id = await get_or_create_symbol(
        pool, ticker, exchange_code, sec_type, currency, con_id
    )

    last = await get_last_bar_date(pool, "ohlcv_10min", symbol_id)
    if last is not None:
        log.debug("%s 10min: already has data, skipping backfill", ticker)
        return 0

    log.info("%s 10min: requesting %d-day intraday history", ticker, settings.intraday_backfill_days)
    try:
        bars: BarDataList = await ib.reqHistoricalDataAsync(
            contract=contract,
            endDateTime="",
            durationStr=f"{settings.intraday_backfill_days} D",
            barSizeSetting="10 mins",
            whatToShow="TRADES",      # ADJUSTED_LAST not available for intraday
            useRTH=True,
            formatDate=1,
            keepUpToDate=False,
        )
    except Exception as exc:
        log.error("%s 10min backfill failed: %s", ticker, exc)
        return 0

    n = await upsert_ohlcv_10min(pool, symbol_id, bars)
    log.info("%s 10min: backfilled %d bars", ticker, n)
    return n


async def run_daily_update(ib: IB, pool: asyncpg.Pool, tickers: list[dict]) -> None:
    """Fetch incremental daily bars for all symbols in the given list.

    Applies IBKR pacing between requests.
    Each entry in `tickers` is a dict with keys: ticker, exchange_code, sec_type, currency, con_id.
    """
    log.info("Starting daily incremental update for %d symbols", len(tickers))
    total_written = 0
    for i, sym in enumerate(tickers):
        n = await incremental_daily(
            ib, pool,
            ticker=sym["ticker"],
            exchange_code=sym.get("exchange_code", "ASX"),
            sec_type=sym.get("sec_type", "STK"),
            currency=sym.get("currency", "AUD"),
            con_id=sym.get("con_id"),
        )
        total_written += n

        # Pacing: sleep between every request
        await asyncio.sleep(settings.ibkr_request_interval)
        # Extra pause every N requests
        if (i + 1) % settings.ibkr_batch_size == 0:
            log.debug("Pacing pause after %d requests", i + 1)
            await asyncio.sleep(settings.ibkr_batch_pause)

    log.info("Daily update complete: %d new bars across %d symbols", total_written, len(tickers))


async def run_backfill_all(ib: IB, pool: asyncpg.Pool, tickers: list[dict]) -> None:
    """Backfill daily history for any symbols that have no data yet.

    Skips symbols that already have daily bars. Safe to re-run.
    """
    log.info("Checking %d symbols for missing daily history", len(tickers))
    for i, sym in enumerate(tickers):
        n = await backfill_daily(
            ib, pool,
            ticker=sym["ticker"],
            exchange_code=sym.get("exchange_code", "ASX"),
            sec_type=sym.get("sec_type", "STK"),
            currency=sym.get("currency", "AUD"),
            con_id=sym.get("con_id"),
        )
        if n > 0:
            # Only pause after actual fetches (backfill_daily returns 0 if symbol already has data)
            await asyncio.sleep(settings.ibkr_request_interval)
        if (i + 1) % settings.ibkr_batch_size == 0:
            await asyncio.sleep(settings.ibkr_batch_pause)

    log.info("Backfill pass complete")
