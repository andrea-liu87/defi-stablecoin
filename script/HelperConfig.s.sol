// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    uint8 public constant DECIMALS = 8;
int256 public constant ETH_USD_PRICE = 2000e8;
int256 public constant BTC_USD_PRICE = 1000e8;

    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig{
        address priceFeedwBtc;
        address priceFeedwETH;
        address wBTC;
        address wETH;
        uint256 privateKey;
    }

    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor(){
        if(block.chainid == 11155111){
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaConfig() public view returns (NetworkConfig memory networkConfig){
        networkConfig = NetworkConfig({
            priceFeedwBtc: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            priceFeedwETH: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wBTC: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            wETH: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            privateKey: vm.envUint("PRIVATE_KEY")
        });
        return networkConfig;
    }

    function getOrCreateAnvilConfig() public returns(NetworkConfig memory localConfig){
        if (activeNetworkConfig.priceFeedwETH != address(0)){
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator wETHPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wETH = new ERC20Mock("wETH", "wETH", msg.sender, 1000e8);
        MockV3Aggregator wBTCPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock wBTC = new ERC20Mock("wBTC", "wBTC", msg.sender, 1000e8);
        vm.stopBroadcast();

        localConfig = NetworkConfig({
            priceFeedwBtc: address(wBTCPriceFeed),
            priceFeedwETH: address(wETHPriceFeed),
            wBTC: address(wBTC),
            wETH: address(wETH),
            privateKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
        return localConfig;
    }
}