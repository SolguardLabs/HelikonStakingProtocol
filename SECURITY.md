
# Security Policy

## Scope

The review scope includes all Vyper contracts in `src/`, the Python behavior model in `tests/`, and the deployment/CI scripts.

## Expected Invariants

- Principal tracked by `HelikonStakingVault` remains backed by staking token balance.
- Reward indices are monotonic and move only through `EpochRewarder`.
- Position ownership and operator approvals gate position mutations.
- Boost tiers are managed by authorized governance or boost manager roles.
- Exit penalties are transferred to `PenaltyReserve` and classified for accounting.
- Reward payouts are transferred only by `EpochRewarder` after a vault claim.

## Validation

```bash
python scripts/compile_sources.py
python -m pytest -q
```

## Reporting

Reports should include affected files, severity, reproduction steps, economic impact, and suggested remediation. Keep reports private until maintainers have acknowledged and triaged the issue.
