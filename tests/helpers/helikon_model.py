
from __future__ import annotations

from dataclasses import dataclass

BPS = 10_000
RAY = 10**27


@dataclass
class Tier:
    multiplier_bps: int
    duration: int
    renewal_delay: int = 0
    fee_bps: int = 0
    min_principal: int = 0


@dataclass
class Position:
    owner: str
    principal: int
    base_weight: int
    accounting_weight: int
    multiplier_bps: int
    tier_id: int
    boost_expires_at: int
    last_boost_end: int
    unlock_at: int
    reward_index_paid: int
    pending_reward: int = 0
    claimed: int = 0
    closed: bool = False


class HelikonModel:
    def __init__(self, epoch_duration: int, reward_rate: int):
        self.now = 0
        self.epoch_duration = epoch_duration
        self.reward_rate = reward_rate
        self.current_epoch = 0
        self.global_index = 0
        self.last_update = 0
        self.total_accounting_weight = 0
        self.total_principal = 0
        self.total_claimed = 0
        self.positions: dict[int, Position] = {}
        self.tiers: dict[int, Tier] = {}
        self.next_position_id = 1

    def add_tier(self, tier_id: int, multiplier_bps: int, duration: int, renewal_delay: int = 0, fee_bps: int = 0, min_principal: int = 0) -> None:
        self.tiers[tier_id] = Tier(multiplier_bps, duration, renewal_delay, fee_bps, min_principal)

    def warp(self, seconds: int) -> None:
        assert seconds >= 0
        self.now += seconds

    def _sync(self) -> None:
        if self.now <= self.last_update:
            return
        elapsed = self.now - self.last_update
        if self.total_accounting_weight > 0:
            emitted = elapsed * self.reward_rate
            self.global_index += emitted * RAY // self.total_accounting_weight
        self.last_update = self.now

    def _accrue(self, position: Position) -> None:
        if self.global_index > position.reward_index_paid:
            position.pending_reward += position.accounting_weight * (self.global_index - position.reward_index_paid) // RAY
            position.reward_index_paid = self.global_index

    def _refresh_marker(self, position: Position) -> None:
        if position.boost_expires_at and self.now >= position.boost_expires_at and position.multiplier_bps != BPS:
            position.multiplier_bps = BPS
            position.tier_id = 0
            position.last_boost_end = position.boost_expires_at
            position.boost_expires_at = 0

    def stake(self, owner: str, amount: int, lock_duration: int = 0) -> int:
        assert amount > 0
        self._sync()
        pid = self.next_position_id
        self.next_position_id += 1
        self.positions[pid] = Position(owner, amount, amount, amount, BPS, 0, 0, 0, self.now + lock_duration if lock_duration else 0, self.global_index)
        self.total_principal += amount
        self.total_accounting_weight += amount
        return pid

    def activate_boost(self, position_id: int, tier_id: int) -> None:
        position = self.positions[position_id]
        tier = self.tiers[tier_id]
        assert position.principal >= tier.min_principal
        if position.last_boost_end:
            assert self.now >= position.last_boost_end + tier.renewal_delay
        self._sync()
        self._accrue(position)
        self._refresh_marker(position)
        old_weight = position.accounting_weight
        new_weight = position.principal * tier.multiplier_bps // BPS
        position.accounting_weight = new_weight
        position.multiplier_bps = tier.multiplier_bps
        position.tier_id = tier_id
        position.boost_expires_at = self.now + tier.duration
        self.total_accounting_weight += new_weight - old_weight

    def refresh_boost(self, position_id: int) -> None:
        position = self.positions[position_id]
        self._sync()
        self._accrue(position)
        self._refresh_marker(position)

    def claim(self, position_id: int) -> int:
        position = self.positions[position_id]
        self._sync()
        self._refresh_marker(position)
        self._accrue(position)
        reward = position.pending_reward
        position.pending_reward = 0
        position.claimed += reward
        self.total_claimed += reward
        return reward

    def unstake(self, position_id: int, amount: int) -> tuple[int, int]:
        position = self.positions[position_id]
        assert 0 < amount <= position.principal
        self._sync()
        self._refresh_marker(position)
        self._accrue(position)
        penalty = 0
        if position.unlock_at and self.now < position.unlock_at:
            penalty = amount * (position.unlock_at - self.now) // (365 * 24 * 60 * 60) // 5
        old_weight = position.accounting_weight
        position.principal -= amount
        if position.principal == 0:
            position.accounting_weight = 0
            position.closed = True
        else:
            position.base_weight = position.principal
            position.accounting_weight = position.principal * position.multiplier_bps // BPS
        self.total_principal -= amount
        self.total_accounting_weight += position.accounting_weight - old_weight
        return amount - penalty, penalty

    def close_epoch(self) -> None:
        self._sync()
        self.current_epoch += 1
        self.last_update = self.current_epoch * self.epoch_duration
