-- 06-retention.sql
-- Drop old compressed chunks from TSDB once they have been archived to B2 Parquet.
-- Parquet archives accumulate forever on B2 at negligible cost (~$0.006/GB/mo).
-- Daily data is kept forever in TSDB as it is tiny (~13 MB/year compressed).

-- 10-min bars: keep 24 months in TSDB
SELECT add_retention_policy('ohlcv_10min', INTERVAL '24 months');

-- 1-min bars: keep 6 months in TSDB (dominant storage driver; B2 has full history)
SELECT add_retention_policy('ohlcv_1min', INTERVAL '6 months');

-- Daily bars: no retention (kept forever — data is tiny and useful for long backtests)
-- SELECT add_retention_policy('ohlcv_daily', INTERVAL '...'); -- intentionally omitted

-- Tick data: keep 3 months in TSDB
SELECT add_retention_policy('tick_data', INTERVAL '3 months');

-- Indicators: aligned with the source bar table they are derived from (10-min)
SELECT add_retention_policy('indicators', INTERVAL '24 months');

-- Account snapshots: keep 5 years (very small table)
SELECT add_retention_policy('account_snapshot', INTERVAL '5 years');

-- Trade log: keep forever (immutable audit trail; very small)
-- SELECT add_retention_policy('trade_log', ...); -- intentionally omitted
