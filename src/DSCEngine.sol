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
import {AggregatorV3Interface} from
    "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console} from "../lib/forge-std/src/console.sol";

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
    error DSCEngine_HealthFactorOkay();
    error DSCEngine_HealthFactorNotImproving();

    mapping(address tokenAddresses => address priceFeed) private s_tokenAllowedForCollateral;
    DecentralizedStablecoin private i_dsc;
    mapping(address userAddress => mapping(address tokenAddress => uint256 amount)) private s_collateralDeposit;
    mapping(address userAddress => uint256) private s_dsc;
    address[] private s_collateralTokens;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant HEALTHFACTOR_THRESHOLD = 50; //200% COLLATERAL VALUE
    uint256 private constant HEALTHFACTOR_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant LIQUIDATION_PRECISION = 100;

    ///////////////////////
    /// Events ///////////
    //////////////////////
    event CollateralDeposited(address, address, uint256);
    event CollateralRedeemed(
        address indexed tokenCollateralAddress, uint256 indexed amountRedeemed, address from, address to
    );

    //////////////////////
    /// Modifier ////////
    ////////////////////
    modifier mustMoreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_tokenAllowedForCollateral[tokenAddress] == address(0)) {
            revert DSCEngine__TokenIsNotAllowed();
        }
        _;
    }

    //////////////////////
    /// Function ////////
    ////////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscContractAddres) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_tokenAllowedForCollateral[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStablecoin(dscContractAddres);
    }

    /**
     *
     * @param tokenAddressForCollateral address for collateral token
     * @param amount amount token to be deposit as collateral
     * @param amountToBeMinted DSC amount to be minted
     * This function will deposit wETH or wBTC as collateral and mint DSC
     */
    function depositCollateralAndMintDsc(address tokenAddressForCollateral, uint256 amount, uint256 amountToBeMinted)
        external
    {
        depositCollateral(tokenAddressForCollateral, amount);
        mintDsc(amountToBeMinted);
    }

    /**
     *
     * @param tokenAddressForCollateral Token address for collateral deposit
     * @param amount Amount of token deposited
     */
    function depositCollateral(address tokenAddressForCollateral, uint256 amount)
        public
        mustMoreThanZero(amount)
        isAllowedToken(tokenAddressForCollateral)
        nonReentrant
    {
        s_collateralDeposit[msg.sender][tokenAddressForCollateral] += amount;
        emit CollateralDeposited(msg.sender, tokenAddressForCollateral, amount);

        bool success = IERC20(tokenAddressForCollateral).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc(uint256 dscAmount, address collateralTokenAddress, uint256 amountToBeRedeem)
        external
    {
        _burnDsc(dscAmount, msg.sender, msg.sender);
        _redeemCollateral(collateralTokenAddress, amountToBeRedeem, msg.sender, msg.sender);
        _revertIfHealthFactorTooLow(msg.sender);
    }

    function redeemCollateral(address collateralTokenAddress, uint256 amountToBeRedeem)
        public
        mustMoreThanZero(amountToBeRedeem)
        nonReentrant
    {
        _redeemCollateral(collateralTokenAddress, amountToBeRedeem, msg.sender, msg.sender);
        _revertIfHealthFactorTooLow(msg.sender);
    }

    /**
     * @param amountToBeMinted The amount of DSC that user intended to be minted
     * You can only mint DSC if you have  enough collateral
     */
    function mintDsc(uint256 amountToBeMinted) public mustMoreThanZero(amountToBeMinted) nonReentrant {
        s_dsc[msg.sender] += amountToBeMinted;
        _revertIfHealthFactorTooLow(msg.sender);
        bool mint = i_dsc.mint(msg.sender, amountToBeMinted);
        if (!mint) {
            revert DSCEngine__MintingIsFailed();
        }
    }

    function burnDsc(uint256 amount) external mustMoreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorTooLow(msg.sender);
    }

    /*
    * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
    * This is collateral that you're going to take from the user who is insolvent.
    * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
    * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
    * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
    *
    * @notice: You can partially liquidate a user.
    * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
    * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
    to work.
    * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
    anyone.
    * For example, if the price of the collateral plummeted before anyone could be liquidated.
    */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        mustMoreThanZero(debtToCover)
        nonReentrant
    {
        uint256 healthFactor = _getHealthFactor(user);
        if (healthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine_HealthFactorOkay();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(collateral, debtToCover);
        uint256 liquidationBonus = tokenAmountFromDebtCovered * LIQUIDATION_BONUS / LIQUIDATION_PRECISION;
        uint256 totalCollateralRedeemed = tokenAmountFromDebtCovered + liquidationBonus;
        _redeemCollateral(collateral, totalCollateralRedeemed, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _getHealthFactor(user);
        if (endingUserHealthFactor <= healthFactor) {
            revert DSCEngine_HealthFactorNotImproving();
        }
        _revertIfHealthFactorTooLow(msg.sender);
    }

    ////////////////////////////////////////
    /// Private & Internal Function ////////
    ///////////////////////////////////////
    function _revertIfHealthFactorTooLow(address user) internal view {
        uint256 healthFactor = _getHealthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
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
    function _getHealthFactor(address user) private view returns (uint256) {
        (uint256 totalCollateralValue, uint256 dscAmount) = _getAccountInformation(user);
        if (dscAmount == 0) return type(uint256).max;
        //10e18*0.5* 1e18 / 2e20 =
        uint256 collateralValueAdjusted = (totalCollateralValue * HEALTHFACTOR_THRESHOLD) / HEALTHFACTOR_PRECISION;
        uint256 healthFactor = (collateralValueAdjusted * PRECISION) / dscAmount;
        return healthFactor;
    }

    /**
     *
     * @param user user address
     * @return totalCollateralValue total collateral value in USD
     * @return dscAmount DSC amount the user had
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalCollateralValue, uint256 dscAmount)
    {
        dscAmount = s_dsc[user];
        totalCollateralValue = getTotalCollateralValueInUSD(user);
        return (totalCollateralValue, dscAmount);
    }

    function _redeemCollateral(address collateralTokenAddress, uint256 amountToBeRedeem, address from, address to)
        private
    {
        s_collateralDeposit[from][collateralTokenAddress] -= amountToBeRedeem;
        emit CollateralRedeemed(collateralTokenAddress, amountToBeRedeem, from, to);
        bool success = IERC20(collateralTokenAddress).transfer(to, amountToBeRedeem);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @dev low level function. Not to called bofere checking Health Factor
     * @param amount Amount DSC tobe burnt
     */
    function _burnDsc(uint256 amount, address onBehalf, address dscFrom) private {
        s_dsc[onBehalf] -= amount;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
    }

    ////////////////////////////////////////
    /// Public & External View Function ////////
    ///////////////////////////////////////
    function getTokenAmountFromUSD(address token, uint256 amount) public view returns (uint256) {
        (, int256 priceFeed,,,) = AggregatorV3Interface(s_tokenAllowedForCollateral[token]).latestRoundData();
        return amount / (uint256(priceFeed) * ADDITIONAL_FEED_PRECISION) * PRECISION;
    }

    function getTotalCollateralValueInUSD(address user) public view returns (uint256 totalValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 collateralAmount = s_collateralDeposit[user][token];
            totalValueInUsd += getUSDValue(token, collateralAmount);
        }
        return totalValueInUsd;
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        (, int256 priceFeed,,,) = AggregatorV3Interface(s_tokenAllowedForCollateral[token]).latestRoundData();
        return (uint256(priceFeed) * amount * ADDITIONAL_FEED_PRECISION) / PRECISION;
    }

    ///////////////////////
    ////// GETTER ////////
    //////////////////////

    function getAccountInformation(address user) public returns (uint256 totalCollateralValue, uint256 dscAmount) {
        return _getAccountInformation(user);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposit[user][token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _getHealthFactor(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return HEALTHFACTOR_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }
}
