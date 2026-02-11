// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { console2 } from "forge-std/src/console2.sol";
import { Script } from "forge-std/src/Script.sol";

abstract contract SetupScript is Script {
    /// @dev The address of the transaction broadcaster.
    address internal broadcaster;

    /* =================================================== */
    /*                   Config Constants                  */
    /* =================================================== */

    uint256 public constant NETWORK_BASE = 8453;
    uint256 public constant NETWORK_BASE_SEPOLIA = 84_532;
    uint256 public constant NETWORK_INTUITION = 1155;
    uint256 public constant NETWORK_INTUITION_SEPOLIA = 13_579;
    uint256 public constant NETWORK_ANVIL = 31_337;

    /* =================================================== */
    /*                  Network Specific                   */
    /* =================================================== */

    // Global Config
    address internal ADMIN;
    address internal TRUST_TOKEN;

    /* =================================================== */
    /*                  Network Agnostic                   */
    /* =================================================== */

    /// @dev deterministic address of the EntryPoint contract on all chains (v0.8.0)
    address internal constant ENTRY_POINT = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;

    constructor() {
        if (block.chainid == NETWORK_BASE) {
            uint256 deployerKey = vm.envUint("DEPLOYER_MAINNET");
            broadcaster = vm.rememberKey(deployerKey);
        } else if (block.chainid == NETWORK_INTUITION) {
            uint256 deployerKey = vm.envUint("DEPLOYER_MAINNET");
            broadcaster = vm.rememberKey(deployerKey);
        } else if (block.chainid == NETWORK_BASE_SEPOLIA) {
            uint256 deployerKey = vm.envUint("DEPLOYER_TESTNET");
            broadcaster = vm.rememberKey(deployerKey);
        } else if (block.chainid == NETWORK_INTUITION_SEPOLIA) {
            uint256 deployerKey = vm.envUint("DEPLOYER_TESTNET");
            broadcaster = vm.rememberKey(deployerKey);
        } else if (block.chainid == NETWORK_ANVIL) {
            uint256 deployerKey = vm.envUint("DEPLOYER_LOCAL");
            broadcaster = vm.rememberKey(deployerKey);
        } else {
            revert("Unsupported chain for broadcasting");
        }
    }

    modifier broadcast() {
        vm.startBroadcast(broadcaster);
        console2.log("Broadcasting from:", broadcaster);
        _;
        vm.stopBroadcast();
    }

    function setUp() public virtual {
        console2.log("NETWORK: =+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+");
        info("ChainID:", block.chainid);
        info("Broadcasting:", broadcaster);

        if (block.chainid == NETWORK_BASE_SEPOLIA) {
            TRUST_TOKEN = 0xA54b4E6e356b963Ee00d1C947f478d9194a1a210;
            ADMIN = vm.envAddress("BASE_SEPOLIA_ADMIN_ADDRESS");
        } else if (block.chainid == NETWORK_INTUITION_SEPOLIA) {
            TRUST_TOKEN = 0xDE80b6EE63f7D809427CA350e30093F436A0fe35; // Wrapped Trust
            ADMIN = vm.envAddress("INTUITION_SEPOLIA_ADMIN_ADDRESS");
        } else if (block.chainid == NETWORK_BASE) {
            TRUST_TOKEN = 0x6cd905dF2Ed214b22e0d48FF17CD4200C1C6d8A3;
            ADMIN = 0xBc01aB3839bE8933f6B93163d129a823684f4CDF;
        } else if (block.chainid == NETWORK_INTUITION) {
            TRUST_TOKEN = 0x81cFb09cb44f7184Ad934C09F82000701A4bF672;
            ADMIN = 0xbeA18ab4c83a12be25f8AA8A10D8747A07Cdc6eb;
        } else if (block.chainid == NETWORK_ANVIL) {
            ADMIN = vm.envAddress("ANVIL_ADMIN_ADDRESS");
        } else {
            revert("Unsupported chain for broadcasting");
        }

        console2.log("");
        console2.log("CONFIGURATION: =+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+");
        info("Admin Address", ADMIN);
        info("Trust Token", TRUST_TOKEN);
    }

    function info(string memory label, address addr) internal pure {
        console2.log("");
        console2.log(label);
        console2.log("-------------------------------------------------------------------");
        console2.log(addr);
        console2.log("-------------------------------------------------------------------");
    }

    function info(string memory label, bytes32 data) internal pure {
        console2.log("");
        console2.log(label);
        console2.log("-------------------------------------------------------------------");
        console2.logBytes32(data);
        console2.log("-------------------------------------------------------------------");
    }

    function info(string memory label, uint256 data) internal pure {
        console2.log("");
        console2.log(label);
        console2.log("-------------------------------------------------------------------");
        console2.log(data);
        console2.log("-------------------------------------------------------------------");
    }

    function contractInfo(string memory label, address data) internal pure {
        console2.log(label, ":", data);
    }
}
