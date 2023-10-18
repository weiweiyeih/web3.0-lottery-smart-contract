// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {Lottery} from "../src/Lottery.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mock/LinkToken.sol";

contract HelperConfig is Script {
    // 1. Build a struct & activeNetworkConfig;
    // 2. constructor()
    // 3. Set getSepoliaEthConfig()
    // 4. set getOrCreateAnvilEthConfig()
    //      1. check if activeNetworkConfig.vrfCoordinator not exists
    //      2. Deploy VRFCoordinatorV2Mock to get vrfCoordinator address
    //      3. NetworkConfig({})

    struct NetworkConfig {
        uint256 costOfATicket;
        uint256 commisionRate;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint64 subscriptionId;
        uint32 callbackGasLimit;
        address link;
        uint256 deployerKey;
    }

    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        NetworkConfig memory sepoliaConfig = NetworkConfig({
            costOfATicket: 0.0099 ether, // == USD15.45
            commisionRate: 5, // == 5%
            interval: 3600, // == 60 mins
            vrfCoordinator: 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625,
            gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c,
            subscriptionId: 0,
            callbackGasLimit: 500000,
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789, // from the docs
            deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });
        return sepoliaConfig;
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.vrfCoordinator != address(0)) {
            return activeNetworkConfig;
        }

        uint96 baseFee = 0.25 ether; // == 0.25 LINK
        uint96 gasPriceLink = 1e9; // == 1 gwei LINK
        vm.startBroadcast();
        VRFCoordinatorV2Mock vrfCoordinatorMock = new VRFCoordinatorV2Mock(baseFee, gasPriceLink);
        LinkToken linkToken = new LinkToken();
        vm.stopBroadcast();

        NetworkConfig memory anvilConfig = NetworkConfig({
            costOfATicket: 0.0099 ether, // USD15.45
            commisionRate: 5, // == 5%
            interval: 3600, // == 60 mins
            vrfCoordinator: address(vrfCoordinatorMock),
            gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c, // same to sepolia
            subscriptionId: 0,
            callbackGasLimit: 500000,
            link: address(linkToken), // from the imported mock
            deployerKey: DEFAULT_ANVIL_KEY
        });
        return anvilConfig;
    }
}
