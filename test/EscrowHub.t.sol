// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EscrowHub.sol";
import "../src/MockERC20.sol";

/// @notice Tests for the bonus multi-deal contract (5 tests).
contract EscrowHubTest is Test {
    MockERC20 token;
    EscrowHub hub;

    address alice   = makeAddr("alice");
    address carol   = makeAddr("carol");
    address bob     = makeAddr("bob");      // payee
    address arbiter = makeAddr("arbiter");

    function setUp() public {
        token = new MockERC20("Test USD", "tUSD");
        hub = new EscrowHub(token);
        token.mint(alice, 1_000e6);
        token.mint(carol, 1_000e6);
    }

    function _createAndFund(address payer, uint256 amount) internal returns (uint256 id) {
        vm.startPrank(payer);
        id = hub.createDeal(bob, arbiter, amount, block.timestamp + 7 days);
        token.approve(address(hub), amount);
        hub.deposit(id);
        vm.stopPrank();
    }

    function _status(uint256 id) internal view returns (EscrowHub.Status s) {
        (, , , , , s) = hub.deals(id);
    }

    function test_DealIdsIncrement() public {
        vm.prank(alice);
        uint256 a = hub.createDeal(bob, arbiter, 1e6, block.timestamp + 1 days);
        vm.prank(carol);
        uint256 b = hub.createDeal(bob, arbiter, 1e6, block.timestamp + 1 days);
        assertEq(a, 1);
        assertEq(b, 2);
    }

    function test_SameUserManyDeals_AreIndependent() public {
        uint256 d1 = _createAndFund(alice, 100e6);
        uint256 d2 = _createAndFund(alice, 50e6);

        vm.prank(alice);
        hub.release(d1);
        vm.prank(bob);
        hub.dispute(d2);

        assertEq(uint(_status(d1)), uint(EscrowHub.Status.Released));
        assertEq(uint(_status(d2)), uint(EscrowHub.Status.Disputed));
        assertEq(token.balanceOf(bob), 100e6);
    }

    function test_HubHoldsSumOfFundedDeals() public {
        _createAndFund(alice, 100e6);
        _createAndFund(carol, 200e6);
        assertEq(token.balanceOf(address(hub)), 300e6);
    }

    function test_RevertWhen_OtherUserReleasesYourDeal() public {
        uint256 d = _createAndFund(alice, 100e6);
        vm.expectRevert(abi.encodeWithSelector(EscrowHub.NotPayer.selector, carol));
        vm.prank(carol);
        hub.release(d);
    }

    function test_RevertWhen_ReleasingUnknownDeal() public {
        vm.expectRevert(abi.encodeWithSelector(EscrowHub.NotPayer.selector, alice));
        vm.prank(alice);
        hub.release(999);       // blank deal: payer is address(0), so NotPayer
    }
}
