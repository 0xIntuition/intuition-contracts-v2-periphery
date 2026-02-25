// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ICLFactory } from "contracts/interfaces/external/aerodrome/ICLFactory.sol";
import { ICLQuoter } from "contracts/interfaces/external/aerodrome/ICLQuoter.sol";
import { ISlipstreamSwapRouter } from "contracts/interfaces/external/aerodrome/ISlipstreamSwapRouter.sol";
import { FinalityState, IMetaERC20Hub } from "contracts/interfaces/external/metalayer/IMetaERC20Hub.sol";
import { IWETH } from "contracts/interfaces/external/IWETH.sol";
import { ITrustSwapAndBridgeRouter } from "contracts/interfaces/ITrustSwapAndBridgeRouter.sol";

/**
 * @title TrustSwapAndBridgeRouter
 * @author 0xIntuition
 * @notice Minimal router that validates pre-built Slipstream (CL) paths, delegates swaps to the
 *         Slipstream SwapRouter and bridges resulting TRUST to Intuition mainnet via Metalayer.
 */
contract TrustSwapAndBridgeRouter is ITrustSwapAndBridgeRouter, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* =================================================== */
    /*                      CONSTANTS                      */
    /* =================================================== */

    /// @notice Base mainnet TRUST address
    address public constant TRUST_ADDRESS = 0x6cd905dF2Ed214b22e0d48FF17CD4200C1C6d8A3;

    /// @notice Base mainnet WETH address (canonical Base WETH)
    address public constant WETH_ADDRESS = 0x4200000000000000000000000000000000000006;

    /// @notice TRUST token contract on Base
    IERC20 public constant trustToken = IERC20(TRUST_ADDRESS);

    /// @dev Minimum packed path length: 1 hop = 20 (addr) + 3 (tickSpacing) + 20 (addr) = 43 bytes
    uint256 private constant MIN_PATH_LENGTH = 43;

    /// @dev Each additional hop adds 23 bytes (3 tickSpacing + 20 address)
    uint256 private constant HOP_SIZE = 23;

    /// @dev Size of an address in the packed path
    uint256 private constant ADDR_SIZE = 20;

    /// @notice The single allowlisted Slipstream SwapRouter
    address public constant slipstreamSwapRouter = 0xcbBb8035cAc7D4B3Ca7aBb74cF7BdF900215Ce0D;

    /// @notice Slipstream CL Factory for pool existence verification
    ICLFactory public constant slipstreamFactory = ICLFactory(0xaDe65c38CD4849aDBA595a4323a8C7DdfE89716a);

    /// @notice Slipstream CL Quoter for swap quotes
    address public constant slipstreamQuoter = 0x3d4C22254F86f64B7eC90ab8F7aeC1FBFD271c6C;

    /// @notice MetaERC20Hub contract for cross-chain bridging
    IMetaERC20Hub public constant metaERC20Hub = IMetaERC20Hub(0xE12aaF1529Ae21899029a9b51cca2F2Bc2cfC421);

    /// @notice Recipient domain ID for bridging (Intuition mainnet)
    uint32 public constant recipientDomain = 1155;

    /// @notice Gas limit for bridge transactions
    uint256 public constant bridgeGasLimit = 100_000;

    /// @notice Finality state for bridge transactions
    FinalityState public constant finalityState = FinalityState.INSTANT;

    /* =================================================== */
    /*                   SWAP FUNCTIONS                    */
    /* =================================================== */

    /// @inheritdoc ITrustSwapAndBridgeRouter
    function swapAndBridgeWithETH(
        bytes calldata path,
        uint256 minTrustOut,
        address recipient
    )
        external
        payable
        nonReentrant
        returns (uint256 amountOut, bytes32 transferId)
    {
        if (recipient == address(0)) revert TrustSwapAndBridgeRouter_InvalidRecipient();
        if (_extractTokenAtOffset(path, 0) != WETH_ADDRESS) {
            revert TrustSwapAndBridgeRouter_PathDoesNotStartWithWETH();
        }
        if (_extractTokenAtOffset(path, path.length >= ADDR_SIZE ? path.length - ADDR_SIZE : 0) != TRUST_ADDRESS) {
            revert TrustSwapAndBridgeRouter_PathDoesNotEndWithTRUST();
        }

        _validatePoolsExist(path);

        bytes32 recipientAddress = _formatRecipientAddress(recipient);

        uint256 bridgeFee = metaERC20Hub.quoteTransferRemote(recipientDomain, recipientAddress, minTrustOut);
        if (msg.value <= bridgeFee) {
            revert TrustSwapAndBridgeRouter_InsufficientETH();
        }

        uint256 swapEth = msg.value - bridgeFee;

        IWETH(WETH_ADDRESS).deposit{ value: swapEth }();

        IERC20(WETH_ADDRESS).safeIncreaseAllowance(slipstreamSwapRouter, swapEth);

        amountOut = ISlipstreamSwapRouter(slipstreamSwapRouter)
            .exactInput(
                ISlipstreamSwapRouter.ExactInputParams({
                    path: path,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: swapEth,
                    amountOutMinimum: minTrustOut
                })
            );

        transferId = _bridgeTrust(amountOut, recipientAddress, bridgeFee);

        emit SwappedAndBridgedFromETH(msg.sender, swapEth, amountOut, recipientAddress, transferId);
    }

    /// @inheritdoc ITrustSwapAndBridgeRouter
    function swapAndBridgeWithERC20(
        address tokenIn,
        uint256 amountIn,
        bytes calldata path,
        uint256 minTrustOut,
        address recipient
    )
        external
        payable
        nonReentrant
        returns (uint256 amountOut, bytes32 transferId)
    {
        if (amountIn == 0) revert TrustSwapAndBridgeRouter_AmountInZero();
        if (recipient == address(0)) revert TrustSwapAndBridgeRouter_InvalidRecipient();
        if (tokenIn == address(0) || tokenIn == TRUST_ADDRESS) {
            revert TrustSwapAndBridgeRouter_InvalidToken();
        }
        if (_extractTokenAtOffset(path, 0) != tokenIn) {
            revert TrustSwapAndBridgeRouter_PathDoesNotStartWithToken();
        }
        if (_extractTokenAtOffset(path, path.length >= ADDR_SIZE ? path.length - ADDR_SIZE : 0) != TRUST_ADDRESS) {
            revert TrustSwapAndBridgeRouter_PathDoesNotEndWithTRUST();
        }

        _validatePoolsExist(path);

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        bytes32 recipientAddress = _formatRecipientAddress(recipient);

        uint256 bridgeFee = metaERC20Hub.quoteTransferRemote(recipientDomain, recipientAddress, minTrustOut);
        if (msg.value < bridgeFee) {
            revert TrustSwapAndBridgeRouter_InsufficientBridgeFee();
        }

        IERC20(tokenIn).safeIncreaseAllowance(slipstreamSwapRouter, amountIn);

        amountOut = ISlipstreamSwapRouter(slipstreamSwapRouter)
            .exactInput(
                ISlipstreamSwapRouter.ExactInputParams({
                    path: path,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: minTrustOut
                })
            );

        transferId = _bridgeTrust(amountOut, recipientAddress, bridgeFee);

        uint256 refundAmount = msg.value - bridgeFee;
        _refundExcess(refundAmount);

        emit SwappedAndBridgedFromERC20(msg.sender, tokenIn, amountIn, amountOut, recipientAddress, transferId);
    }

    /// @inheritdoc ITrustSwapAndBridgeRouter
    function bridgeTrust(
        uint256 trustAmount,
        address recipient
    )
        external
        payable
        nonReentrant
        returns (bytes32 transferId)
    {
        if (trustAmount == 0) revert TrustSwapAndBridgeRouter_AmountInZero();
        if (recipient == address(0)) revert TrustSwapAndBridgeRouter_InvalidRecipient();

        bytes32 recipientAddress = _formatRecipientAddress(recipient);
        uint256 bridgeFee = metaERC20Hub.quoteTransferRemote(recipientDomain, recipientAddress, trustAmount);
        if (msg.value < bridgeFee) revert TrustSwapAndBridgeRouter_InsufficientBridgeFee();

        trustToken.safeTransferFrom(msg.sender, address(this), trustAmount);
        transferId = _bridgeTrust(trustAmount, recipientAddress, bridgeFee);

        uint256 refundAmount = msg.value - bridgeFee;
        _refundExcess(refundAmount);

        emit TrustBridged(msg.sender, trustAmount, recipientAddress, transferId);
    }

    /* =================================================== */
    /*                   QUOTE FUNCTIONS                   */
    /* =================================================== */

    /// @inheritdoc ITrustSwapAndBridgeRouter
    function quoteBridgeFee(uint256 trustAmount, address recipient) external view returns (uint256 bridgeFee) {
        bytes32 recipientAddress = _formatRecipientAddress(recipient);
        bridgeFee = metaERC20Hub.quoteTransferRemote(recipientDomain, recipientAddress, trustAmount);
    }

    /// @inheritdoc ITrustSwapAndBridgeRouter
    function quoteExactInput(bytes calldata path, uint256 amountIn) external returns (uint256 amountOut) {
        try ICLQuoter(slipstreamQuoter).quoteExactInput(path, amountIn) returns (
            uint256 quotedAmountOut, uint160[] memory, uint32[] memory, uint256
        ) {
            amountOut = quotedAmountOut;
        } catch {
            amountOut = 0;
        }
    }

    /* =================================================== */
    /*                 INTERNAL FUNCTIONS                  */
    /* =================================================== */

    /// @dev Formats an EVM address into Metalayer recipient bytes32 format.
    function _formatRecipientAddress(address recipient) internal pure returns (bytes32 formattedRecipientAddress) {
        formattedRecipientAddress = bytes32(uint256(uint160(recipient)));
    }

    /// @dev Extracts a token address from a packed Slipstream path at a byte offset.
    ///      Path format: token0 (20 bytes) | tickSpacing (3 bytes) | token1 (20 bytes) | ...
    function _extractTokenAtOffset(bytes calldata path, uint256 offset) internal pure returns (address token) {
        if (path.length < MIN_PATH_LENGTH) revert TrustSwapAndBridgeRouter_InvalidPath();
        if (offset > path.length - ADDR_SIZE) revert TrustSwapAndBridgeRouter_InvalidPath();
        assembly {
            token := shr(96, calldataload(add(path.offset, offset)))
        }
    }

    /**
     * @dev Validates that all pools referenced in the packed path exist in the CL factory.
     *      Iterates hop-by-hop, extracting (tokenA, tickSpacing, tokenB) and checking
     *      ICLFactory.getPool(tokenA, tokenB, tickSpacing) != address(0).
     */
    function _validatePoolsExist(bytes calldata path) internal view {
        if (path.length < MIN_PATH_LENGTH) revert TrustSwapAndBridgeRouter_InvalidPath();
        if ((path.length - ADDR_SIZE) % HOP_SIZE != 0) revert TrustSwapAndBridgeRouter_InvalidPath();

        uint256 numHops = (path.length - ADDR_SIZE) / HOP_SIZE;
        uint256 offset = 0;

        for (uint256 i = 0; i < numHops; i++) {
            address tokenA;
            int24 tickSpacing;
            address tokenB;

            assembly {
                tokenA := shr(96, calldataload(add(path.offset, offset)))
                tickSpacing := signextend(2, shr(232, calldataload(add(path.offset, add(offset, 20)))))
                tokenB := shr(96, calldataload(add(path.offset, add(offset, 23))))
            }

            if (slipstreamFactory.getPool(tokenA, tokenB, tickSpacing) == address(0)) {
                revert TrustSwapAndBridgeRouter_PoolDoesNotExist();
            }

            offset += HOP_SIZE;
        }
    }

    /// @dev Internal function to bridge TRUST to destination chain via Metalayer.
    function _bridgeTrust(
        uint256 amountOut,
        bytes32 recipientAddress,
        uint256 bridgeFee
    )
        internal
        returns (bytes32 transferId)
    {
        trustToken.safeIncreaseAllowance(address(metaERC20Hub), amountOut);

        transferId = metaERC20Hub.transferRemote{ value: bridgeFee }(
            recipientDomain, recipientAddress, amountOut, bridgeGasLimit, finalityState
        );
    }

    /// @dev Internal function to refund excess ETH to the user after deducting bridge fee.
    function _refundExcess(uint256 refundAmount) internal {
        if (refundAmount > 0) {
            (bool success,) = msg.sender.call{ value: refundAmount }("");
            if (!success) revert TrustSwapAndBridgeRouter_ETHRefundFailed();
        }
    }
}
