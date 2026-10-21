// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC20.sol";
import "./ReentrancyGuard.sol";

/// @title  Escrow — a single-deal stablecoin escrow
/// @notice Payer funds the deal; releases to payee, or refunds after a deadline.
///         Either side can raise a dispute, which only the arbiter can resolve.
contract Escrow is ReentrancyGuard {
    // ----- Types -----
    enum Status { None, Funded, Released, Refunded, Disputed, Resolved }

    // ----- Immutable config (set once, never change -> cheaper & safer) -----
    IERC20  public immutable token;      // the stablecoin used for this deal
    address public immutable payer;
    address public immutable payee;
    address public immutable arbiter;
    uint256 public immutable amount;     // exact amount (token units, e.g. 6 decimals)
    uint256 public immutable deadline;   // refund allowed only after this time

    // ----- Mutable state -----
    Status public status;

    // ----- Events (receipts) -----
    event Deposited(address indexed payer, uint256 amount);
    event Released(address indexed payee, uint256 amount);
    event Refunded(address indexed payer, uint256 amount);
    event Disputed(address indexed by);
    event DisputeResolved(address indexed winner, uint256 amount);

    // ----- Custom errors -----
    error ZeroAddress();
    error ZeroAmount();
    error NotPayer(address caller);
    error NotArbiter(address caller);
    error NotParty(address caller);
    error WrongStatus(Status expected, Status actual);
    error DeadlineNotReached(uint256 deadline, uint256 nowTime);
    error InvalidWinner(address winner);

    // ----- Modifiers -----
    modifier onlyPayer() {
        if (msg.sender != payer) revert NotPayer(msg.sender);
        _;
    }
    modifier onlyArbiter() {
        if (msg.sender != arbiter) revert NotArbiter(msg.sender);
        _;
    }
    modifier inStatus(Status expected) {
        if (status != expected) revert WrongStatus(expected, status);
        _;
    }

    // ----- Constructor: set up the deal -----
    constructor(
        IERC20 _token,
        address _payer,
        address _payee,
        address _arbiter,
        uint256 _amount,
        uint256 _deadline
    ) {
        if (address(_token) == address(0) || _payer == address(0)
            || _payee == address(0) || _arbiter == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();

        token = _token;
        payer = _payer;
        payee = _payee;
        arbiter = _arbiter;
        amount = _amount;
        deadline = _deadline;
        // status starts at None (0) until the payer funds it
    }

    /// @notice Payer deposits `amount` of the token into escrow.
    /// @dev    Payer must approve() this contract first (ERC-20 allowance).
    function deposit() external onlyPayer inStatus(Status.None) nonReentrant {
        // EFFECTS first
        status = Status.Funded;
        emit Deposited(payer, amount);
        // INTERACTIONS last: pull the tokens in
        bool ok = token.transferFrom(payer, address(this), amount);
        require(ok, "transferFrom failed");
    }

    /// @notice Payer releases the funds to the payee.
    function release() external onlyPayer inStatus(Status.Funded) nonReentrant {
        status = Status.Released;                    // EFFECTS
        emit Released(payee, amount);
        require(token.transfer(payee, amount), "transfer failed");  // INTERACTIONS
    }

    /// @notice Payer reclaims the funds, but only after the deadline.
    function refund() external onlyPayer inStatus(Status.Funded) nonReentrant {
        if (block.timestamp < deadline) revert DeadlineNotReached(deadline, block.timestamp);
        status = Status.Refunded;                    // EFFECTS
        emit Refunded(payer, amount);
        require(token.transfer(payer, amount), "transfer failed");  // INTERACTIONS
    }

    /// @notice Either the payer or the payee can raise a dispute while funded.
    function dispute() external inStatus(Status.Funded) {
        if (msg.sender != payer && msg.sender != payee) revert NotParty(msg.sender);
        status = Status.Disputed;
        emit Disputed(msg.sender);
    }

    /// @notice The arbiter decides who gets the money.
    function resolveDispute(address winner)
        external
        onlyArbiter
        inStatus(Status.Disputed)
        nonReentrant
    {
        if (winner != payer && winner != payee) revert InvalidWinner(winner);
        status = Status.Resolved;                    // EFFECTS
        emit DisputeResolved(winner, amount);
        require(token.transfer(winner, amount), "transfer failed");  // INTERACTIONS
    }
}
