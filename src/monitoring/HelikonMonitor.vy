# pragma version ^0.4.0


# @title HelikonMonitor
# @notice Keeper-oriented health checks for staking and reward accounting.

interface IVault:
    def protocol_snapshot() -> (uint256, uint256, uint256, uint256, uint256): view
    def principal_solvent() -> bool: view

vault: public(address)
max_weight_spread_bps: public(uint256)
last_scan_ok: public(bool)
last_scan_at: public(uint256)

event ScanRecorded:
    ok: bool
    timestamp: uint256

@deploy
def __init__(_vault: address):
    assert _vault != empty(address), "ZERO_VAULT"
    self.vault = _vault
    self.max_weight_spread_bps = 50000

@view
@internal
def _check_protocol() -> bool:
    total_principal: uint256 = 0
    total_base_weight: uint256 = 0
    total_accounting_weight: uint256 = 0
    total_rewards_claimed: uint256 = 0
    total_exit_penalties: uint256 = 0
    total_principal, total_base_weight, total_accounting_weight, total_rewards_claimed, total_exit_penalties = staticcall IVault(self.vault).protocol_snapshot()
    if not staticcall IVault(self.vault).principal_solvent():
        return False
    if total_base_weight > 0 and total_accounting_weight * 10000 // total_base_weight > self.max_weight_spread_bps:
        return False
    return True

@external
def set_max_weight_spread(_spread_bps: uint256):
    assert _spread_bps >= 10000, "SPREAD_LOW"
    self.max_weight_spread_bps = _spread_bps

@view
@external
def check_protocol() -> bool:
    return self._check_protocol()

@external
def record_scan() -> bool:
    ok: bool = self._check_protocol()
    self.last_scan_ok = ok
    self.last_scan_at = block.timestamp
    log ScanRecorded(ok=ok, timestamp=block.timestamp)
    return ok
