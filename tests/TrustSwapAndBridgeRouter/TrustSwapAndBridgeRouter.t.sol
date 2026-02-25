// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { Test } from "forge-std/src/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TrustSwapAndBridgeRouter } from "contracts/TrustSwapAndBridgeRouter.sol";
import { ITrustSwapAndBridgeRouter } from "contracts/interfaces/ITrustSwapAndBridgeRouter.sol";
import { ISlipstreamSwapRouter } from "contracts/interfaces/external/aerodrome/ISlipstreamSwapRouter.sol";
import { FinalityState } from "contracts/interfaces/external/metalayer/IMetaERC20Hub.sol";

/* =================================================== */
/*                       MOCKS                         */
/* =================================================== */

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    bool public initialized;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function initialize(string memory _name, string memory _symbol, uint8 _decimals) external {
        require(!initialized, "MockERC20: already initialized");
        initialized = true;
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function burn(address from, uint256 amount) external {
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockWETH is MockERC20 {
    constructor() MockERC20("Wrapped Ether", "WETH", 18) { }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
    }

    function withdraw(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        payable(msg.sender).transfer(amount);
    }

    receive() external payable {
        deposit();
    }
}

contract MockSlipstreamSwapRouter {
    uint256 public outputMultiplier = 1e12;
    bool public shouldFail;

    function setOutputMultiplier(uint256 multiplier) external {
        outputMultiplier = multiplier;
    }

    function setShouldFail(bool fail) external {
        shouldFail = fail;
    }

    function exactInput(ISlipstreamSwapRouter.ExactInputParams calldata params) external returns (uint256 amountOut) {
        require(!shouldFail, "MockSlipstreamSwapRouter: swap failed");

        amountOut = params.amountIn * outputMultiplier;
        require(amountOut >= params.amountOutMinimum, "Too little received");
        require(params.recipient != address(0), "Invalid recipient");

        bytes calldata path = params.path;
        address tokenIn = address(bytes20(path[:20]));
        address tokenOut = address(bytes20(path[path.length - 20:]));

        IERC20(tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        MockERC20(tokenOut).mint(params.recipient, amountOut);
    }
}

contract MockCLFactory {
    mapping(bytes32 => address) internal pools;

    function setPool(address tokenA, address tokenB, int24 tickSpacing, address pool) external {
        pools[_key(tokenA, tokenB, tickSpacing)] = pool;
    }

    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address) {
        address pool = pools[_key(tokenA, tokenB, tickSpacing)];
        if (pool != address(0)) return pool;
        return pools[_key(tokenB, tokenA, tickSpacing)];
    }

    function _key(address tokenA, address tokenB, int24 tickSpacing) internal pure returns (bytes32) {
        return keccak256(abi.encode(tokenA, tokenB, tickSpacing));
    }
}

contract MockCLQuoter {
    uint256 public outputMultiplier = 1e12;
    bool public shouldFail;

    function setOutputMultiplier(uint256 multiplier) external {
        outputMultiplier = multiplier;
    }

    function setShouldFail(bool fail) external {
        shouldFail = fail;
    }

    function quoteExactInput(
        bytes memory,
        uint256 amountIn
    )
        external
        view
        returns (uint256 amountOut, uint160[] memory, uint32[] memory, uint256)
    {
        require(!shouldFail, "MockCLQuoter: quote failed");
        amountOut = amountIn * outputMultiplier;
    }
}

contract MockMetaERC20Hub {
    uint256 public constant BRIDGE_FEE = 0.001 ether;
    uint256 public transferCounter;

    function quoteTransferRemote(uint32, bytes32, uint256) external pure returns (uint256) {
        return BRIDGE_FEE;
    }

    function transferRemote(
        uint32,
        bytes32,
        uint256,
        uint256,
        FinalityState
    )
        external
        payable
        returns (bytes32 transferId)
    {
        require(msg.value >= BRIDGE_FEE, "MockMetaERC20Hub: insufficient fee");
        transferCounter++;
        transferId = keccak256(abi.encodePacked(transferCounter, block.timestamp, msg.sender));
    }
}

contract TrustSwapAndBridgeRouterHarness is TrustSwapAndBridgeRouter {
    function exposedExtractLastToken(bytes calldata path) external pure returns (address token) {
        token = _extractLastToken(path);
    }

    function exposedValidatePoolsExist(bytes calldata path) external view {
        _validatePoolsExist(path);
    }

    function exposedRefundExcess(uint256 refundAmount) external {
        _refundExcess(refundAmount);
    }
}

contract RejectETHRefundReceiver {
    receive() external payable {
        revert("RejectETHRefundReceiver: reject");
    }

    function callRefundExcess(TrustSwapAndBridgeRouterHarness routerHarness, uint256 refundAmount) external {
        routerHarness.exposedRefundExcess(refundAmount);
    }
}

/* =================================================== */
/*                       TESTS                         */
/* =================================================== */

contract TrustSwapAndBridgeRouterTest is Test {
    TrustSwapAndBridgeRouter public trustSwapRouter;
    MockMetaERC20Hub public metaERC20Hub;
    MockSlipstreamSwapRouter public swapRouter;
    MockCLFactory public clFactory;
    MockCLQuoter public clQuoter;

    MockERC20 public usdcToken;
    MockERC20 public trustToken;

    address public user = makeAddr("user");
    address public alice = makeAddr("alice");

    address public constant BASE_MAINNET_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant BASE_MAINNET_TRUST = 0x6cd905dF2Ed214b22e0d48FF17CD4200C1C6d8A3;
    address payable public constant BASE_MAINNET_WETH = payable(0x4200000000000000000000000000000000000006);

    int24 public constant TICK_SPACING_100 = 100;
    int24 public constant TICK_SPACING_200 = 200;

    uint32 public constant RECIPIENT_DOMAIN = 1155;
    uint256 public constant BRIDGE_GAS_LIMIT = 100_000;
    FinalityState public constant FINALITY_STATE = FinalityState.INSTANT;
    uint256 public constant DEFAULT_OUTPUT_MULTIPLIER = 1e12;

    address public constant MOCK_POOL_1 = address(0xDEAD1);
    address public constant MOCK_POOL_2 = address(0xDEAD2);

    function setUp() public {
        MockERC20 usdcTemplate = new MockERC20("", "", 0);
        MockERC20 trustTemplate = new MockERC20("", "", 0);
        MockWETH wethTemplate = new MockWETH();

        vm.etch(BASE_MAINNET_USDC, address(usdcTemplate).code);
        vm.etch(BASE_MAINNET_TRUST, address(trustTemplate).code);
        vm.etch(BASE_MAINNET_WETH, address(wethTemplate).code);

        usdcToken = MockERC20(BASE_MAINNET_USDC);
        trustToken = MockERC20(BASE_MAINNET_TRUST);

        usdcToken.initialize("USD Coin", "USDC", 6);
        trustToken.initialize("Trust Token", "TRUST", 18);
        MockWETH(BASE_MAINNET_WETH).initialize("Wrapped Ether", "WETH", 18);

        MockSlipstreamSwapRouter swapRouterTemplate = new MockSlipstreamSwapRouter();
        MockCLFactory clFactoryTemplate = new MockCLFactory();
        MockCLQuoter clQuoterTemplate = new MockCLQuoter();
        MockMetaERC20Hub metaERC20HubTemplate = new MockMetaERC20Hub();

        trustSwapRouter = new TrustSwapAndBridgeRouter();

        vm.etch(trustSwapRouter.slipstreamSwapRouter(), address(swapRouterTemplate).code);
        vm.etch(address(trustSwapRouter.slipstreamFactory()), address(clFactoryTemplate).code);
        vm.etch(trustSwapRouter.slipstreamQuoter(), address(clQuoterTemplate).code);
        vm.etch(address(trustSwapRouter.metaERC20Hub()), address(metaERC20HubTemplate).code);

        swapRouter = MockSlipstreamSwapRouter(trustSwapRouter.slipstreamSwapRouter());
        clFactory = MockCLFactory(address(trustSwapRouter.slipstreamFactory()));
        clQuoter = MockCLQuoter(trustSwapRouter.slipstreamQuoter());
        metaERC20Hub = MockMetaERC20Hub(address(trustSwapRouter.metaERC20Hub()));

        swapRouter.setOutputMultiplier(DEFAULT_OUTPUT_MULTIPLIER);
        clQuoter.setOutputMultiplier(DEFAULT_OUTPUT_MULTIPLIER);

        clFactory.setPool(BASE_MAINNET_USDC, BASE_MAINNET_TRUST, TICK_SPACING_100, MOCK_POOL_1);
        clFactory.setPool(BASE_MAINNET_WETH, BASE_MAINNET_USDC, TICK_SPACING_200, MOCK_POOL_2);
        clFactory.setPool(BASE_MAINNET_WETH, BASE_MAINNET_TRUST, TICK_SPACING_100, MOCK_POOL_1);

        usdcToken.mint(user, 1_000_000e6);
        usdcToken.mint(alice, 1_000_000e6);

        vm.prank(user);
        usdcToken.approve(address(trustSwapRouter), type(uint256).max);

        vm.prank(alice);
        usdcToken.approve(address(trustSwapRouter), type(uint256).max);
    }

    /* =================================================== */
    /*                   PATH HELPERS                      */
    /* =================================================== */

    function _buildSingleHopPath(
        address tokenIn,
        int24 tickSpacing,
        address tokenOut
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(tokenIn, tickSpacing, tokenOut);
    }

    function _buildTwoHopPath(
        address tokenIn,
        int24 tickSpacing1,
        address intermediate,
        int24 tickSpacing2,
        address tokenOut
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(tokenIn, tickSpacing1, intermediate, tickSpacing2, tokenOut);
    }

    /* =================================================== */
    /*               CONSTANT / VIEW TESTS                 */
    /* =================================================== */

    function test_constantsAndViews_matchExpectedMainnetConfig() public view {
        assertEq(address(trustSwapRouter.trustToken()), BASE_MAINNET_TRUST);
        assertEq(trustSwapRouter.slipstreamSwapRouter(), 0xcbBb8035cAc7D4B3Ca7aBb74cF7BdF900215Ce0D);
        assertEq(address(trustSwapRouter.slipstreamFactory()), 0xaDe65c38CD4849aDBA595a4323a8C7DdfE89716a);
        assertEq(trustSwapRouter.slipstreamQuoter(), 0x3d4C22254F86f64B7eC90ab8F7aeC1FBFD271c6C);
        assertEq(address(trustSwapRouter.metaERC20Hub()), 0xE12aaF1529Ae21899029a9b51cca2F2Bc2cfC421);
        assertEq(trustSwapRouter.recipientDomain(), RECIPIENT_DOMAIN);
        assertEq(trustSwapRouter.bridgeGasLimit(), BRIDGE_GAS_LIMIT);
        assertTrue(trustSwapRouter.finalityState() == FINALITY_STATE);
    }

    /* =================================================== */
    /*              SWAP WITH ETH FUNCTION TESTS           */
    /* =================================================== */

    function test_swapAndBridgeWithETH_singleHop_successful() public {
        uint256 ethAmountForSwap = 1 ether;
        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();
        uint256 totalEth = ethAmountForSwap + bridgeFee;
        uint256 expectedOutput = ethAmountForSwap * DEFAULT_OUTPUT_MULTIPLIER;

        bytes memory path = _buildSingleHopPath(BASE_MAINNET_WETH, TICK_SPACING_100, BASE_MAINNET_TRUST);

        vm.deal(user, totalEth);

        vm.prank(user);
        (uint256 amountOut, bytes32 transferId) =
            trustSwapRouter.swapAndBridgeWithETH{ value: totalEth }(path, expectedOutput, user);

        assertEq(amountOut, expectedOutput);
        assertTrue(transferId != bytes32(0));
    }

    function test_swapAndBridgeWithETH_twoHop_successful() public {
        uint256 ethAmountForSwap = 1 ether;
        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();
        uint256 totalEth = ethAmountForSwap + bridgeFee;
        uint256 expectedOutput = ethAmountForSwap * DEFAULT_OUTPUT_MULTIPLIER;

        bytes memory path = _buildTwoHopPath(
            BASE_MAINNET_WETH, TICK_SPACING_200, BASE_MAINNET_USDC, TICK_SPACING_100, BASE_MAINNET_TRUST
        );

        vm.deal(user, totalEth);

        vm.prank(user);
        (uint256 amountOut,) = trustSwapRouter.swapAndBridgeWithETH{ value: totalEth }(path, expectedOutput, user);

        assertEq(amountOut, expectedOutput);
    }

    function test_swapAndBridgeWithETH_emitsEvent() public {
        uint256 ethAmountForSwap = 1 ether;
        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();
        uint256 totalEth = ethAmountForSwap + bridgeFee;
        uint256 expectedOutput = ethAmountForSwap * DEFAULT_OUTPUT_MULTIPLIER;

        bytes memory path = _buildSingleHopPath(BASE_MAINNET_WETH, TICK_SPACING_100, BASE_MAINNET_TRUST);

        vm.deal(user, totalEth);

        vm.expectEmit(true, true, true, false);
        emit ITrustSwapAndBridgeRouter.SwappedAndBridgedFromETH(
            user, ethAmountForSwap, expectedOutput, bytes32(uint256(uint160(user))), bytes32(0)
        );

        vm.prank(user);
        trustSwapRouter.swapAndBridgeWithETH{ value: totalEth }(path, expectedOutput, user);
    }

    function test_swapAndBridgeWithETH_revertsOnInsufficientETH() public {
        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();

        bytes memory path = _buildSingleHopPath(BASE_MAINNET_WETH, TICK_SPACING_100, BASE_MAINNET_TRUST);

        vm.deal(user, bridgeFee);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_InsufficientETH.selector)
        );
        trustSwapRouter.swapAndBridgeWithETH{ value: bridgeFee }(path, 1, user);
    }

    function test_swapAndBridgeWithETH_revertsOnZeroRecipient() public {
        bytes memory path = _buildSingleHopPath(BASE_MAINNET_WETH, TICK_SPACING_100, BASE_MAINNET_TRUST);

        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();
        uint256 totalEth = 1 ether + bridgeFee;

        vm.deal(user, totalEth);

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_InvalidRecipient.selector)
        );
        trustSwapRouter.swapAndBridgeWithETH{ value: totalEth }(path, 0, address(0));
        vm.stopPrank();
    }

    function test_swapAndBridgeWithETH_revertsOnZeroETH() public {
        bytes memory path = _buildSingleHopPath(BASE_MAINNET_WETH, TICK_SPACING_100, BASE_MAINNET_TRUST);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_InsufficientETH.selector)
        );
        trustSwapRouter.swapAndBridgeWithETH(path, 0, user);
    }

    function test_swapAndBridgeWithETH_revertsOnPathNotStartingWithWETH() public {
        bytes memory path = _buildSingleHopPath(BASE_MAINNET_USDC, TICK_SPACING_100, BASE_MAINNET_TRUST);

        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();

        vm.deal(user, 1 ether + bridgeFee);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_PathDoesNotStartWithWETH.selector)
        );
        trustSwapRouter.swapAndBridgeWithETH{ value: 1 ether + bridgeFee }(path, 0, user);
    }

    function test_swapAndBridgeWithETH_revertsOnPathNotEndingWithTRUST() public {
        bytes memory path = _buildSingleHopPath(BASE_MAINNET_WETH, TICK_SPACING_100, BASE_MAINNET_USDC);

        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();

        vm.deal(user, 1 ether + bridgeFee);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_PathDoesNotEndWithTRUST.selector)
        );
        trustSwapRouter.swapAndBridgeWithETH{ value: 1 ether + bridgeFee }(path, 0, user);
    }

    function test_swapAndBridgeWithETH_revertsOnPoolDoesNotExist() public {
        address unknownToken = makeAddr("unknownToken");
        bytes memory path =
            _buildTwoHopPath(BASE_MAINNET_WETH, TICK_SPACING_100, unknownToken, TICK_SPACING_100, BASE_MAINNET_TRUST);

        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();

        vm.deal(user, 1 ether + bridgeFee);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_PoolDoesNotExist.selector)
        );
        trustSwapRouter.swapAndBridgeWithETH{ value: 1 ether + bridgeFee }(path, 0, user);
    }

    function test_swapAndBridgeWithETH_revertsOnInvalidPathLength() public {
        bytes memory path = abi.encodePacked(BASE_MAINNET_WETH, TICK_SPACING_100);

        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();

        vm.deal(user, 1 ether + bridgeFee);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_InvalidPath.selector));
        trustSwapRouter.swapAndBridgeWithETH{ value: 1 ether + bridgeFee }(path, 0, user);
    }

    function testFuzz_swapAndBridgeWithETH(uint256 ethAmount) public {
        ethAmount = bound(ethAmount, 0.001 ether, 100 ether);

        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();
        uint256 totalEth = ethAmount + bridgeFee;

        bytes memory path = _buildSingleHopPath(BASE_MAINNET_WETH, TICK_SPACING_100, BASE_MAINNET_TRUST);

        vm.deal(user, totalEth);

        vm.prank(user);
        (uint256 amountOut,) = trustSwapRouter.swapAndBridgeWithETH{ value: totalEth }(path, 0, user);

        assertEq(amountOut, ethAmount * DEFAULT_OUTPUT_MULTIPLIER);
    }

    /* =================================================== */
    /*             SWAP WITH ERC20 FUNCTION TESTS          */
    /* =================================================== */

    function test_swapAndBridgeWithERC20_singleHop_successful() public {
        uint256 amountIn = 100e6;
        uint256 expectedOutput = amountIn * DEFAULT_OUTPUT_MULTIPLIER;
        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();

        bytes memory path = _buildSingleHopPath(BASE_MAINNET_USDC, TICK_SPACING_100, BASE_MAINNET_TRUST);

        uint256 userUsdcBalanceBefore = usdcToken.balanceOf(user);

        vm.deal(user, bridgeFee);

        vm.prank(user);
        (uint256 amountOut,) = trustSwapRouter.swapAndBridgeWithERC20{ value: bridgeFee }(
            BASE_MAINNET_USDC, amountIn, path, expectedOutput, user
        );

        assertEq(amountOut, expectedOutput);
        assertEq(usdcToken.balanceOf(user), userUsdcBalanceBefore - amountIn);
    }

    function test_swapAndBridgeWithERC20_twoHop_successful() public {
        MockERC20 tokenA = new MockERC20("Token A", "TOKA", 18);
        tokenA.mint(user, 1000e18);

        clFactory.setPool(address(tokenA), BASE_MAINNET_USDC, TICK_SPACING_200, MOCK_POOL_2);

        vm.prank(user);
        tokenA.approve(address(trustSwapRouter), type(uint256).max);

        uint256 amountIn = 100e18;
        uint256 expectedOutput = amountIn * DEFAULT_OUTPUT_MULTIPLIER;
        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();

        bytes memory path = _buildTwoHopPath(
            address(tokenA), TICK_SPACING_200, BASE_MAINNET_USDC, TICK_SPACING_100, BASE_MAINNET_TRUST
        );

        vm.deal(user, bridgeFee);

        vm.prank(user);
        (uint256 amountOut,) = trustSwapRouter.swapAndBridgeWithERC20{ value: bridgeFee }(
            address(tokenA), amountIn, path, expectedOutput, user
        );

        assertEq(amountOut, expectedOutput);
    }

    function test_swapAndBridgeWithERC20_emitsEvent() public {
        uint256 amountIn = 100e6;
        uint256 expectedOutput = amountIn * DEFAULT_OUTPUT_MULTIPLIER;
        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();

        bytes memory path = _buildSingleHopPath(BASE_MAINNET_USDC, TICK_SPACING_100, BASE_MAINNET_TRUST);

        vm.deal(user, bridgeFee);

        vm.expectEmit(true, true, true, false);
        emit ITrustSwapAndBridgeRouter.SwappedAndBridgedFromERC20(
            user, BASE_MAINNET_USDC, amountIn, expectedOutput, bytes32(uint256(uint160(user))), bytes32(0)
        );

        vm.prank(user);
        trustSwapRouter.swapAndBridgeWithERC20{ value: bridgeFee }(
            BASE_MAINNET_USDC, amountIn, path, expectedOutput, user
        );
    }

    function test_swapAndBridgeWithERC20_refundsExcessETH() public {
        uint256 amountIn = 100e6;
        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();
        uint256 excessETH = 0.5 ether;
        uint256 totalETH = bridgeFee + excessETH;

        bytes memory path = _buildSingleHopPath(BASE_MAINNET_USDC, TICK_SPACING_100, BASE_MAINNET_TRUST);

        vm.deal(user, totalETH);

        uint256 userEthBefore = user.balance;

        vm.prank(user);
        trustSwapRouter.swapAndBridgeWithERC20{ value: totalETH }(BASE_MAINNET_USDC, amountIn, path, 0, user);

        assertEq(user.balance, userEthBefore - bridgeFee);
    }

    function test_swapAndBridgeWithERC20_revertsOnZeroRecipient() public {
        uint256 amountIn = 100e6;
        bytes memory path = _buildSingleHopPath(BASE_MAINNET_USDC, TICK_SPACING_100, BASE_MAINNET_TRUST);

        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();
        vm.deal(user, bridgeFee);

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_InvalidRecipient.selector)
        );
        trustSwapRouter.swapAndBridgeWithERC20{ value: bridgeFee }(BASE_MAINNET_USDC, amountIn, path, 0, address(0));
        vm.stopPrank();
    }

    function test_swapAndBridgeWithERC20_revertsOnZeroAmountIn() public {
        bytes memory path = _buildSingleHopPath(BASE_MAINNET_USDC, TICK_SPACING_100, BASE_MAINNET_TRUST);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_AmountInZero.selector)
        );
        trustSwapRouter.swapAndBridgeWithERC20(BASE_MAINNET_USDC, 0, path, 0, user);
    }

    function test_swapAndBridgeWithERC20_revertsOnInvalidTokenZeroAddress() public {
        bytes memory path = _buildSingleHopPath(address(0), TICK_SPACING_100, BASE_MAINNET_TRUST);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_InvalidToken.selector)
        );
        trustSwapRouter.swapAndBridgeWithERC20(address(0), 100e6, path, 0, user);
    }

    function test_swapAndBridgeWithERC20_revertsOnInvalidTokenTRUST() public {
        bytes memory path = _buildSingleHopPath(BASE_MAINNET_TRUST, TICK_SPACING_100, BASE_MAINNET_TRUST);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_InvalidToken.selector)
        );
        trustSwapRouter.swapAndBridgeWithERC20(BASE_MAINNET_TRUST, 100e6, path, 0, user);
    }

    function test_swapAndBridgeWithERC20_revertsOnPathTokenMismatch() public {
        bytes memory path = _buildSingleHopPath(BASE_MAINNET_WETH, TICK_SPACING_100, BASE_MAINNET_TRUST);

        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();
        vm.deal(user, bridgeFee);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_PathDoesNotStartWithToken.selector
            )
        );
        trustSwapRouter.swapAndBridgeWithERC20{ value: bridgeFee }(BASE_MAINNET_USDC, 100e6, path, 0, user);
    }

    function test_swapAndBridgeWithERC20_revertsOnPathNotEndingWithTRUST() public {
        bytes memory path = _buildSingleHopPath(BASE_MAINNET_USDC, TICK_SPACING_100, BASE_MAINNET_WETH);

        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();
        vm.deal(user, bridgeFee);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_PathDoesNotEndWithTRUST.selector)
        );
        trustSwapRouter.swapAndBridgeWithERC20{ value: bridgeFee }(BASE_MAINNET_USDC, 100e6, path, 0, user);
    }

    function test_swapAndBridgeWithERC20_revertsOnPoolDoesNotExist() public {
        address unknownToken = makeAddr("unknownToken");
        bytes memory path =
            _buildTwoHopPath(BASE_MAINNET_USDC, TICK_SPACING_100, unknownToken, TICK_SPACING_100, BASE_MAINNET_TRUST);

        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();
        vm.deal(user, bridgeFee);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_PoolDoesNotExist.selector)
        );
        trustSwapRouter.swapAndBridgeWithERC20{ value: bridgeFee }(BASE_MAINNET_USDC, 100e6, path, 0, user);
    }

    function test_swapAndBridgeWithERC20_revertsOnInsufficientBridgeFee() public {
        uint256 amountIn = 100e6;

        bytes memory path = _buildSingleHopPath(BASE_MAINNET_USDC, TICK_SPACING_100, BASE_MAINNET_TRUST);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_InsufficientBridgeFee.selector)
        );
        trustSwapRouter.swapAndBridgeWithERC20(BASE_MAINNET_USDC, amountIn, path, 0, user);
    }

    function test_swapAndBridgeWithERC20_revertsOnInvalidPathLength() public {
        bytes memory path = abi.encodePacked(BASE_MAINNET_USDC, TICK_SPACING_100);

        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();
        vm.deal(user, bridgeFee);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_InvalidPath.selector));
        trustSwapRouter.swapAndBridgeWithERC20{ value: bridgeFee }(BASE_MAINNET_USDC, 100e6, path, 0, user);
    }

    function testFuzz_swapAndBridgeWithERC20(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, 1_000_000e6);

        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();

        bytes memory path = _buildSingleHopPath(BASE_MAINNET_USDC, TICK_SPACING_100, BASE_MAINNET_TRUST);

        usdcToken.mint(user, amountIn);
        vm.deal(user, bridgeFee);

        vm.prank(user);
        (uint256 amountOut,) =
            trustSwapRouter.swapAndBridgeWithERC20{ value: bridgeFee }(BASE_MAINNET_USDC, amountIn, path, 0, user);

        assertEq(amountOut, amountIn * DEFAULT_OUTPUT_MULTIPLIER);
    }

    /* =================================================== */
    /*                  BRIDGE TRUST TESTS                 */
    /* =================================================== */

    function test_bridgeTrust_successful() public {
        uint256 trustAmount = 1000e18;
        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();

        trustToken.mint(user, trustAmount);
        vm.deal(user, bridgeFee);

        uint256 userTrustBefore = trustToken.balanceOf(user);
        uint256 routerTrustBefore = trustToken.balanceOf(address(trustSwapRouter));

        vm.startPrank(user);
        trustToken.approve(address(trustSwapRouter), trustAmount);
        bytes32 transferId = trustSwapRouter.bridgeTrust{ value: bridgeFee }(trustAmount, alice);
        vm.stopPrank();

        assertTrue(transferId != bytes32(0));
        assertEq(trustToken.balanceOf(user), userTrustBefore - trustAmount);
        assertEq(trustToken.balanceOf(address(trustSwapRouter)), routerTrustBefore + trustAmount);
    }

    function test_bridgeTrust_emitsEvent() public {
        uint256 trustAmount = 500e18;
        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();

        trustToken.mint(user, trustAmount);
        vm.deal(user, bridgeFee);

        vm.startPrank(user);

        trustToken.approve(address(trustSwapRouter), trustAmount);

        vm.expectEmit(true, true, true, false);
        emit ITrustSwapAndBridgeRouter.TrustBridged(user, trustAmount, bytes32(uint256(uint160(alice))), bytes32(0));

        trustSwapRouter.bridgeTrust{ value: bridgeFee }(trustAmount, alice);
        vm.stopPrank();
    }

    function test_bridgeTrust_refundsExcessETH() public {
        uint256 trustAmount = 300e18;
        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();
        uint256 excessETH = 0.25 ether;
        uint256 totalETH = bridgeFee + excessETH;

        trustToken.mint(user, trustAmount);
        vm.deal(user, totalETH);

        uint256 userEthBefore = user.balance;

        vm.startPrank(user);
        trustToken.approve(address(trustSwapRouter), trustAmount);
        trustSwapRouter.bridgeTrust{ value: totalETH }(trustAmount, alice);
        vm.stopPrank();

        assertEq(user.balance, userEthBefore - bridgeFee);
    }

    function test_bridgeTrust_revertsOnZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_AmountInZero.selector)
        );
        trustSwapRouter.bridgeTrust(0, alice);
    }

    function test_bridgeTrust_revertsOnZeroRecipient() public {
        uint256 trustAmount = 100e18;
        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();

        trustToken.mint(user, trustAmount);
        vm.deal(user, bridgeFee);

        vm.startPrank(user);
        trustToken.approve(address(trustSwapRouter), trustAmount);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_InvalidRecipient.selector)
        );
        trustSwapRouter.bridgeTrust{ value: bridgeFee }(trustAmount, address(0));
        vm.stopPrank();
    }

    function test_bridgeTrust_revertsOnInsufficientBridgeFee() public {
        uint256 trustAmount = 100e18;
        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();

        trustToken.mint(user, trustAmount);
        vm.deal(user, bridgeFee - 1);

        vm.startPrank(user);
        trustToken.approve(address(trustSwapRouter), trustAmount);
        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_InsufficientBridgeFee.selector)
        );
        trustSwapRouter.bridgeTrust{ value: bridgeFee - 1 }(trustAmount, alice);
        vm.stopPrank();
    }

    /* =================================================== */
    /*                 QUOTE FUNCTION TESTS                */
    /* =================================================== */

    function test_quoteBridgeFee_successful() public view {
        uint256 bridgeFee = trustSwapRouter.quoteBridgeFee(1000e18, user);
        assertEq(bridgeFee, metaERC20Hub.BRIDGE_FEE());
    }

    function test_quoteBridgeFee_withZeroAmount() public view {
        uint256 bridgeFee = trustSwapRouter.quoteBridgeFee(0, user);
        assertEq(bridgeFee, metaERC20Hub.BRIDGE_FEE());
    }

    function test_quoteExactInput_successful() public {
        uint256 amountIn = 100e6;
        bytes memory path = _buildSingleHopPath(BASE_MAINNET_USDC, TICK_SPACING_100, BASE_MAINNET_TRUST);

        uint256 amountOut = trustSwapRouter.quoteExactInput(path, amountIn);

        assertEq(amountOut, amountIn * DEFAULT_OUTPUT_MULTIPLIER);
    }

    function test_quoteExactInput_returnsZeroOnFailure() public {
        clQuoter.setShouldFail(true);

        uint256 amountIn = 100e6;
        bytes memory path = _buildSingleHopPath(BASE_MAINNET_USDC, TICK_SPACING_100, BASE_MAINNET_TRUST);

        uint256 amountOut = trustSwapRouter.quoteExactInput(path, amountIn);

        assertEq(amountOut, 0);
    }

    /* =================================================== */
    /*              INTERNAL COVERAGE TESTS                */
    /* =================================================== */

    function test_extractLastToken_revertsOnPathTooShort_viaHarness() public {
        TrustSwapAndBridgeRouterHarness routerHarness = new TrustSwapAndBridgeRouterHarness();
        bytes memory shortPath = abi.encodePacked(BASE_MAINNET_WETH);

        vm.expectRevert(abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_InvalidPath.selector));
        routerHarness.exposedExtractLastToken(shortPath);
    }

    function test_validatePoolsExist_revertsOnPathTooShort_viaHarness() public {
        TrustSwapAndBridgeRouterHarness routerHarness = new TrustSwapAndBridgeRouterHarness();
        bytes memory shortPath = abi.encodePacked(BASE_MAINNET_USDC);

        vm.expectRevert(abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_InvalidPath.selector));
        routerHarness.exposedValidatePoolsExist(shortPath);
    }

    function test_refundExcess_revertsWhenRecipientRejectsETH_viaHarness() public {
        TrustSwapAndBridgeRouterHarness routerHarness = new TrustSwapAndBridgeRouterHarness();
        RejectETHRefundReceiver rejectingReceiver = new RejectETHRefundReceiver();
        uint256 refundAmount = 0.1 ether;

        vm.deal(address(routerHarness), refundAmount);

        vm.expectRevert(
            abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_ETHRefundFailed.selector)
        );
        rejectingReceiver.callRefundExcess(routerHarness, refundAmount);
    }

    /* =================================================== */
    /*              PATH VALIDATION TESTS                  */
    /* =================================================== */

    function test_pathValidation_revertsOnPathTooShort() public {
        bytes memory shortPath = abi.encodePacked(BASE_MAINNET_WETH);

        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();
        vm.deal(user, 1 ether + bridgeFee);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_InvalidPath.selector));
        trustSwapRouter.swapAndBridgeWithETH{ value: 1 ether + bridgeFee }(shortPath, 0, user);
    }

    function test_pathValidation_revertsOnWrongLengthModulo() public {
        // Build a 50-byte path that starts with USDC and ends with TRUST but has wrong modulo
        // Valid: 43 (1 hop), 66 (2 hops). 50 is invalid modulo.
        bytes memory badPath = new bytes(50);
        bytes20 usdcBytes = bytes20(BASE_MAINNET_USDC);
        bytes20 trustBytes = bytes20(BASE_MAINNET_TRUST);
        for (uint256 i = 0; i < 20; i++) {
            badPath[i] = usdcBytes[i];
            badPath[30 + i] = trustBytes[i];
        }

        uint256 bridgeFee = metaERC20Hub.BRIDGE_FEE();
        vm.deal(user, bridgeFee);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ITrustSwapAndBridgeRouter.TrustSwapAndBridgeRouter_InvalidPath.selector));
        trustSwapRouter.swapAndBridgeWithERC20{ value: bridgeFee }(BASE_MAINNET_USDC, 100e6, badPath, 0, user);
    }

    /* =================================================== */
    /*                   VIEW FUNCTION TESTS               */
    /* =================================================== */

    function test_trustToken_returnsCorrectAddress() public view {
        assertEq(address(trustSwapRouter.trustToken()), BASE_MAINNET_TRUST);
    }

    function test_slipstreamSwapRouter_returnsCorrectAddress() public view {
        assertEq(trustSwapRouter.slipstreamSwapRouter(), address(swapRouter));
    }

    function test_slipstreamFactory_returnsCorrectAddress() public view {
        assertEq(address(trustSwapRouter.slipstreamFactory()), address(clFactory));
    }

    function test_slipstreamQuoter_returnsCorrectAddress() public view {
        assertEq(trustSwapRouter.slipstreamQuoter(), address(clQuoter));
    }
}
