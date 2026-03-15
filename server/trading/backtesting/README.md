# Backtesting Framework

Local research library for strategy backtesting using data collected from IBKR TWS.
See `workbench/25-backtesting-framework.md` for architecture and data science rationale.

## Prerequisites

1. TimescaleDB is running with all `initdb/` SQL scripts applied (01 through 09).
2. `index_constituents` is populated. Run bootstrap order:

```bash
# Step 1 — Populate constituent history from ASX quarterly PDF announcements
docker exec trading_data_collector \
    uv run /app/scripts/bootstrap_constituents.py

# Step 2 — Fetch full daily bar history for all ever-members
docker exec trading_data_collector \
    uv run /app/scripts/bootstrap_asx_daily.py
```

Both scripts are idempotent and safe to re-run. Step 2 skips symbols that already have data.

## Running the notebook

Open code-server at `https://vscode.<your-domain>`, navigate to the backtesting workspace,
and open `notebooks/asx200_sma_poc.ipynb`. All dependencies are installed in the workspace
virtualenv:

```bash
# From the backtesting/ directory
uv add duckdb pandas numpy pyarrow pandas-market-calendars vectorbt psycopg2-binary
```

## Module overview

| File | Purpose |
|------|---------|
| `data_loader.py` | Load OHLCV from Parquet (preferred) or TimescaleDB. Constituent-aware. |
| `signals.py` | Pure signal functions: `sma()`, `sma_crossover_signals()`, `signal_grid()`. |
| `evaluation.py` | Performance metrics: CAGR, max drawdown, Sharpe, Sortino, Calmar, benchmark compare. |

## Data science invariants (enforced)

1. **No look-ahead**: `signals.py` only reads index ≤ T. Execution shift (T+1 open) is done in the notebook.
2. **No survivorship bias**: `load_constituent_universe()` queries `universe_at_date()` for each date T.
3. **Chronological split only**: in-sample fit, then report on untouched out-of-sample period.
4. **Transaction costs modelled**: 0.10% per side applied at every fill.
5. **Benchmark required**: all results compared to STW (ASX200 ETF) buy-and-hold.

## Porting a strategy to live execution

Once a strategy is validated in backtest:

1. Extract the signal function from `signals.py` (already a pure function — no changes needed).
2. In `server/trading/strategy-runner/src/strategies/`, create a new module that imports the
   signal function and implements the `BaseStrategy` interface (`on_bar()`, `on_fill()`).
3. Add the strategy to `strategy-runner/strategies.yml`.

The signal logic does not need to be rewritten — the same function used in backtesting is
used in live execution, which reduces the risk of implementation divergence.
