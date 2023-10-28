// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
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
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {AutomationCompatible} from "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";
import {console} from "forge-std/console.sol";

contract Lottery is VRFConsumerBaseV2, AutomationCompatible {
    //** Errors */
    error Lottery__MustBetween1And99();
    error Lottery__NotEnoughEthSent();
    error Lottery__TransferFailed();
    error Lottery__OnlyOwner();
    error Lottery__NotOpen();
    error Lottery__UpkeepNotNeeded(uint256 timeLeft, uint256 lotteryState, bool hasPlayers);
    error Lottery__NoCommision();

    //** Type Declaration */
    enum LotteryState {
        OPEN,
        CALCULATING
    }

    //** State Varibales */
    uint16 private constant REQUEST_CONFIRMATIONS = 3; // Minimum
    uint32 private constant NUM_WORDS = 1;

    address private immutable i_owner;
    uint256 private immutable i_costOfATicket;
    uint256 private s_roundCount;
    uint256 private s_poolBalance;
    uint256 private s_commissionBalance;
    uint256 private immutable i_commisionRate;
    uint256 private immutable i_interval;

    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    LotteryState private s_lotteryState;
    uint256 private s_lastTimeStamp;
    bool private s_hasPlayers;

    mapping(uint256 => mapping(uint256 => address[])) private s_roundToSelectedNumToAddresses;
    mapping(uint256 => address[]) private s_roundToAllPlayers;
    mapping(uint256 => mapping(address => uint256[])) private s_roundToAddressToSelectedNumbers;
    mapping(uint256 => uint256) private s_roundToWinningNumer;

    //** Eevent */
    event PurchasedTicket(uint256 indexed round, address indexed player, uint256 indexed number);
    event DrawnLuckyNumber(uint256 indexed round, uint256 indexed luckyNumber);
    event SentPrizeToWinners(uint256 indexed round, address[] indexed winners, uint256 indexed prize);
    event ThisRoundNoWinners(uint256 indexed round);
    event RequestedRandomWords(uint256 indexed requestId);

    modifier onlyOwner() {
        if (msg.sender != i_owner) {
            revert Lottery__OnlyOwner();
        }
        _;
    }

    constructor(
        uint256 costOfATicket,
        uint256 commisionRate,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_costOfATicket = costOfATicket;
        i_commisionRate = commisionRate;
        i_interval = interval;

        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        i_owner = msg.sender;
        s_roundCount = 1;
        s_lotteryState = LotteryState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    function buyTicket(uint256 number) public payable {
        if (s_lotteryState != LotteryState.OPEN) {
            revert Lottery__NotOpen();
        }
        if (number < 1 || number > 99) {
            revert Lottery__MustBetween1And99();
        }
        if (msg.value < i_costOfATicket) {
            revert Lottery__NotEnoughEthSent();
        }
        s_hasPlayers = true;
        s_roundToSelectedNumToAddresses[s_roundCount][number].push(msg.sender);
        s_roundToAddressToSelectedNumbers[s_roundCount][msg.sender].push(number);
        s_roundToAllPlayers[s_roundCount].push(msg.sender);
        uint256 commision = (msg.value * i_commisionRate) / 100;
        s_commissionBalance += commision;
        s_poolBalance += (msg.value - commision);
        emit PurchasedTicket(s_roundCount, msg.sender, number);
    }

    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        // set the conditions
        // 1. time has passed
        // 2. state is open
        // 3. has players
        // 4. has balance

        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = s_lotteryState == LotteryState.OPEN;
        bool hasBalance = s_poolBalance > 0;

        // if upkeepNeeded == ture, performUpkeep will run
        upkeepNeeded = (timeHasPassed && isOpen && s_hasPlayers && hasBalance);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */ ) external override {
        // revalidating
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Lottery__UpkeepNotNeeded((block.timestamp - s_lastTimeStamp), uint256(s_lotteryState), s_hasPlayers);
        }
        // execute the logic
        s_lotteryState = LotteryState.CALCULATING;

        uint256 requestId = i_vrfCoordinator.requestRandomWords( // an unique address on each chain -> constructor()
            i_gasLane, // keyHash == gasLane: the max gas you want to spend, different from chain to chain -> constructor() -> bytes32
            i_subscriptionId, // get from the subscription manager by funding with "LINK" -> constructor() -> uint64
            REQUEST_CONFIRMATIONS, // how many confirmed blocks are good for you? -> constant -> uint16 -> 3
            i_callbackGasLimit, // the mas gas you want to spend for the "callback" function, different from chain to chain -> constructor() -> uint32
            NUM_WORDS // number of random numbers we need? -> constant -> uint32 -> 1
        );
        emit RequestedRandomWords(requestId);
    }

    function fulfillRandomWords(uint256, /* requestId */ uint256[] memory randomWords) internal override {
        uint256 luckyNumber = (randomWords[0] % 99) + 1;
        emit DrawnLuckyNumber(s_roundCount, luckyNumber);
        s_roundToWinningNumer[s_roundCount] = luckyNumber;

        s_lotteryState = LotteryState.OPEN;
        s_lastTimeStamp = block.timestamp;
        s_hasPlayers = false;
        uint256 numOfWinners = s_roundToSelectedNumToAddresses[s_roundCount][luckyNumber].length;
        if (numOfWinners > 0) {
            uint256 prize = s_poolBalance / numOfWinners;
            address[] memory winners = s_roundToSelectedNumToAddresses[s_roundCount][luckyNumber];

            for (uint256 i = 0; i < numOfWinners; i++) {
                address winner = winners[i];

                (bool success,) = winner.call{value: prize}("");
                if (!success) {
                    revert Lottery__TransferFailed();
                }
            }
            s_poolBalance = 0;

            emit SentPrizeToWinners(s_roundCount, winners, prize);
        } else {
            emit ThisRoundNoWinners(s_roundCount);
        }

        s_roundCount++;
    }

    function withdrawCommision() external onlyOwner {
        if (s_commissionBalance <= 0) {
            revert Lottery__NoCommision();
        }
        (bool success,) = i_owner.call{value: s_commissionBalance}("");
        if (!success) {
            revert Lottery__TransferFailed();
        }
        s_commissionBalance = 0;
    }

    //** Getter functions */
    function getRoundToSelectedNumToAddresses(uint256 round, uint256 number) external view returns (address[] memory) {
        return s_roundToSelectedNumToAddresses[round][number];
    }

    function getRoundToAddressToSelectedNumbers(uint256 round, address player)
        external
        view
        returns (uint256[] memory)
    {
        return s_roundToAddressToSelectedNumbers[round][player];
    }

    function getRoundToWinningNumber(uint256 round) external view returns (uint256) {
        return s_roundToWinningNumer[round];
    }

    function getPoolBalance() external view returns (uint256) {
        return s_poolBalance;
    }

    function getCommisionBalance() external view returns (uint256) {
        return s_commissionBalance;
    }

    function getTimeLeftToDraw() external view returns (uint256) {
        require((s_lastTimeStamp + i_interval) > block.timestamp, "Now is time to draw!");
        return ((s_lastTimeStamp + i_interval) - block.timestamp);
    }

    function getLotteryState() external view returns (LotteryState) {
        return s_lotteryState;
    }

    function getHasPlayers() external view returns (bool) {
        return s_hasPlayers;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRoundCount() external view returns (uint256) {
        return s_roundCount;
    }

    function getOwner() external view returns (address) {
        return i_owner;
    }
}
