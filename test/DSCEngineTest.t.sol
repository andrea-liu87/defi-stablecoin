// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployDecentralizedStablecoin} from "../script/DeployDecentralizedStablecoin.s.sol";
import {DecentralizedStablecoin} from "../src/DecentralizedStablecoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

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
        uint256 expectedWeth = usdAmount/ETH_USD_PRICE;
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
        ERC20Mock ranToken = new ERC20Mock("RAN",  "RAN", USER, AMOUNT_COLLATERAL);

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

// bool success = IERC20(tokenAddressForCollateral).transferFrom(
//             msg.sender,
//             address(this),
//             amount
//         );
    function testDepositTransferredToDSCE() public depositedCollateral {
        assertEq(IERC20(weth).balanceOf(address(dscengine)), AMOUNT_COLLATERAL);
    }
}
