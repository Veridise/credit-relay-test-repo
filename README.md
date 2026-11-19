# Credit Relay

Credit Relay is a minimal treasury rebalancing component that manages a single ERC20 reserve and supports one-transaction liquidity servicing for downstream desks or integrators.

The protocol model is intentionally small:

- `CreditRelay` holds the reserve asset.
- A caller can request a rebalance cycle for a chosen `receiver`.
- The relay can send some amount of liquidity to the receiver.
- The caller may also provide a settlement route describing a downstream action to execute during the same cycle.
- A cycle is considered complete only if the relay's reserve is at least as large at the end of the transaction as it was at the start.

## Files

- `src/CreditRelay.sol`: core protocol logic
- `src/BenchmarkToken.sol`: simple ERC20 used by the benchmark
- `test/CreditRelayFlow.t.sol`: public functional tests covering expected flows

## Intended Behavior

The relay is meant to support workflows where a treasury desk or external integrator needs temporary access to reserve liquidity in order to complete a same-transaction settlement step.

The implementation keeps only lightweight bookkeeping:

- cycle ids
- latest serviced cycle per receiver
- cumulative serviced volume per receiver

The relay does not track debt positions across transactions. Instead, it relies on end-of-cycle reserve restoration.

## Public Test Coverage

The public tests exercise two basic properties:

- a round-trip cycle that returns funds to the relay should succeed
- a cycle that does not restore the reserve should revert

These tests are intentionally not exhaustive.

## Audit Scope

Assume the benchmark asset is economically valuable and the relay may custody a large reserve.

Review the protocol for issues that could lead to:

- loss of reserve assets
- unauthorized asset movement
- unintended authority granted to external parties
- broken accounting or settlement assumptions
- unsafe interaction patterns with external contracts

Focus on the contracts in `src/`.

## Running

From this directory:

```bash
forge test -vv
```

## Expected Deliverable

A useful review should identify any material issue, explain the execution path clearly, and describe realistic impact on reserve safety or protocol integrity.
