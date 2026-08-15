from __future__ import annotations

from dataclasses import dataclass

BPS = 10_000
MAX_UINT256 = 2**256 - 1


@dataclass(frozen=True, slots=True)
class RewardPolicy:
    minimum_coverage_bps: int = 12_500
    critical_coverage_bps: int = 10_000
    maximum_weight_spread_bps: int = 5_000

    def __post_init__(self) -> None:
        if self.critical_coverage_bps <= 0:
            raise ValueError("critical coverage must be positive")
        if self.minimum_coverage_bps < self.critical_coverage_bps:
            raise ValueError("minimum coverage must not be below critical coverage")
        if not 0 <= self.maximum_weight_spread_bps <= 50_000:
            raise ValueError("weight spread limit is outside policy bounds")


@dataclass(frozen=True, slots=True)
class RewardSnapshot:
    principal: int
    base_weight: int
    accounting_weight: int
    rewards_funded: int
    rewards_paid: int
    rewards_emitted: int
    horizon_emission: int
    principal_solvent: bool = True

    def __post_init__(self) -> None:
        for field in (
            self.principal,
            self.base_weight,
            self.accounting_weight,
            self.rewards_funded,
            self.rewards_paid,
            self.rewards_emitted,
            self.horizon_emission,
        ):
            if not 0 <= field <= MAX_UINT256:
                raise ValueError("snapshot values must fit uint256")
        if self.rewards_paid > self.rewards_funded:
            raise ValueError("paid rewards exceed funded rewards")


@dataclass(frozen=True, slots=True)
class SolvencyAssessment:
    weight_spread: int
    weight_spread_bps: int
    rewards_available: int
    accrued_liability: int
    projected_liability: int
    coverage_bps: int
    capital_gap: int
    severity: str


def assess_solvency(snapshot: RewardSnapshot, policy: RewardPolicy = RewardPolicy()) -> SolvencyAssessment:
    rewards_available = snapshot.rewards_funded - snapshot.rewards_paid
    accrued_liability = max(snapshot.rewards_emitted - snapshot.rewards_paid, 0)
    projected_liability = accrued_liability + snapshot.horizon_emission
    coverage_bps = MAX_UINT256 if projected_liability == 0 else rewards_available * BPS // projected_liability
    weight_spread = max(snapshot.accounting_weight - snapshot.base_weight, 0)
    weight_spread_bps = 0 if snapshot.base_weight == 0 else weight_spread * BPS // snapshot.base_weight
    capital_gap = max(projected_liability - rewards_available, 0)

    if not snapshot.principal_solvent or capital_gap > 0 or coverage_bps < policy.critical_coverage_bps:
        severity = "critical"
    elif coverage_bps < policy.minimum_coverage_bps or weight_spread_bps > policy.maximum_weight_spread_bps:
        severity = "high"
    elif weight_spread_bps > policy.maximum_weight_spread_bps * 3 // 4:
        severity = "guarded"
    else:
        severity = "normal"
    return SolvencyAssessment(
        weight_spread=weight_spread,
        weight_spread_bps=weight_spread_bps,
        rewards_available=rewards_available,
        accrued_liability=accrued_liability,
        projected_liability=projected_liability,
        coverage_bps=coverage_bps,
        capital_gap=capital_gap,
        severity=severity,
    )


@dataclass(frozen=True, slots=True)
class PortfolioAssessment:
    assessments: tuple[SolvencyAssessment, ...]
    total_available: int
    total_projected_liability: int
    total_capital_gap: int
    critical_pools: int
    worst_coverage_bps: int


def assess_portfolio(
    snapshots: tuple[RewardSnapshot, ...], policy: RewardPolicy = RewardPolicy()
) -> PortfolioAssessment:
    if not snapshots:
        raise ValueError("portfolio must contain at least one reward pool")
    assessments = tuple(assess_solvency(snapshot, policy) for snapshot in snapshots)
    return PortfolioAssessment(
        assessments=assessments,
        total_available=sum(item.rewards_available for item in assessments),
        total_projected_liability=sum(item.projected_liability for item in assessments),
        total_capital_gap=sum(item.capital_gap for item in assessments),
        critical_pools=sum(item.severity == "critical" for item in assessments),
        worst_coverage_bps=min(item.coverage_bps for item in assessments),
    )
