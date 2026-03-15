# signals.py — Pure signal-generation functions for strategy backtesting.
#
# All functions here are STATELESS and FREE OF SIDE EFFECTS. They take price
# Series or DataFrames and return boolean or numeric Series.
#
# Look-ahead bias guarantee:
#   Every function is written so that the output at index position T depends
#   ONLY on inputs at positions ≤ T. This is enforced by using
#   pandas.Series.rolling() (which is causal by default) and verified by the
#   unit tests in tests/test_signals.py.
#
#   Execution timing: signals at bar T represent what is known at end-of-bar T.
#   Actual execution must occur at the NEXT bar's open (T+1). The backtesting
#   engine (asx200_sma_poc.ipynb) is responsible for this shift — these
#   functions do NOT shift. This separation of concerns is intentional.
#
# All inputs must be pd.Series with a timezone-aware DatetimeIndex.
# NaN-forward: a NaN output is the CORRECT result during warm-up; do not fill.

import numpy as np
import pandas as pd


# ─── Building blocks ──────────────────────────────────────────────────────

def sma(series: pd.Series, window: int) -> pd.Series:
    """Simple moving average over `window` bars.

    Returns NaN for the first (window − 1) bars — this is correct and
    intentional. Never fill these NaNs with synthetic values.
    """
    if window < 1:
        raise ValueError(f"window must be ≥ 1, got {window}")
    return series.rolling(window=window, min_periods=window).mean()


def ema(series: pd.Series, span: int) -> pd.Series:
    """Exponential moving average with given span (adjust=False for recursive computation).

    pandas ewm with adjust=False is equivalent to the recursive EMA formula:
        EMA[t] = alpha * price[t] + (1 - alpha) * EMA[t-1]
    where alpha = 2 / (span + 1).

    The first `span - 1` values will have increasing confidence as more data
    accumulates; the function returns values from bar 0 (no min_periods NaN gap
    unlike SMA). For backtesting with a strict warm-up discipline, subsist the
    first `span * 3` values as the warm-up period for EMA.
    """
    if span < 1:
        raise ValueError(f"span must be ≥ 1, got {span}")
    return series.ewm(span=span, adjust=False).mean()


def atr(high: pd.Series, low: pd.Series, close: pd.Series, window: int = 14) -> pd.Series:
    """Average True Range over `window` bars.

    True Range = max(high−low, |high−prev_close|, |low−prev_close|)
    Returns NaN for the first `window` bars.
    """
    prev_close = close.shift(1)
    tr = pd.concat([
        high - low,
        (high - prev_close).abs(),
        (low  - prev_close).abs(),
    ], axis=1).max(axis=1)
    return tr.rolling(window=window, min_periods=window).mean()


# ─── SMA crossover ────────────────────────────────────────────────────────

def sma_crossover_signals(
    close: pd.Series,
    n_fast: int,
    n_slow: int,
) -> tuple[pd.Series, pd.Series]:
    """Dual SMA crossover entry and exit signals.

    Entry (True) when sma_fast crosses ABOVE sma_slow on bar T:
        sma_fast[T] > sma_slow[T]  AND  sma_fast[T-1] <= sma_slow[T-1]

    Exit (True) when sma_fast crosses BELOW sma_slow on bar T:
        sma_fast[T] < sma_slow[T]  AND  sma_fast[T-1] >= sma_slow[T-1]

    Rules:
    - Both signals are False for any bar where either SMA is NaN (warm-up).
    - Entry and exit cannot both be True on the same bar.
    - Returns (entries, exits) as boolean pd.Series aligned to close.index.

    Look-ahead guarantee:
    - sma_fast[T] = mean(close[T-n_fast+1 : T+1]) — uses close[T] (current bar close)
      which is correct: we compute the signal AFTER bar T closes.
    - The shift(1) for the previous-bar comparison is causal (uses data ≤ T−1).
    - Execution at OPEN of T+1 is the responsibility of the caller.
    """
    if n_fast >= n_slow:
        raise ValueError(
            f"n_fast ({n_fast}) must be strictly less than n_slow ({n_slow})"
        )

    fast = sma(close, n_fast)
    slow = sma(close, n_slow)

    # Both SMAs must be non-NaN for a valid signal
    both_valid = fast.notna() & slow.notna()

    above = fast > slow      # fast is currently above slow
    cross_up   =  above & ~above.shift(1).fillna(True)    # was NOT above on previous bar
    cross_down = ~above &  above.shift(1).fillna(False)   # was above on previous bar

    entries = (cross_up   & both_valid).fillna(False)
    exits   = (cross_down & both_valid).fillna(False)

    return entries, exits


def sma_position(
    close: pd.Series,
    n_fast: int,
    n_slow: int,
) -> pd.Series:
    """Return the current SMA regime as an integer Series.

    Returns:
        1  where sma_fast > sma_slow (in-trend, hold long)
        0  where sma_fast <= sma_slow (out-of-trend)
        NaN during warm-up (either SMA is NaN)

    Use this for position-based backtesting (hold while 1, exit when 0)
    as an alternative to the crossed-signal approach. Both are correct;
    the crossed-signal approach generates fewer trades on small fluctuations
    because it only fires at the exact crossover bar.
    """
    fast = sma(close, n_fast)
    slow = sma(close, n_slow)
    pos = pd.Series(0.0, index=close.index)
    pos[fast > slow] = 1.0
    pos[fast.isna() | slow.isna()] = np.nan
    return pos


# ─── Signal grid for parameter search ─────────────────────────────────────

def signal_grid(
    close: pd.Series,
    fast_periods: list[int],
    slow_periods: list[int],
) -> dict[tuple[int, int], tuple[pd.Series, pd.Series]]:
    """Compute SMA crossover signals for all (fast, slow) combinations.

    Skips combinations where fast >= slow.
    Returns a dict: {(n_fast, n_slow): (entries, exits)}.

    Used by the parameter sensitivity analysis in the POC notebook.
    All computations are in-sample; never expose grid search results to
    the test set.
    """
    grid: dict[tuple[int, int], tuple[pd.Series, pd.Series]] = {}
    for nf in fast_periods:
        for ns in slow_periods:
            if nf >= ns:
                continue
            grid[(nf, ns)] = sma_crossover_signals(close, nf, ns)
    return grid
