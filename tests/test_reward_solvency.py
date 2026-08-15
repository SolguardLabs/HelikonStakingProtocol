from __future__ import annotations

from dataclasses import FrozenInstanceError

import pytest

from sdk.helikon import RewardPolicy, RewardSnapshot, assess_portfolio, assess_solvency


def snapshot(**overrides: int | bool) -> RewardSnapshot:
    values: dict[str, int | bool] = {
        "principal": 1_000_000,
        "base_weight": 1_000_000,
        "accounting_weight": 1_200_000,
        "rewards_funded": 500_000,
        "rewards_paid": 100_000,
        "rewards_emitted": 250_000,
        "horizon_emission": 100_000,
        "principal_solvent": True,
    }
    values.update(overrides)
    return RewardSnapshot(**values)  # type: ignore[arg-type]


def test_assessment_exposes_loss_waterfall() -> None:
    result = assess_solvency(snapshot())
    assert result.rewards_available == 400_000
    assert result.accrued_liability == 150_000
    assert result.projected_liability == 250_000
    assert result.coverage_bps == 16_000
    assert result.capital_gap == 0
    assert result.weight_spread_bps == 2_000
    assert result.severity == "normal"


def test_capital_gap_is_critical() -> None:
    result = assess_solvency(snapshot(rewards_funded=220_000))
    assert result.capital_gap == 130_000
    assert result.severity == "critical"


def test_principal_insolvency_is_critical() -> None:
    assert assess_solvency(snapshot(principal_solvent=False)).severity == "critical"


def test_weight_concentration_can_be_high() -> None:
    result = assess_solvency(snapshot(accounting_weight=1_600_000))
    assert result.weight_spread_bps == 6_000
    assert result.severity == "high"


def test_near_limit_weight_is_guarded() -> None:
    result = assess_solvency(snapshot(accounting_weight=1_400_000))
    assert result.weight_spread_bps == 4_000
    assert result.severity == "guarded"


def test_empty_liability_has_unbounded_coverage() -> None:
    result = assess_solvency(snapshot(rewards_paid=250_000, rewards_emitted=250_000, horizon_emission=0))
    assert result.coverage_bps == 2**256 - 1


def test_snapshot_rejects_negative_and_inconsistent_values() -> None:
    with pytest.raises(ValueError):
        snapshot(principal=-1)
    with pytest.raises(ValueError):
        snapshot(rewards_funded=99_999)


def test_policy_enforces_ordered_thresholds() -> None:
    with pytest.raises(ValueError):
        RewardPolicy(minimum_coverage_bps=9_000, critical_coverage_bps=10_000)


def test_assessment_is_immutable() -> None:
    result = assess_solvency(snapshot())
    with pytest.raises(FrozenInstanceError):
        result.capital_gap = 1  # type: ignore[misc]


def test_portfolio_aggregates_independent_pools() -> None:
    result = assess_portfolio((snapshot(), snapshot(rewards_funded=220_000)))
    assert len(result.assessments) == 2
    assert result.total_available == 520_000
    assert result.total_projected_liability == 500_000
    assert result.total_capital_gap == 130_000
    assert result.critical_pools == 1


def test_portfolio_rejects_empty_input() -> None:
    with pytest.raises(ValueError):
        assess_portfolio(())
