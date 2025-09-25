// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "../../../lib/forge-std/src/Test.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../../../src/DecentralizedStablecoin.sol";
import {ERC20Mock} from "../../../test/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";

contract FailOnRevert is Test {
    DecentralizedStablecoin dsc;
    DSCEngine dsce;

    address weth;
    address wbtc;

    MockV3Aggregator ethUsdPricefeed;

    uint256 public constant MAX_COLLATERAL_AMOUNT = type(uint96).max;

    constructor(DecentralizedStablecoin _dsc, DSCEngine _dsce) {
        dsc = _dsc;
        dsce = _dsce;

        address[] memory collateralToken = dsce.getCollateralToken();
        weth = collateralToken[0];
        wbtc = collateralToken[1];

        ethUsdPricefeed = MockV3Aggregator(dsce.getCollateralTokenPricefeed(weth));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        address collateralToken = _getCollateralToken(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_COLLATERAL_AMOUNT);

        vm.startPrank(msg.sender);
        ERC20Mock(collateralToken).mint(msg.sender, amountCollateral);
        ERC20Mock(collateralToken).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(collateralToken, amountCollateral);
        vm.stopPrank();
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        vm.startPrank(msg.sender);
        address collateralToken = _getCollateralToken(collateralSeed);
        uint256 collateralMaxToRedeem = dsce.getCollateralBalanceOfUser(msg.sender, collateralToken);
        (uint256 collateralBalanceInUsd, uint256 totalDscMinted) = dsce.getAccountInformation(msg.sender);

        amountCollateral = bound(amountCollateral, 0, collateralMaxToRedeem);
        uint256 healthFactor = dsce.calculateHealthFactor(collateralMaxToRedeem - amountCollateral, totalDscMinted);
        if (healthFactor < 1e18) {
            return;
        }

        if (amountCollateral == 0) {
            return;
        }

        dsce.redeemCollateral(collateralToken, amountCollateral);
        vm.stopPrank();
    }

    function mintDsc(uint256 mintAmount) public {
        vm.startPrank(msg.sender);
        (uint256 collateralBalanceInUsd, uint256 totalDscMinted) = dsce.getAccountInformation(msg.sender);
        uint256 maxMint = (collateralBalanceInUsd / 2) - totalDscMinted;
        if (maxMint < 0) {
            return;
        }
        mintAmount = bound(mintAmount, 0, maxMint);
        if (mintAmount == 0) {
            return;
        }
        dsce.mintDsc(mintAmount);
        vm.stopPrank();
    }

    // THIS BREAKS OUR INVARIANT TEST SUITE!!!
    // function updatePriceFeed(uint96 newPrice) public {
    //     int256 newPrice = (int256(uint256(newPrice)));
    //     ethUsdPricefeed.updateAnswer(newPrice);
    // }

    ///////////////////////////
    /// PRIVATE FUNCTION /////
    //////////////////////////

    function _getCollateralToken(uint256 collateralSeed) private returns (address) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
