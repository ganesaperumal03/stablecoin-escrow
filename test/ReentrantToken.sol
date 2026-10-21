// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/IERC20.sol";
import "../src/Escrow.sol";

/// @notice A MALICIOUS token used only in tests. During `transfer`, it tries to
///         re-enter the escrow's `release()`. A correct escrow (CEI + nonReentrant)
///         must make this re-entry revert, so no double payout is possible.
contract ReentrantToken is IERC20 {
    string public name = "Evil";
    string public symbol = "EVIL";
    uint8 public constant decimals = 6;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    Escrow public target;
    bool public attacking;
    bool public reentered;          // test can read this to confirm the attempt happened

    function setTarget(Escrow t) external { target = t; }
    function startAttack() external { attacking = true; }

    function mint(address to, uint256 v) external {
        balanceOf[to] += v;
        totalSupply += v;
        emit Transfer(address(0), to, v);
    }

    function approve(address s, uint256 v) external returns (bool) {
        allowance[msg.sender][s] = v;
        emit Approval(msg.sender, s, v);
        return true;
    }

    function transferFrom(address f, address t, uint256 v) external returns (bool) {
        uint256 a = allowance[f][msg.sender];
        require(a >= v, "allowance");
        if (a != type(uint256).max) allowance[f][msg.sender] = a - v;
        balanceOf[f] -= v;
        balanceOf[t] += v;
        emit Transfer(f, t, v);
        return true;
    }

    function transfer(address t, uint256 v) external returns (bool) {
        // The attack: while the escrow is paying out, call release() again.
        if (attacking && address(target) != address(0)) {
            attacking = false;      // attempt only once
            reentered = true;
            target.release();       // should REVERT because of nonReentrant / wrong status
        }
        balanceOf[msg.sender] -= v;
        balanceOf[t] += v;
        emit Transfer(msg.sender, t, v);
        return true;
    }
}
