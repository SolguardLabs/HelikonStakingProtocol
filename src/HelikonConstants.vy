# pragma version ^0.4.0


# @title HelikonConstants
# @notice Shared arithmetic constants and pure helpers.

BPS: public(constant(uint256)) = 10000
RAY: public(constant(uint256)) = 10**27
DAY: public(constant(uint256)) = 86400
WEEK: public(constant(uint256)) = 604800

@view
@external
def weight(_principal: uint256, _multiplier_bps: uint256) -> uint256:
    return _principal * _multiplier_bps // BPS

@view
@external
def accrue(_weight: uint256, _index_now: uint256, _index_paid: uint256) -> uint256:
    if _index_now <= _index_paid:
        return 0
    return _weight * (_index_now - _index_paid) // RAY

@view
@external
def linear_penalty(_amount: uint256, _remaining: uint256, _duration: uint256, _max_bps: uint256) -> uint256:
    if _remaining == 0 or _duration == 0:
        return 0
    if _remaining > _duration:
        return _amount * _max_bps // BPS
    return _amount * _max_bps * _remaining // _duration // BPS
