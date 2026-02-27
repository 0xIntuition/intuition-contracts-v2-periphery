// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {
    AutomationCompatibleInterface
} from "contracts/interfaces/external/chainlink/AutomationCompatibleInterface.sol";
import { IBaseEmissionsController } from "intuition-contracts-v2/interfaces/IBaseEmissionsController.sol";
import { ICoreEmissionsController } from "intuition-contracts-v2/interfaces/ICoreEmissionsController.sol";

/**
 * @title EmissionsAutomationAdapter
 * @author 0xIntuition
 * @notice A contract that integrates with keepers to automate the minting and bridging of emissions
 */
contract EmissionsAutomationAdapter is AccessControl, ReentrancyGuard, Pausable, AutomationCompatibleInterface {
    /* =================================================== */
    /*                     CONSTANTS                       */
    /* =================================================== */

    /// @notice Role identifier for upkeep operations
    bytes32 public constant UPKEEP_ROLE = keccak256("UPKEEP_ROLE");

    /* =================================================== */
    /*                    IMMUTABLES                       */
    /* =================================================== */

    /// @notice Reference to the BaseEmissionsController contract
    IBaseEmissionsController public immutable baseEmissionsController;

    /* =================================================== */
    /*                      EVENTS                         */
    /* =================================================== */

    /// @notice Emitted when the BaseEmissionsController address is updated
    /// @param newBaseEmissionsController The new BaseEmissionsController address
    event BaseEmissionsControllerSet(address indexed newBaseEmissionsController);

    /// @notice Emitted when upkeep mints and bridges emissions for an epoch
    /// @param epochNumber The epoch number for which upkeep was performed
    event UpkeepPerformed(uint256 indexed epochNumber);

    /* =================================================== */
    /*                      ERRORS                         */
    /* =================================================== */

    /// @notice Error for invalid address inputs
    error EmissionsAutomationAdapter_InvalidAddress();

    /* =================================================== */
    /*                 CONSTRUCTOR                         */
    /* =================================================== */

    /**
     * @notice Constructor for the EmissionsAutomationAdapter
     * @param _admin The address of the admin
     * @param _baseEmissionsController The address of the BaseEmissionsController contract
     */
    constructor(address _admin, address _baseEmissionsController) {
        if (_admin == address(0)) revert EmissionsAutomationAdapter_InvalidAddress();
        if (_baseEmissionsController == address(0)) revert EmissionsAutomationAdapter_InvalidAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        baseEmissionsController = IBaseEmissionsController(_baseEmissionsController);
        emit BaseEmissionsControllerSet(_baseEmissionsController);
    }

    /* =================================================== */
    /*                  ADMIN FUNCTIONS                    */
    /* =================================================== */

    /// @notice Pauses the contract, preventing performUpkeep from executing
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract, allowing performUpkeep to execute
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /* =================================================== */
    /*                 EXTERNAL FUNCTIONS                  */
    /* =================================================== */

    /// @inheritdoc AutomationCompatibleInterface
    function performUpkeep(
        bytes calldata /* performData */
    )
        external
        override
        nonReentrant
        onlyRole(UPKEEP_ROLE)
        whenNotPaused
    {
        _mintAndBridgeCurrentEpochIfNeeded();
    }

    /* =================================================== */
    /*                 VIEW FUNCTIONS                      */
    /* =================================================== */

    /// @inheritdoc AutomationCompatibleInterface
    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        upkeepNeeded = _shouldMint();
    }

    /* =================================================== */
    /*                 INTERNAL FUNCTIONS                  */
    /* =================================================== */

    /// @notice Internal function to mint and bridge emissions for the current epoch if needed
    function _mintAndBridgeCurrentEpochIfNeeded() internal {
        uint256 currentEpoch = _getCurrentEpoch();
        if (baseEmissionsController.getEpochMintedAmount(currentEpoch) != 0) return;

        baseEmissionsController.mintAndBridgeCurrentEpoch();
        emit UpkeepPerformed(currentEpoch);
    }

    /// @notice Internal function to determine if minting is needed for the current epoch
    function _shouldMint() internal view returns (bool) {
        uint256 currentEpoch = _getCurrentEpoch();
        return baseEmissionsController.getEpochMintedAmount(currentEpoch) == 0;
    }

    /// @notice Internal function to get the current epoch number from the BaseEmissionsController
    function _getCurrentEpoch() internal view returns (uint256) {
        return ICoreEmissionsController(address(baseEmissionsController)).getCurrentEpoch();
    }
}
