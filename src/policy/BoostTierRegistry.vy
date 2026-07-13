# pragma version ^0.4.0


# @title BoostTierRegistry
# @notice Stores temporary boost tiers used by the staking vault.

interface IAccess:
    def has_role(role: uint256, account: address) -> bool: view

struct BoostTier:
    multiplier_bps: uint256
    min_principal: uint256
    max_principal: uint256
    duration: uint256
    renewal_delay: uint256
    activation_fee_bps: uint256
    max_exit_penalty_bps: uint256
    active: bool
    updated_at: uint256

GOVERNOR_ROLE: constant(uint256) = 1
BOOST_MANAGER_ROLE: constant(uint256) = 6
BPS: constant(uint256) = 10000
MAX_MULTIPLIER_BPS: constant(uint256) = 50000

access: public(address)
next_tier_id: public(uint256)
default_tier_id: public(uint256)
tiers: public(HashMap[uint256, BoostTier])

event TierCreated:
    tier_id: indexed(uint256)
    multiplier_bps: uint256
    duration: uint256

event TierUpdated:
    tier_id: indexed(uint256)
    active: bool

@deploy
def __init__(_access: address):
    assert _access != empty(address), "ZERO_ACCESS"
    self.access = _access
    self.next_tier_id = 1

@internal
def _only_manager():
    is_governor: bool = staticcall IAccess(self.access).has_role(GOVERNOR_ROLE, msg.sender)
    is_manager: bool = staticcall IAccess(self.access).has_role(BOOST_MANAGER_ROLE, msg.sender)
    assert is_governor or is_manager, "ONLY_MANAGER"

@internal
def _validate(_tier: BoostTier):
    assert _tier.multiplier_bps >= BPS, "MULTIPLIER_LOW"
    assert _tier.multiplier_bps <= MAX_MULTIPLIER_BPS, "MULTIPLIER_HIGH"
    assert _tier.duration > 0, "DURATION_ZERO"
    assert _tier.activation_fee_bps <= 2000, "FEE_HIGH"
    assert _tier.max_exit_penalty_bps <= 5000, "PENALTY_HIGH"
    if _tier.max_principal > 0:
        assert _tier.max_principal >= _tier.min_principal, "BAD_RANGE"

@external
def create_tier(
    _multiplier_bps: uint256,
    _min_principal: uint256,
    _max_principal: uint256,
    _duration: uint256,
    _renewal_delay: uint256,
    _activation_fee_bps: uint256,
    _max_exit_penalty_bps: uint256,
    _active: bool,
) -> uint256:
    self._only_manager()
    tier_id: uint256 = self.next_tier_id
    tier: BoostTier = BoostTier(
        multiplier_bps=_multiplier_bps,
        min_principal=_min_principal,
        max_principal=_max_principal,
        duration=_duration,
        renewal_delay=_renewal_delay,
        activation_fee_bps=_activation_fee_bps,
        max_exit_penalty_bps=_max_exit_penalty_bps,
        active=_active,
        updated_at=block.timestamp,
    )
    self._validate(tier)
    self.tiers[tier_id] = tier
    self.next_tier_id = tier_id + 1
    if self.default_tier_id == 0:
        self.default_tier_id = tier_id
    log TierCreated(tier_id=tier_id, multiplier_bps=_multiplier_bps, duration=_duration)
    return tier_id

@external
def set_tier_active(_tier_id: uint256, _active: bool):
    self._only_manager()
    assert _tier_id > 0 and _tier_id < self.next_tier_id, "TIER_UNKNOWN"
    self.tiers[_tier_id].active = _active
    self.tiers[_tier_id].updated_at = block.timestamp
    log TierUpdated(tier_id=_tier_id, active=_active)

@view
@external
def require_active_tier(_tier_id: uint256) -> (uint256, uint256, uint256, uint256, uint256, uint256, uint256):
    assert _tier_id > 0 and _tier_id < self.next_tier_id, "TIER_UNKNOWN"
    tier: BoostTier = self.tiers[_tier_id]
    assert tier.active, "TIER_INACTIVE"
    return tier.multiplier_bps, tier.min_principal, tier.max_principal, tier.duration, tier.renewal_delay, tier.activation_fee_bps, tier.max_exit_penalty_bps

@view
@external
def quote_weight(_principal: uint256, _tier_id: uint256) -> uint256:
    tier: BoostTier = self.tiers[_tier_id]
    assert tier.active, "TIER_INACTIVE"
    assert _principal >= tier.min_principal, "PRINCIPAL_LOW"
    if tier.max_principal > 0:
        assert _principal <= tier.max_principal, "PRINCIPAL_HIGH"
    return _principal * tier.multiplier_bps // BPS

@view
@external
def quote_activation_fee(_principal: uint256, _tier_id: uint256) -> uint256:
    tier: BoostTier = self.tiers[_tier_id]
    return _principal * tier.activation_fee_bps // BPS
