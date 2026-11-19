// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../src/BenchmarkToken.sol";
import "../src/CreditRelay.sol";

contract TreasuryDesk {
    BenchmarkToken internal immutable asset;
    CreditRelay internal immutable relay;
    uint256 public completedAmount;

    constructor(address asset_, address relay_) {
        asset = BenchmarkToken(asset_);
        relay = CreditRelay(relay_);
    }

    function settle(uint256 amount) external {
        completedAmount += amount;
        require(asset.transfer(address(relay), amount), "repayment failed");
    }
}

contract IdleDesk {
    uint256 public touches;

    function note() external {
        touches += 1;
    }
}

contract CreditRelayFlowTest {
    uint256 internal constant INITIAL_RESERVE = 1_000_000 ether;

    function testRebalanceRoundTrip() public {
        BenchmarkToken asset = new BenchmarkToken("Benchmark Asset", "BMA", INITIAL_RESERVE, address(this));
        CreditRelay relay = new CreditRelay(address(asset));
        TreasuryDesk desk = new TreasuryDesk(address(asset), address(relay));

        require(asset.transfer(address(relay), INITIAL_RESERVE), "funding failed");

        CreditRelay.Route memory route = CreditRelay.Route({
            endpoint: address(desk),
            payload: abi.encodeCall(TreasuryDesk.settle, (125 ether))
        });

        relay.rebalance(125 ether, address(desk), route);

        require(asset.balanceOf(address(relay)) == INITIAL_RESERVE, "reserve mismatch");
        require(asset.balanceOf(address(desk)) == 0, "desk retained funds");
        require(relay.cycleCount() == 1, "cycle count mismatch");
        require(relay.latestCycleFor(address(desk)) == 1, "desk cycle mismatch");
        require(relay.servicedAmountFor(address(desk)) == 125 ether, "desk volume mismatch");
        require(desk.completedAmount() == 125 ether, "desk accounting mismatch");
    }

    function testRevertsWhenRoundTripIsIncomplete() public {
        BenchmarkToken asset = new BenchmarkToken("Benchmark Asset", "BMA", INITIAL_RESERVE, address(this));
        CreditRelay relay = new CreditRelay(address(asset));
        IdleDesk desk = new IdleDesk();

        require(asset.transfer(address(relay), INITIAL_RESERVE), "funding failed");

        CreditRelay.Route memory route = CreditRelay.Route({
            endpoint: address(desk),
            payload: abi.encodeCall(IdleDesk.note, ())
        });

        (bool ok, ) = address(relay).call(
            abi.encodeCall(CreditRelay.rebalance, (25 ether, address(desk), route))
        );

        require(!ok, "cycle should fail");
        require(asset.balanceOf(address(relay)) == INITIAL_RESERVE, "reserve changed");
        require(asset.balanceOf(address(desk)) == 0, "desk balance changed");
        require(relay.cycleCount() == 0, "cycle counter changed");
        require(desk.touches() == 0, "desk state changed");
    }
}
