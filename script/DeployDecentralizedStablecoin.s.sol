// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStablecoin} from "../src/DecentralizedStablecoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract DeployDecentralizedStablecoin is Script {
    address[] tokenAddress;
    address[] pricefeedAddress;

    function run() external returns (DecentralizedStablecoin, DSCEngine, HelperConfig) {
        HelperConfig helperconfig = new HelperConfig();
        (address priceFeedwBtc, address priceFeedwETH, address wBTC, address wETH, uint256 deployerKey) =
            helperconfig.activeNetworkConfig();

        tokenAddress = [wBTC, wETH];
        pricefeedAddress = [priceFeedwBtc, priceFeedwETH];

        vm.startBroadcast(deployerKey);
        DecentralizedStablecoin decentralizedStablecoin = new DecentralizedStablecoin();
        DSCEngine dscEngine = new DSCEngine(tokenAddress, pricefeedAddress, address(decentralizedStablecoin));
        decentralizedStablecoin.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
        return (decentralizedStablecoin, dscEngine, helperconfig);
    }
}
