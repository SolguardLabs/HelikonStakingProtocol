# pragma version ^0.4.0


# @title HelikonLens
# @notice Aggregates staking and reward reads for clients.

interface IVault:
    def pending_rewards(position_id: uint256) -> uint256: view
    def position_health(position_id: uint256) -> (uint256, uint256, uint256, uint256, bool): view
    def protocol_snapshot() -> (uint256, uint256, uint256, uint256, uint256): view
    def owner_of(position_id: uint256) -> address: view
    def principal_solvent() -> bool: view

vault: public(address)

@deploy
def __init__(_vault: address):
    assert _vault != empty(address), "ZERO_VAULT"
    self.vault = _vault

@view
@external
def position_card(_position_id: uint256) -> (address, uint256, uint256, uint256, uint256, bool):
    principal: uint256 = 0
    base_weight: uint256 = 0
    accounting_weight: uint256 = 0
    multiplier_bps: uint256 = 0
    expired: bool = False
    principal, base_weight, accounting_weight, multiplier_bps, expired = staticcall IVault(self.vault).position_health(_position_id)
    pending: uint256 = staticcall IVault(self.vault).pending_rewards(_position_id)
    owner: address = staticcall IVault(self.vault).owner_of(_position_id)
    return owner, principal, accounting_weight, multiplier_bps, pending, expired

@view
@external
def protocol_card() -> (uint256, uint256, uint256, uint256, uint256, bool):
    total_principal: uint256 = 0
    total_base_weight: uint256 = 0
    total_accounting_weight: uint256 = 0
    total_rewards_claimed: uint256 = 0
    total_exit_penalties: uint256 = 0
    total_principal, total_base_weight, total_accounting_weight, total_rewards_claimed, total_exit_penalties = staticcall IVault(self.vault).protocol_snapshot()
    solvent: bool = staticcall IVault(self.vault).principal_solvent()
    return total_principal, total_base_weight, total_accounting_weight, total_rewards_claimed, total_exit_penalties, solvent
