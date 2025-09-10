// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.19;

import {DecentralizedStablecoin} from "../src/DecentralizedStablecoin.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Andrea Liu
 * createdAt August 2025
 * 
 * The system is designed to be as minimal as possible, and the token is maintain to be 
 * 1 token == $1 pegged.
 * 
 * The engine has properties :
 * - Exogenous Collateral
 * - Algorithmic Stability
 * - Dollar Pegged
 * 
 * It is similar to DAI, when DAI no governance, no fess only backed by wETH & wBTC collateral.
 * 
 * Our DSC system should always be "overcollateralized". At all point the collateral value
 * should always be greater than the DSC values.
 * 
 * @notice This contract is the core of DSC System. It handles all algorithmic of minting,
 * redeeming DSC as well as depositing and withdrawing collateral.
 */
contract DSCEngine is ReentrancyGuard {
    //////////////////////
    /// Error //////// 
    ////////////////////
    error DSCEngine__MustBeMoreThanZero(); 
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenIsNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreakHealthFactor(uint256);
    error DSCEngine__MintingIsFailed();

    mapping (address tokenAddresses => address priceFeed) private s_tokenAllowedForCollateral;
    DecentralizedStablecoin private i_dsc;
    mapping (address userAddress => mapping(address tokenAddress => uint256 amount)) private s_collateralDeposit;
    mapping (address userAddress => uint256) private s_dsc;
    address[] private s_collateralTokens;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant HEALTHFACTOR_THRESHOLD = 50; //200% COLLATERAL VALUE
    uint256 private constant HEALTHFACTOR_PRECISION = 100;

    ///////////////////////
    /// Events ///////////
    //////////////////////
    event CollateralDeposited(address, address, uint256);
    
    
    //////////////////////
    /// Modifier //////// 
    //////////////////// 
    modifier mustMoreThanZero(uint256 amount) {
        if(amount <= 0){
            revert DSCEngine__MustBeMoreThanZero();
        }   
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if(s_tokenAllowedForCollateral[tokenAddress] == address(0)){
            revert DSCEngine__TokenIsNotAllowed();
        }
        _;
    }

////////////////////// 
/// Function //////// 
////////////////////
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscContractAddres){
            if(tokenAddresses.length != priceFeedAddresses.length){
                revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
            }
            for (uint256 i=0; i < tokenAddresses.length; i++){
                s_tokenAllowedForCollateral[tokenAddresses[i]] = priceFeedAddresses[i];
                s_collateralTokens.push(tokenAddresses[i]);
            }
            i_dsc = DecentralizedStablecoin(dscContractAddres);
        }

    function depositCollateralAndMintDsc() external {}

/**
 * 
 * @param tokenAddressForCollateral Token address for collateral deposit
 * @param amount Amount of token deposited
 */
    function depositCollateral(
        address tokenAddressForCollateral, 
        uint256 amount
    ) external mustMoreThanZero(amount)
    isAllowedToken(tokenAddressForCollateral)
    nonReentrant {
        s_collateralDeposit[msg.sender][tokenAddressForCollateral] += amount;
        emit CollateralDeposited(msg.sender, tokenAddressForCollateral, amount);

        bool success = IERC20(tokenAddressForCollateral).transferFrom(msg.sender, address(this), amount);
        if (!success){
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /**
     * @param amountToBeMinted The amount of DSC that user intended to be minted
     * You can only mint DSC if you have  enough collateral
     */
    function mintDsc(uint256 amountToBeMinted) external 
    mustMoreThanZero(amountToBeMinted)
    nonReentrant {
        s_dsc[msg.sender] += amountToBeMinted;
        _revertIfHealthFactorTooLow(msg.sender);
        bool mint = i_dsc.mint(msg.sender, amountToBeMinted);
        if (!mint){
            revert DSCEngine__MintingIsFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}
    
    function getHealthFactor() external view {}

//////////////////////////////////////// 
/// Private & Internal Function //////// 
///////////////////////////////////////
function _revertIfHealthFactorTooLow(address user) internal view {
    uint256 healthFactor = _getHealthFactor(user);
    if (healthFactor < 1){
        revert DSCEngine__BreakHealthFactor(healthFactor);
    }
}

/**
 * Based on AAVE documentation 
 * Health Factor = (Total Collateral Value * Weighted Average Liquidation Threshold) / Total Borrow Value
 * 
 * Returns how close to liquidation a user is
 * If a user goes below 1, then they can be liquidated.
 */
function _getHealthFactor(address user) private view returns(uint256){
    (uint256 totalCollateralValue, uint256 dscAmount) = _getAccountInformation(user);
    uint256 collateralValueAdjusted = totalCollateralValue*HEALTHFACTOR_THRESHOLD /HEALTHFACTOR_PRECISION;
    uint256 healthFactor = collateralValueAdjusted*PRECISION / dscAmount;
    return healthFactor;
}

function _getAccountInformation(address user) private view returns(uint256 totalCollateralValue, uint256 dscAmount){
    dscAmount = s_dsc[user];
    totalCollateralValue = getTotalCollateralValue(user);
    return (totalCollateralValue, dscAmount);
}

//////////////////////////////////////// 
/// Public & External View Function //////// 
///////////////////////////////////////
function getTotalCollateralValue(address user) public view returns(uint256 totalValueInUsd){
    for (uint256 i=0; i<s_collateralTokens.length; i++){
        address token = s_collateralTokens[i];
        uint256 collateralAmount = s_collateralDeposit[user][token];
        totalValueInUsd += getUSDValue(token, collateralAmount);
    }
    return totalValueInUsd;
}

function getUSDValue(address token, uint256 amount) public view returns(uint256) {
    (,int256 priceFeed,,,) = AggregatorV3Interface(s_tokenAllowedForCollateral[token]).latestRoundData();
    return uint256(priceFeed)*amount*ADDITIONAL_FEED_PRECISION/PRECISION;
}
}