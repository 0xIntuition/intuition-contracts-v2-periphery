// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

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
contract EmissionsAutomationAdapter is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AutomationCompatibleInterface
{
    /* =================================================== */
    /*                     CONSTANTS                       */
    /* =================================================== */

    /// @notice Role identifier for upkeep operations
    bytes32 public constant UPKEEP_ROLE = keccak256("UPKEEP_ROLE");

    /* =================================================== */
    /*                  STATE VARIABLES                    */
    /* =================================================== */

    /// @notice Reference to the BaseEmissionsController contract
    IBaseEmissionsController public baseEmissionsController;

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /* =================================================== */
    /*                    INITIALIZER                      */
    /* =================================================== */

    /**
     * @notice Initializes the EmissionsAutomationAdapter
     * @param _admin The address of the admin
     * @param _baseEmissionsController The address of the BaseEmissionsController contract
     */
    function initialize(address _admin, address _baseEmissionsController) external initializer {
        if (_admin == address(0)) revert EmissionsAutomationAdapter_InvalidAddress();
        if (_baseEmissionsController == address(0)) revert EmissionsAutomationAdapter_InvalidAddress();

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        baseEmissionsController = IBaseEmissionsController(_baseEmissionsController);
        emit BaseEmissionsControllerSet(_baseEmissionsController);
    }

    /* =================================================== */
    /*                  ADMIN FUNCTIONS                    */
    /* =================================================== */

    /// @notice Updates the BaseEmissionsController contract address
    /// @param _controller The new BaseEmissionsController address
    function setBaseEmissionsController(address _controller) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_controller == address(0)) revert EmissionsAutomationAdapter_InvalidAddress();
        baseEmissionsController = IBaseEmissionsController(_controller);
        emit BaseEmissionsControllerSet(_controller);
    }

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
        uint256 currentEpoch = ICoreEmissionsController(address(baseEmissionsController)).getCurrentEpoch();
        if (baseEmissionsController.getEpochMintedAmount(currentEpoch) != 0) return;

        baseEmissionsController.mintAndBridgeCurrentEpoch();
        emit UpkeepPerformed(currentEpoch);
    }

    /// @notice Internal function to determine if minting is needed for the current epoch
    function _shouldMint() internal view returns (bool) {
        uint256 currentEpoch = ICoreEmissionsController(address(baseEmissionsController)).getCurrentEpoch();
        return baseEmissionsController.getEpochMintedAmount(currentEpoch) == 0;
    }
}
