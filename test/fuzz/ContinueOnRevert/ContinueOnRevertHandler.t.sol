// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "../../../lib/forge-std/src/Test.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {DecentralizedStablecoin} from "../../../src/DecentralizedStablecoin.sol";
import {ERC20Mock} from "../../../test/mocks/ERC20Mock.sol";

contract ContinueOnRevertHandler is Test {
    DecentralizedStablecoin dsc;
    DSCEngine dsce;

    address weth;
    address wbtc;

    uint256 public constant MAX_COLLATERAL_AMOUNT = type(uint96).max;

    constructor(DecentralizedStablecoin _dsc, DSCEngine _dsce) {
        dsc = _dsc;
        dsce = _dsce;

        address[] memory collateralToken = dsce.getCollateralToken();
        weth = collateralToken[0];
        wbtc = collateralToken[1];
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
        address collateralToken = _getCollateralToken(collateralSeed);
        uint256 collateralMaxToRedeem = dsce.getCollateralBalanceOfUser(msg.sender, collateralToken);
        amountCollateral = bound(amountCollateral, 0, collateralMaxToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        dsce.redeemCollateral(collateralToken, amountCollateral);
        vm.stopPrank();
    }

    function mintDsc(uint256 mintAmount) public {
        mintAmount = bound(mintAmount, 0, MAX_COLLATERAL_AMOUNT);
        vm.prank(msg.sender);
        dsce.mintDsc(mintAmount);
    }

    function burnDsc(uint256 burnAmount) public {
        burnAmount = bound(burnAmount, 0, dsc.balanceOf(msg.sender));
        dsce.burnDsc(burnAmount);
    }

    function liquadateDsc(uint256 collateralSeed, address liquidationAddress, uint256 liquidationAmount) public {
        address collateralToken = _getCollateralToken(collateralSeed);
        liquidationAmount = bound(liquidationAmount, 0, dsc.balanceOf(liquidationAddress));
        dsce.liquidate(collateralToken, liquidationAddress, liquidationAmount);
    }

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
