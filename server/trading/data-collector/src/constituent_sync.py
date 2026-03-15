# constituent_sync.py — Sync current ASX200 membership from IBKR and/or ASX direct.
#
# Two sync modes:
#   1. Live sync from IBKR scanner: detects additions/deletions vs the DB's current
#      open records, triggers backfill for new entrants, closes records for exits.
#   2. Fallback: download the ASX's own constituent CSV (asx.com.au) for current members.
#
# IBKR constituent discovery limitations:
#   IBKR does not provide a "give me all index members" API for non-US indices.
#   For ASX200, the most reliable live source is the ASX website's daily constituent
#   file. IBKR scanners can be used as a cross-check.
#
# Ongoing sync is intentionally conservative: it only records changes it is confident
# about. Ambiguous cases are logged as warnings for manual review.

import csv
import io
import logging
import zipfile
from datetime import date, datetime, timezone

import asyncpg
import httpx

from bar_history import run_backfill_all
from config import settings
from db import (
    close_constituent,
    get_current_constituents,
    get_or_create_symbol,
    upsert_constituent,
)

log = logging.getLogger(__name__)

# ASX publishes a daily ZIP containing the current ASX300 constituent list.
# The ASX200 members are tagged in this file (INDEXCODE = 'S&P/ASX 200').
# URL is publicly accessible without authentication.
ASX_CONSTITUENT_ZIP_URL = "https://www.asx.com.au/data/asx300.zip"

# Expected column names in the ASX ZIP CSV (as of 2024; may change)
_ASX_TICKER_COL = "ASX code"
_ASX_INDEX_COL = "Index"
_ASX200_LABEL = "S&P/ASX 200"
_ASX_NAME_COL = "Company"


async def download_current_asx200() -> list[dict]:
    """Download the ASX's daily constituent file and return current ASX200 members.

    Returns a list of dicts with keys: ticker, name.
    The ASX ticker is the 3-letter code; IBKR uses the same code for ASX stocks.
    """
    log.info("Downloading current ASX constituent list from %s", ASX_CONSTITUENT_ZIP_URL)
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.get(ASX_CONSTITUENT_ZIP_URL, follow_redirects=True)
        resp.raise_for_status()

    members = []
    with zipfile.ZipFile(io.BytesIO(resp.content)) as zf:
        csv_name = next(n for n in zf.namelist() if n.lower().endswith(".csv"))
        with zf.open(csv_name) as f:
            text = f.read().decode("utf-8-sig")  # strip BOM if present

    reader = csv.DictReader(io.StringIO(text))
    for row in reader:
        # The CSV contains ASX300; filter to ASX200 by index tag
        if row.get(_ASX_INDEX_COL, "").strip() == _ASX200_LABEL:
            ticker = row.get(_ASX_TICKER_COL, "").strip().upper()
            name   = row.get(_ASX_NAME_COL, "").strip()
            if ticker:
                members.append({"ticker": ticker, "name": name})

    log.info("Downloaded %d current ASX200 members", len(members))
    return members


async def sync_asx200(
    pool: asyncpg.Pool,
    ib,  # ib_insync IB instance (used for backfill of new entrants)
) -> None:
    """Sync the `index_constituents` table against the current live ASX200 member list.

    - New members since the last sync: insert constituent record with entry_date=today,
      trigger full history backfill.
    - Members that disappeared from the live list: close their record with exit_date=today.

    This function is scheduled weekly and on startup.
    """
    today = date.today()

    # ── Get current members from ASX website ──────────────────────────────
    try:
        live_members = await download_current_asx200()
    except Exception as exc:
        log.error("Failed to download ASX constituent list: %s — skipping sync", exc)
        return

    # Ensure all live symbols are in the symbols table
    live_symbol_ids: dict[str, int] = {}
    for m in live_members:
        sid = await get_or_create_symbol(
            pool,
            ticker=m["ticker"],
            exchange_code="ASX",
            sec_type="STK",
            currency="AUD",
        )
        live_symbol_ids[m["ticker"]] = sid

    # ── Compare against DB's current open records ──────────────────────────
    db_current: set[int] = await get_current_constituents(pool, "ASX200")
    live_ids: set[int] = set(live_symbol_ids.values())

    # --- New entrants: in live list but not in DB yet ---
    new_ids = live_ids - db_current
    if new_ids:
        new_tickers = [t for t, sid in live_symbol_ids.items() if sid in new_ids]
        log.info("ASX200 new entrants detected: %s", new_tickers)
        for ticker, sid in [(t, live_symbol_ids[t]) for t in new_tickers]:
            await upsert_constituent(
                pool, "ASX200", sid, entry_date=today, source="asx_download"
            )
        # Backfill history for new entrants so indicators are warm immediately
        new_sym_list = [{"ticker": t, "exchange_code": "ASX", "sec_type": "STK", "currency": "AUD"}
                        for t in new_tickers]
        await run_backfill_all(ib, pool, new_sym_list)

    # --- Exits: in DB but not in live list ---
    # Only close records if the symbol disappeared from the ASX200 constituent list.
    # This is conservative: we log a warning if count is surprisingly large (bulk error).
    exited_ids = db_current - live_ids
    if exited_ids:
        if len(exited_ids) > 20:
            # Sanity check: > 20 removals in one sync is almost certainly a download error
            log.warning(
                "Unexpectedly large number of constituent exits detected (%d). "
                "This may be a data download error — skipping exit processing. "
                "Investigate manually.", len(exited_ids)
            )
            return

        log.info("ASX200 exits detected: %d symbol(s)", len(exited_ids))
        for sid in exited_ids:
            await close_constituent(pool, "ASX200", sid, exit_date=today)

    if not new_ids and not exited_ids:
        log.info("ASX200 constituent sync: no changes detected")
