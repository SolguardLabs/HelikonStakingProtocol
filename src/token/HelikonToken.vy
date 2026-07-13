# pragma version ^0.4.0


# @title HelikonToken
# @notice Minimal ERC20 token for local deployments and integration tests.

name: public(String[64])
symbol: public(String[16])
decimals: public(uint8)
totalSupply: public(uint256)
admin: public(address)
minter: public(address)
paused: public(bool)

balances: public(HashMap[address, uint256])
allowances: public(HashMap[address, HashMap[address, uint256]])
INFINITE_ALLOWANCE: constant(uint256) = max_value(uint256)

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

event MinterUpdated:
    old_minter: indexed(address)
    new_minter: indexed(address)

event PauseChanged:
    paused: bool

@deploy
def __init__(_name: String[64], _symbol: String[16], _decimals: uint8, _admin: address):
    assert _admin != empty(address), "ZERO_ADMIN"
    self.name = _name
    self.symbol = _symbol
    self.decimals = _decimals
    self.admin = _admin
    self.minter = _admin

@internal
def _transfer(_sender: address, _receiver: address, _amount: uint256):
    assert not self.paused, "TOKEN_PAUSED"
    assert _receiver != empty(address), "ZERO_RECEIVER"
    assert self.balances[_sender] >= _amount, "BALANCE_LOW"
    self.balances[_sender] -= _amount
    self.balances[_receiver] += _amount
    log Transfer(sender=_sender, receiver=_receiver, value=_amount)

@external
def transfer(_receiver: address, _amount: uint256) -> bool:
    self._transfer(msg.sender, _receiver, _amount)
    return True

@external
def approve(_spender: address, _amount: uint256) -> bool:
    assert _spender != empty(address), "ZERO_SPENDER"
    self.allowances[msg.sender][_spender] = _amount
    log Approval(owner=msg.sender, spender=_spender, value=_amount)
    return True

@external
def transferFrom(_sender: address, _receiver: address, _amount: uint256) -> bool:
    allowed: uint256 = self.allowances[_sender][msg.sender]
    if allowed != INFINITE_ALLOWANCE:
        assert allowed >= _amount, "ALLOWANCE_LOW"
        self.allowances[_sender][msg.sender] = allowed - _amount
        log Approval(owner=_sender, spender=msg.sender, value=allowed - _amount)
    self._transfer(_sender, _receiver, _amount)
    return True

@external
def mint(_receiver: address, _amount: uint256):
    assert msg.sender == self.minter or msg.sender == self.admin, "ONLY_MINTER"
    assert _receiver != empty(address), "ZERO_RECEIVER"
    assert _amount > 0, "ZERO_AMOUNT"
    self.totalSupply += _amount
    self.balances[_receiver] += _amount
    log Transfer(sender=empty(address), receiver=_receiver, value=_amount)

@external
def burn(_amount: uint256):
    assert _amount > 0, "ZERO_AMOUNT"
    assert self.balances[msg.sender] >= _amount, "BALANCE_LOW"
    self.balances[msg.sender] -= _amount
    self.totalSupply -= _amount
    log Transfer(sender=msg.sender, receiver=empty(address), value=_amount)

@external
def set_minter(_minter: address):
    assert msg.sender == self.admin, "ONLY_ADMIN"
    assert _minter != empty(address), "ZERO_MINTER"
    old: address = self.minter
    self.minter = _minter
    log MinterUpdated(old_minter=old, new_minter=_minter)

@external
def set_pause(_paused: bool):
    assert msg.sender == self.admin, "ONLY_ADMIN"
    self.paused = _paused
    log PauseChanged(paused=_paused)

@view
@external
def balanceOf(_owner: address) -> uint256:
    return self.balances[_owner]

@view
@external
def allowance(_owner: address, _spender: address) -> uint256:
    return self.allowances[_owner][_spender]
