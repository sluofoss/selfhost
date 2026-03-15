#!/usr/bin/env python3
"""bootstrap_asx_daily.py — One-shot historical daily bar pull for all ASX200 ever-members.

Usage (run from inside the data-collector container, or with uv run):
    uv run scripts/bootstrap_asx_daily.py [--symbol-limit N] [--dry-run]

Prerequisites:
  1. TimescaleDB must be running with 09-index-constituents.sql applied.
  2. index_constituents must be populated (run bootstrap_constituents.py first).
  3. TWS must be running and connected to IBKR (paper account is fine).

This script:
  - Reads all symbols that were ever in ASX200 from index_constituents.
  - For each symbol, fetches up to 20 years of daily adjusted closing bars from IBKR.
  - Upserts bars into ohlcv_daily.
  - Also fetches STW (ASX200 ETF) as the benchmark series.
  - Exports a Parquet snapshot on completion.

IBKR pacing: 2 s between requests, 10 s pause every 50 requests.
Estimated runtime for ~400 symbols: ~15-20 minutes.

This is safe to resume: get_last_bar_date() is checked before each request and
symbols with existing data are skipped (backfill_daily returns 0 for those).
"""

import argparse
import asyncio
import logging
import sys
from datetime import date
from pathlib import Path

from ib_insync import IB, util

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))
from bar_history import run_backfill_all
from config import settings
from db import create_pool, get_ever_constituents, get_or_create_symbol
from parquet_export import export_daily

log = logging.getLogger(__name__)

# STW is the SPDR S&P/ASX 200 ETF — used as the benchmark series in backtesting
BENCHMARK_SYMBOLS = [
    {"ticker": "STW", "exchange_code": "ASX", "sec_type": "STK", "currency": "AUD"},
]

util.startLoop()


async def run(symbol_limit: int | None, dry_run: bool) -> None:
    pool = await create_pool()

    ib = IB()
    log.info("Connecting to TWS at %s:%d ...", settings.tws_host, settings.tws_port)
    await ib.connectAsync(settings.tws_host, settings.tws_port, clientId=20)
    log.info("Connected")

    # ── Collect symbols to fetch ───────────────────────────────────────────
    ever_members = await get_ever_constituents(pool, "ASX200")
    if not ever_members:
        log.error(
            "No symbols found in index_constituents. "
            "Run bootstrap_constituents.py first to populate the constituent history."
        )
        ib.disconnect()
        await pool.close()
        return

    # Always include benchmark symbols even if not in index_constituents
    all_symbols = ever_members + [
        s for s in BENCHMARK_SYMBOLS
        if s["ticker"] not in {m["ticker"] for m in ever_members}
    ]

    if symbol_limit:
        log.info("Limiting to first %d symbols (--symbol-limit)", symbol_limit)
        all_symbols = all_symbols[:symbol_limit]

    log.info("Will fetch daily history for %d symbols total", len(all_symbols))

    if dry_run:
        log.info("[DRY RUN] Would fetch: %s", [s["ticker"] for s in all_symbols])
        ib.disconnect()
        await pool.close()
        return

    # ── Fetch bars ─────────────────────────────────────────────────────────
    await run_backfill_all(ib, pool, all_symbols)

    # ── Export Parquet snapshot ────────────────────────────────────────────
    log.info("Exporting Parquet snapshots for all completed years")
    current_year = date.today().year
    for year in range(2000, current_year + 1):
        path = await export_daily(pool, market="ASX", exchange_codes=["ASX"], for_year=year)
        if path:
            log.info("Exported %s", path)

    ib.disconnect()
    await pool.close()
    log.info("Bootstrap complete")


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-8s %(message)s",
    )
    parser = argparse.ArgumentParser(description="Bootstrap historical daily bars for all ASX200 ever-members")
    parser.add_argument("--symbol-limit", type=int, default=None,
                        help="Limit to the first N symbols (useful for testing)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show which symbols would be fetched without actually calling IBKR")
    args = parser.parse_args()
    asyncio.run(run(symbol_limit=args.symbol_limit, dry_run=args.dry_run))
