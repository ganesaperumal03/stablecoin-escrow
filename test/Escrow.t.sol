// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Escrow.sol";
import "../src/MockERC20.sol";
import "./ReentrantToken.sol";

/// @title  Full test suite for Escrow.sol (18 tests)
/// @notice Covers happy paths, permissions, wrong states, timing, events,
///         fuzz tests, and a real reentrancy attack.
contract EscrowTest is Test {
    MockERC20 token;
    Escrow escrow;

    address payer    = makeAddr("payer");
    address payee    = makeAddr("payee");
    address arbiter  = makeAddr("arbiter");
    address stranger = makeAddr("stranger");

    uint256 constant AMOUNT = 100e6;          // 100 tUSD (6 decimals)
    uint256 deadline;

    event Released(address indexed payee, uint256 amount);

    function setUp() public {
        token = new MockERC20("Test USD", "tUSD");
        deadline = block.timestamp + 7 days;
        escrow = new Escrow(token, payer, payee, arbiter, AMOUNT, deadline);

        token.mint(payer, 1_000e6);
        vm.prank(payer);
        token.approve(address(escrow), AMOUNT);
    }

    function _fund() internal {
        vm.prank(payer);
        escrow.deposit();
    }

    // ---------- 1-4: Happy paths ----------
    function test_Deposit_SetsFundedAndHoldsTokens() public {
        _fund();
        assertEq(uint(escrow.status()), uint(Escrow.Status.Funded));
        assertEq(token.balanceOf(address(escrow)), AMOUNT);
    }

    function test_Release_PaysPayee() public {
        _fund();
        vm.prank(payer);
        escrow.release();
        assertEq(uint(escrow.status()), uint(Escrow.Status.Released));
        assertEq(token.balanceOf(payee), AMOUNT);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function test_Refund_AfterDeadline_PaysPayerBack() public {
        _fund();
        uint256 beforeBal = token.balanceOf(payer);
        vm.warp(deadline + 1);
        vm.prank(payer);
        escrow.refund();
        assertEq(uint(escrow.status()), uint(Escrow.Status.Refunded));
        assertEq(token.balanceOf(payer), beforeBal + AMOUNT);
    }

    function test_Dispute_ThenArbiterResolvesForPayee() public {
        _fund();
        vm.prank(payee);
        escrow.dispute();
        assertEq(uint(escrow.status()), uint(Escrow.Status.Disputed));
        vm.prank(arbiter);
        escrow.resolveDispute(payee);
        assertEq(uint(escrow.status()), uint(Escrow.Status.Resolved));
        assertEq(token.balanceOf(payee), AMOUNT);
    }

    // ---------- 5-9: Permission checks ----------
    function test_RevertWhen_StrangerDeposits() public {
        vm.expectRevert(abi.encodeWithSelector(Escrow.NotPayer.selector, stranger));
        vm.prank(stranger);
        escrow.deposit();
    }

    function test_RevertWhen_PayeeReleases() public {
        _fund();
        vm.expectRevert(abi.encodeWithSelector(Escrow.NotPayer.selector, payee));
        vm.prank(payee);
        escrow.release();
    }

    function test_RevertWhen_StrangerRefunds() public {
        _fund();
        vm.warp(deadline + 1);
        vm.expectRevert(abi.encodeWithSelector(Escrow.NotPayer.selector, stranger));
        vm.prank(stranger);
        escrow.refund();
    }

    function test_RevertWhen_NonArbiterResolves() public {
        _fund();
        vm.prank(payer);
        escrow.dispute();
        vm.expectRevert(abi.encodeWithSelector(Escrow.NotArbiter.selector, payer));
        vm.prank(payer);
        escrow.resolveDispute(payer);
    }

    function test_RevertWhen_StrangerDisputes() public {
        _fund();
        vm.expectRevert(abi.encodeWithSelector(Escrow.NotParty.selector, stranger));
        vm.prank(stranger);
        escrow.dispute();
    }

    // ---------- 10-13: Wrong state / timing ----------
    function test_RevertWhen_ReleaseBeforeDeposit() public {
        vm.expectRevert(
            abi.encodeWithSelector(Escrow.WrongStatus.selector, Escrow.Status.Funded, Escrow.Status.None)
        );
        vm.prank(payer);
        escrow.release();
    }

    function test_RevertWhen_ReleaseTwice() public {
        _fund();
        vm.prank(payer);
        escrow.release();
        vm.expectRevert(
            abi.encodeWithSelector(Escrow.WrongStatus.selector, Escrow.Status.Funded, Escrow.Status.Released)
        );
        vm.prank(payer);
        escrow.release();
    }

    function test_RevertWhen_RefundBeforeDeadline() public {
        _fund();
        vm.expectRevert(
            abi.encodeWithSelector(Escrow.DeadlineNotReached.selector, deadline, block.timestamp)
        );
        vm.prank(payer);
        escrow.refund();
    }

    function test_RevertWhen_ResolveToInvalidWinner() public {
        _fund();
        vm.prank(payer);
        escrow.dispute();
        vm.expectRevert(abi.encodeWithSelector(Escrow.InvalidWinner.selector, stranger));
        vm.prank(arbiter);
        escrow.resolveDispute(stranger);
    }

    // ---------- 14: Constructor validation ----------
    function test_RevertWhen_ConstructorZeroAmount() public {
        vm.expectRevert(Escrow.ZeroAmount.selector);
        new Escrow(token, payer, payee, arbiter, 0, deadline);
    }

    // ---------- 15: Events ----------
    function test_Release_EmitsEvent() public {
        _fund();
        vm.expectEmit(true, false, false, true);
        emit Released(payee, AMOUNT);
        vm.prank(payer);
        escrow.release();
    }

    // ---------- 16-17: Fuzz tests ----------
    function testFuzz_ReleasePaysExactAmount(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e6);
        MockERC20 t = new MockERC20("Test USD", "tUSD");
        Escrow e = new Escrow(t, payer, payee, arbiter, amount, block.timestamp + 1 days);
        t.mint(payer, amount);
        vm.startPrank(payer);
        t.approve(address(e), amount);
        e.deposit();
        e.release();
        vm.stopPrank();
        assertEq(t.balanceOf(payee), amount);
    }

    function testFuzz_OnlyPayerCanRelease(address caller) public {
        vm.assume(caller != payer);
        _fund();
        vm.expectRevert(abi.encodeWithSelector(Escrow.NotPayer.selector, caller));
        vm.prank(caller);
        escrow.release();
    }

    // ---------- 18: Reentrancy attack ----------
    function test_ReentrancyAttack_IsBlocked() public {
        ReentrantToken evil = new ReentrantToken();
        Escrow e = new Escrow(evil, payer, payee, arbiter, AMOUNT, block.timestamp + 1 days);
        evil.mint(payer, AMOUNT);
        vm.prank(payer);
        evil.approve(address(e), AMOUNT);
        vm.prank(payer);
        e.deposit();

        evil.setTarget(e);
        evil.startAttack();

        vm.expectRevert();
        vm.prank(payer);
        e.release();

        assertEq(uint(e.status()), uint(Escrow.Status.Funded));
        assertEq(evil.balanceOf(payee), 0);
    }
}
