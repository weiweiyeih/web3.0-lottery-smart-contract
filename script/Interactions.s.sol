// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mock/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

// 1. CreateSubscription
// 2. FundSubscription
// 3. AddConsumer

/**
 *  uint256 costOfATicket;
 *     uint256 commisionRate;
 *     uint256 interval;
 *     address vrfCoordinator;
 *     bytes32 gasLane;
 *     uint64 subscriptionId;
 *     uint32 callbackGasLimit;
 *     address link;
 *     uint256 deployerKey;
 */

contract CreateSubscription is Script {
    // 1. kick off
    function run() external returns (uint64) {
        return createSubscriptionUsingConfig();
    }

    // 2. get the required args
    function createSubscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (,,, address vrfCoordinator,,,,, uint256 deployerKey) = helperConfig.activeNetworkConfig();
        return createSubscription(vrfCoordinator, deployerKey);
    }

    // 3. call the function on the VRFCoordinator
    function createSubscription(address vrfCoordinator, uint256 deployerKey) public returns (uint64) {
        vm.startBroadcast(deployerKey);
        uint64 subId = VRFCoordinatorV2Mock(vrfCoordinator).createSubscription();
        vm.stopBroadcast();
        return subId;
    }
}

contract FundSubscription is Script {
    uint96 public constant FUND_AMOUNT = 3 ether;

    // 1. kick off
    function run() external {
        return fundSubscriptionUsingConfig();
    }

    // 2. get the required args
    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        (,,, address vrfCoordinator,, uint64 subscriptionId,, address link, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();
        return fundSubscription(vrfCoordinator, subscriptionId, link, deployerKey);
    }

    // 3. call the function on the VRFCoordinator
    function fundSubscription(address vrfCoordinator, uint64 subscriptionId, address link, uint256 deployerKey)
        public
    {
        if (block.chainid == 31337) {
            // Anvil
            vm.startBroadcast(deployerKey);
            VRFCoordinatorV2Mock(vrfCoordinator).fundSubscription(subscriptionId, FUND_AMOUNT);
            vm.stopBroadcast();
        } else {
            // sepolia
            // need LINK address -> refactory HelperConfig.s.sol
            vm.startBroadcast(deployerKey);
            LinkToken(link).transferAndCall(vrfCoordinator, FUND_AMOUNT, abi.encode(subscriptionId));
            vm.stopBroadcast();
        }
    }
}

contract AddConsumer is Script {
    function run() external {
        // need consumer contract address, which cannot get from HelperConfig.s.sol
        // -> most recent deployed contract -> devopsTool
        // -> forge install Cyfrin/foundry-devops --no-commit
        address lottery = DevOpsTools.get_most_recent_deployment("Lottery", block.chainid);
        addConsumerUsingConfig(lottery);
    }

    function addConsumerUsingConfig(address consumer) public {
        HelperConfig helperConfig = new HelperConfig();
        (,,, address vrfCoordinator,, uint64 subscriptionId,,, uint256 deployerKey) = helperConfig.activeNetworkConfig();
        addConsumer(vrfCoordinator, subscriptionId, consumer, deployerKey);
    }

    function addConsumer(address vrfCoordinator, uint64 subscriptionId, address consumer, uint256 deployerKey) public {
        vm.startBroadcast(deployerKey);
        VRFCoordinatorV2Mock(vrfCoordinator).addConsumer(subscriptionId, consumer);
        vm.stopBroadcast();
    }
}
