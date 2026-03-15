-- 09-index-constituents.sql
-- Point-in-time index constituent tracking.
--
-- Stores which symbols were in a given index on any historical date.
-- This eliminates survivorship bias in backtesting: the universe on date T
-- is exactly the stocks that were actually in the index at time T — including
-- names that were subsequently delisted or removed.
--
-- Design principles:
--   - entry_date / exit_date are DATE (exchange local date), not TIMESTAMPTZ,
--     because index changes are announced and effective as of an exchange open,
--     not a specific UTC timestamp. The backtesting query: universe_at_date(code, T)
--     uses T as an exchange-local date.
--   - exit_date NULL means the symbol is currently in the index.
--   - A symbol that re-enters the index after a gap gets a separate row with a new entry_date.
--   - The table is append-friendly: the bootstrap script inserts historical rows; the
--     constituent_sync.py service adds new rows as changes occur.

-- ─── Reference table for index definitions ────────────────────────────────
CREATE TABLE indices (
    id    SERIAL PRIMARY KEY,
    code  TEXT UNIQUE NOT NULL,   -- 'ASX200', 'SP500', 'NASDAQ100', etc.
    name  TEXT        NOT NULL
);

INSERT INTO indices (code, name) VALUES
    ('ASX200',   'S&P/ASX 200'),
    ('SP500',    'S&P 500'),
    ('NASDAQ100','NASDAQ-100')
ON CONFLICT (code) DO NOTHING;

-- ─── Point-in-time constituent records ────────────────────────────────────
-- One row per (index, symbol, membership interval).
-- A symbol that leaves and re-joins gets multiple rows with different entry/exit dates.
CREATE TABLE index_constituents (
    id          SERIAL PRIMARY KEY,
    index_id    INTEGER NOT NULL REFERENCES indices(id),
    symbol_id   INTEGER NOT NULL REFERENCES symbols(id),
    entry_date  DATE    NOT NULL,  -- first day in index (effective at market open)
    exit_date   DATE,              -- first day NOT in index; NULL = currently a member
    source      TEXT,              -- 'bootstrap_pdf', 'ibkr_scanner', 'manual'
    notes       TEXT,              -- e.g. 'replaced by XYZ on 2019-06-21'
    CONSTRAINT no_overlap CHECK (exit_date IS NULL OR exit_date > entry_date),
    CONSTRAINT unique_membership UNIQUE (index_id, symbol_id, entry_date)
);

-- Fast lookup: current members of an index (most frequent query)
CREATE INDEX idx_constituents_current
    ON index_constituents (index_id, exit_date)
    WHERE exit_date IS NULL;

-- Range query: which symbols were in the index on a given date
-- Used by: universe_at_date() below and backtesting data loader
CREATE INDEX idx_constituents_range
    ON index_constituents (index_id, entry_date, exit_date);

-- Reverse lookup: all periods a given symbol was in any index
CREATE INDEX idx_constituents_symbol
    ON index_constituents (symbol_id, entry_date);

-- ─── Point-in-time universe function ──────────────────────────────────────
-- Returns all symbol_ids that were in `p_index_code` on date `p_as_of`.
-- Usage in backtesting Python loader:
--   SELECT symbol_id FROM universe_at_date('ASX200', '2015-06-01')
--
-- Inclusion criteria: entry_date <= p_as_of AND (exit_date IS NULL OR exit_date > p_as_of)
-- This means: the stock entered on or before p_as_of, and either is still in the index
-- or departed strictly after p_as_of (so it was in the index on p_as_of itself).
CREATE OR REPLACE FUNCTION universe_at_date(
    p_index_code TEXT,
    p_as_of      DATE
)
RETURNS TABLE (symbol_id INTEGER) AS $$
    SELECT ic.symbol_id
    FROM index_constituents ic
    JOIN indices i ON i.id = ic.index_id
    WHERE i.code = p_index_code
      AND ic.entry_date <= p_as_of
      AND (ic.exit_date IS NULL OR ic.exit_date > p_as_of);
$$ LANGUAGE sql STABLE;

-- ─── Convenience view: current ASX200 with ticker detail ──────────────────
CREATE VIEW asx200_current AS
    SELECT
        s.ticker,
        s.con_id,
        s.currency,
        ic.entry_date   AS current_entry_date,
        ic.notes
    FROM index_constituents ic
    JOIN indices   i ON i.id = ic.index_id
    JOIN symbols   s ON s.id = ic.symbol_id
    WHERE i.code = 'ASX200'
      AND ic.exit_date IS NULL
    ORDER BY s.ticker;

-- ─── Full constituent history view ────────────────────────────────────────
-- Shows all past and present members with their membership windows.
-- Used by bootstrap_asx_daily.py to determine which symbols to fetch history for.
CREATE VIEW index_universe_full AS
    SELECT
        i.code          AS index_code,
        s.ticker,
        s.con_id,
        ic.entry_date,
        ic.exit_date,
        ic.source,
        ic.notes
    FROM index_constituents ic
    JOIN indices   i ON i.id = ic.index_id
    JOIN symbols   s ON s.id = ic.symbol_id
    ORDER BY i.code, s.ticker, ic.entry_date;
