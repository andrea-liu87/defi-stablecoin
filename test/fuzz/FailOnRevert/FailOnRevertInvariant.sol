// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

// Invariants properties
// 1. Total supply of collateral > total supply DSC
// 2. Getter view function nver revert

import {Test, console} from "../../../lib/forge-std/src/Test.sol";
import {StdInvariant} from "../../../lib/forge-std/src/StdInvariant.sol";
import {DeployDecentralizedStablecoin} from "../../../script/DeployDecentralizedStablecoin.s.sol";
import {DecentralizedStablecoin} from "../../../src/DecentralizedStablecoin.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {FailOnRevert} from "../../fuzz/FailOnRevert/FailOnRevert.t.sol";

contract OpenInvariantTest is StdInvariant, Test {
    DeployDecentralizedStablecoin deployer;
    DecentralizedStablecoin public dsc;
    DSCEngine public dscengine;
    HelperConfig public config;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;

    function setUp() public {
        deployer = new DeployDecentralizedStablecoin();
        (dsc, dscengine, config) = deployer.run();

        (btcUsdPriceFeed, ethUsdPriceFeed, wbtc, weth,) = config.activeNetworkConfig();
        FailOnRevert handler = new FailOnRevert(dsc, dscengine);
        targetContract(address(handler));
    }

    function invariant_testProtocolValueGreaterThanDSC_SOR() public {
        uint256 totalDSCValue = DecentralizedStablecoin(dsc).totalSupply();

        uint256 totalwethValue = IERC20(weth).balanceOf(address(dscengine));
        uint256 totalwethValueInUSD = dscengine.getUSDValue(weth, totalwethValue);

        uint256 totalwbtcValue = IERC20(wbtc).balanceOf(address(dscengine));
        uint256 totalwbtcValueInUSD = dscengine.getUSDValue(wbtc, totalwbtcValue);

        console.log("wethValue: %s", totalwethValueInUSD);
        console.log("wbtcValue: %s", totalwbtcValueInUSD);
        console.log("totalSupply: %s", totalDSCValue);

        assert((totalwbtcValueInUSD + totalwethValueInUSD) >= totalDSCValue);
    }

    function invariant_testGetterMustNeverRevert() public {
        dscengine.getAdditionalFeedPrecision();
        dscengine.getCollateralToken();
        dscengine.getLiquidationBonus();
        dscengine.getLiquidationThreshold();
        dscengine.getMinHealthFactor();
        dscengine.getPrecision();
    }
}
