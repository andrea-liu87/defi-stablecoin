// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

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

import {ERC20Burnable, ERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/*
 * @title DecentralizedStablecoin
 * @author Andrea Liu 
 * @created at Aug 2025
 * Collateral : Exogenous (ETH & BTC)
 * Minting : Algorithmic
 * Relative stability : Pegged to USD
 * 
 * This is the contract meant to be governed by DSCEngine. This contract is just
 * the ERC20 implementation of stablecoin system.
 */
contract DecentralizedStablecoin is ERC20Burnable, Ownable {
    error DecentralizedStablecoin_AmountMustNotBe0();
    error DecentralizedStablecoin_AmountMoreThanBalance();
    error DecentralizedStablecoin_AddressIsZero();

    constructor() Ownable(msg.sender) ERC20("DecentralizedStablecoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            revert DecentralizedStablecoin_AmountMustNotBe0();
        }

        if (_amount > balance) {
            revert DecentralizedStablecoin_AmountMoreThanBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStablecoin_AddressIsZero();
        }

        if (_amount <= 0) {
            revert DecentralizedStablecoin_AmountMustNotBe0();
        }
        _mint(_to, _amount);
        return true;
    }
}
