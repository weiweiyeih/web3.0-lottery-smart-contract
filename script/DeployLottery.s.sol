// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Lottery} from "../src/Lottery.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";

contract DeployLottery is Script {
    HelperConfig public helperConfig;
    Lottery public lottery;

    function run() external returns (Lottery, HelperConfig) {
        helperConfig = new HelperConfig();
        (
            uint256 costOfATicket,
            uint256 commisionRate,
            uint256 interval,
            address vrfCoordinator,
            bytes32 gasLane,
            uint64 subscriptionId,
            uint32 callbackGasLimit,
            address link,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        if (subscriptionId == 0) {
            // CreateSubscription
            CreateSubscription createSubscription = new CreateSubscription();
            subscriptionId = createSubscription.createSubscription(vrfCoordinator, deployerKey);

            // FundSubscription
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(vrfCoordinator, subscriptionId, link, deployerKey);
        }

        vm.startBroadcast();
        lottery = new Lottery(
             costOfATicket,
             commisionRate,
             interval,
             vrfCoordinator,
             gasLane,
             subscriptionId,
             callbackGasLimit
             );
        vm.stopBroadcast();

        // AddConsumer
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(vrfCoordinator, subscriptionId, address(lottery), deployerKey);

        return (lottery, helperConfig);
    }
}
