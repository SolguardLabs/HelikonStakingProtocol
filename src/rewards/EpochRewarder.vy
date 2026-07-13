# pragma version ^0.4.0


# @title EpochRewarder
# @notice Reward index controller with scheduled epoch budgets.

interface IERC20:
    def transferFrom(sender: address, receiver: address, amount: uint256) -> bool: nonpayable
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def balanceOf(owner: address) -> uint256: view

interface IAccess:
    def has_role(role: uint256, account: address) -> bool: view

struct Epoch:
    start_at: uint256
    end_at: uint256
    budget: uint256
    reward_rate: uint256
    emitted: uint256
    index_start: uint256
    index_end: uint256
    closed: bool

GOVERNOR_ROLE: constant(uint256) = 1
REWARD_MANAGER_ROLE: constant(uint256) = 2
KEEPER_ROLE: constant(uint256) = 3
RAY: constant(uint256) = 10**27

reward_token: public(address)
access: public(address)
vault: public(address)
genesis: public(uint256)
epoch_duration: public(uint256)
current_epoch: public(uint256)
global_index: public(uint256)
last_update: public(uint256)
last_observed_weight: public(uint256)
total_rewards_funded: public(uint256)
total_rewards_paid: public(uint256)
total_rewards_emitted: public(uint256)
epochs: public(HashMap[uint256, Epoch])

event EpochScheduled:
    epoch_id: indexed(uint256)
    budget: uint256
    reward_rate: uint256

event RewardsFunded:
    funder: indexed(address)
    amount: uint256

event RewardIndexUpdated:
    epoch_id: indexed(uint256)
    index_value: uint256
    emitted: uint256
    observed_weight: uint256

event RewardPaid:
    recipient: indexed(address)
    amount: uint256

event EpochClosed:
    epoch_id: indexed(uint256)
    index_end: uint256

@deploy
def __init__(_reward_token: address, _access: address, _genesis: uint256, _epoch_duration: uint256):
    assert _reward_token != empty(address), "ZERO_REWARD"
    assert _access != empty(address), "ZERO_ACCESS"
    assert _epoch_duration > 0, "BAD_DURATION"
    self.reward_token = _reward_token
    self.access = _access
    self.genesis = _genesis
    self.epoch_duration = _epoch_duration
    self.last_update = _genesis

@internal
def _has(_role: uint256, _account: address) -> bool:
    return staticcall IAccess(self.access).has_role(_role, _account)

@external
def set_vault(_vault: address):
    assert self._has(GOVERNOR_ROLE, msg.sender), "ONLY_GOVERNOR"
    assert self.vault == empty(address), "VAULT_SET"
    assert _vault != empty(address), "ZERO_VAULT"
    self.vault = _vault

@external
def fund_rewards(_amount: uint256):
    assert _amount > 0, "ZERO_AMOUNT"
    ok: bool = extcall IERC20(self.reward_token).transferFrom(msg.sender, self, _amount)
    assert ok, "TRANSFER_FAILED"
    self.total_rewards_funded += _amount
    log RewardsFunded(funder=msg.sender, amount=_amount)

@external
def schedule_epoch(_epoch_id: uint256, _budget: uint256, _reward_rate: uint256):
    assert self._has(REWARD_MANAGER_ROLE, msg.sender) or self._has(GOVERNOR_ROLE, msg.sender), "ONLY_REWARDS"
    assert _budget > 0, "ZERO_BUDGET"
    assert _reward_rate > 0, "ZERO_RATE"
    start_at: uint256 = self.genesis + _epoch_id * self.epoch_duration
    self.epochs[_epoch_id] = Epoch(start_at=start_at, end_at=start_at + self.epoch_duration, budget=_budget, reward_rate=_reward_rate, emitted=0, index_start=self.global_index, index_end=0, closed=False)
    log EpochScheduled(epoch_id=_epoch_id, budget=_budget, reward_rate=_reward_rate)

@internal
def _sync_current(_observed_weight: uint256) -> uint256:
    if block.timestamp <= self.last_update:
        self.last_observed_weight = _observed_weight
        return self.global_index
    epoch: Epoch = self.epochs[self.current_epoch]
    cutoff: uint256 = block.timestamp
    if epoch.end_at > 0 and cutoff > epoch.end_at:
        cutoff = epoch.end_at
    if cutoff <= self.last_update:
        self.last_observed_weight = _observed_weight
        return self.global_index
    elapsed: uint256 = cutoff - self.last_update
    emission: uint256 = elapsed * epoch.reward_rate
    remaining: uint256 = 0
    if epoch.budget > epoch.emitted:
        remaining = epoch.budget - epoch.emitted
    if remaining == 0:
        emission = 0
    elif emission > remaining:
        emission = remaining
    if _observed_weight > 0 and emission > 0:
        self.global_index += emission * RAY // _observed_weight
        epoch.emitted += emission
        self.total_rewards_emitted += emission
        self.epochs[self.current_epoch] = epoch
    self.last_update = cutoff
    self.last_observed_weight = _observed_weight
    log RewardIndexUpdated(epoch_id=self.current_epoch, index_value=self.global_index, emitted=emission, observed_weight=_observed_weight)
    return self.global_index

@external
def sync(_observed_weight: uint256) -> uint256:
    assert msg.sender == self.vault or self._has(KEEPER_ROLE, msg.sender), "ONLY_SYNC"
    return self._sync_current(_observed_weight)

@external
def close_epoch(_observed_weight: uint256) -> uint256:
    assert msg.sender == self.vault or self._has(KEEPER_ROLE, msg.sender), "ONLY_SYNC"
    index_value: uint256 = self._sync_current(_observed_weight)
    epoch: Epoch = self.epochs[self.current_epoch]
    assert block.timestamp >= epoch.end_at, "EPOCH_ACTIVE"
    epoch.closed = True
    epoch.index_end = index_value
    self.epochs[self.current_epoch] = epoch
    log EpochClosed(epoch_id=self.current_epoch, index_end=index_value)
    self.current_epoch += 1
    self.last_update = self.genesis + self.current_epoch * self.epoch_duration
    return index_value

@external
def pay_reward(_recipient: address, _amount: uint256):
    assert msg.sender == self.vault, "ONLY_VAULT"
    assert _recipient != empty(address), "ZERO_RECIPIENT"
    if _amount > 0:
        self.total_rewards_paid += _amount
        ok: bool = extcall IERC20(self.reward_token).transfer(_recipient, _amount)
        assert ok, "PAY_FAILED"
        log RewardPaid(recipient=_recipient, amount=_amount)

@view
@external
def preview_global_index(_timestamp: uint256, _observed_weight: uint256) -> uint256:
    if _timestamp <= self.last_update or _observed_weight == 0:
        return self.global_index
    epoch: Epoch = self.epochs[self.current_epoch]
    cutoff: uint256 = _timestamp
    if epoch.end_at > 0 and cutoff > epoch.end_at:
        cutoff = epoch.end_at
    if cutoff <= self.last_update:
        return self.global_index
    emission: uint256 = (cutoff - self.last_update) * epoch.reward_rate
    remaining: uint256 = 0
    if epoch.budget > epoch.emitted:
        remaining = epoch.budget - epoch.emitted
    if remaining == 0:
        return self.global_index
    if emission > remaining:
        emission = remaining
    return self.global_index + emission * RAY // _observed_weight

@view
@external
def reward_liquidity() -> uint256:
    return staticcall IERC20(self.reward_token).balanceOf(self)
