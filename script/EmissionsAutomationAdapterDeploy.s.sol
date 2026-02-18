// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { console2 } from "forge-std/src/console2.sol";
import { Script } from "forge-std/src/Script.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { EmissionsAutomationAdapter } from "contracts/EmissionsAutomationAdapter.sol";
import { SetupScript } from "script/SetupScript.s.sol";

/*
LOCAL
forge script script/base/EmissionsAutomationAdapterDeploy.s.sol:EmissionsAutomationAdapterDeploy \
--optimizer-runs 10000 \
--rpc-url anvil \
--broadcast \
--slow

TESTNET
forge script script/base/EmissionsAutomationAdapterDeploy.s.sol:EmissionsAutomationAdapterDeploy \
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
forge script script/base/EmissionsAutomationAdapterDeploy.s.sol:EmissionsAutomationAdapterDeploy \
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
    /* =================================================== */
    /*                   Config Constants                  */
    /* =================================================== */

    // ===== Upgrades TimelockController Address =====
    address public constant UPGRADES_TIMELOCK_CONTROLLER = 0x1E442BbB08c98100b18fa830a88E8A57b5dF9157;

    /// @dev Deployed contracts
    EmissionsAutomationAdapter public emissionsAutomationAdapterImplementation;
    TransparentUpgradeableProxy public emissionsAutomationAdapterProxy;

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
        contractInfo("EmissionsAutomationAdapter Implementation", address(emissionsAutomationAdapterImplementation));
        contractInfo("EmissionsAutomationAdapter Proxy", address(emissionsAutomationAdapterProxy));
    }

    /* =================================================== */
    /*                   INTERNAL DEPLOY                   */
    /* =================================================== */

    function _deploy() internal {
        // Deploy EmissionsAutomationAdapter implementation
        emissionsAutomationAdapterImplementation = new EmissionsAutomationAdapter();
        info("EmissionsAutomationAdapter Implementation", address(emissionsAutomationAdapterImplementation));

        // Prepare initialization data
        bytes memory initData =
            abi.encodeWithSelector(EmissionsAutomationAdapter.initialize.selector, ADMIN, BASE_EMISSIONS_CONTROLLER);

        // Deploy EmissionsAutomationAdapter proxy
        emissionsAutomationAdapterProxy = new TransparentUpgradeableProxy(
            address(emissionsAutomationAdapterImplementation), UPGRADES_TIMELOCK_CONTROLLER, initData
        );
        info("EmissionsAutomationAdapter Proxy", address(emissionsAutomationAdapterProxy));
    }
}
