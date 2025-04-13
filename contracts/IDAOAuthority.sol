// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IDAOAuthority Interface
 * @notice Defines the interface for a DAO-controlled authority contract.
 * @dev This interface is used by systems needing authorization checks, typically for critical functions.
 */
interface IDAOAuthority {
    /**
     * @notice Checks if a given address is authorized by the DAO.
     * @param _caller The address to check for authorization.
     * @return bool True if the address is authorized, false otherwise.
     */
    function isAuthorized(address _caller) external view returns (bool);
}