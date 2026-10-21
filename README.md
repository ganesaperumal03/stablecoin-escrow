# 🤝 stablecoin-escrow

**A stablecoin escrow smart contract in Solidity, built and tested with Foundry.**

A payer deposits a stablecoin into the contract. The payer can **release** it to the payee, or **refund** it after a deadline. Either side can raise a **dispute**, which only a neutral **arbiter** can resolve.

> 📍 **Deployed on Base Sepolia:** `0x_YOUR_ESCROW_ADDRESS_HERE`
> 🔍 Verified source: `https://sepolia.basescan.org/address/0x_YOUR_ESCROW_ADDRESS_HERE#code`

---

## 🚦 How a deal works

```
                 deposit (payer)
   None ─────────────────────────► Funded
                                     │
       ┌─────────────────────────────┼──────────────────────────────┐
       │ release (payer)             │ refund (payer,               │ dispute (payer or payee)
       ▼                             │  only after deadline)        ▼
   Released ✅                        ▼                           Disputed
                                  Refunded ↩️                          │ resolveDispute (arbiter)
                                                                      ▼
                                                                  Resolved ⚖️
```

| Action | Who | Required state | Extra rule | New state |
|---|---|---|---|---|
| `deposit()` | payer | None | payer approved the token first | Funded |
| `release()` | payer | Funded | — | Released |
| `refund()` | payer | Funded | `block.timestamp >= deadline` | Refunded |
| `dispute()` | payer or payee | Funded | — | Disputed |
| `resolveDispute(winner)` | arbiter | Disputed | winner is payer or payee | Resolved |

Released, Refunded and Resolved are **final**: no further action is possible, so funds can never be paid out twice.

---

## 📦 Contracts

| File | Purpose |
|---|---|
| [`src/Escrow.sol`](src/Escrow.sol) | **Main contract.** One deal per deployment; deal terms are `immutable`. |
| [`src/EscrowHub.sol`](src/EscrowHub.sol) | **Bonus.** Many independent deals in one contract (`mapping(uint256 => Deal)`), so many users, and one user with many deals, can use a single deployment. |
| `src/MockERC20.sol` | 6-decimal test stablecoin used in tests and the testnet demo |
| `src/IERC20.sol`, `src/ReentrancyGuard.sol` | Minimal local copies so the project compiles with no extra installs (see *Improvements*) |
| `test/ReentrantToken.sol` | **Malicious token** that tries to re-enter `release()`, used to attack the escrow in tests |

---

## 🛡️ Security design

- **Checks → Effects → Interactions:** every function that moves money updates `status` **before** calling the token
- **`nonReentrant`** on every money-moving function (second line of defence)
- **State machine** (`enum Status`) blocks double release, release after refund, etc.
- **`immutable`** deal terms (payer, payee, arbiter, amount, deadline) cannot be changed after deployment
- **Custom errors** with context, e.g. `NotPayer(caller)`, `WrongStatus(expected, actual)`, `DeadlineNotReached(deadline, now)`
- **Input validation:** no zero addresses, no zero amount, dispute winner must be payer or payee
- **Events** for every state change: `Deposited`, `Released`, `Refunded`, `Disputed`, `DisputeResolved`

---

## 🧪 Tests (23 total)

```bash
forge test -vvv
```

**`test/Escrow.t.sol` — 18 tests for the main contract**

| Group | Tests |
|---|---|
| Happy paths | deposit, release, refund after deadline, dispute resolved by arbiter |
| Permissions | stranger can't deposit, payee can't release, stranger can't refund, non-arbiter can't resolve, stranger can't dispute |
| State & timing | can't release before deposit, **can't release twice**, can't refund before deadline, winner must be a party |
| Validation & events | zero amount rejected, `Released` event emitted with correct data |
| 🎲 Fuzz | `testFuzz_ReleasePaysExactAmount(uint256)` — payee always receives exactly the amount; `testFuzz_OnlyPayerCanRelease(address)` — any non-payer reverts |
| 🔐 Reentrancy | `test_ReentrancyAttack_IsBlocked` — a malicious token re-enters `release()` during payout; the call reverts, status stays `Funded`, nothing is paid twice |

**`test/EscrowHub.t.sol` — 5 tests for the bonus contract:** deal IDs increment, one user's deals are independent, the hub holds the sum of funded deals, another user can't release your deal, unknown deal IDs are rejected.

Cheatcodes used: `vm.prank`, `vm.startPrank`, `vm.warp`, `vm.expectRevert` (with exact error selectors and arguments), `vm.expectEmit`, `vm.assume`, `bound`.

---

## 🚀 Quick start

```bash
git clone https://github.com/<your-username>/stablecoin-escrow.git
cd stablecoin-escrow
forge install foundry-rs/forge-std
forge build
forge test
```

### Deploy to Base Sepolia

```bash
cp .env.example .env          # add PRIVATE_KEY (TEST wallet only) and BASESCAN_API_KEY
source .env

# 1) dry run (simulation only)
forge script script/DeployEscrow.s.sol --rpc-url base_sepolia

# 2) deploy + verify
forge script script/DeployEscrow.s.sol --rpc-url base_sepolia \
  --private-key $PRIVATE_KEY --broadcast --verify
```

The script deploys a test token (`tUSD`), mints some to the deployer, and deploys an `Escrow` where the deployer is the payer. Optional settings via env vars: `PAYEE`, `ARBITER`, `AMOUNT`, `WINDOW`.

### Try it

```bash
cast call <ESCROW_ADDRESS> "status()(uint8)" --rpc-url base_sepolia     # 0=None, 1=Funded, ...
cast call <ESCROW_ADDRESS> "deadline()(uint256)" --rpc-url base_sepolia
```

---

## 🗂️ Project structure

```
stablecoin-escrow/
├── src/
│   ├── Escrow.sol            # main single-deal escrow
│   ├── EscrowHub.sol         # bonus multi-deal escrow
│   ├── MockERC20.sol         # test stablecoin
│   ├── IERC20.sol
│   └── ReentrancyGuard.sol
├── test/
│   ├── Escrow.t.sol          # 18 tests
│   ├── EscrowHub.t.sol       # 5 tests
│   └── ReentrantToken.sol    # attacker used in the reentrancy test
├── script/
│   └── DeployEscrow.s.sol
├── foundry.toml
├── .env.example
└── README.md
```

---

## 🚧 Limitations and improvements

- Replace the local `IERC20` / `ReentrancyGuard` with **OpenZeppelin** (`forge install OpenZeppelin/openzeppelin-contracts`) and use **`SafeERC20`** (`safeTransfer`/`safeTransferFrom`) so tokens that don't return `bool` (like USDT on Ethereum) are handled
- The arbiter decides all-or-nothing; a production version could support **split settlements** and an **arbiter fee**
- No dispute deadline: if the arbiter never acts, funds stay locked. A fallback timeout would fix this
- Fee-on-transfer tokens are not supported (the contract assumes it receives exactly `amount`)
- Gasless funding with **EIP-2612 `permit`** or **EIP-3009 `receiveWithAuthorization`** would let payers fund in one step without holding ETH
- Not audited. Testnet use only

---

## 📚 Background

Week 3 of my **AI + Stablecoin Payments** roadmap: Solidity essentials (types, storage/memory/calldata, modifiers, events, custom errors, checks-effects-interactions) and Foundry (unit tests, fuzz tests, cheatcodes, anvil, deploy scripts).

Previous weeks: [`stablecoin-basics`](https://github.com/<your-username>/stablecoin-basics) · [`tx-explainer`](https://github.com/<your-username>/tx-explainer)
