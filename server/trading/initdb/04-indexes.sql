-- 04-indexes.sql
-- Composite indexes on (symbol_id, time DESC) for each hypertable.
-- TimescaleDB creates a primary index on (time DESC) automatically;
-- the symbol_id prefix is what makes per-symbol range queries fast.

CREATE INDEX ON ohlcv_10min (symbol_id, time DESC);
CREATE INDEX ON ohlcv_1min  (symbol_id, time DESC);
CREATE INDEX ON ohlcv_daily (symbol_id, time DESC);
CREATE INDEX ON tick_data   (symbol_id, time DESC);
CREATE INDEX ON indicators  (symbol_id, time DESC);
CREATE INDEX ON trade_log   (strategy,  time DESC);
CREATE INDEX ON trade_log   (symbol_id, time DESC);
