// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployDecentralizedStablecoin} from "../../script/DeployDecentralizedStablecoin.s.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../test/mocks/ERC20Mock.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MockFailedMintDSC} from "../../test/mocks/MockFailedMintDSC.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDecentralizedStablecoin deployer;
    DecentralizedStablecoin public dsc;
    DSCEngine public dscengine;
    HelperConfig public config;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 amountToMint = 100 ether;

    int256 public constant ETH_USD_PRICE = 2000e8;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    function setUp() public {
        deployer = new DeployDecentralizedStablecoin();
        (dsc, dscengine, config) = deployer.run();

        (btcUsdPriceFeed, ethUsdPriceFeed, wbtc, weth, deployerKey) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////////////
    /// CONSTRUCTOR TEST //////////
    ///////////////////////////////
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testRevertIfPriceFeedAndTokenAddressLengthNotSame() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        dscengine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ///////////////////////////////
    /// PRICEFEED TEST ////////////
    ///////////////////////////////

    function testUSDValue() public {
        uint256 ETH_USD_PRICE = 2000;
        uint256 ethAmount = 15e18;
        uint256 expectedValue = ethAmount * ETH_USD_PRICE;
        uint256 actualValue = dscengine.getUSDValue(weth, ethAmount);
        assertEq(expectedValue, actualValue);
    }

    function testGetTokenAmountFromUSD() public {
        uint256 usdAmount = 100;
        uint256 ETH_USD_PRICE = 2000e8;
        uint256 expectedWeth = usdAmount / ETH_USD_PRICE;
        uint256 actualWeth = dscengine.getTokenAmountFromUSD(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ///////////////////////////////
    /// DEPOSIT COLLATERAL TEST ///
    ///////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscengine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscengine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedTokenCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenIsNotAllowed.selector);
        dscengine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscengine), AMOUNT_COLLATERAL);
        dscengine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetSomeInfo() public depositedCollateral {
        (uint256 totalCollateralValue, uint256 dscAmount) = dscengine.getAccountInformation(USER);
        uint256 expectedDscAmount = 0;
        uint256 expectedCollateralValueInUsd = dscengine.getUSDValue(weth, AMOUNT_COLLATERAL);
        assertEq(dscAmount, expectedDscAmount);
        assertEq(totalCollateralValue, expectedCollateralValueInUsd);
    }

    function testDepositTransferredToDSCE() public depositedCollateral {
        assertEq(IERC20(weth).balanceOf(address(dscengine)), AMOUNT_COLLATERAL);
    }

    ///////////////////////////////
    /// REDEEM COLLATERAL TEST ///
    ///////////////////////////////
    function testRevertsIfRedeemAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscengine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testDSCEBalanceAfterRedeem() public depositedCollateral {
        vm.startPrank(USER);
        dscengine.redeemCollateral(weth, AMOUNT_COLLATERAL);

        (uint256 totalCollateralValue, uint256 dscAmount) = dscengine.getAccountInformation(USER);
        assertEq(totalCollateralValue, 0);
        assertEq(dscAmount, 0);
        vm.stopPrank();
    }

    function testRevertIfHealthFactorTooLowAfterRedeem() public depositedCollateral {
        vm.startPrank(USER);
        dscengine.mintDsc(amountToMint);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreakHealthFactor.selector, 0));
        dscengine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ///////////////////////////////
    /// MINT DSC TEST /////////////
    ///////////////////////////////
    function testDSCBalanceAfterMinted() public depositedCollateral {
        vm.startPrank(USER);
        dscengine.mintDsc(amountToMint);
        (, uint256 dscAmount) = dscengine.getAccountInformation(USER);
        assertEq(dscAmount, amountToMint);
        vm.stopPrank();
    }

    function testRevertIfMintingIsFailed() public depositedCollateral {
        vm.startPrank(USER);

        tokenAddresses = [wbtc, weth];
        priceFeedAddresses = [btcUsdPriceFeed, ethUsdPriceFeed];

        MockFailedMintDSC mockdsc = new MockFailedMintDSC();
        DSCEngine mockdscengine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockdsc));
        mockdsc.transferOwnership(address(mockdscengine));

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);

        ERC20Mock(weth).approve(address(mockdscengine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MintingIsFailed.selector);
        mockdscengine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    ///////////////////////////////
    /// BURN DSC TEST /////////////
    ///////////////////////////////
    modifier depositedAndMintDSC() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscengine), AMOUNT_COLLATERAL);
        dscengine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
        _;
    }

    function testBurnAmountMustMoreThanZero() public depositedAndMintDSC {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscengine.burnDsc(0);
        vm.stopPrank();
    }

    function testCanBurnDSC() public depositedAndMintDSC {
        vm.startPrank(USER);
        dsc.approve(address(dscengine), amountToMint);
        dscengine.burnDsc(amountToMint);

        (, uint256 dscAmount) = dscengine.getAccountInformation(USER);
        assertEq(dscAmount, 0);
        vm.stopPrank();
    }

    ///////////////////////////////
    /// LIQUIDATE DSC TEST ////////
    ///////////////////////////////
    function testDebtToCoverAmountMustMoreThanZero() public depositedAndMintDSC {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscengine.liquidate(weth, USER, 0);
        vm.stopPrank();
    }

    function testRevertIfHealthFactorIsOkay() public depositedAndMintDSC {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine_HealthFactorOkay.selector);
        dscengine.liquidate(weth, USER, amountToMint);
        vm.stopPrank();
    }

    function testLiquidatorGetLiquidationPayout() public {
        //setup USER
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscengine), AMOUNT_COLLATERAL);
        dscengine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();

        // setup eth price drop & USER health factor low
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 healthFactor = dscengine.getHealthFactor(USER);
        console.log("USER Health Factor: ", healthFactor);

        // setup liquidator account
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscengine), collateralToCover);
        dscengine.depositCollateralAndMintDsc(weth, collateralToCover, amountToMint);

        uint256 liquidatorTokenBalanceInitial = ERC20Mock(weth).balanceOf(liquidator);
        uint256 dsceTokenBalanceInitial = ERC20Mock(weth).balanceOf(address(dscengine));

        dsc.approve(address(dscengine), amountToMint);
        dscengine.liquidate(weth, USER, amountToMint);

        uint256 liquidatorTokenBalance = ERC20Mock(weth).balanceOf(liquidator);
        uint256 dsceTokenBalance = ERC20Mock(weth).balanceOf(address(dscengine));

        uint256 tokenAmountFromDebtCovered = dscengine.getTokenAmountFromUSD(address(weth), amountToMint);
        uint256 LIQUIDATION_BONUS = dscengine.getLiquidationBonus();
        uint256 LIQUIDATION_PRECISION = dscengine.getLiquidationPrecision();
        uint256 liquidationBonus = tokenAmountFromDebtCovered * LIQUIDATION_BONUS / LIQUIDATION_PRECISION;
        uint256 expectedPayout = tokenAmountFromDebtCovered + liquidationBonus;

        assertEq(liquidatorTokenBalance, expectedPayout);
        vm.stopPrank();
    }
}
