// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {DeployDecentralizedStablecoin} from "../script/DeployDecentralizedStablecoin.s.sol";
import {DecentralizedStablecoin} from "../src/DecentralizedStablecoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract DSCTest is Test {
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
          
          assert(keccak256(abi.encodePacked(dscContract.name())) ==  keccak256(abi.encodePacked(name)));
     }

//      function testIfAmountIsZeroCantBurn() public {
//           address owner = msg.sender;
//           vm.prank(owner);

//           vm.expectRevert(DecentralizedStablecoin.DecentralizedStablecoin_AmountMustNotBe0.selector);
//           dscContract.burn(0);
//      }

//      function testAmountToBurnShouldNotLessThanBalance() public {
//         address owner = msg.sender;
//         vm.prank(owner);
       
//         dscContract.mint(USER, 100);

//         vm.expectRevert(DecentralizedStablecoin.DecentralizedStablecoin_AmountMoreThanBalance.selector);
//         //vm.prank(owner);
//         dscContract.burn(101);
//     }

//      function testCanMintAndHaveBalance() public {
//         address owner = msg.sender;
//         vm.prank(owner);
       
//         bool tokenId = dscContract.mint(USER, 1);

//         assert(dscContract.balanceOf(USER) == 1);
//         assert(tokenId == true);
//     }
}