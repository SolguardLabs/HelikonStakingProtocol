
from tests.helpers.helikon_model import BPS, HelikonModel

DAY = 24 * 60 * 60
WEEK = 7 * DAY
TOKEN = 10**18


def configured_model() -> HelikonModel:
    model = HelikonModel(epoch_duration=WEEK, reward_rate=TOKEN)
    model.add_tier(1, multiplier_bps=15_000, duration=2 * DAY, renewal_delay=DAY, fee_bps=25)
    model.add_tier(2, multiplier_bps=25_000, duration=DAY, renewal_delay=0, fee_bps=50)
    return model


def test_stake_tracks_principal_and_base_weight():
    model = configured_model()
    pid = model.stake("alice", 1_000 * TOKEN, lock_duration=30 * DAY)
    position = model.positions[pid]
    assert position.owner == "alice"
    assert position.principal == 1_000 * TOKEN
    assert position.accounting_weight == 1_000 * TOKEN
    assert model.total_principal == 1_000 * TOKEN


def test_claim_accrues_epoch_rewards_for_active_weight():
    model = configured_model()
    pid = model.stake("alice", 1_000 * TOKEN)
    model.warp(DAY)
    reward = model.claim(pid)
    assert reward == DAY * TOKEN
    assert model.positions[pid].claimed == reward


def test_boost_lifecycle_updates_visible_multiplier_after_expiry():
    model = configured_model()
    pid = model.stake("alice", 1_000 * TOKEN)
    model.activate_boost(pid, 1)
    assert model.positions[pid].multiplier_bps == 15_000
    model.warp(2 * DAY + 1)
    model.refresh_boost(pid)
    assert model.positions[pid].multiplier_bps == BPS
    assert model.positions[pid].tier_id == 0
    assert model.positions[pid].last_boost_end > 0


def test_unstake_applies_time_based_penalty_and_reduces_weight():
    model = configured_model()
    pid = model.stake("alice", 1_000 * TOKEN, lock_duration=365 * DAY)
    model.warp(30 * DAY)
    received, penalty = model.unstake(pid, 250 * TOKEN)
    assert penalty > 0
    assert received + penalty == 250 * TOKEN
    assert model.positions[pid].principal == 750 * TOKEN


def test_close_epoch_advances_accounting_window():
    model = configured_model()
    pid = model.stake("alice", 1_000 * TOKEN)
    model.warp(WEEK)
    before = model.claim(pid)
    model.close_epoch()
    assert before == WEEK * TOKEN
    assert model.current_epoch == 1
    assert model.last_update == WEEK


def test_multiple_stakers_share_rewards_by_weight():
    model = configured_model()
    alice = model.stake("alice", 1_000 * TOKEN)
    bob = model.stake("bob", 1_000 * TOKEN)
    model.activate_boost(alice, 1)
    model.warp(DAY)
    alice_reward = model.claim(alice)
    bob_reward = model.claim(bob)
    assert alice_reward > bob_reward
    assert alice_reward + bob_reward == DAY * TOKEN
