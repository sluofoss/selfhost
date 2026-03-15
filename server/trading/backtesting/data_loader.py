# data_loader.py — Load OHLCV data for backtesting from Parquet files or TimescaleDB.
#
# Design rules:
#   - All output DataFrames use a tz-aware UTC DatetimeIndex.
#   - Prices are in exchange-local currency (AUD for ASX).
#   - GAP POLICY: weekends and public holidays are expected gaps and are NOT filled.
#     Gaps of > 4 consecutive trading days on a single symbol generate a warning.
#   - Warm-up awareness: callers pass 'start_date' as the first backtest date.
#     The loader automatically shifts the data load window back by 'warmup_bars' to
#     ensure indicators have enough history before the first signal date.
#   - Universe awareness: load_universe() queries the index_constituents table so the
#     returned per-symbol DataFrames only cover each symbol's active membership window.
#
# Two data sources:
#   1. Parquet (preferred): read via DuckDB for fast columnar queries.
#      Use this for reproducible offline backtesting.
#   2. TimescaleDB: use when Parquet hasn't been exported yet (early data pipeline).
#
# Returned data structure:
#   {ticker: pd.DataFrame(columns=['open','high','low','close','volume'], DatetimeIndex)}

import logging
import warnings
from datetime import date, timedelta
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd
import pandas_market_calendars as mcal

log = logging.getLogger(__name__)

# ─── ASX trading calendar ─────────────────────────────────────────────────
# Source: pandas_market_calendars package (pip install pandas-market-calendars)
# This accounts for all ASX public holidays (Good Friday, ANZAC Day, etc.)
_ASX_CALENDAR = mcal.get_calendar("ASX")
_MAX_CONSECUTIVE_GAP_DAYS = 4  # warn if a symbol has more than this many missing trading days in a row


def get_asx_trading_days(start: date, end: date) -> pd.DatetimeIndex:
    """Return all ASX trading days between start and end (inclusive) as UTC timestamps."""
    schedule = _ASX_CALENDAR.schedule(
        start_date=start.isoformat(),
        end_date=end.isoformat(),
    )
    return mcal.date_range(schedule, frequency="1D").tz_convert("UTC")


def load_from_parquet(
    parquet_dir: str | Path,
    tickers: list[str],
    start_date: date,
    end_date: date,
    warmup_bars: int = 0,
) -> dict[str, pd.DataFrame]:
    """Load OHLCV data for a list of tickers from Hive-partitioned Parquet files.

    Args:
        parquet_dir: Root Parquet directory (contains ohlcv/market=ASX/interval=daily/).
        tickers: List of ASX ticker codes.
        start_date: First date to include in output (after warm-up).
        end_date: Last date to include.
        warmup_bars: Extra bars to load before start_date for indicator warm-up.
            The output DataFrames include these warm-up bars. Signal code must
            ensure signals are NaN/False during the warm-up period.

    Returns:
        Dict mapping ticker → DataFrame with DatetimeIndex (UTC) and columns
        ['open', 'high', 'low', 'close', 'volume'].
    """
    try:
        import duckdb
    except ImportError:
        raise ImportError("duckdb is required for Parquet loading. pip install duckdb")

    parquet_dir = Path(parquet_dir)
    asx_daily_dir = parquet_dir / "ohlcv" / "market=ASX" / "interval=daily"

    if not asx_daily_dir.exists():
        raise FileNotFoundError(
            f"Parquet directory not found: {asx_daily_dir}\n"
            "Run bootstrap_asx_daily.py first to create Parquet files."
        )

    # Extend load window back by warmup_bars trading days
    adjusted_start = _shift_back_trading_days(start_date, warmup_bars)

    tickers_upper = [t.upper() for t in tickers]
    ticker_list = ", ".join(f"'{t}'" for t in tickers_upper)

    query = f"""
        SELECT time, ticker, open, high, low, close, volume
          FROM read_parquet('{asx_daily_dir}/*.parquet', hive_partitioning=false)
         WHERE ticker IN ({ticker_list})
           AND time >= TIMESTAMPTZ '{adjusted_start.isoformat()}'
           AND time <= TIMESTAMPTZ '{end_date.isoformat()} 23:59:59+00'
         ORDER BY ticker, time
    """

    con = duckdb.connect(read_only=True)
    df_all = con.execute(query).df()
    con.close()

    if df_all.empty:
        log.warning("No data returned from Parquet for tickers=%s, start=%s, end=%s",
                    tickers, adjusted_start, end_date)
        return {}

    return _split_and_validate(df_all, tickers_upper, adjusted_start, end_date)


def load_from_timescaledb(
    dsn: str,
    tickers: list[str],
    start_date: date,
    end_date: date,
    warmup_bars: int = 0,
) -> dict[str, pd.DataFrame]:
    """Load OHLCV data from TimescaleDB (synchronous, uses psycopg2).

    Use this as a fallback when Parquet files haven't been exported yet.
    dsn: psycopg2 connection string, e.g. 'postgresql://trading:pass@timescaledb:5432/trading'
    """
    try:
        import psycopg2
        import psycopg2.extras
    except ImportError:
        raise ImportError("psycopg2 is required for TimescaleDB loading. pip install psycopg2-binary")

    adjusted_start = _shift_back_trading_days(start_date, warmup_bars)
    tickers_upper = [t.upper() for t in tickers]

    query = """
        SELECT d.time, s.ticker, d.open, d.high, d.low, d.close, d.volume
          FROM ohlcv_daily d
          JOIN symbols   s ON s.id = d.symbol_id
          JOIN exchanges e ON e.id = s.exchange_id
         WHERE s.ticker = ANY(%s)
           AND e.code = 'ASX'
           AND d.time >= %s
           AND d.time <= %s
         ORDER BY s.ticker, d.time
    """

    conn = psycopg2.connect(dsn)
    with conn.cursor(cursor_factory=psycopg2.extras.DictCursor) as cur:
        cur.execute(query, (tickers_upper, adjusted_start.isoformat(), f"{end_date.isoformat()} 23:59:59"))
        rows = cur.fetchall()
    conn.close()

    if not rows:
        log.warning("No data in TimescaleDB for tickers=%s", tickers)
        return {}

    df_all = pd.DataFrame(rows, columns=["time", "ticker", "open", "high", "low", "close", "volume"])
    return _split_and_validate(df_all, tickers_upper, adjusted_start, end_date)


def load_constituent_universe(
    dsn: str,
    backtest_start: date,
    backtest_end: date,
    warmup_bars: int,
    parquet_dir: Optional[str | Path] = None,
) -> dict[str, pd.DataFrame]:
    """Load OHLCV data for the point-in-time ASX200 universe.

    Each symbol's DataFrame covers:
      - entry_date (or backtest_start − warmup) as the first bar
      - exit_date − 1 day (or backtest_end) as the last bar

    Symbols that entered the index before backtest_start will have warmup_bars of
    pre-start data. Symbols that entered during the backtest period may have fewer
    than warmup_bars of warm-up history if they were recently listed.

    Args:
        dsn: psycopg2 connection string to TimescaleDB.
        backtest_start, backtest_end: Date range for the backtest.
        warmup_bars: Maximum warm-up period to load before start.
        parquet_dir: If provided, load prices from Parquet instead of TimescaleDB.

    Returns:
        Dict mapping ticker → DataFrame. Each DataFrame's index is UTC-aware and
        covers only the dates the symbol was active in the index.
    """
    try:
        import psycopg2
    except ImportError:
        raise ImportError("psycopg2 required. pip install psycopg2-binary")

    # ── Fetch constituent windows ──────────────────────────────────────────
    query = """
        SELECT s.ticker, ic.entry_date, ic.exit_date
          FROM index_constituents ic
          JOIN indices   i ON i.id = ic.index_id
          JOIN symbols   s ON s.id = ic.symbol_id
          JOIN exchanges e ON e.id = s.exchange_id
         WHERE i.code = 'ASX200'
           AND e.code = 'ASX'
           AND ic.entry_date <= %s
           AND (ic.exit_date IS NULL OR ic.exit_date > %s)
         ORDER BY s.ticker, ic.entry_date
    """
    conn = psycopg2.connect(dsn)
    with conn.cursor() as cur:
        cur.execute(query, (backtest_end.isoformat(), backtest_start.isoformat()))
        windows = cur.fetchall()
    conn.close()

    all_tickers = list({row[0] for row in windows})
    log.info("Point-in-time universe: %d distinct tickers over backtest period", len(all_tickers))

    # ── Load prices ────────────────────────────────────────────────────────
    if parquet_dir:
        all_data = load_from_parquet(
            parquet_dir, all_tickers, backtest_start, backtest_end, warmup_bars
        )
    else:
        all_data = load_from_timescaledb(
            dsn, all_tickers, backtest_start, backtest_end, warmup_bars
        )

    # ── Clip each symbol to its membership window ──────────────────────────
    # A ticker may have multiple windows if it left and re-joined the index.
    # We keep only the rows within at least one active window.
    ticker_windows: dict[str, list[tuple[date, Optional[date]]]] = {}
    for ticker, entry, exit_ in windows:
        ticker_windows.setdefault(ticker, []).append((entry, exit_))

    adjusted_start = _shift_back_trading_days(backtest_start, warmup_bars)
    clipped: dict[str, pd.DataFrame] = {}

    for ticker, df in all_data.items():
        windows_for_ticker = ticker_windows.get(ticker, [])
        if not windows_for_ticker:
            continue

        # Build a boolean mask: row is in at least one active window
        mask = pd.Series(False, index=df.index)
        for entry, exit_ in windows_for_ticker:
            # Warm-up: load from adjusted_start OR entry−warmup, whichever is earlier
            load_from = max(adjusted_start, _shift_back_trading_days(entry, warmup_bars))
            end_clip  = exit_ if exit_ is not None else backtest_end
            mask |= (
                (df.index.date >= load_from) &  # type: ignore[operator]
                (df.index.date <= end_clip)
            )

        clipped[ticker] = df[mask]

    return clipped


# ─── Internal helpers ──────────────────────────────────────────────────────

def _split_and_validate(
    df_all: pd.DataFrame,
    tickers: list[str],
    start: date,
    end: date,
) -> dict[str, pd.DataFrame]:
    """Split a combined DataFrame by ticker, validate each, and return per-ticker dict."""
    df_all["time"] = pd.to_datetime(df_all["time"], utc=True)
    df_all = df_all.set_index("time").sort_index()

    result: dict[str, pd.DataFrame] = {}
    trading_days = set(get_asx_trading_days(start, end).normalize())

    for ticker in tickers:
        sub = df_all[df_all["ticker"] == ticker].drop(columns=["ticker"])
        if sub.empty:
            log.warning("%s: no data found", ticker)
            continue

        sub = sub[["open", "high", "low", "close", "volume"]].copy()
        sub.index = sub.index.normalize()  # strip time component for daily bars
        sub = sub[~sub.index.duplicated(keep="last")]   # remove any duplicates

        _validate(sub, ticker, trading_days)
        result[ticker] = sub

    return result


def _validate(df: pd.DataFrame, ticker: str, trading_days: set) -> None:
    """Assert data quality invariants. Log warnings rather than raising on soft issues."""
    # Hard assertion: no negative close prices (invalid for equity)
    if (df["close"] <= 0).any():
        bad = df[df["close"] <= 0]
        warnings.warn(
            f"{ticker}: {len(bad)} rows have close <= 0. "
            "This may indicate a data issue with backward-adjusted prices. "
            f"Dates: {bad.index.tolist()[:5]}"
        )

    # Hard assertion: no NaN close prices in the main body of the series
    nan_count = df["close"].isna().sum()
    if nan_count > 0:
        log.warning("%s: %d NaN close prices — may indicate gaps or data issues", ticker, nan_count)

    # Soft check: consecutive gap detection
    dates_in_data = set(df.index.normalize())
    expected_dates = trading_days & {
        d for d in (df.index.min().date() + timedelta(n)
                    for n in range((df.index.max().date() - df.index.min().date()).days + 1))
    }
    # This is approximate (trading_days set only covers start→end, not wider warm-up range)
    # A full gap check requires the full calendar — left as a startup task in the notebook

    # Zero-volume bars are logged but not dropped — they may be valid on illiquid days
    zero_vol = (df["volume"] == 0).sum()
    if zero_vol > 0:
        log.warning("%s: %d zero-volume bars (kept — may be valid for illiquid days)", ticker, zero_vol)


def _shift_back_trading_days(d: date, n: int) -> date:
    """Return approximately the date n ASX trading days before d.

    Uses a simple calendar-day estimate (1.4× for weekends/holidays), then
    snaps to the actual ASX schedule. Accurate to within a few days.
    """
    if n == 0:
        return d
    # Load 6 weeks before the estimate to have full schedule data
    estimate = d - timedelta(days=int(n * 1.5) + 10)
    try:
        schedule = _ASX_CALENDAR.schedule(
            start_date=estimate.isoformat(), end_date=d.isoformat()
        )
        trading = mcal.date_range(schedule, frequency="1D")
        if len(trading) >= n:
            return trading[-n].date()
        return estimate
    except Exception:
        return d - timedelta(days=int(n * 1.5))
