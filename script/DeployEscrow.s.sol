// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/Escrow.sol";
import "../src/MockERC20.sol";

/// @notice Deploys a test token + an Escrow to a testnet.
/// Run (dry):  forge script script/DeployEscrow.s.sol --rpc-url base_sepolia
/// Run (live): forge script script/DeployEscrow.s.sol --rpc-url base_sepolia \
///                 --private-key $PRIVATE_KEY --broadcast --verify
contract DeployEscrow is Script {
    function run() external {
        // ---- Read config from environment variables (never hard-code secrets!) ----
        // The deployer becomes the payer here (change to suit your demo).
        address payee   = vm.envOr("PAYEE",   address(0xBEEF));
        address arbiter = vm.envOr("ARBITER", address(0xA111));
        uint256 amount  = vm.envOr("AMOUNT",  uint256(100e6));        // 100 tokens
        uint256 window  = vm.envOr("WINDOW",  uint256(7 days));

        vm.startBroadcast();                       // 🔴 everything below is a REAL tx

        // 1) Deploy a test stablecoin (6 decimals) and mint some to the deployer
        MockERC20 token = new MockERC20("Test USD", "tUSD");
        token.mint(msg.sender, 1_000_000e6);

        // 2) Deploy the escrow: deployer is the payer
        Escrow escrow = new Escrow(
            token,
            msg.sender,                            // payer = deployer
            payee,
            arbiter,
            amount,
            block.timestamp + window
        );

        vm.stopBroadcast();

        // Printed to your console after the run:
        console.log("Test token deployed at:", address(token));
        console.log("Escrow deployed at:    ", address(escrow));
        console.log("Payer (deployer):      ", msg.sender);
    }
}
