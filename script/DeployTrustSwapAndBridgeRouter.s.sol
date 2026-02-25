// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { console2 } from "forge-std/src/console2.sol";

import { FinalityState } from "contracts/interfaces/external/metalayer/IMetaERC20Hub.sol";
import { TrustSwapAndBridgeRouter } from "contracts/TrustSwapAndBridgeRouter.sol";
import { SetupScript } from "script/SetupScript.s.sol";

/*
MAINNET (Base)
forge script script/base/DeployTrustSwapAndBridgeRouter.s.sol:DeployTrustSwapAndBridgeRouter \
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

contract DeployTrustSwapAndBridgeRouter is SetupScript {
    error UnsupportedChainId();
    error RouterConfigMismatch();

    /* =================================================== */
    /*                   Config Constants                  */
    /* =================================================== */

    // ===== Base Mainnet MetaERC20Hub for Bridging =====
    address public constant BASE_MAINNET_META_ERC20_HUB = 0xE12aaF1529Ae21899029a9b51cca2F2Bc2cfC421;

    // ===== Aerodrome Slipstream (CL) Addresses on Base =====
    address public constant SLIPSTREAM_SWAP_ROUTER = 0xcbBb8035cAc7D4B3Ca7aBb74cF7BdF900215Ce0D;
    address public constant SLIPSTREAM_FACTORY = 0xaDe65c38CD4849aDBA595a4323a8C7DdfE89716a;
    address public constant SLIPSTREAM_QUOTER = 0x3d4C22254F86f64B7eC90ab8F7aeC1FBFD271c6C;

    // ===== Bridging Configuration =====
    uint32 public constant INTUITION_MAINNET_DOMAIN = 1155;
    uint256 public constant BRIDGE_GAS_LIMIT = 100_000;
    FinalityState public constant BRIDGE_FINALITY_STATE = FinalityState.INSTANT;

    /// @dev Deployed router contract
    TrustSwapAndBridgeRouter public trustSwapAndBridgeRouter;

    function setUp() public override {
        super.setUp();
    }

    function run() public broadcast {
        if (block.chainid != NETWORK_BASE) revert UnsupportedChainId();

        console2.log("");
        console2.log("DEPLOYMENTS: =+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+");

        _deploy();

        console2.log("");
        console2.log("DEPLOYMENT COMPLETE: =+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+");
        contractInfo("TrustSwapAndBridgeRouter", address(trustSwapAndBridgeRouter));
    }

    /* =================================================== */
    /*                   INTERNAL DEPLOY                   */
    /* =================================================== */

    function _deploy() internal {
        trustSwapAndBridgeRouter = new TrustSwapAndBridgeRouter();
        _verifyDeployment(trustSwapAndBridgeRouter);
        info("TrustSwapAndBridgeRouter", address(trustSwapAndBridgeRouter));
    }

    function _verifyDeployment(TrustSwapAndBridgeRouter deployedRouter) internal view {
        if (deployedRouter.slipstreamSwapRouter() != SLIPSTREAM_SWAP_ROUTER) revert RouterConfigMismatch();
        if (address(deployedRouter.slipstreamFactory()) != SLIPSTREAM_FACTORY) revert RouterConfigMismatch();
        if (deployedRouter.slipstreamQuoter() != SLIPSTREAM_QUOTER) revert RouterConfigMismatch();
        if (address(deployedRouter.metaERC20Hub()) != BASE_MAINNET_META_ERC20_HUB) revert RouterConfigMismatch();
        if (deployedRouter.recipientDomain() != INTUITION_MAINNET_DOMAIN) revert RouterConfigMismatch();
        if (deployedRouter.bridgeGasLimit() != BRIDGE_GAS_LIMIT) revert RouterConfigMismatch();
        if (deployedRouter.finalityState() != BRIDGE_FINALITY_STATE) revert RouterConfigMismatch();
    }
}
