# pragma version ^0.4.0

# @title RewardSolvencyController
# @notice Read-only solvency policy for staking principal, emissions, and reward reserves.

interface IAccess:
    def has_role(role: uint256, account: address) -> bool: view

interface IStakingVault:
    def protocol_snapshot() -> (uint256, uint256, uint256, uint256, uint256): view
    def principal_solvent() -> bool: view

interface IRewarder:
    def total_rewards_funded() -> uint256: view
    def total_rewards_paid() -> uint256: view
    def total_rewards_emitted() -> uint256: view

struct Assessment:
    principal: uint256
    base_weight: uint256
    accounting_weight: uint256
    weight_spread: uint256
    weight_spread_bps: uint256
    rewards_available: uint256
    accrued_liability: uint256
    projected_liability: uint256
    coverage_bps: uint256
    capital_gap: uint256
    severity: uint256
    principal_solvent: bool

GOVERNOR_ROLE: constant(uint256) = 1
RISK_ROLE: constant(uint256) = 5
BPS: constant(uint256) = 10000
NORMAL: constant(uint256) = 0
GUARDED: constant(uint256) = 1
HIGH: constant(uint256) = 2
CRITICAL: constant(uint256) = 3

access: public(address)
vault: public(address)
rewarder: public(address)
min_coverage_bps: public(uint256)
critical_coverage_bps: public(uint256)
max_weight_spread_bps: public(uint256)
last_assessment_at: public(uint256)
last_severity: public(uint256)
last_capital_gap: public(uint256)

event PolicyUpdated:
    min_coverage_bps: uint256
    critical_coverage_bps: uint256
    max_weight_spread_bps: uint256

event AssessmentRecorded:
    severity: indexed(uint256)
    coverage_bps: uint256
    weight_spread_bps: uint256
    capital_gap: uint256

@deploy
def __init__(_access: address, _vault: address, _rewarder: address):
    assert _access != empty(address), "ZERO_ACCESS"
    assert _vault != empty(address), "ZERO_VAULT"
    assert _rewarder != empty(address), "ZERO_REWARDER"
    self.access = _access
    self.vault = _vault
    self.rewarder = _rewarder
    self.min_coverage_bps = 12500
    self.critical_coverage_bps = 10000
    self.max_weight_spread_bps = 5000

@internal
@view
def _has_policy_role(_account: address) -> bool:
    return staticcall IAccess(self.access).has_role(GOVERNOR_ROLE, _account) or staticcall IAccess(self.access).has_role(RISK_ROLE, _account)

@external
def set_policy(_min_coverage_bps: uint256, _critical_coverage_bps: uint256, _max_weight_spread_bps: uint256):
    assert self._has_policy_role(msg.sender), "ONLY_POLICY"
    assert _critical_coverage_bps > 0, "ZERO_CRITICAL"
    assert _min_coverage_bps >= _critical_coverage_bps, "COVERAGE_ORDER"
    assert _max_weight_spread_bps <= 50000, "SPREAD_HIGH"
    self.min_coverage_bps = _min_coverage_bps
    self.critical_coverage_bps = _critical_coverage_bps
    self.max_weight_spread_bps = _max_weight_spread_bps
    log PolicyUpdated(min_coverage_bps=_min_coverage_bps, critical_coverage_bps=_critical_coverage_bps, max_weight_spread_bps=_max_weight_spread_bps)

@internal
@view
def _assess(_horizon_emission: uint256) -> Assessment:
    principal: uint256 = 0
    base_weight: uint256 = 0
    accounting_weight: uint256 = 0
    rewards_claimed: uint256 = 0
    exit_penalties: uint256 = 0
    principal, base_weight, accounting_weight, rewards_claimed, exit_penalties = staticcall IStakingVault(self.vault).protocol_snapshot()
    funded: uint256 = staticcall IRewarder(self.rewarder).total_rewards_funded()
    paid: uint256 = staticcall IRewarder(self.rewarder).total_rewards_paid()
    emitted: uint256 = staticcall IRewarder(self.rewarder).total_rewards_emitted()
    available: uint256 = 0
    if funded > paid:
        available = funded - paid
    accrued: uint256 = 0
    if emitted > paid:
        accrued = emitted - paid
    projected: uint256 = accrued + _horizon_emission
    coverage: uint256 = max_value(uint256)
    if projected > 0:
        coverage = available * BPS // projected
    spread: uint256 = 0
    if accounting_weight > base_weight:
        spread = accounting_weight - base_weight
    spread_bps: uint256 = 0
    if base_weight > 0:
        spread_bps = spread * BPS // base_weight
    gap: uint256 = 0
    if projected > available:
        gap = projected - available
    solvent: bool = staticcall IStakingVault(self.vault).principal_solvent()
    severity: uint256 = NORMAL
    if not solvent or gap > 0 or coverage < self.critical_coverage_bps:
        severity = CRITICAL
    elif coverage < self.min_coverage_bps or spread_bps > self.max_weight_spread_bps:
        severity = HIGH
    elif spread_bps > self.max_weight_spread_bps * 3 // 4:
        severity = GUARDED
    return Assessment(principal=principal, base_weight=base_weight, accounting_weight=accounting_weight, weight_spread=spread, weight_spread_bps=spread_bps, rewards_available=available, accrued_liability=accrued, projected_liability=projected, coverage_bps=coverage, capital_gap=gap, severity=severity, principal_solvent=solvent)

@external
@view
def assess(_horizon_emission: uint256) -> Assessment:
    return self._assess(_horizon_emission)

@external
def record_assessment(_horizon_emission: uint256) -> Assessment:
    assessment: Assessment = self._assess(_horizon_emission)
    self.last_assessment_at = block.timestamp
    self.last_severity = assessment.severity
    self.last_capital_gap = assessment.capital_gap
    log AssessmentRecorded(severity=assessment.severity, coverage_bps=assessment.coverage_bps, weight_spread_bps=assessment.weight_spread_bps, capital_gap=assessment.capital_gap)
    return assessment
