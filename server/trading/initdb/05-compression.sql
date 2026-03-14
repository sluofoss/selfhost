-- 05-compression.sql
-- Enable compression on each hypertable.
-- segment_by = symbol_id groups all rows for one symbol into a single compressed
-- segment, which means decompressing one symbol never decompresses another.
-- order_by = time gives the best delta-of-delta encoding for timestamps.

-- ohlcv_10min
ALTER TABLE ohlcv_10min SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'symbol_id',
    timescaledb.compress_orderby   = 'time'
);
SELECT add_compression_policy('ohlcv_10min', INTERVAL '2 days');

-- ohlcv_1min
ALTER TABLE ohlcv_1min SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'symbol_id',
    timescaledb.compress_orderby   = 'time'
);
SELECT add_compression_policy('ohlcv_1min', INTERVAL '1 day');

-- ohlcv_daily — compress after 7 days; data is small so this mainly helps indexing
ALTER TABLE ohlcv_daily SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'symbol_id',
    timescaledb.compress_orderby   = 'time'
);
SELECT add_compression_policy('ohlcv_daily', INTERVAL '7 days');

-- tick_data — compresses very well due to slowly changing bid/ask prices
ALTER TABLE tick_data SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'symbol_id',
    timescaledb.compress_orderby   = 'time'
);
SELECT add_compression_policy('tick_data', INTERVAL '1 day');

-- indicators
ALTER TABLE indicators SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'symbol_id',
    timescaledb.compress_orderby   = 'time'
);
SELECT add_compression_policy('indicators', INTERVAL '2 days');

-- account_snapshot (no symbol segmentation; compress after 7 days)
ALTER TABLE account_snapshot SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 'time'
);
SELECT add_compression_policy('account_snapshot', INTERVAL '7 days');

-- trade_log (no symbol segmentation for now; compress after 7 days)
ALTER TABLE trade_log SET (
    timescaledb.compress,
    timescaledb.compress_orderby = 'time'
);
SELECT add_compression_policy('trade_log', INTERVAL '7 days');
