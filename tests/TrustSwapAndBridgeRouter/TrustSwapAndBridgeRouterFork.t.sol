// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { Test } from "forge-std/src/Test.sol";
import { console2 } from "forge-std/src/console2.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TrustSwapAndBridgeRouter } from "contracts/TrustSwapAndBridgeRouter.sol";
import { ITrustSwapAndBridgeRouter } from "contracts/interfaces/ITrustSwapAndBridgeRouter.sol";
import { ICLQuoter } from "contracts/interfaces/external/aerodrome/ICLQuoter.sol";
import { FinalityState, IMetaERC20Hub } from "contracts/interfaces/external/metalayer/IMetaERC20Hub.sol";

/**
 * @title TrustSwapAndBridgeRouterFork
 * @notice Fork integration tests against real Aerodrome Slipstream pools on Base mainnet.
 *         MetaERC20Hub bridge calls are mocked via vm.mockCall since the hub's domain config
 *         is not controllable in a fork environment.
 */
contract TrustSwapAndBridgeRouterFork is Test {
    /* =================================================== */
    /*                   BASE ADDRESSES                    */
    /* =================================================== */

    address public constant TRUST = 0x6cd905dF2Ed214b22e0d48FF17CD4200C1C6d8A3;
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;

    address public constant CL_SWAP_ROUTER = 0xcbBb8035cAc7D4B3Ca7aBb74cF7BdF900215Ce0D;
    address public constant CL_FACTORY = 0xaDe65c38CD4849aDBA595a4323a8C7DdfE89716a;
    address public constant CL_QUOTER = 0x3d4C22254F86f64B7eC90ab8F7aeC1FBFD271c6C;
    address public constant META_ERC20_HUB = 0xE12aaF1529Ae21899029a9b51cca2F2Bc2cfC421;

    uint256 public constant FORK_BLOCK = 41_970_000;

    uint256 public constant MOCK_BRIDGE_FEE = 0.001 ether;
    bytes32 public constant MOCK_TRANSFER_ID = keccak256("mock-transfer-id");

    /* =================================================== */
    /*                   TICK SPACINGS                     */
    /* =================================================== */

    int24 public constant TS_WETH_USDC = 50;
    int24 public constant TS_USDC_TRUST = 1;
    int24 public constant TS_DAI_USDC = 1;

    /* =================================================== */
    /*                   TEST STATE                        */
    /* =================================================== */

    TrustSwapAndBridgeRouter public router;
    address public user = address(0xBEEF);
    address public recipient = address(0xCAFE);

    function setUp() public {
        vm.createSelectFork("base", FORK_BLOCK);

        router = new TrustSwapAndBridgeRouter();

        assertEq(router.slipstreamSwapRouter(), CL_SWAP_ROUTER, "Slipstream router mismatch");
        assertEq(address(router.slipstreamFactory()), CL_FACTORY, "Slipstream factory mismatch");
        assertEq(router.slipstreamQuoter(), CL_QUOTER, "Slipstream quoter mismatch");
        assertEq(address(router.metaERC20Hub()), META_ERC20_HUB, "MetaERC20Hub mismatch");
        assertEq(router.recipientDomain(), 1155, "Recipient domain mismatch");
        assertEq(router.bridgeGasLimit(), 100_000, "Bridge gas limit mismatch");
        assertEq(uint256(router.finalityState()), uint256(FinalityState.INSTANT), "Finality state mismatch");

        // Mock MetaERC20Hub.quoteTransferRemote → returns MOCK_BRIDGE_FEE
        vm.mockCall(
            META_ERC20_HUB,
            abi.encodeWithSelector(IMetaERC20Hub.quoteTransferRemote.selector),
            abi.encode(MOCK_BRIDGE_FEE)
        );

        // Mock MetaERC20Hub.transferRemote → returns MOCK_TRANSFER_ID
        vm.mockCall(
            META_ERC20_HUB, abi.encodeWithSelector(IMetaERC20Hub.transferRemote.selector), abi.encode(MOCK_TRANSFER_ID)
        );

        // Fund user
        vm.deal(user, 100 ether);
    }

    /* =================================================== */
    /*           TEST 1: ETH → WETH → USDC → TRUST        */
    /* =================================================== */

    function test_fork_swapETHToTrustViaUSDC() external {
        bytes memory path = abi.encodePacked(WETH, TS_WETH_USDC, USDC, TS_USDC_TRUST, TRUST);

        uint256 swapEth = 0.01 ether;
        uint256 totalValue = swapEth + MOCK_BRIDGE_FEE;

        uint256 userEthBefore = user.balance;
        uint256 routerTrustBefore = IERC20(TRUST).balanceOf(address(router));

        vm.prank(user);
        (uint256 amountOut, bytes32 transferId) =
            router.swapAndBridgeWithETH{ value: totalValue }(path, 1, recipient, block.timestamp + 1 hours);

        assertGt(amountOut, 0, "Should receive TRUST from swap");
        assertEq(transferId, MOCK_TRANSFER_ID, "Transfer ID should match mock");
        assertEq(user.balance, userEthBefore - totalValue, "User should spend exact ETH");

        // TRUST remains in router since bridge is mocked (mock doesn't pull tokens)
        uint256 routerTrustAfter = IERC20(TRUST).balanceOf(address(router));
        assertEq(routerTrustAfter - routerTrustBefore, amountOut, "Router should hold swapped TRUST");

        console2.log("ETH -> USDC -> TRUST: swapped %d wei ETH for %d TRUST", swapEth, amountOut);
    }

    function test_fork_swapETHToTrustViaUSDC_withMinOutput() external {
        bytes memory path = abi.encodePacked(WETH, TS_WETH_USDC, USDC, TS_USDC_TRUST, TRUST);

        uint256 swapEth = 0.01 ether;
        uint256 totalValue = swapEth + MOCK_BRIDGE_FEE;

        // First get a quote to know expected output
        (uint256 expectedOut,,,) = ICLQuoter(CL_QUOTER).quoteExactInput(path, swapEth);
        assertGt(expectedOut, 0, "Quote should return non-zero");

        // Use 99% of expected as minOutput (1% slippage tolerance)
        uint256 minTrustOut = (expectedOut * 99) / 100;

        vm.prank(user);
        (uint256 amountOut,) =
            router.swapAndBridgeWithETH{ value: totalValue }(path, minTrustOut, recipient, block.timestamp + 1 hours);

        assertGe(amountOut, minTrustOut, "Output should meet minimum");

        console2.log("ETH -> USDC -> TRUST: quoted", expectedOut, "got", amountOut);
    }

    /* =================================================== */
    /*             TEST 2: USDC → TRUST DIRECT             */
    /* =================================================== */

    function test_fork_swapUSDCToTrustDirect() external {
        bytes memory path = abi.encodePacked(USDC, TS_USDC_TRUST, TRUST);

        uint256 amountIn = 10e6; // 10 USDC
        deal(USDC, user, amountIn);

        uint256 userUsdcBefore = IERC20(USDC).balanceOf(user);
        assertEq(userUsdcBefore, amountIn, "User should have USDC");

        vm.startPrank(user);
        IERC20(USDC).approve(address(router), amountIn);

        (uint256 amountOut, bytes32 transferId) = router.swapAndBridgeWithERC20{ value: MOCK_BRIDGE_FEE }(
            USDC, amountIn, path, 1, recipient, block.timestamp + 1 hours
        );
        vm.stopPrank();

        assertGt(amountOut, 0, "Should receive TRUST from swap");
        assertEq(transferId, MOCK_TRANSFER_ID, "Transfer ID should match mock");
        assertEq(IERC20(USDC).balanceOf(user), 0, "User USDC should be spent");

        uint256 routerTrust = IERC20(TRUST).balanceOf(address(router));
        assertEq(routerTrust, amountOut, "Router should hold swapped TRUST");

        console2.log("USDC -> TRUST: swapped %d USDC for %d TRUST", amountIn, amountOut);
    }

    function test_fork_swapUSDCToTrustDirect_withMinOutput() external {
        bytes memory path = abi.encodePacked(USDC, TS_USDC_TRUST, TRUST);

        uint256 amountIn = 10e6; // 10 USDC
        deal(USDC, user, amountIn);

        // Get quote first
        (uint256 expectedOut,,,) = ICLQuoter(CL_QUOTER).quoteExactInput(path, amountIn);
        assertGt(expectedOut, 0, "Quote should return non-zero");

        uint256 minTrustOut = (expectedOut * 99) / 100;

        vm.startPrank(user);
        IERC20(USDC).approve(address(router), amountIn);

        (uint256 amountOut,) = router.swapAndBridgeWithERC20{ value: MOCK_BRIDGE_FEE }(
            USDC, amountIn, path, minTrustOut, recipient, block.timestamp + 1 hours
        );
        vm.stopPrank();

        assertGe(amountOut, minTrustOut, "Output should meet minimum");

        console2.log("USDC -> TRUST: quoted", expectedOut, "got", amountOut);
    }

    /* =================================================== */
    /*        TEST 3: DAI → USDC → TRUST (TWO-HOP)        */
    /* =================================================== */

    function test_fork_swapDAIToTrustViaUSDC() external {
        bytes memory path = abi.encodePacked(DAI, TS_DAI_USDC, USDC, TS_USDC_TRUST, TRUST);

        uint256 amountIn = 10e18; // 10 DAI
        deal(DAI, user, amountIn);

        vm.startPrank(user);
        IERC20(DAI).approve(address(router), amountIn);

        (uint256 amountOut, bytes32 transferId) = router.swapAndBridgeWithERC20{ value: MOCK_BRIDGE_FEE }(
            DAI, amountIn, path, 1, recipient, block.timestamp + 1 hours
        );
        vm.stopPrank();

        assertGt(amountOut, 0, "Should receive TRUST from swap");
        assertEq(transferId, MOCK_TRANSFER_ID, "Transfer ID should match mock");
        assertEq(IERC20(DAI).balanceOf(user), 0, "User DAI should be spent");

        uint256 routerTrust = IERC20(TRUST).balanceOf(address(router));
        assertEq(routerTrust, amountOut, "Router should hold swapped TRUST");

        console2.log("DAI -> USDC -> TRUST: swapped %d DAI for %d TRUST", amountIn, amountOut);
    }

    function test_fork_swapDAIToTrustViaUSDC_withMinOutput() external {
        bytes memory path = abi.encodePacked(DAI, TS_DAI_USDC, USDC, TS_USDC_TRUST, TRUST);

        uint256 amountIn = 10e18; // 10 DAI
        deal(DAI, user, amountIn);

        (uint256 expectedOut,,,) = ICLQuoter(CL_QUOTER).quoteExactInput(path, amountIn);
        assertGt(expectedOut, 0, "Quote should return non-zero");

        uint256 minTrustOut = (expectedOut * 99) / 100;

        vm.startPrank(user);
        IERC20(DAI).approve(address(router), amountIn);

        (uint256 amountOut,) = router.swapAndBridgeWithERC20{ value: MOCK_BRIDGE_FEE }(
            DAI, amountIn, path, minTrustOut, recipient, block.timestamp + 1 hours
        );
        vm.stopPrank();

        assertGe(amountOut, minTrustOut, "Output should meet minimum");

        console2.log("DAI -> USDC -> TRUST: quoted", expectedOut, "got", amountOut);
    }

    /* =================================================== */
    /*               TEST 4: DIRECT TRUST BRIDGE          */
    /* =================================================== */

    function test_fork_bridgeTrust_successful() external {
        uint256 trustAmount = 10e18;
        deal(TRUST, user, trustAmount);

        uint256 routerTrustBefore = IERC20(TRUST).balanceOf(address(router));

        vm.startPrank(user);
        IERC20(TRUST).approve(address(router), trustAmount);
        bytes32 transferId = router.bridgeTrust{ value: MOCK_BRIDGE_FEE }(trustAmount, recipient);
        vm.stopPrank();

        assertEq(transferId, MOCK_TRANSFER_ID, "Transfer ID should match mock");
        assertEq(IERC20(TRUST).balanceOf(user), 0, "User TRUST should be spent");
        assertEq(IERC20(TRUST).balanceOf(address(router)), routerTrustBefore + trustAmount, "Router should hold TRUST");
    }

    function test_fork_bridgeTrust_refundsExcessETH() external {
        uint256 trustAmount = 3e18;
        uint256 excessEth = 0.2 ether;
        uint256 totalValue = MOCK_BRIDGE_FEE + excessEth;

        deal(TRUST, user, trustAmount);
        uint256 userEthBefore = user.balance;

        vm.startPrank(user);
        IERC20(TRUST).approve(address(router), trustAmount);
        router.bridgeTrust{ value: totalValue }(trustAmount, recipient);
        vm.stopPrank();

        assertEq(user.balance, userEthBefore - MOCK_BRIDGE_FEE, "Only bridge fee should be deducted");
    }

    function test_fork_bridgeTrust_revertsOnInsufficientBridgeFee() external {
        uint256 trustAmount = 1e18;
        deal(TRUST, user, trustAmount);

        vm.startPrank(user);
        IERC20(TRUST).approve(address(router), trustAmount);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_InsufficientBridgeFee.selector)
        );
        router.bridgeTrust{ value: MOCK_BRIDGE_FEE - 1 }(trustAmount, recipient);
        vm.stopPrank();
    }

    /* =================================================== */
    /*              QUOTE FUNCTIONS (FORK)                 */
    /* =================================================== */

    function test_fork_quoteExactInput_singleHop() external {
        bytes memory path = abi.encodePacked(USDC, TS_USDC_TRUST, TRUST);

        (uint256 quotedAmount, bool success) = router.quoteExactInput(path, 10e6);
        assertTrue(success, "Quote should succeed for valid path");
        assertGt(quotedAmount, 0, "Quote should return non-zero for valid path");

        console2.log("QuoteExactInput: 10 USDC ->", quotedAmount, "TRUST");
    }

    function test_fork_quoteExactInput_multiHop() external {
        bytes memory path = abi.encodePacked(WETH, TS_WETH_USDC, USDC, TS_USDC_TRUST, TRUST);

        (uint256 quotedAmount, bool success) = router.quoteExactInput(path, 0.01 ether);
        assertTrue(success, "Quote should succeed for valid multi-hop path");
        assertGt(quotedAmount, 0, "Quote should return non-zero for valid multi-hop path");

        console2.log("QuoteExactInput: 0.01 ETH ->", quotedAmount, "TRUST");
    }

    function test_fork_quoteBridgeFee() external view {
        uint256 fee = router.quoteBridgeFee(1e18, recipient);
        assertEq(fee, MOCK_BRIDGE_FEE, "Bridge fee should match mock");
    }

    /* =================================================== */
    /*              EXCESS ETH REFUND (FORK)               */
    /* =================================================== */

    function test_fork_excessETHRefundOnERC20Swap() external {
        bytes memory path = abi.encodePacked(USDC, TS_USDC_TRUST, TRUST);

        uint256 amountIn = 1e6; // 1 USDC
        deal(USDC, user, amountIn);

        uint256 excessEth = 0.5 ether;
        uint256 totalValue = MOCK_BRIDGE_FEE + excessEth;

        uint256 userEthBefore = user.balance;

        vm.startPrank(user);
        IERC20(USDC).approve(address(router), amountIn);
        router.swapAndBridgeWithERC20{ value: totalValue }(
            USDC, amountIn, path, 1, recipient, block.timestamp + 1 hours
        );
        vm.stopPrank();

        uint256 userEthAfter = user.balance;
        assertEq(userEthAfter, userEthBefore - MOCK_BRIDGE_FEE, "Only bridge fee should be deducted");
    }

    /* =================================================== */
    /*        RECEIVE() DUST ACCEPTANCE (FORK)             */
    /* =================================================== */

    /// @notice Verifies the router can receive ETH dust refunds from the Slipstream SwapRouter
    ///         during a swapAndBridgeWithETH call. The receive() function must accept ETH
    ///         sent back by the swap router's internal refundETH path.
    function test_fork_swapAndBridgeWithETH_routerAcceptsSwapDust() external {
        bytes memory path = abi.encodePacked(WETH, TS_WETH_USDC, USDC, TS_USDC_TRUST, TRUST);

        uint256 swapEth = 0.01 ether;
        uint256 totalValue = swapEth + MOCK_BRIDGE_FEE;

        // Force deterministic non-zero refund path from Slipstream router.
        vm.deal(CL_SWAP_ROUTER, 1 wei);
        uint256 routerEthBefore = address(router).balance;

        vm.prank(user);
        (uint256 amountOut,) =
            router.swapAndBridgeWithETH{ value: totalValue }(path, 1, recipient, block.timestamp + 1 hours);

        assertGt(amountOut, 0, "Should receive TRUST from swap");

        // The router's ETH balance captures any dust refunded by the SwapRouter.
        // In the swapAndBridgeWithETH path, there is no explicit _refundExcess call
        // for swap dust — the receive() function silently accepts it.
        uint256 routerEthAfter = address(router).balance;

        // The key assertion: the router balance should strictly increase,
        // proving receive() accepted a non-zero refund without reverting.
        assertGt(routerEthAfter, routerEthBefore, "Router should capture ETH dust from swap");
        assertEq(CL_SWAP_ROUTER.balance, 0, "SwapRouter dust should be refunded out");

        console2.log("Router ETH dust captured: %d wei", routerEthAfter - routerEthBefore);
    }

    /// @notice Reproduces the original sweepToken contamination path (S-324):
    ///         attacker sends 1 wei into Slipstream SwapRouter via payable sweepToken, then a user swap
    ///         must still succeed because this router now accepts refundETH callbacks via receive().
    function test_fork_swapAndBridgeWithETH_sweepTokenDustDoesNotDos() external {
        bytes memory path = abi.encodePacked(WETH, TS_WETH_USDC, USDC, TS_USDC_TRUST, TRUST);
        uint256 swapEth = 0.01 ether;
        uint256 totalValue = swapEth + MOCK_BRIDGE_FEE;
        address attacker = makeAddr("attacker");

        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        (bool ok,) = CL_SWAP_ROUTER.call{ value: 1 wei }(
            abi.encodeWithSignature("sweepToken(address,uint256,address)", TRUST, 0, attacker)
        );
        assertTrue(ok, "sweepToken contamination call should succeed");
        assertEq(CL_SWAP_ROUTER.balance, 1 wei, "SwapRouter should hold 1 wei before swap");

        vm.prank(user);
        (uint256 amountOut,) =
            router.swapAndBridgeWithETH{ value: totalValue }(path, 1, recipient, block.timestamp + 1 hours);

        assertGt(amountOut, 0, "Swap should still succeed after contamination");
        assertEq(CL_SWAP_ROUTER.balance, 0, "refundETH should clear SwapRouter ETH dust");
    }

    /* =================================================== */
    /*                POOL VALIDATION (FORK)               */
    /* =================================================== */

    function test_fork_revertsOnNonExistentPool() external {
        // Use tick spacing 10 which has no USDC/TRUST pool
        bytes memory badPath = abi.encodePacked(USDC, int24(10), TRUST);

        deal(USDC, user, 1e6);

        vm.startPrank(user);
        IERC20(USDC).approve(address(router), 1e6);

        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_PoolDoesNotExist.selector)
        );
        router.swapAndBridgeWithERC20{ value: MOCK_BRIDGE_FEE }(
            USDC, 1e6, badPath, 1, recipient, block.timestamp + 1 hours
        );
        vm.stopPrank();
    }
}
