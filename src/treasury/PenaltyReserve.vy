# pragma version ^0.4.0


# @title PenaltyReserve
# @notice Tracks and custodies exit penalties credited by staking modules.

interface IERC20:
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def balanceOf(owner: address) -> uint256: view

asset: public(address)
treasury: public(address)
total_penalties: public(uint256)
total_slashed: public(uint256)
credits_by_kind: public(HashMap[uint256, uint256])

event CreditNotified:
    kind: indexed(uint256)
    amount: uint256

event TreasuryWithdraw:
    recipient: indexed(address)
    amount: uint256

@deploy
def __init__(_asset: address, _treasury: address):
    assert _asset != empty(address), "ZERO_ASSET"
    assert _treasury != empty(address), "ZERO_TREASURY"
    self.asset = _asset
    self.treasury = _treasury

@external
def notify_credit(_amount: uint256, _kind: uint256):
    assert _amount > 0, "ZERO_AMOUNT"
    if _kind == 1:
        self.total_penalties += _amount
    elif _kind == 2:
        self.total_slashed += _amount
    self.credits_by_kind[_kind] += _amount
    log CreditNotified(kind=_kind, amount=_amount)

@external
def withdraw(_recipient: address, _amount: uint256):
    assert msg.sender == self.treasury, "ONLY_TREASURY"
    assert _recipient != empty(address), "ZERO_RECIPIENT"
    ok: bool = extcall IERC20(self.asset).transfer(_recipient, _amount)
    assert ok, "TRANSFER_FAILED"
    log TreasuryWithdraw(recipient=_recipient, amount=_amount)

@view
@external
def reserve_balance() -> uint256:
    return staticcall IERC20(self.asset).balanceOf(self)
