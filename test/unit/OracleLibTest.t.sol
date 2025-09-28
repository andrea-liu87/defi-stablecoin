// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";
import {AggregatorV3Interface} from
    "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {DeployDecentralizedStablecoin} from "../../script/DeployDecentralizedStablecoin.s.sol";
import {DecentralizedStablecoin} from "../../src/DecentralizedStablecoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract OracleLibTest is Test {
    DeployDecentralizedStablecoin deployer;
    DecentralizedStablecoin public dsc;
    DSCEngine public dscengine;
    HelperConfig public config;

    address ethUsdPricefeed;
    MockV3Aggregator public aggregator;
    uint8 public constant DECIMALS = 8;
    int256 public constant INITAL_PRICE = 2000 ether;

    uint256 public constant TIMEOUT = 4 hours;

    using OracleLib for AggregatorV3Interface;

    function setUp() external {
        //  deployer = new DeployDecentralizedStablecoin();
        // (dsc, dscengine, config) = deployer.run();

        // (, ethUsdPricefeed, , , ) = config.activeNetworkConfig();
        aggregator = new MockV3Aggregator(DECIMALS, INITAL_PRICE);
    }

    function testIfTimePassedTimeoutIsRevert() public {
        AggregatorV3Interface(address(aggregator)).latestRoundData();
        vm.warp(block.timestamp + TIMEOUT);
        vm.expectRevert(OracleLib.OracleLib_ErrorStaleData.selector);
        AggregatorV3Interface(address(aggregator)).checkStaleLatestRoundData();
    }
}
