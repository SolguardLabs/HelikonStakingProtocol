# pragma version ^0.4.0


# @title HelikonStakingVault
# @notice Principal custody, reward claims, temporary boosts, and early exit accounting.

interface IERC20:
    def transferFrom(sender: address, receiver: address, amount: uint256) -> bool: nonpayable
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def balanceOf(owner: address) -> uint256: view

interface IAccess:
    def has_role(role: uint256, account: address) -> bool: view

interface IBoostRegistry:
    def require_active_tier(tier_id: uint256) -> (uint256, uint256, uint256, uint256, uint256, uint256, uint256): view

interface IRewarder:
    def sync(observed_weight: uint256) -> uint256: nonpayable
    def pay_reward(recipient: address, amount: uint256): nonpayable
    def close_epoch(observed_weight: uint256) -> uint256: nonpayable
    def current_epoch() -> uint256: view
    def preview_global_index(timestamp: uint256, observed_weight: uint256) -> uint256: view

interface IReserve:
    def notify_credit(amount: uint256, kind: uint256): nonpayable

struct Position:
    owner: address
    principal: uint256
    base_weight: uint256
    accounting_weight: uint256
    current_multiplier_bps: uint256
    active_tier_id: uint256
    boost_started_at: uint256
    boost_expires_at: uint256
    last_boost_end: uint256
    unlock_at: uint256
    reward_index_paid: uint256
    pending_reward: uint256
    total_claimed: uint256
    status: uint256

GOVERNOR_ROLE: constant(uint256) = 1
GUARDIAN_ROLE: constant(uint256) = 4
BPS: constant(uint256) = 10000
RAY: constant(uint256) = 10**27
ACTIVE: constant(uint256) = 1
CLOSED: constant(uint256) = 2
KIND_EXIT: constant(uint256) = 1

staking_token: public(address)
reward_token: public(address)
access: public(address)
boost_registry: public(address)
rewarder: public(address)
penalty_reserve: public(address)
next_position_id: public(uint256)
total_principal: public(uint256)
total_base_weight: public(uint256)
total_accounting_weight: public(uint256)
total_rewards_claimed: public(uint256)
total_exit_penalties: public(uint256)
deposits_paused: public(bool)
exits_paused: public(bool)
boosts_paused: public(bool)
positions: public(HashMap[uint256, Position])
operator_approvals: public(HashMap[address, HashMap[address, bool]])
position_operator: public(HashMap[uint256, address])

event PositionOpened:
    position_id: indexed(uint256)
    owner: indexed(address)
    principal: uint256
    weight: uint256

event BoostActivated:
    position_id: indexed(uint256)
    tier_id: indexed(uint256)
    weight: uint256
    expires_at: uint256

event BoostStatusRefreshed:
    position_id: indexed(uint256)
    multiplier_bps: uint256

event RewardClaimed:
    position_id: indexed(uint256)
    recipient: indexed(address)
    amount: uint256

event PositionWithdrawn:
    position_id: indexed(uint256)
    recipient: indexed(address)
    amount: uint256
    penalty: uint256

@deploy
def __init__(_staking_token: address, _reward_token: address, _access: address, _boost_registry: address, _rewarder: address, _penalty_reserve: address):
    assert _staking_token != empty(address), "ZERO_STAKING"
    assert _reward_token != empty(address), "ZERO_REWARD"
    assert _access != empty(address), "ZERO_ACCESS"
    assert _boost_registry != empty(address), "ZERO_REGISTRY"
    assert _rewarder != empty(address), "ZERO_REWARDER"
    assert _penalty_reserve != empty(address), "ZERO_RESERVE"
    self.staking_token = _staking_token
    self.reward_token = _reward_token
    self.access = _access
    self.boost_registry = _boost_registry
    self.rewarder = _rewarder
    self.penalty_reserve = _penalty_reserve
    self.next_position_id = 1

@internal
def _has_control(_account: address) -> bool:
    return staticcall IAccess(self.access).has_role(GOVERNOR_ROLE, _account) or staticcall IAccess(self.access).has_role(GUARDIAN_ROLE, _account)

@internal
def _weight(_principal: uint256, _multiplier_bps: uint256) -> uint256:
    return _principal * _multiplier_bps // BPS

@internal
def _is_authorized(_position_id: uint256, _account: address) -> bool:
    position: Position = self.positions[_position_id]
    if position.owner == _account:
        return True
    if self.position_operator[_position_id] == _account:
        return True
    return self.operator_approvals[position.owner][_account]

@internal
def _require_authorized(_position_id: uint256):
    assert self._is_authorized(_position_id, msg.sender), "NOT_AUTHORIZED"

@internal
def _sync() -> uint256:
    return extcall IRewarder(self.rewarder).sync(self.total_accounting_weight)

@internal
def _accrue(_position_id: uint256, _index: uint256):
    position: Position = self.positions[_position_id]
    if position.status != ACTIVE:
        return
    if _index > position.reward_index_paid:
        position.pending_reward += position.accounting_weight * (_index - position.reward_index_paid) // RAY
        position.reward_index_paid = _index
        self.positions[_position_id] = position

@internal
def _refresh_boost_marker(_position_id: uint256):
    position: Position = self.positions[_position_id]
    if position.status != ACTIVE:
        return
    if position.boost_expires_at != 0 and block.timestamp >= position.boost_expires_at and position.current_multiplier_bps != BPS:
        position.current_multiplier_bps = BPS
        position.active_tier_id = 0
        position.last_boost_end = position.boost_expires_at
        position.boost_expires_at = 0
        self.positions[_position_id] = position
        log BoostStatusRefreshed(position_id=_position_id, multiplier_bps=BPS)

@external
def set_pauses(_deposits: bool, _exits: bool, _boosts: bool):
    assert self._has_control(msg.sender), "ONLY_CONTROL"
    self.deposits_paused = _deposits
    self.exits_paused = _exits
    self.boosts_paused = _boosts

@external
def set_approval_for_all(_operator: address, _approved: bool):
    assert _operator != empty(address), "ZERO_OPERATOR"
    self.operator_approvals[msg.sender][_operator] = _approved

@external
def stake(_amount: uint256, _recipient: address, _lock_duration: uint256) -> uint256:
    assert not self.deposits_paused, "DEPOSITS_PAUSED"
    assert _amount > 0, "ZERO_AMOUNT"
    assert _recipient != empty(address), "ZERO_RECIPIENT"
    index_value: uint256 = self._sync()
    ok: bool = extcall IERC20(self.staking_token).transferFrom(msg.sender, self, _amount)
    assert ok, "TRANSFER_FROM_FAILED"
    position_id: uint256 = self.next_position_id
    weight: uint256 = self._weight(_amount, BPS)
    unlock_at: uint256 = 0
    if _lock_duration > 0:
        unlock_at = block.timestamp + _lock_duration
    self.positions[position_id] = Position(owner=_recipient, principal=_amount, base_weight=weight, accounting_weight=weight, current_multiplier_bps=BPS, active_tier_id=0, boost_started_at=0, boost_expires_at=0, last_boost_end=0, unlock_at=unlock_at, reward_index_paid=index_value, pending_reward=0, total_claimed=0, status=ACTIVE)
    self.next_position_id = position_id + 1
    self.total_principal += _amount
    self.total_base_weight += weight
    self.total_accounting_weight += weight
    log PositionOpened(position_id=position_id, owner=_recipient, principal=_amount, weight=weight)
    return position_id

@external
def activate_boost(_position_id: uint256, _tier_id: uint256):
    assert not self.boosts_paused, "BOOSTS_PAUSED"
    self._require_authorized(_position_id)
    index_value: uint256 = self._sync()
    self._accrue(_position_id, index_value)
    self._refresh_boost_marker(_position_id)
    position: Position = self.positions[_position_id]
    assert position.status == ACTIVE, "POSITION_INACTIVE"
    multiplier_bps: uint256 = 0
    min_principal: uint256 = 0
    max_principal: uint256 = 0
    duration: uint256 = 0
    renewal_delay: uint256 = 0
    fee_bps: uint256 = 0
    penalty_bps: uint256 = 0
    multiplier_bps, min_principal, max_principal, duration, renewal_delay, fee_bps, penalty_bps = staticcall IBoostRegistry(self.boost_registry).require_active_tier(_tier_id)
    assert position.principal >= min_principal, "PRINCIPAL_LOW"
    if max_principal > 0:
        assert position.principal <= max_principal, "PRINCIPAL_HIGH"
    if position.last_boost_end > 0:
        assert block.timestamp >= position.last_boost_end + renewal_delay, "RENEWAL_DELAY"
    fee: uint256 = position.principal * fee_bps // BPS
    if fee > 0:
        paid: bool = extcall IERC20(self.staking_token).transferFrom(msg.sender, self.penalty_reserve, fee)
        assert paid, "FEE_TRANSFER_FAILED"
        extcall IReserve(self.penalty_reserve).notify_credit(fee, KIND_EXIT)
    old_weight: uint256 = position.accounting_weight
    new_weight: uint256 = self._weight(position.principal, multiplier_bps)
    position.accounting_weight = new_weight
    position.current_multiplier_bps = multiplier_bps
    position.active_tier_id = _tier_id
    position.boost_started_at = block.timestamp
    position.boost_expires_at = block.timestamp + duration
    self.positions[_position_id] = position
    self.total_accounting_weight = self.total_accounting_weight + new_weight - old_weight
    log BoostActivated(position_id=_position_id, tier_id=_tier_id, weight=new_weight, expires_at=position.boost_expires_at)

@external
def refresh_boost(_position_id: uint256):
    self._require_authorized(_position_id)
    index_value: uint256 = self._sync()
    self._accrue(_position_id, index_value)
    self._refresh_boost_marker(_position_id)

@external
def claim(_position_id: uint256, _recipient: address) -> uint256:
    self._require_authorized(_position_id)
    assert _recipient != empty(address), "ZERO_RECIPIENT"
    index_value: uint256 = self._sync()
    self._refresh_boost_marker(_position_id)
    self._accrue(_position_id, index_value)
    position: Position = self.positions[_position_id]
    reward: uint256 = position.pending_reward
    position.pending_reward = 0
    position.total_claimed += reward
    self.positions[_position_id] = position
    if reward > 0:
        self.total_rewards_claimed += reward
        extcall IRewarder(self.rewarder).pay_reward(_recipient, reward)
    log RewardClaimed(position_id=_position_id, recipient=_recipient, amount=reward)
    return reward

@external
def unstake(_position_id: uint256, _amount: uint256, _recipient: address, _max_penalty: uint256) -> uint256:
    assert not self.exits_paused, "EXITS_PAUSED"
    self._require_authorized(_position_id)
    assert _recipient != empty(address), "ZERO_RECIPIENT"
    position: Position = self.positions[_position_id]
    assert position.status == ACTIVE, "POSITION_INACTIVE"
    assert _amount > 0 and _amount <= position.principal, "BAD_AMOUNT"
    index_value: uint256 = self._sync()
    self._refresh_boost_marker(_position_id)
    self._accrue(_position_id, index_value)
    position = self.positions[_position_id]
    penalty: uint256 = 0
    if position.unlock_at > block.timestamp:
        penalty = _amount * (position.unlock_at - block.timestamp) // (365 * 86400) // 5
    assert penalty <= _max_penalty, "PENALTY_HIGH"
    old_weight: uint256 = position.accounting_weight
    position.principal -= _amount
    if position.principal == 0:
        position.accounting_weight = 0
        position.status = CLOSED
    else:
        position.base_weight = position.principal
        position.accounting_weight = self._weight(position.principal, position.current_multiplier_bps)
    self.positions[_position_id] = position
    self.total_principal -= _amount
    if self.total_base_weight >= _amount:
        self.total_base_weight -= _amount
    if old_weight >= position.accounting_weight:
        self.total_accounting_weight -= old_weight - position.accounting_weight
    else:
        self.total_accounting_weight += position.accounting_weight - old_weight
    if penalty > 0:
        self.total_exit_penalties += penalty
        okp: bool = extcall IERC20(self.staking_token).transfer(self.penalty_reserve, penalty)
        assert okp, "PENALTY_TRANSFER_FAILED"
        extcall IReserve(self.penalty_reserve).notify_credit(penalty, KIND_EXIT)
    received: uint256 = _amount - penalty
    if received > 0:
        ok: bool = extcall IERC20(self.staking_token).transfer(_recipient, received)
        assert ok, "TRANSFER_FAILED"
    log PositionWithdrawn(position_id=_position_id, recipient=_recipient, amount=_amount, penalty=penalty)
    return received

@external
def close_current_epoch() -> uint256:
    return extcall IRewarder(self.rewarder).close_epoch(self.total_accounting_weight)

@view
@external
def pending_rewards(_position_id: uint256) -> uint256:
    position: Position = self.positions[_position_id]
    if position.status != ACTIVE:
        return 0
    preview: uint256 = staticcall IRewarder(self.rewarder).preview_global_index(block.timestamp, self.total_accounting_weight)
    if preview <= position.reward_index_paid:
        return position.pending_reward
    return position.pending_reward + position.accounting_weight * (preview - position.reward_index_paid) // RAY

@view
@external
def owner_of(_position_id: uint256) -> address:
    return self.positions[_position_id].owner

@view
@external
def position_health(_position_id: uint256) -> (uint256, uint256, uint256, uint256, bool):
    position: Position = self.positions[_position_id]
    expired: bool = False
    if position.boost_expires_at > 0 and block.timestamp >= position.boost_expires_at:
        expired = True
    return position.principal, position.base_weight, position.accounting_weight, position.current_multiplier_bps, expired

@view
@external
def protocol_snapshot() -> (uint256, uint256, uint256, uint256, uint256):
    return self.total_principal, self.total_base_weight, self.total_accounting_weight, self.total_rewards_claimed, self.total_exit_penalties

@view
@external
def principal_solvent() -> bool:
    return staticcall IERC20(self.staking_token).balanceOf(self) >= self.total_principal
