-- 03-hypertables.sql
-- Create all time-series tables and convert them to TimescaleDB hypertables.
-- Separate tables per interval allow different chunk sizes, compression policies,
-- and retention policies — one combined table with an 'interval' column would not.

-- ─── OHLCV 10-minute bars ─────────────────────────────────────────────────────
-- Coverage: US (NYSE/NASDAQ/ARCA), ASX, BTC, CFDs
-- Chunk interval: 1 week — good balance of chunk count vs chunk size at ~8,000 symbols
CREATE TABLE ohlcv_10min (
    time       TIMESTAMPTZ NOT NULL,
    symbol_id  INTEGER     NOT NULL REFERENCES symbols(id),
    open       DOUBLE PRECISION,
    high       DOUBLE PRECISION,
    low        DOUBLE PRECISION,
    close      DOUBLE PRECISION,
    volume     BIGINT,
    bar_count  INTEGER     -- number of trades in this bar (IBKR reqHistoricalData field)
);

SELECT create_hypertable('ohlcv_10min', 'time',
    chunk_time_interval => INTERVAL '1 week');

-- ─── OHLCV 1-minute bars ──────────────────────────────────────────────────────
-- Optional; only collect when a strategy specifically needs sub-10-min resolution.
-- Chunk interval: 1 day — keeps chunk count manageable at ~8,000 symbols, 1-min rate
CREATE TABLE ohlcv_1min (
    time       TIMESTAMPTZ NOT NULL,
    symbol_id  INTEGER     NOT NULL REFERENCES symbols(id),
    open       DOUBLE PRECISION,
    high       DOUBLE PRECISION,
    low        DOUBLE PRECISION,
    close      DOUBLE PRECISION,
    volume     BIGINT,
    bar_count  INTEGER
);

SELECT create_hypertable('ohlcv_1min', 'time',
    chunk_time_interval => INTERVAL '1 day');

-- ─── OHLCV Daily bars ─────────────────────────────────────────────────────────
-- Never purged from TSDB (retention policy: forever).
-- Chunk interval: 1 month — daily data is small enough to hold large chunks
CREATE TABLE ohlcv_daily (
    time       TIMESTAMPTZ NOT NULL,
    symbol_id  INTEGER     NOT NULL REFERENCES symbols(id),
    open       DOUBLE PRECISION,
    high       DOUBLE PRECISION,
    low        DOUBLE PRECISION,
    close      DOUBLE PRECISION,
    volume     BIGINT,
    bar_count  INTEGER
);

SELECT create_hypertable('ohlcv_daily', 'time',
    chunk_time_interval => INTERVAL '1 month');

-- ─── Tick data ────────────────────────────────────────────────────────────────
-- Best bid/ask/last from reqTickByTickData. Collect only for active watchlist.
-- Chunk interval: 1 day — high row rate requires tight chunking for compression
CREATE TABLE tick_data (
    time        TIMESTAMPTZ NOT NULL,
    symbol_id   INTEGER     NOT NULL REFERENCES symbols(id),
    bid_price   DOUBLE PRECISION,
    ask_price   DOUBLE PRECISION,
    last_price  DOUBLE PRECISION,
    last_size   INTEGER,
    bid_size    INTEGER,
    ask_size    INTEGER
);

SELECT create_hypertable('tick_data', 'time',
    chunk_time_interval => INTERVAL '1 day');

-- ─── Pre-computed indicators ──────────────────────────────────────────────────
-- Written back by the data-collector Python process after each bar batch.
-- EMA/RSI are recursive and must be computed in Python, not SQL.
-- Chunk interval: 1 week — same as ohlcv_10min (usually aligned with bar inserts)
CREATE TABLE indicators (
    time        TIMESTAMPTZ NOT NULL,
    symbol_id   INTEGER     NOT NULL,
    ema_12      DOUBLE PRECISION,
    ema_26      DOUBLE PRECISION,
    rsi_14      DOUBLE PRECISION,
    macd        DOUBLE PRECISION,
    macd_signal DOUBLE PRECISION,
    bb_upper    DOUBLE PRECISION,   -- Bollinger upper (20-period, +2σ)
    bb_lower    DOUBLE PRECISION,   -- Bollinger lower (20-period, -2σ)
    atr_14      DOUBLE PRECISION
);

SELECT create_hypertable('indicators', 'time',
    chunk_time_interval => INTERVAL '1 week');

-- ─── Account snapshots ────────────────────────────────────────────────────────
-- Hourly account state snapshots for equity curve tracking and monitoring.
CREATE TABLE account_snapshot (
    time           TIMESTAMPTZ NOT NULL,
    net_liq        DOUBLE PRECISION,
    cash           DOUBLE PRECISION,
    unrealized_pnl DOUBLE PRECISION,
    realized_pnl   DOUBLE PRECISION
);

SELECT create_hypertable('account_snapshot', 'time');

-- ─── Trade log ────────────────────────────────────────────────────────────────
-- Audit trail for all strategy-generated order fills.
CREATE TABLE trade_log (
    time        TIMESTAMPTZ NOT NULL,
    strategy    TEXT        NOT NULL,
    symbol_id   INTEGER     NOT NULL,
    side        TEXT        NOT NULL,   -- 'BUY' or 'SELL'
    quantity    INTEGER     NOT NULL,
    fill_price  DOUBLE PRECISION,
    commission  DOUBLE PRECISION,
    order_id    INTEGER,
    notes       TEXT
);

SELECT create_hypertable('trade_log', 'time');
