// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {Lottery} from "../../src/Lottery.sol";
import {DeployLottery} from "../../script/DeployLottery.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

contract RaffleTest is Test {
    //** Evevnts */
    event PurchasedTicket(uint256 indexed round, address indexed player, uint256 indexed number);
    event SentPrizeToWinners(uint256 indexed round, address[] indexed winners, uint256 indexed prize);
    event ThisRoundNoWinners(uint256 indexed round);

    DeployLottery public deployer;
    Lottery public lottery;
    HelperConfig public helperConfig;

    uint256 public costOfATicket;
    uint256 public commisionRate;
    uint256 public interval;
    address public vrfCoordinator;
    bytes32 public gasLane;
    uint64 public subscriptionId;
    uint32 public callbackGasLimit;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        deployer = new DeployLottery();
        (lottery, helperConfig) = deployer.run();
        (costOfATicket, commisionRate, interval, vrfCoordinator, gasLane, subscriptionId, callbackGasLimit,,) =
            helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    ////////////////////////
    /// buyTicket         //
    ////////////////////////

    function testBuyTicketRevertsIfLotteryStateNotOpen(uint256 number1, uint256 number2) public {
        number1 = bound(number1, 1, 99);
        number2 = bound(number2, 1, 99);
        vm.prank(PLAYER);
        lottery.buyTicket{value: costOfATicket}(number1);
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        lottery.performUpkeep("");

        vm.prank(PLAYER);
        vm.expectRevert(Lottery.Lottery__NotOpen.selector);
        lottery.buyTicket{value: costOfATicket}(number2);
    }

    function testBuyTicketRevertsIfNumberOutOfRange(uint256 number) public {
        vm.assume(number < 1 || number > 99);
        vm.prank(PLAYER);
        vm.expectRevert(Lottery.Lottery__MustBetween1And99.selector);
        lottery.buyTicket{value: costOfATicket}(number);
    }

    function testBuyTicketRevertsIfNotSentEnoughEth(uint256 number, uint256 etherSent) public {
        number = bound(number, 1, 99);
        vm.assume(etherSent < costOfATicket);
        vm.prank(PLAYER);
        vm.expectRevert(Lottery.Lottery__NotEnoughEthSent.selector);
        lottery.buyTicket{value: etherSent}(number);
    }

    function testBuyTicketUpdatesRoundToSelectedNumToAddresses(uint256 number) public {
        number = bound(number, 1, 99);
        vm.prank(PLAYER);
        lottery.buyTicket{value: costOfATicket}(number);
        address[] memory players = lottery.getRoundToSelectedNumToAddresses(1, number);
        assertEq(players[0], PLAYER);
    }

    function testBuyTicketUpdatesPoolBalanceAndCommisionBalance(uint256 number) public {
        number = bound(number, 1, 99);
        vm.prank(PLAYER);
        lottery.buyTicket{value: costOfATicket}(number);

        uint256 expectedCommisionBalance = (costOfATicket * commisionRate) / 100;
        uint256 actualCommisionBalance = lottery.getCommisionBalance();
        uint256 expectedPoolBalance = costOfATicket - expectedCommisionBalance;
        uint256 actualPoolBalance = lottery.getPoolBalance();
        assertEq(expectedCommisionBalance, actualCommisionBalance);
        assertEq(expectedPoolBalance, actualPoolBalance);
    }

    function testBuyTicketUpdatesHasPlayers(uint256 number) public {
        number = bound(number, 1, 99);
        vm.prank(PLAYER);
        lottery.buyTicket{value: costOfATicket}(number);

        assert(lottery.getHasPlayers());
    }

    function testEventEmitsOnBuyingTicket(uint256 number) public {
        number = bound(number, 1, 99);
        vm.prank(PLAYER);
        vm.expectEmit(true, true, true, false, address(lottery)); // (topic 1, topic 2, topic 3, log data, emitter)
        emit PurchasedTicket(1, PLAYER, number); // manualy created on top of test contract
        lottery.buyTicket{value: costOfATicket}(number);
    }

    ////////////////////////
    /// checkUpkeep       //
    ////////////////////////

    function testCheckUpkeepReturnsFalseIfTimeHasntPassed(uint256 number) public {
        number = bound(number, 1, 99);
        vm.prank(PLAYER);
        lottery.buyTicket{value: costOfATicket}(number);

        (bool checkUpkeepNeeded,) = lottery.checkUpkeep("");

        console.log("Lottery State: ", uint256(lottery.getLotteryState())); // 0 == OPEN
        console.log("Has Players: ", lottery.getHasPlayers());
        console.log("Has Balance: ", lottery.getPoolBalance());
        assert(!checkUpkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfLotteryIsNotOpen(uint256 number1, uint256 number2) public {
        number1 = bound(number1, 1, 99);
        number2 = bound(number2, 1, 99);
        vm.prank(PLAYER);
        lottery.buyTicket{value: costOfATicket}(number1);
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        lottery.performUpkeep(""); // state == CALCULATING

        (bool checkUpkeepNeeded,) = lottery.checkUpkeep("");

        assert(!checkUpkeepNeeded);
    }

    function testCheckUpkeppReturnsFalseIfHasNoBalanceAndNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool checkUpkeepNeeded,) = lottery.checkUpkeep("");

        assert(!checkUpkeepNeeded);
    }

    modifier buyTicketAndTimePassed(uint256 number) {
        number = bound(number, 1, 99);
        vm.prank(PLAYER);
        lottery.buyTicket{value: costOfATicket}(number);
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testCheckUpkeppReturnsFalseIfHasBalanceButNoPlayers(uint256 number1)
        public
        buyTicketAndTimePassed(number1)
        skipFork
    {
        // Arrange
        // modifier
        vm.recordLogs();
        lottery.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(lottery));
        if (lottery.getPoolBalance() == 0) {
            return;
        }

        vm.warp(block.timestamp + interval + 1); // time has passed
        vm.roll(block.number + 1); // time has passed
        assert(lottery.getPoolBalance() > 0); // has balance
        assert(lottery.getHasPlayers() == false); // no players
        // assert(lottery.getNumOfCurrentPlayers() == 0); // no players
        assert(uint256(lottery.getLotteryState()) == 0); // == OPEN
        // Act
        (bool checkUpkeepNeeded,) = lottery.checkUpkeep("");
        // Assert
        assert(!checkUpkeepNeeded);
    }

    ////////////////////////
    /// performUpkeep     //
    ////////////////////////

    function testPerformUpkeepUpdatesLotteryStateAndEmitsRquestId(uint256 number)
        public
        buyTicketAndTimePassed(number)
    {
        vm.recordLogs();
        lottery.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs(); // import Vm type
        bytes32 requestId = entries[1].topics[1];

        assert(uint256(lottery.getLotteryState()) == 1);
        assert(uint256(requestId) > 0);
    }

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue(uint256 number) public buyTicketAndTimePassed(number) {
        // Arrange
        // modifier
        // Act / Assert
        (bool checkUpkeepNeeded,) = lottery.checkUpkeep("");
        assert(checkUpkeepNeeded);
        lottery.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 lotteryState = 0;
        uint256 numPlayers = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                Lottery.Lottery__UpkeepNotNeeded.selector,
                (block.timestamp - lottery.getLastTimeStamp()),
                lotteryState,
                numPlayers
            )
        );
        lottery.performUpkeep("");
    }

    /////////////////////////////
    /// fulfillRandomWords     //
    /////////////////////////////

    function testFulfillRandomWordsUpdatesStateAndTimeStampAndSetsHasPlayersFalseAndIncreasesRoundCount(uint256 number)
        public
        buyTicketAndTimePassed(number)
        skipFork
    {
        // Arrange
        // modifier
        vm.recordLogs();
        lottery.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        uint256 startingLastTimeStamp = lottery.getLastTimeStamp();
        uint256 startingRoundCount = lottery.getRoundCount();
        // Act
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(lottery));
        // Assert
        Lottery.LotteryState lotteryState = lottery.getLotteryState();
        uint256 endingLastTimeStamp = lottery.getLastTimeStamp();
        bool hasPlayers = lottery.getHasPlayers();
        uint256 endingRoundCount = lottery.getRoundCount();
        assert(uint256(lotteryState) == 0); // OPEN
        assert(endingLastTimeStamp > startingLastTimeStamp);
        assert(hasPlayers == false);
        assert(endingRoundCount == startingRoundCount + 1);
    }

    function testFulfillRandomWordsEmitsLuckyNumber(uint256 number) public buyTicketAndTimePassed(number) skipFork {
        // Arrange
        // modifier
        vm.recordLogs();
        lottery.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        uint256 currentRoundCount = lottery.getRoundCount();
        // Act
        vm.recordLogs();
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(lottery));
        // Assert
        Vm.Log[] memory entries2 = vm.getRecordedLogs();
        bytes32 roundCount = entries2[0].topics[1];
        bytes32 luckNumber = entries2[0].topics[2];

        assert(uint256(roundCount) == currentRoundCount);
        assert(uint256(luckNumber) > 0 && uint256(luckNumber) < 100);
    }

    // we have known the lucky number will be 33.
    function testFulfillRandomWordsSendsPrizeToWinnerIfHasWinners() public buyTicketAndTimePassed(33) skipFork {
        // Arrange
        // modifier
        vm.recordLogs();
        lottery.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 startingUserBalance = address(PLAYER).balance;
        uint256 startingPoolBalance = lottery.getPoolBalance();

        // Act
        // vm.recordLogs();
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(lottery));
        // Assert
        // Vm.Log[] memory entries2 = vm.getRecordedLogs();
        // bytes32 roundCount = entries2[0].topics[1];
        // bytes32 luckNumber = entries2[0].topics[2];
        // assert(uint256(luckNumber) == 33);

        uint256 endingUserBalance = address(PLAYER).balance;
        uint256 endingPoolBalance = lottery.getPoolBalance();
        assert(endingUserBalance == startingUserBalance + startingPoolBalance);
        assert(endingPoolBalance == 0);
    }

    // we have known the lucky number will be 33.
    function testFulfillRandomWordsEmitsEnentIfHasWinners() public buyTicketAndTimePassed(33) skipFork {
        // Arrange
        // modifier
        vm.recordLogs();
        lottery.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 round = lottery.getRoundCount();
        address[] memory winners = lottery.getRoundToSelectedNumToAddresses(round, 33);
        uint256 startingPoolBalance = lottery.getPoolBalance();

        // Act / Assert
        vm.expectEmit(true, true, true, false, address(lottery)); // (topic 1, topic 2, topic 3, log data, emitter)
        emit SentPrizeToWinners(round, winners, startingPoolBalance); // manualy created on top of test contract
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(lottery));
    }

    // we have known the lucky number will be 33.
    function testFulfillRandomWordsKeepPoolBalanceIfNoWinners() public buyTicketAndTimePassed(32) skipFork {
        // Arrange
        // modifier
        vm.recordLogs();
        lottery.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        // uint256 currentRoundCount = lottery.getRoundCount();
        uint256 startingUserBalance = address(PLAYER).balance;
        uint256 startingPoolBalance = lottery.getPoolBalance();
        // Act
        // vm.recordLogs();
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(lottery));
        // Assert
        // Vm.Log[] memory entries2 = vm.getRecordedLogs();
        // bytes32 roundCount = entries2[0].topics[1];
        // bytes32 luckNumber = entries2[0].topics[2];
        // assert(uint256(luckNumber) == 33);

        uint256 endingUserBalance = address(PLAYER).balance;
        uint256 endingPoolBalance = lottery.getPoolBalance();
        assert(endingUserBalance == startingUserBalance);
        assert(endingPoolBalance == startingPoolBalance);
    }

    // we have known the lucky number will be 33.
    function testFulfillRandomWordsEmitsEnentIfNoWinners() public buyTicketAndTimePassed(32) skipFork {
        // Arrange
        // modifier
        vm.recordLogs();
        lottery.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 round = lottery.getRoundCount();

        // Act / Assert
        vm.expectEmit(true, false, false, false, address(lottery)); // (topic 1, topic 2, topic 3, log data, emitter)
        emit ThisRoundNoWinners(round); // manualy created on top of test contract
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(lottery));
    }

    // The final test
    // we have known the lucky number will be 33, and set 2 winners for this round.
    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public buyTicketAndTimePassed(33) skipFork {
        // Arrange
        // modifier
        uint256 additionalEntrants = 5;
        uint256 satrtingIndex = 1;
        for (uint256 i = satrtingIndex; i < satrtingIndex + additionalEntrants; i++) {
            address player = address(uint160(i)); // the reason that satrtingIndex = 1; i.e. address(1)...address(5)
            hoax(player, STARTING_USER_BALANCE); // vm.prank() + vm.deal()
            lottery.buyTicket{value: costOfATicket}(31 + i);
        }

        vm.recordLogs();
        lottery.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 startingRoundCount = lottery.getRoundCount();

        uint256 previousTimeStamp = lottery.getLastTimeStamp();
        // Act

        vm.recordLogs();
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(lottery));
        Vm.Log[] memory entries2 = vm.getRecordedLogs();
        // bytes32 roundCount = entries2[0].topics[1];
        bytes32 luckyNumber = entries2[0].topics[2];

        uint256 endingPoolBalance = lottery.getPoolBalance();
        uint256 endingRoundCount = lottery.getRoundCount();
        uint256 prize = ((costOfATicket - (costOfATicket * commisionRate / 100)) * 6) / 2;
        // Assert
        assert(uint256(lottery.getLotteryState()) == 0); // reset to OPEN
        assert(previousTimeStamp < block.timestamp); // reset timeStamp
        assert(lottery.getHasPlayers() == false);
        assert(endingPoolBalance == 0); // reset balancePool
        assert(endingRoundCount == startingRoundCount + 1); // update roundCount
        assert(lottery.getRoundToSelectedNumToAddresses(startingRoundCount, uint256(luckyNumber)).length == 2); // picked 2 players
        assert(address(PLAYER).balance == STARTING_USER_BALANCE - costOfATicket + prize); // sent prize to winner
    }

    ///////////////////////
    // withdrawCommision //
    ///////////////////////

    function testWithdrawCommisionRevertsIfNotOwner(uint256 number) public buyTicketAndTimePassed(number) {
        vm.expectRevert(Lottery.Lottery__OnlyOwner.selector);
        lottery.withdrawCommision();
    }

    function testWithdrawCommisionRevertsIfNoCommision() public {
        address owner = lottery.getOwner();
        vm.prank(owner);
        vm.expectRevert(Lottery.Lottery__NoCommision.selector);
        lottery.withdrawCommision();
    }

    function testWithdrawCommsionSendsEthToOwner(uint256 number) public buyTicketAndTimePassed(number) {
        // Arrange
        // modifier
        address owner = lottery.getOwner();
        uint256 startingOwnerBalance = owner.balance;
        uint256 startingCommisionBalance = lottery.getCommisionBalance();
        // Act

        vm.prank(owner);
        lottery.withdrawCommision();
        // Assert
        uint256 endingOwnerBalance = owner.balance;
        uint256 endingCommisionBalance = lottery.getCommisionBalance();
        assert(endingOwnerBalance == startingOwnerBalance + startingCommisionBalance);
        assert(endingCommisionBalance == 0);
    }
}
