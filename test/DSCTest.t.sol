// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {StdCheats} from "../lib/forge-std/src/StdCheats.sol";
import {DeployDecentralizedStablecoin} from "../script/DeployDecentralizedStablecoin.s.sol";
import {DecentralizedStablecoin} from "../src/DecentralizedStablecoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract DSCTest is StdCheats, Test {
    DeployDecentralizedStablecoin public deployer;
    DecentralizedStablecoin public dscContract;
    DSCEngine public dscengine;
    HelperConfig public config;

    address public USER = makeAddr("user");

    function setUp() public {
        deployer = new DeployDecentralizedStablecoin();
        (dscContract, dscengine, config) = deployer.run();
    }

    function testName() public {
        string memory name = "DecentralizedStablecoin";

        assert(keccak256(abi.encodePacked(dscContract.name())) == keccak256(abi.encodePacked(name)));
    }

    function testIfAmountIsZeroCantBurn() public {
        vm.prank(dscContract.owner());

        vm.expectRevert(DecentralizedStablecoin.DecentralizedStablecoin_AmountMustNotBe0.selector);
        dscContract.burn(0);
    }

    function testAmountToBurnShouldNotLessThanBalance() public {
        address owner = dscContract.owner();
        vm.startPrank(owner);

        dscContract.mint(USER, 100);

        vm.expectRevert(DecentralizedStablecoin.DecentralizedStablecoin_AmountMoreThanBalance.selector);
        dscContract.burn(101);
        vm.stopPrank();
    }

    function testCanMintAndHaveBalance() public {
        address owner = dscContract.owner();
        vm.prank(owner);

        bool tokenId = dscContract.mint(USER, 1);

        assert(dscContract.balanceOf(USER) == 1);
        assert(tokenId == true);
    }
}
