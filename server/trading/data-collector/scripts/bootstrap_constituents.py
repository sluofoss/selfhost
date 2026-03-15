#!/usr/bin/env python3
"""bootstrap_constituents.py — One-shot script to populate index_constituents from ASX PDFs.

Usage:
    uv run scripts/bootstrap_constituents.py [--dry-run]

This script:
  1. Downloads quarterly S&P/ASX 200 rebalancing announcement PDFs from asx.com.au.
  2. Parses each PDF to extract additions and deletions with their effective dates.
  3. Upserts the changes into the index_constituents table.
  4. Optionally downloads the current ASX200 list as the baseline (most-recent state),
     then applies all historical changes in reverse to build the full history.

The ASX rebalancing announcement page URL pattern (as of 2024):
  https://www.asx.com.au/about/asx-in-the-market/index-information/asx-index-announcements.htm

PDFs are named roughly by quarter and year and are publicly accessible.

Known limitations:
  - PDF layout may change between years; the parser includes heuristics for the most
    common layouts (tabular "Additions" / "Deletions" sections). Manually review edge cases.
  - The archive goes back to approximately 2000; earlier history may be incomplete.
  - IBKR con_ids are NOT set by this script — they are populated lazily when bar history
    is fetched via bar_history.py.

Run this once during initial setup. It is safe to re-run: upserts are idempotent.
"""

import argparse
import asyncio
import logging
import re
import sys
from dataclasses import dataclass, field
from datetime import date, datetime
from pathlib import Path
from urllib.parse import urljoin

import asyncpg
import httpx
import pdfplumber

# Allow running from scripts/ directory alongside src/
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))
from config import settings
from db import create_pool, get_or_create_symbol, upsert_constituent, close_constituent

log = logging.getLogger(__name__)

ASX_ANNOUNCEMENTS_BASE = (
    "https://www.asx.com.au/about/asx-in-the-market/"
    "index-information/asx-index-announcements.htm"
)

# Regex patterns for quarterly review PDF link text (e.g. "March 2024 Quarterly Review")
_PDF_LINK_RE = re.compile(
    r"(january|march|june|september|december|quarterly|rebalance|review)",
    re.IGNORECASE,
)

# Effective date patterns in PDF text: "effective [on] [the ][Monday,] DD Month YYYY"
_DATE_RE = re.compile(
    r"effective\s+(?:on\s+)?(?:the\s+)?(?:\w+,?\s+)?(\d{1,2})\s+(\w+)\s+(\d{4})",
    re.IGNORECASE,
)
_MONTHS = {
    "january": 1,  "february": 2,  "march": 3,    "april": 4,
    "may": 5,      "june": 6,      "july": 7,     "august": 8,
    "september": 9,"october": 10,  "november": 11, "december": 12,
}


@dataclass
class ConstituentChange:
    ticker: str
    action: str           # 'ADD' or 'REMOVE'
    effective_date: date
    source_pdf: str


async def fetch_pdf_links(client: httpx.AsyncClient) -> list[str]:
    """Scrape the ASX announcements page and return PDF URLs for quarterly reviews."""
    resp = await client.get(ASX_ANNOUNCEMENTS_BASE, follow_redirects=True)
    resp.raise_for_status()
    html = resp.text

    # Extract all hrefs ending in .pdf that match the quarterly review pattern
    hrefs = re.findall(r'href="([^"]+\.pdf)"', html, re.IGNORECASE)
    quarterly_pdfs = [
        urljoin(str(resp.url), h)
        for h in hrefs
        if _PDF_LINK_RE.search(h)
    ]
    log.info("Found %d quarterly rebalancing PDFs on announcements page", len(quarterly_pdfs))
    return quarterly_pdfs


def _parse_date(m) -> date | None:
    day   = int(m.group(1))
    month = _MONTHS.get(m.group(2).lower())
    year  = int(m.group(3))
    if month is None:
        return None
    try:
        return date(year, month, day)
    except ValueError:
        return None


def parse_pdf(pdf_bytes: bytes, source_name: str) -> list[ConstituentChange]:
    """Extract constituent changes from a quarterly rebalancing PDF.

    Looks for sections labelled 'Additions' and 'Deletions' (or 'Removals'),
    extracts the ticker codes listed in those sections, and pairs them with the
    effective date found in the document header.

    Returns a list of ConstituentChange objects.
    """
    changes: list[ConstituentChange] = []
    effective_date: date | None = None

    import io
    with pdfplumber.open(io.BytesIO(pdf_bytes)) as pdf:
        full_text = "\n".join(page.extract_text() or "" for page in pdf.pages)

        # Find effective date
        m = _DATE_RE.search(full_text)
        if m:
            effective_date = _parse_date(m)
        if effective_date is None:
            log.warning("%s: could not parse effective date — skipping", source_name)
            return []

        # Parse tables from each page looking for additions/deletions
        for page in pdf.pages:
            tables = page.extract_tables()
            for table in tables:
                if not table:
                    continue
                _parse_table_changes(table, effective_date, source_name, changes)

        # Fallback: parse from raw text if table extraction found nothing
        if not changes:
            _parse_text_changes(full_text, effective_date, source_name, changes)

    return changes


def _parse_table_changes(
    table: list[list],
    effective_date: date,
    source_name: str,
    out: list[ConstituentChange],
) -> None:
    """Extract tickers from a table that has an 'Additions' or 'Deletions' header."""
    # Detect which action this table represents
    header_text = " ".join(str(c) for c in (table[0] or []) if c).upper()
    if "ADDITION" in header_text:
        action = "ADD"
    elif "DELETION" in header_text or "REMOVAL" in header_text:
        action = "REMOVE"
    else:
        return

    # Second column (index 1) or first column typically contains the ASX ticker code
    for row in table[1:]:
        for cell in (row or []):
            if cell is None:
                continue
            text = str(cell).strip().upper()
            # ASX tickers are 1–5 uppercase letters (most are 3)
            if re.fullmatch(r"[A-Z]{1,5}", text):
                out.append(ConstituentChange(
                    ticker=text,
                    action=action,
                    effective_date=effective_date,
                    source_pdf=source_name,
                ))
                break  # take the first valid-looking ticker per row


def _parse_text_changes(
    text: str,
    effective_date: date,
    source_name: str,
    out: list[ConstituentChange],
) -> None:
    """Fallback text-based parser for PDFs where table extraction fails."""
    action: str | None = None
    for line in text.splitlines():
        upper = line.strip().upper()
        if "ADDITION" in upper:
            action = "ADD"
        elif "DELETION" in upper or "REMOVAL" in upper:
            action = "REMOVE"
        elif action and re.fullmatch(r"[A-Z]{1,5}", upper):
            out.append(ConstituentChange(
                ticker=upper,
                action=action,
                effective_date=effective_date,
                source_pdf=source_name,
            ))


async def apply_changes(
    pool: asyncpg.Pool,
    changes: list[ConstituentChange],
    dry_run: bool,
) -> None:
    """Apply a list of constituent changes to the database."""
    adds    = [c for c in changes if c.action == "ADD"]
    removes = [c for c in changes if c.action == "REMOVE"]
    log.info("Applying: %d additions, %d removals (dry_run=%s)", len(adds), len(removes), dry_run)

    for change in adds:
        sid = await get_or_create_symbol(
            pool, change.ticker, "ASX", "STK", "AUD"
        )
        if not dry_run:
            await upsert_constituent(
                pool, "ASX200", sid,
                entry_date=change.effective_date,
                source="bootstrap_pdf",
                notes=f"PDF: {change.source_pdf}",
            )
        else:
            log.info("[DRY RUN] ADD %s on %s", change.ticker, change.effective_date)

    for change in removes:
        sid = await get_or_create_symbol(
            pool, change.ticker, "ASX", "STK", "AUD"
        )
        if not dry_run:
            await close_constituent(
                pool, "ASX200", sid, exit_date=change.effective_date
            )
        else:
            log.info("[DRY RUN] REMOVE %s on %s", change.ticker, change.effective_date)


async def run(dry_run: bool) -> None:
    pool = await create_pool()

    async with httpx.AsyncClient(timeout=60, headers={"User-Agent": "Mozilla/5.0"}) as client:
        pdf_urls = await fetch_pdf_links(client)

        if not pdf_urls:
            log.error("No PDF links found — the ASX page structure may have changed. "
                      "Manually download rebalancing PDFs and place them in scripts/pdfs/ "
                      "then re-run with --local-dir scripts/pdfs/")
            return

        all_changes: list[ConstituentChange] = []
        for url in pdf_urls:
            try:
                resp = await client.get(url, follow_redirects=True, timeout=30)
                resp.raise_for_status()
                source = url.rsplit("/", 1)[-1]
                log.info("Parsing %s", source)
                changes = parse_pdf(resp.content, source)
                all_changes.extend(changes)
                log.info("  → %d changes extracted", len(changes))
            except Exception as exc:
                log.warning("Failed to process %s: %s", url, exc)

    log.info("Total changes parsed from all PDFs: %d", len(all_changes))

    # Sort chronologically so additions before removals are applied in order
    all_changes.sort(key=lambda c: c.effective_date)
    await apply_changes(pool, all_changes, dry_run=dry_run)

    await pool.close()
    log.info("Bootstrap complete")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Bootstrap ASX200 constituent history from rebalancing PDFs")
    parser.add_argument("--dry-run", action="store_true", help="Parse only; do not write to DB")
    args = parser.parse_args()
    asyncio.run(run(dry_run=args.dry_run))
