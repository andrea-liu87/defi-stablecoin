// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {AggregatorV3Interface} from
    "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title Oracle Lib
 * @author Andrea Liu
 * @notice This library will check Oracle Chainlink for any stale data.
 * If a price is stale, function will revert and render DSCEngine is unsuable - this is by design
 * We want the DSCEngine freeze is the price is stale
 */
library OracleLib {
    //ERROR
    error OracleLib_ErrorStaleData();

    uint256 public constant TIMEOUT = 3 hours;

    function checkStaleLatestRoundData(AggregatorV3Interface pricefeed)
        public
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, answer, startedAt, updatedAt, answeredInRound) = pricefeed.latestRoundData();

        uint256 timePassed = block.timestamp - updatedAt;
        if (timePassed > TIMEOUT) {
            revert OracleLib_ErrorStaleData();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
