// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface ISettlementAsset {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

library RouteExecutor {
    function execute(address endpoint, bytes calldata payload) internal returns (bool) {
        (bool ok, ) = endpoint.call(payload);
        return ok;
    }
}

abstract contract CycleLedger {
    ISettlementAsset internal immutable settlementAsset;
    uint64 internal cycleNonce;

    mapping(address => uint64) internal latestCycle;
    mapping(address => uint256) internal servicedVolume;

    struct Snapshot {
        uint256 reserveBefore;
        uint64 cycleId;
    }

    constructor(address asset_) {
        settlementAsset = ISettlementAsset(asset_);
    }

    function asset() external view returns (address) {
        return address(settlementAsset);
    }

    function cycleCount() external view returns (uint64) {
        return cycleNonce;
    }

    function latestCycleFor(address account) external view returns (uint64) {
        return latestCycle[account];
    }

    function servicedAmountFor(address account) external view returns (uint256) {
        return servicedVolume[account];
    }

    function _checkpoint(uint256 amount) internal returns (Snapshot memory snapshot) {
        uint256 reserveBefore = settlementAsset.balanceOf(address(this));
        require(_canService(reserveBefore, amount), "reserve too low");

        cycleNonce += 1;
        snapshot = Snapshot({reserveBefore: reserveBefore, cycleId: cycleNonce});
    }

    function _canService(uint256 reserveBefore, uint256 amount) internal pure returns (bool) {
        return reserveBefore >= amount;
    }

    function _record(address receiver, Snapshot memory snapshot, uint256 amount) internal {
        latestCycle[receiver] = snapshot.cycleId;
        servicedVolume[receiver] += amount;
    }
}

contract CreditRelay is CycleLedger {
    using RouteExecutor for address;

    struct Route {
        address endpoint;
        bytes payload;
    }

    event CycleClosed(address indexed receiver, uint256 amount, uint64 indexed cycleId);

    constructor(address asset_) CycleLedger(asset_) {}

    function rebalance(uint256 amount, address receiver, Route calldata route) external {
        Snapshot memory snapshot = _checkpoint(amount);
        _advanceLiquidity(receiver, amount);
        _runRoute(route);
        _closeCycle(receiver, amount, snapshot);
    }

    function _advanceLiquidity(address receiver, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        require(settlementAsset.transfer(receiver, amount), "transfer failed");
    }

    function _runRoute(Route calldata route) internal {
        if (!_hasRoute(route)) {
            return;
        }

        require(route.endpoint.execute(route.payload), "route failed");
    }

    function _hasRoute(Route calldata route) internal pure returns (bool) {
        return route.endpoint != address(0);
    }

    function _closeCycle(address receiver, uint256 amount, Snapshot memory snapshot) internal {
        _record(receiver, snapshot, amount);
        require(settlementAsset.balanceOf(address(this)) >= snapshot.reserveBefore, "cycle unsettled");
        emit CycleClosed(receiver, amount, snapshot.cycleId);
    }
}
