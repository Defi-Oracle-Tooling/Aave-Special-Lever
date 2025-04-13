# Combined Leverage System

This project implements an advanced Aave v3 Toggle-Optimized Leverage system that integrates:

-  **Flash Loan-Enabled Recursive Leverage:** Uses flash loans to atomically execute recursive leverage loops.
-  **Dynamic LTV Rotation:** Adjusts the LTV in real time using simulated oracle data.
-  **eMode Layering & Asset Isolation:** Increases borrowing capacity by grouping correlated assets.
-  **Yield & Strategy Routing:** Auto-toggles collateral positions and routes yields to external protocols.
-  **DAO Safety & Emergency Unwind:** Provides an emergency exit mechanism controlled by a DAO authority.

## System Architecture

The system is built around the central `CombinedLeverageSystem.sol` contract, which inherits functionality from several specialized modules:

-  **`FlashLoanReceiver.sol`**: Handles the logic for initiating and (in a real implementation) repaying flash loans, enabling the core recursive leverage loop.
-  **`OracleBasedLTVController.sol`**: Manages the Loan-to-Value (LTV) ratio dynamically based on external oracle data (simulated here), adjusting risk exposure.
-  **`StrategyRouter.sol`**: Routes generated yield to external protocols or strategies and potentially auto-toggles collateral assets based on predefined conditions (simulated here).
-  **`IDAOAuthority.sol`**: Defines an interface for DAO-controlled authorization, specifically used for triggering the emergency exit mechanism. A simple implementation (`DAOAuthority.sol`) is provided.

## Detailed Workflow: `executeLeverage`

The core `executeLeverage` function orchestrates the combined strategy:

1. **Pre-checks:** Ensures the system is not in emergency mode.
2. **Flash Loan Leverage:** Calls `flashLoanExecute` (from `FlashLoanReceiver`) to simulate the atomic flash loan, swap, deposit, borrow, and repayment cycle needed for recursive leveraging.
3. **Dynamic LTV Adjustment:** Calls `updateLTV` (from `OracleBasedLTVController`) to adjust the system's LTV based on simulated market conditions or oracle data. This step implicitly handles eMode benefits if configured for correlated assets within the LTV logic.
4. **Yield Routing:** Calls `autoRouteYield` (from `StrategyRouter`) to simulate routing any generated yield to external DeFi protocols or strategies.
5. **State Update:** Records the leveraged amount.
6. **Event Emission:** Logs the successful execution.

## Emergency Exit

The `emergencyExit` function provides a safety mechanism:

-  **Authorization:** Can only be called by an address authorized by the `DAOAuthority` contract.
-  **State Change:** Sets an `emergency` flag to halt core operations like `executeLeverage`.
-  **Unwind Logic:** (Placeholder) In a full implementation, this function would contain logic to unwind all positions: repay debts, withdraw collateral, and secure funds.
-  **Event Emission:** Logs the activation of the emergency exit.

## Customization and Production Considerations

-  **Real Integrations:** Replace simulated functions (`flashLoanExecute`, `updateLTV`, `autoRouteYield`) with actual calls to Aave V3 contracts, Chainlink oracles, and target yield protocols (e.g., Curve, Pendle).
-  **Security:** Implement robust security measures, including access controls, input validation, reentrancy guards, and thorough audits.
-  **Gas Optimization:** Optimize contract interactions to minimize gas costs, especially within the recursive loop.
-  **Error Handling:** Add detailed error handling and revert messages.
-  **Oracle Reliability:** Ensure the chosen oracle is reliable and secure. Consider fallback mechanisms.
-  **DAO Authority:** Implement a robust and secure DAO governance mechanism for the `DAOAuthority`.

## Folder Structure

```bash
combined-leverage-system/
├── contracts/
│   ├── CombinedLeverageSystem.sol
│   ├── FlashLoanReceiver.sol
│   ├── OracleBasedLTVController.sol
│   ├── StrategyRouter.sol
│   └── IDAOAuthority.sol
├── test/
│   └── CombinedLeverageSystem.test.js
├── hardhat.config.js
├── package.json
└── README.md
```

## How to Run

1. **Install Dependencies:**

   ```bash
   npm install
   ```

2. **Run Tests:**
   ```bash
   npx hardhat test
   ```

3. **Deployment:**
   Deploy the contracts to your chosen network following Hardhat deployment processes.

## Review & Customize
*   **Review & Customize:**
    The provided Solidity contracts are a simplified demonstration. For production use, integrate proper external protocol calls (such as Aave flash loan calls and Chainlink oracle feeds) and add security measures.
*   **Deploy & Test:**
    Use Hardhat to deploy these contracts to your testnet/mainnet. Run the tests with `npx hardhat test` to ensure all functionalities work as expected.
*   **Documentation & Playbook:**
    Use this README and in-code comments as a playbook for your team to understand the implementation details and underlying rationale for each module.