-- 07-continuous-aggs.sql
-- Continuous aggregates are TimescaleDB materialized views that auto-refresh
-- as new rows are inserted. They avoid redundant per-query aggregation for
-- commonly used rollups across all strategies.
--
-- Continuous aggs only work on RAW hypertables, not on other continuous aggs
-- (until TimescaleDB 2.9+ where hierarchical CAggs are supported).
-- These are built directly on ohlcv_10min as the base.

-- ─── Hourly OHLCV rollup from 10-minute bars ──────────────────────────────────
CREATE MATERIALIZED VIEW ohlcv_1h
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time) AS time,
    symbol_id,
    FIRST(open,  time) AS open,
    MAX(high)          AS high,
    MIN(low)           AS low,
    LAST(close,  time) AS close,
    SUM(volume)        AS volume,
    SUM(bar_count)     AS bar_count
FROM ohlcv_10min
GROUP BY time_bucket('1 hour', time), symbol_id
WITH NO DATA;

SELECT add_continuous_aggregate_policy('ohlcv_1h',
    start_offset      => INTERVAL '3 hours',
    end_offset        => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');

-- ─── Daily VWAP from 10-minute bars ───────────────────────────────────────────
-- VWAP = sum(close * volume) / sum(volume) — approximation using bar close price.
-- For tick-accurate VWAP use tick_data table instead.
CREATE MATERIALIZED VIEW daily_vwap
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 day', time) AS time,
    symbol_id,
    SUM(close * volume) / NULLIF(SUM(volume), 0) AS vwap,
    SUM(volume)                                  AS total_volume
FROM ohlcv_10min
GROUP BY time_bucket('1 day', time), symbol_id
WITH NO DATA;

SELECT add_continuous_aggregate_policy('daily_vwap',
    start_offset      => INTERVAL '2 days',
    end_offset        => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 hour');

-- ─── 20-period SMA on 10-minute bars (SQL window function, no recursion) ──────
-- SMA and Bollinger bands can live in SQL because they use pure window functions.
-- EMA, RSI, ATR are recursive and are computed in Python (see 08-materialized-indicators.sql).
CREATE MATERIALIZED VIEW sma_20_10min AS
SELECT
    time,
    symbol_id,
    close,
    AVG(close) OVER (
        PARTITION BY symbol_id
        ORDER BY time
        ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
    ) AS sma_20,
    STDDEV(close) OVER (
        PARTITION BY symbol_id
        ORDER BY time
        ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
    ) AS stddev_20
FROM ohlcv_10min;

CREATE INDEX ON sma_20_10min (symbol_id, time DESC);

-- ─── Rolling 20-day volatility (annualised) from daily bars ───────────────────
CREATE MATERIALIZED VIEW volatility_20d AS
SELECT
    time,
    symbol_id,
    -- Annualised daily return volatility (252 trading days)
    STDDEV(
        LN(close / LAG(close) OVER (PARTITION BY symbol_id ORDER BY time))
    ) OVER (
        PARTITION BY symbol_id
        ORDER BY time
        ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
    ) * SQRT(252) AS vol_20d
FROM ohlcv_daily;

CREATE INDEX ON volatility_20d (symbol_id, time DESC);
