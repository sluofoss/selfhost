# evaluation.py — Portfolio and trade-level performance metrics.
#
# All functions are pure (no I/O, no side effects). Inputs are pandas Series.
#
# Conventions:
#   - equity_curve: Series of portfolio value indexed by date (not returns).
#   - returns: Series of period returns (fractional, not percent). e.g. 0.02 = +2%.
#   - risk_free_rate: annualised rate (fractional). e.g. 0.043 = 4.3% p.a.
#     Pass the RBA cash rate current at the time of the backtest. Do not hard-code.
#   - All Sharpe/Sortino computations annualise by multiplying by sqrt(periods_per_year).
#     For daily data: periods_per_year ≈ 252 (ASX trading days per year).
#
# No assumptions about leverage or short selling — these functions work with
# whatever equity curve or trade log the caller provides.

import warnings
from typing import Optional

import numpy as np
import pandas as pd

ASX_TRADING_DAYS_PER_YEAR: int = 252


# ─── Equity-curve metrics ─────────────────────────────────────────────────

def cagr(equity_curve: pd.Series) -> float:
    """Compound Annual Growth Rate.

    CAGR = (end_value / start_value) ^ (1 / years) - 1
    Returns NaN if equity_curve has < 2 data points or covers < 1 day.
    """
    if len(equity_curve) < 2:
        return float("nan")
    start_val = equity_curve.iloc[0]
    end_val   = equity_curve.iloc[-1]
    if start_val <= 0:
        warnings.warn("equity_curve starts at <= 0; CAGR is undefined")
        return float("nan")

    # Compute number of years from the DatetimeIndex
    days = (equity_curve.index[-1] - equity_curve.index[0]).days
    if days <= 0:
        return float("nan")
    years = days / 365.25
    return (end_val / start_val) ** (1.0 / years) - 1.0


def max_drawdown(equity_curve: pd.Series) -> float:
    """Maximum peak-to-trough drawdown as a positive fraction.

    e.g. 0.35 means the portfolio fell 35% from a peak before recovering.
    Returns NaN for empty input.
    """
    if equity_curve.empty:
        return float("nan")
    rolling_max = equity_curve.cummax()
    drawdown = (equity_curve - rolling_max) / rolling_max
    return float(drawdown.min()) * -1.0   # return as a positive number


def drawdown_series(equity_curve: pd.Series) -> pd.Series:
    """Return the full drawdown series (negative fractions from rolling peak).

    Useful for plotting underwater equity curves.
    """
    rolling_max = equity_curve.cummax()
    return (equity_curve - rolling_max) / rolling_max


def sharpe(
    returns: pd.Series,
    risk_free_rate: float,
    periods_per_year: int = ASX_TRADING_DAYS_PER_YEAR,
) -> float:
    """Annualised Sharpe ratio.

    sharpe = (mean_excess_return / std_return) * sqrt(periods_per_year)
    where mean_excess_return = mean(returns) − (risk_free_rate / periods_per_year)

    Returns NaN if returns series has < 2 non-NaN values or std is zero.
    """
    r = returns.dropna()
    if len(r) < 2:
        return float("nan")
    rf_per_period = risk_free_rate / periods_per_year
    excess = r - rf_per_period
    std = excess.std(ddof=1)
    if std == 0:
        return float("nan")
    return float(excess.mean() / std * np.sqrt(periods_per_year))


def sortino(
    returns: pd.Series,
    risk_free_rate: float,
    periods_per_year: int = ASX_TRADING_DAYS_PER_YEAR,
) -> float:
    """Annualised Sortino ratio (uses downside deviation only).

    sortino = (mean_excess_return / downside_std) * sqrt(periods_per_year)
    Downside std is computed over returns BELOW the risk-free rate only.
    """
    r = returns.dropna()
    if len(r) < 2:
        return float("nan")
    rf_per_period = risk_free_rate / periods_per_year
    excess = r - rf_per_period
    downside = excess[excess < 0]
    if len(downside) == 0:
        return float("inf")    # no losing periods
    downside_std = downside.std(ddof=1)
    if downside_std == 0:
        return float("nan")
    return float(excess.mean() / downside_std * np.sqrt(periods_per_year))


def calmar(equity_curve: pd.Series) -> float:
    """Calmar ratio: CAGR / max_drawdown.

    Higher is better. Penalises strategies with large drawdowns relative to returns.
    Returns NaN if drawdown is zero (no losing period) or CAGR is NaN.
    """
    c = cagr(equity_curve)
    d = max_drawdown(equity_curve)
    if d == 0 or np.isnan(c) or np.isnan(d):
        return float("nan")
    return c / d


def equity_to_returns(equity_curve: pd.Series) -> pd.Series:
    """Convert an equity curve to period returns (fractional)."""
    return equity_curve.pct_change().dropna()


# ─── Trade-log metrics ────────────────────────────────────────────────────

def win_rate(trade_returns: pd.Series) -> float:
    """Fraction of trades with positive return. Returns NaN if no trades."""
    if trade_returns.empty:
        return float("nan")
    return float((trade_returns > 0).sum() / len(trade_returns))


def profit_factor(trade_returns: pd.Series) -> float:
    """Gross profit / gross loss. Returns NaN if no losing trades."""
    gross_profit = trade_returns[trade_returns > 0].sum()
    gross_loss   = trade_returns[trade_returns < 0].abs().sum()
    if gross_loss == 0:
        return float("inf") if gross_profit > 0 else float("nan")
    return float(gross_profit / gross_loss)


def avg_trade_return(trade_returns: pd.Series) -> float:
    """Mean trade return (fractional)."""
    if trade_returns.empty:
        return float("nan")
    return float(trade_returns.mean())


# ─── Benchmark comparison ─────────────────────────────────────────────────

def compare_to_benchmark(
    strategy_returns: pd.Series,
    benchmark_returns: pd.Series,
    risk_free_rate: float,
    periods_per_year: int = ASX_TRADING_DAYS_PER_YEAR,
) -> dict:
    """Compare strategy against a benchmark.

    Both inputs must be aligned (same index). Use .reindex() and .dropna() before
    calling if the indices differ.

    Returns a dict with:
        alpha_annualised: annualised Jensen's alpha (CAPM alpha)
        beta: regression coefficient of strategy on benchmark
        excess_return_annualised: (CAGR_strategy - CAGR_benchmark) per year
        information_ratio: mean(strategy − benchmark) / std(strategy − benchmark)
        tracking_error_annualised: annualised std of (strategy − benchmark)
        strategy_sharpe, benchmark_sharpe
    """
    # Align and drop NaN pairs
    combined = pd.concat(
        {"strat": strategy_returns, "bench": benchmark_returns}, axis=1
    ).dropna()

    if len(combined) < 10:
        warnings.warn("Fewer than 10 overlapping return periods — comparison metrics are unreliable")

    strat  = combined["strat"]
    bench  = combined["bench"]
    active = strat - bench

    # Beta: cov(strat, bench) / var(bench)
    beta = float(np.cov(strat, bench)[0, 1] / np.var(bench, ddof=1)) if len(bench) > 1 else float("nan")

    # Jensen's alpha (daily): mean_excess_strat - beta * mean_excess_bench
    rf_per = risk_free_rate / periods_per_year
    alpha_daily = float((strat - rf_per).mean() - beta * (bench - rf_per).mean())
    alpha_ann   = alpha_daily * periods_per_year

    # Tracking error and information ratio
    tracking_error = float(active.std(ddof=1) * np.sqrt(periods_per_year))
    info_ratio     = float(active.mean() / active.std(ddof=1) * np.sqrt(periods_per_year)) if active.std() > 0 else float("nan")

    # CAGR-based excess return
    strat_eq = (1 + strat).cumprod()
    bench_eq = (1 + bench).cumprod()
    excess_ann = cagr(strat_eq) - cagr(bench_eq)

    return {
        "alpha_annualised":          round(alpha_ann, 4),
        "beta":                       round(beta, 4),
        "excess_return_annualised":  round(excess_ann, 4),
        "information_ratio":          round(info_ratio, 4),
        "tracking_error_annualised": round(tracking_error, 4),
        "strategy_sharpe":  round(sharpe(strat, risk_free_rate, periods_per_year), 4),
        "benchmark_sharpe": round(sharpe(bench, risk_free_rate, periods_per_year), 4),
    }


# ─── Full summary ─────────────────────────────────────────────────────────

def summary(
    equity_curve: pd.Series,
    trade_returns: Optional[pd.Series] = None,
    risk_free_rate: float = 0.043,   # caller should pass current RBA cash rate
    periods_per_year: int = ASX_TRADING_DAYS_PER_YEAR,
) -> dict:
    """Return a complete metrics dict for a strategy run.

    Args:
        equity_curve: Portfolio value over time.
        trade_returns: Per-trade fractional returns (optional; omit for equity-only metrics).
        risk_free_rate: Annualised risk-free rate (use current RBA cash rate).
        periods_per_year: Number of trading days per year (252 for ASX).
    """
    r = equity_to_returns(equity_curve)
    out = {
        "cagr":              round(cagr(equity_curve), 4),
        "max_drawdown":      round(max_drawdown(equity_curve), 4),
        "calmar":            round(calmar(equity_curve), 4),
        "sharpe":            round(sharpe(r, risk_free_rate, periods_per_year), 4),
        "sortino":           round(sortino(r, risk_free_rate, periods_per_year), 4),
        "total_return":      round(float(equity_curve.iloc[-1] / equity_curve.iloc[0] - 1), 4),
        "start_date":        str(equity_curve.index[0].date()),
        "end_date":          str(equity_curve.index[-1].date()),
        "risk_free_rate":    risk_free_rate,
    }
    if trade_returns is not None and not trade_returns.empty:
        out.update({
            "num_trades":  len(trade_returns),
            "win_rate":    round(win_rate(trade_returns), 4),
            "profit_factor": round(profit_factor(trade_returns), 4),
            "avg_trade":   round(avg_trade_return(trade_returns), 6),
        })
    return out
