// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol"; // Import ReentrancyGuard
import "./FlashLoanReceiver.sol";
import "./OracleBasedLTVController.sol";
import "./StrategyRouter.sol";
import "./IDAOAuthority.sol";

/**
 * @title CombinedLeverageSystem
 * @notice Integrates flash loans, dynamic LTV, strategy routing, and DAO-controlled emergency exit.
 * @dev Inherits functionality from specialized modules. Requires a DAOAuthority contract set during construction.
 *      Includes ReentrancyGuard.
 */
contract CombinedLeverageSystem is
    FlashLoanReceiver,
    OracleBasedLTVController,
    StrategyRouter,
    ReentrancyGuard // Inherit ReentrancyGuard
{
    /**
     * @notice Address of the DAO Authority contract responsible for authorizing emergency exits.
     */
    IDAOAuthority public immutable daoAuthority;

    /**
     * @notice Flag indicating if the system is in an emergency state, halting core operations.
     */
    bool public emergency;

    /**
     * @notice Stores the amount leveraged in the last successful execution.
     */
    uint256 public lastLeveragedAmount;

    /**
     * @notice Emitted when the leverage strategy is successfully executed.
     * @param amount The amount leveraged in the operation.
     */
    event LeverageExecuted(uint256 amount);

    /**
     * @notice Emitted when the emergency exit is triggered.
     * @param caller The authorized address that triggered the exit.
     */
    event EmergencyExitTriggered(address caller);


    /**
     * @notice Constructor sets the DAO Authority contract.
     * @param _daoAuthority Address of the deployed IDAOAuthority implementation.
     */
    constructor(address _daoAuthority) {
        require(
            _daoAuthority != address(0),
            "CombinedLeverageSystem: Invalid DAO authority address"
        );
        // Check if the provided address actually implements the interface (optional but recommended)
        // require(IDAOAuthority(_daoAuthority).supportsInterface(type(IDAOAuthority).interfaceId), "CombinedLeverageSystem: Invalid DAO authority contract type"); // Requires supportsInterface implementation in DAOAuthority
        daoAuthority = IDAOAuthority(_daoAuthority);
    }

    /**
     * @notice Executes the combined leverage strategy.
     * @dev Requires the system not to be in an emergency state. Non-reentrant.
     *      Calls internal functions for flash loan leverage, LTV update, and yield routing.
     * @param _amount The initial amount to leverage.
     * @param _simulatedOracleData Simulated data for LTV adjustment.
     * @param _strategyParams Parameters for the yield routing strategy.
     */
    function executeLeverage(
        uint256 _amount,
        bytes memory _simulatedOracleData,
        bytes memory _strategyParams
    ) external nonReentrant { // Add nonReentrant modifier
        require(!emergency, "CombinedLeverageSystem: Emergency mode active");
        require(_amount > 0, "CombinedLeverageSystem: Amount must be positive"); // Added check

        // 1. Flash Loan Leverage (Simulated)
        flashLoanExecute(_amount); // Assumes this doesn't generate yield directly

        // 2. Dynamic LTV Adjustment (Simulated)
        updateLTV(_simulatedOracleData); // Emits LTVUpdated

        // 3. Yield Routing (Simulated)
        // Assuming some yield was generated *conceptually* by the overall strategy leveraging _amount
        uint256 simulatedYield = _amount / 100; // Example: 1% yield assumption
        if (simulatedYield > 0) {
             autoRouteYield(simulatedYield, _strategyParams); // Emits YieldRouted
        }


        // 4. Update State & Emit Event
        lastLeveragedAmount = _amount;
        emit LeverageExecuted(_amount);
    }

    /**
     * @notice Triggers the emergency exit mechanism. Non-reentrant.
     * @dev Can only be called by an address authorized by the DAO Authority.
     *      Sets the emergency flag to halt `executeLeverage`.
     *      Contains a placeholder for actual position unwinding logic.
     */
    function emergencyExit() external nonReentrant { // Add nonReentrant modifier
        require(
            daoAuthority.isAuthorized(msg.sender),
            "CombinedLeverageSystem: Caller not authorized by DAO"
        );
        // Prevent re-triggering if already in emergency state (optional, depends on desired logic)
        // require(!emergency, "CombinedLeverageSystem: Already in emergency mode");
        emergency = true;

        // Placeholder: Implement logic to unwind all positions
        // - Repay all outstanding debts on Aave
        // - Withdraw all collateral from Aave
        // - Transfer funds to a safe address
        // - Potentially interact with external protocols used in StrategyRouter

        emit EmergencyExitTriggered(msg.sender);
    }
}