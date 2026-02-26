// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { console2 } from "forge-std/src/console2.sol";

import { EmissionsAutomationAdapter } from "contracts/EmissionsAutomationAdapter.sol";
import { SetupScript } from "script/SetupScript.s.sol";

/*
LOCAL
forge script script/EmissionsAutomationAdapterDeploy.s.sol:EmissionsAutomationAdapterDeploy \
--optimizer-runs 10000 \
--rpc-url anvil \
--broadcast \
--slow

TESTNET
forge script script/EmissionsAutomationAdapterDeploy.s.sol:EmissionsAutomationAdapterDeploy \
--optimizer-runs 10000 \
--rpc-url base_sepolia \
--broadcast \
--slow \
--verify \
--verifier etherscan \
--verifier-url "https://api.etherscan.io/v2/api?chainid=84532" \
--chain 84532 \
--etherscan-api-key $ETHERSCAN_API_KEY

MAINNET
forge script script/EmissionsAutomationAdapterDeploy.s.sol:EmissionsAutomationAdapterDeploy \
--optimizer-runs 10000 \
--rpc-url base \
--broadcast \
--slow \
--verify \
--verifier etherscan \
--verifier-url "https://api.etherscan.io/v2/api?chainid=8453" \
--chain 8453 \
--etherscan-api-key $ETHERSCAN_API_KEY
*/

contract EmissionsAutomationAdapterDeploy is SetupScript {
    error EmissionsAutomationAdapterDeploymentMismatch();

    /* =================================================== */
    /*                   Config Constants                  */
    /* =================================================== */

    /// @dev Deployed adapter contract
    EmissionsAutomationAdapter public emissionsAutomationAdapter;

    /// @notice Address of the BaseEmissionsController contract
    address public BASE_EMISSIONS_CONTROLLER;

    function setUp() public override {
        super.setUp();

        if (block.chainid == NETWORK_ANVIL) {
            BASE_EMISSIONS_CONTROLLER = vm.envAddress("ANVIL_BASE_EMISSIONS_CONTROLLER");
        } else if (block.chainid == NETWORK_BASE_SEPOLIA) {
            BASE_EMISSIONS_CONTROLLER = vm.envAddress("BASE_SEPOLIA_BASE_EMISSIONS_CONTROLLER");
        } else if (block.chainid == NETWORK_BASE) {
            BASE_EMISSIONS_CONTROLLER = vm.envAddress("BASE_MAINNET_BASE_EMISSIONS_CONTROLLER");
        } else {
            revert("Unsupported chain for EmissionsAutomationAdapter deployment");
        }
    }

    function run() public broadcast {
        console2.log("");
        console2.log("DEPLOYMENTS: =+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+");

        _deploy();

        console2.log("");
        console2.log("DEPLOYMENT COMPLETE: =+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+");
        contractInfo("EmissionsAutomationAdapter", address(emissionsAutomationAdapter));
    }

    /* =================================================== */
    /*                   INTERNAL DEPLOY                   */
    /* =================================================== */

    function _deploy() internal {
        emissionsAutomationAdapter = new EmissionsAutomationAdapter(ADMIN, BASE_EMISSIONS_CONTROLLER);
        _verifyDeployment(emissionsAutomationAdapter);
        info("EmissionsAutomationAdapter", address(emissionsAutomationAdapter));
    }

    function _verifyDeployment(EmissionsAutomationAdapter deployedAdapter) internal view {
        if (address(deployedAdapter.baseEmissionsController()) != BASE_EMISSIONS_CONTROLLER) {
            revert EmissionsAutomationAdapterDeploymentMismatch();
        }
        if (!deployedAdapter.hasRole(deployedAdapter.DEFAULT_ADMIN_ROLE(), ADMIN)) {
            revert EmissionsAutomationAdapterDeploymentMismatch();
        }
    }
}
