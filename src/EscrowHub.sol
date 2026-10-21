// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC20.sol";
import "./ReentrancyGuard.sol";

/// @title  EscrowHub — many escrow deals in ONE contract (bonus/scalable version)
/// @notice One deployment holds unlimited independent deals, each with its own id.
///         Any user can create deals; one user can have many deals at once.
contract EscrowHub is ReentrancyGuard {
    enum Status { None, Funded, Released, Refunded, Disputed, Resolved }

    struct Deal {
        address payer;
        address payee;
        address arbiter;
        uint256 amount;
        uint256 deadline;
        Status  status;
    }

    IERC20 public immutable token;          // one stablecoin for all deals
    uint256 public nextDealId = 1;          // 0 stays "none" (Topic 2)
    mapping(uint256 => Deal) public deals;  // id -> deal (Topic 2)

    event DealCreated(uint256 indexed dealId, address indexed payer, address indexed payee, uint256 amount, uint256 deadline);
    event Deposited(uint256 indexed dealId, uint256 amount);
    event Released(uint256 indexed dealId, address indexed payee, uint256 amount);
    event Refunded(uint256 indexed dealId, address indexed payer, uint256 amount);
    event Disputed(uint256 indexed dealId, address indexed by);
    event DisputeResolved(uint256 indexed dealId, address indexed winner, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error NotPayer(address caller);
    error NotArbiter(address caller);
    error NotParty(address caller);
    error WrongStatus(Status expected, Status actual);
    error DeadlineNotReached(uint256 deadline, uint256 nowTime);
    error InvalidWinner(address winner);

    constructor(IERC20 _token) {
        if (address(_token) == address(0)) revert ZeroAddress();
        token = _token;
    }

    /// @notice Anyone can open a deal as the payer. Returns the new deal id.
    function createDeal(address payee, address arbiter, uint256 amount, uint256 deadline)
        external
        returns (uint256 dealId)
    {
        if (payee == address(0) || arbiter == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        dealId = nextDealId;
        nextDealId += 1;
        deals[dealId] = Deal(msg.sender, payee, arbiter, amount, deadline, Status.None);
        emit DealCreated(dealId, msg.sender, payee, amount, deadline);
    }

    function deposit(uint256 dealId) external nonReentrant {
        Deal storage d = deals[dealId];
        if (msg.sender != d.payer) revert NotPayer(msg.sender);
        if (d.status != Status.None) revert WrongStatus(Status.None, d.status);

        d.status = Status.Funded;                                   // EFFECTS
        emit Deposited(dealId, d.amount);
        require(token.transferFrom(d.payer, address(this), d.amount), "transferFrom failed"); // INTERACTIONS
    }

    function release(uint256 dealId) external nonReentrant {
        Deal storage d = deals[dealId];
        if (msg.sender != d.payer) revert NotPayer(msg.sender);
        if (d.status != Status.Funded) revert WrongStatus(Status.Funded, d.status);

        d.status = Status.Released;
        emit Released(dealId, d.payee, d.amount);
        require(token.transfer(d.payee, d.amount), "transfer failed");
    }

    function refund(uint256 dealId) external nonReentrant {
        Deal storage d = deals[dealId];
        if (msg.sender != d.payer) revert NotPayer(msg.sender);
        if (d.status != Status.Funded) revert WrongStatus(Status.Funded, d.status);
        if (block.timestamp < d.deadline) revert DeadlineNotReached(d.deadline, block.timestamp);

        d.status = Status.Refunded;
        emit Refunded(dealId, d.payer, d.amount);
        require(token.transfer(d.payer, d.amount), "transfer failed");
    }

    function dispute(uint256 dealId) external {
        Deal storage d = deals[dealId];
        if (d.status != Status.Funded) revert WrongStatus(Status.Funded, d.status);
        if (msg.sender != d.payer && msg.sender != d.payee) revert NotParty(msg.sender);

        d.status = Status.Disputed;
        emit Disputed(dealId, msg.sender);
    }

    function resolveDispute(uint256 dealId, address winner) external nonReentrant {
        Deal storage d = deals[dealId];
        if (msg.sender != d.arbiter) revert NotArbiter(msg.sender);
        if (d.status != Status.Disputed) revert WrongStatus(Status.Disputed, d.status);
        if (winner != d.payer && winner != d.payee) revert InvalidWinner(winner);

        d.status = Status.Resolved;
        emit DisputeResolved(dealId, winner, d.amount);
        require(token.transfer(winner, d.amount), "transfer failed");
    }
}
