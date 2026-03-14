-- 02-lookup-tables.sql
-- Reference tables for exchanges and symbols.
-- Integer PKs keep hypertable rows small (4 B instead of repeated VARCHAR text).

CREATE TABLE exchanges (
    id    SERIAL PRIMARY KEY,
    code  TEXT UNIQUE NOT NULL,   -- 'NYSE', 'NASDAQ', 'ASX', 'PAXOS', 'IBCFD'
    name  TEXT,
    tz    TEXT NOT NULL           -- IANA timezone: 'America/New_York', 'Australia/Sydney', 'UTC'
);

-- Seed known exchanges so symbol inserts can reference them immediately
INSERT INTO exchanges (code, name, tz) VALUES
    ('NYSE',    'New York Stock Exchange',    'America/New_York'),
    ('NASDAQ',  'NASDAQ',                     'America/New_York'),
    ('ARCA',    'NYSE Arca',                  'America/New_York'),
    ('ASX',     'Australian Securities Exchange', 'Australia/Sydney'),
    ('PAXOS',   'Paxos (BTC/Crypto)',         'UTC'),
    ('IBCFD',   'IBKR CFDs',                  'UTC'),
    ('CME',     'Chicago Mercantile Exchange','America/New_York')
ON CONFLICT (code) DO NOTHING;

CREATE TABLE symbols (
    id          SERIAL PRIMARY KEY,
    ticker      TEXT NOT NULL,
    exchange_id INTEGER NOT NULL REFERENCES exchanges(id),
    sec_type    TEXT NOT NULL,      -- 'STK', 'CRYPTO', 'CFD', 'FUT', 'OPT'
    currency    TEXT NOT NULL,
    con_id      INTEGER,            -- IBKR contract ID for unambiguous lookup
    active      BOOLEAN DEFAULT true,
    UNIQUE (ticker, exchange_id, sec_type)
);

CREATE INDEX ON symbols (ticker);
CREATE INDEX ON symbols (con_id) WHERE con_id IS NOT NULL;
