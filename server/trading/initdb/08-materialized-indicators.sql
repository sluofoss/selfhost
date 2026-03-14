-- 08-materialized-indicators.sql
-- The `indicators` hypertable (created in 03-hypertables.sql) stores pre-computed
-- EMA, RSI, MACD, Bollinger, and ATR values written back by the Python data-collector
-- after each bar batch. This file documents the intended schema and adds a helper
-- function for upserts; computation is intentionally Python-side (see Discussion).
--
-- Why Python writes indicators instead of SQL:
--   EMA(t) = α * price(t) + (1-α) * EMA(t-1)  — inherently recursive, no window fn
--   RSI requires running avg_gain / avg_loss accumulators
--   A recursive CTE for 8,000 symbols × 10,000 bars = 10–100x slower than numpy
--
-- The Python data-collector computes indicators in ~50 ms per bar batch using
-- pandas-ta or ta-lib, then bulk-upserts into this table.

-- Upsert function used by the data-collector to avoid duplicate rows on restart
CREATE OR REPLACE FUNCTION upsert_indicator(
    p_time        TIMESTAMPTZ,
    p_symbol_id   INTEGER,
    p_ema_12      DOUBLE PRECISION,
    p_ema_26      DOUBLE PRECISION,
    p_rsi_14      DOUBLE PRECISION,
    p_macd        DOUBLE PRECISION,
    p_macd_signal DOUBLE PRECISION,
    p_bb_upper    DOUBLE PRECISION,
    p_bb_lower    DOUBLE PRECISION,
    p_atr_14      DOUBLE PRECISION
) RETURNS VOID LANGUAGE SQL AS $$
    INSERT INTO indicators
        (time, symbol_id, ema_12, ema_26, rsi_14, macd, macd_signal, bb_upper, bb_lower, atr_14)
    VALUES
        (p_time, p_symbol_id, p_ema_12, p_ema_26, p_rsi_14, p_macd, p_macd_signal, p_bb_upper, p_bb_lower, p_atr_14)
    ON CONFLICT DO NOTHING;
$$;

-- Convenience view that joins indicators back to symbol metadata for strategy queries
CREATE VIEW indicators_with_symbol AS
SELECT
    i.time,
    s.ticker,
    e.code   AS exchange,
    s.sec_type,
    i.ema_12,
    i.ema_26,
    i.rsi_14,
    i.macd,
    i.macd_signal,
    i.bb_upper,
    i.bb_lower,
    i.atr_14
FROM indicators i
JOIN symbols   s ON s.id = i.symbol_id
JOIN exchanges e ON e.id = s.exchange_id;
