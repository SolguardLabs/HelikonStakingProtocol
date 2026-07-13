# pragma version ^0.4.0


# @title HelikonAccess
# @notice Shared role and module-pause registry.

DEFAULT_ADMIN_ROLE: constant(uint256) = 0
GOVERNOR_ROLE: constant(uint256) = 1
REWARD_MANAGER_ROLE: constant(uint256) = 2
KEEPER_ROLE: constant(uint256) = 3
GUARDIAN_ROLE: constant(uint256) = 4
TREASURY_ROLE: constant(uint256) = 5
BOOST_MANAGER_ROLE: constant(uint256) = 6
MAX_ROLE: constant(uint256) = 6

roles: public(HashMap[uint256, HashMap[address, bool]])
role_admin: public(HashMap[uint256, uint256])
module_paused: public(HashMap[uint256, bool])
admin_delay: public(uint256)
pending_admin: public(address)
pending_admin_ready_at: public(uint256)

event RoleGranted:
    role: indexed(uint256)
    account: indexed(address)
    sender: indexed(address)

event RoleRevoked:
    role: indexed(uint256)
    account: indexed(address)
    sender: indexed(address)

event ModulePauseChanged:
    module_id: indexed(uint256)
    paused: bool

event PendingAdminSet:
    account: indexed(address)
    ready_at: uint256

@deploy
def __init__(_admin: address, _delay: uint256):
    assert _admin != empty(address), "ZERO_ADMIN"
    self.roles[DEFAULT_ADMIN_ROLE][_admin] = True
    self.admin_delay = _delay
    for role: uint256 in range(7):
        self.role_admin[role] = DEFAULT_ADMIN_ROLE

@view
@internal
def _check_role(_role: uint256, _account: address):
    assert self.roles[_role][_account], "ROLE_MISSING"

@external
def grant_role(_role: uint256, _account: address):
    assert _role <= MAX_ROLE, "ROLE_UNKNOWN"
    assert _account != empty(address), "ZERO_ACCOUNT"
    self._check_role(self.role_admin[_role], msg.sender)
    if not self.roles[_role][_account]:
        self.roles[_role][_account] = True
        log RoleGranted(role=_role, account=_account, sender=msg.sender)

@external
def revoke_role(_role: uint256, _account: address):
    assert _role <= MAX_ROLE, "ROLE_UNKNOWN"
    self._check_role(self.role_admin[_role], msg.sender)
    if self.roles[_role][_account]:
        self.roles[_role][_account] = False
        log RoleRevoked(role=_role, account=_account, sender=msg.sender)

@external
def set_module_pause(_module_id: uint256, _paused: bool):
    assert self.roles[GUARDIAN_ROLE][msg.sender] or self.roles[GOVERNOR_ROLE][msg.sender] or self.roles[DEFAULT_ADMIN_ROLE][msg.sender], "ONLY_CONTROL"
    self.module_paused[_module_id] = _paused
    log ModulePauseChanged(module_id=_module_id, paused=_paused)

@external
def set_pending_admin(_account: address):
    self._check_role(DEFAULT_ADMIN_ROLE, msg.sender)
    assert _account != empty(address), "ZERO_ACCOUNT"
    self.pending_admin = _account
    self.pending_admin_ready_at = block.timestamp + self.admin_delay
    log PendingAdminSet(account=_account, ready_at=self.pending_admin_ready_at)

@external
def accept_admin():
    assert msg.sender == self.pending_admin, "NOT_PENDING"
    assert block.timestamp >= self.pending_admin_ready_at, "DELAY_ACTIVE"
    self.roles[DEFAULT_ADMIN_ROLE][msg.sender] = True
    self.pending_admin = empty(address)
    self.pending_admin_ready_at = 0

@view
@external
def has_role(_role: uint256, _account: address) -> bool:
    return self.roles[_role][_account]

@view
@external
def check_role(_role: uint256, _account: address) -> bool:
    self._check_role(_role, _account)
    return True
