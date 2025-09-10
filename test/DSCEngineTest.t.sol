// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDecentralizedStablecoin} from "../script/DeployDecentralizedStablecoin.s.sol";
import {DecentralizedStablecoin} from "../src/DecentralizedStablecoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

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
    }

    ///////////////////////////////
    /// PRICEFEED TEST ////////////
    ///////////////////////////////

    function testUSDValue() public {
        uint256 ETH_USD_PRICE = 2000;
        uint256 ethAmount = 15e18;
        uint256 expectedValue = ethAmount*ETH_USD_PRICE;
        uint256 actualValue = dscengine.getUSDValue(weth, ethAmount);
        assertEq(expectedValue, actualValue);
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
}