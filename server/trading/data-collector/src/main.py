# main.py — APScheduler entry point for the data-collector service.
#
# Lifecycle:
#   1. Connect to TimescaleDB pool.
#   2. Connect to TWS via ib_insync (with auto-reconnect).
#   3. On startup: sync ASX200 constituents, then backfill any missing history.
#   4. Schedule:
#        - After ASX close (~16:10 AEST daily): incremental daily bar update
#        - After US close (~16:10 ET daily): incremental daily bar update for US symbols
#        - Nightly 02:00 UTC: Parquet export (after all markets have closed)
#        - Weekly Sunday 03:00 UTC: full constituent sync
#   5. Graceful shutdown on SIGTERM/SIGINT.

import asyncio
import logging
import signal
import sys
from datetime import datetime

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from ib_insync import IB, util

import db as db_module
from bar_history import run_backfill_all, run_daily_update
from config import settings
from constituent_sync import sync_asx200
from parquet_export import run_nightly_export

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-8s %(name)s — %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
    stream=sys.stdout,
)
log = logging.getLogger("main")

# ib_insync uses its own event loop integration
util.startLoop()


async def _get_ever_constituents(pool) -> list[dict]:
    """Return all symbols that were ever in ASX200 (for daily update scheduling)."""
    return await db_module.get_ever_constituents(pool, "ASX200")


async def main() -> None:
    log.info("Data collector starting")

    # ── Database pool ──────────────────────────────────────────────────────
    pool = await db_module.create_pool()

    # ── TWS connection ─────────────────────────────────────────────────────
    ib = IB()
    ib.errorEvent += lambda reqId, errorCode, errorString, contract: (
        log.warning("TWS error %d: %s (reqId=%s)", errorCode, errorString, reqId)
        if errorCode not in (2104, 2106, 2158)  # suppress harmless data-farm notices
        else None
    )

    async def connect_tws() -> None:
        while True:
            try:
                await ib.connectAsync(
                    settings.tws_host,
                    settings.tws_port,
                    clientId=settings.tws_client_id,
                )
                log.info("Connected to TWS at %s:%d", settings.tws_host, settings.tws_port)
                return
            except Exception as exc:
                log.warning("TWS connection failed: %s — retrying in 30s", exc)
                await asyncio.sleep(30)

    await connect_tws()

    # Auto-reconnect on disconnect
    async def on_disconnected() -> None:
        log.warning("TWS disconnected — reconnecting in 60s")
        await asyncio.sleep(60)
        await connect_tws()

    ib.disconnectedEvent += lambda: asyncio.ensure_future(on_disconnected())

    # ── Startup tasks ──────────────────────────────────────────────────────
    log.info("Running startup constituent sync + backfill")
    await sync_asx200(pool, ib)
    ever = await _get_ever_constituents(pool)
    await run_backfill_all(ib, pool, ever)
    log.info("Startup tasks complete")

    # ── Scheduler ─────────────────────────────────────────────────────────
    scheduler = AsyncIOScheduler(timezone="UTC")

    # ASX daily update — 06:15 UTC = 16:15 AEST / 17:15 AEDT (after ASX close)
    scheduler.add_job(
        _asx_daily_job,
        CronTrigger(hour=6, minute=15),
        args=[ib, pool],
        id="asx_daily",
        name="ASX daily bar update",
        misfire_grace_time=3600,
        coalesce=True,
    )

    # Nightly Parquet export — 02:00 UTC (all markets closed)
    scheduler.add_job(
        run_nightly_export,
        CronTrigger(hour=2, minute=0),
        args=[pool],
        id="parquet_export",
        name="Nightly Parquet export",
        misfire_grace_time=7200,
        coalesce=True,
    )

    # Weekly constituent sync — Sunday 03:00 UTC
    scheduler.add_job(
        sync_asx200,
        CronTrigger(day_of_week="sun", hour=3, minute=0),
        args=[pool, ib],
        id="constituent_sync_weekly",
        name="Weekly ASX200 constituent sync",
        misfire_grace_time=3600,
        coalesce=True,
    )

    scheduler.start()
    log.info("Scheduler running. Waiting for market events.")

    # ── Graceful shutdown ──────────────────────────────────────────────────
    stop_event = asyncio.Event()

    def _handle_signal(sig):
        log.info("Received signal %s — shutting down", sig.name)
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, _handle_signal, sig)

    await stop_event.wait()

    log.info("Stopping scheduler and disconnecting")
    scheduler.shutdown(wait=False)
    ib.disconnect()
    await pool.close()
    log.info("Data collector stopped")


async def _asx_daily_job(ib: IB, pool) -> None:
    """Fetch incremental daily bars for all ASX200 ever-members."""
    tickers = await _get_ever_constituents(pool)
    await run_daily_update(ib, pool, tickers)


if __name__ == "__main__":
    asyncio.run(main())
