// unit
// integration
// forked
// staging -> run tests on a mainnet or testnet
// fuzzing
// stateful fuzz
// stateless fuzz
// formal verification

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "../../script/Interactions.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {Raffle} from "src/Raffle.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";

contract InteractionsTest is Test {
    HelperConfig helperConfig;
    Raffle public raffle;

    address vrfCoordinator;
    address linkToken;
    address account;
    uint256 entranceFee;
    uint256 interval;
    uint256 subscriptionId;

    address public player = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vrfCoordinator = config.vrfCoordinator;
        linkToken = config.link;
        account = config.account;
        entranceFee = config.entranceFee;
        interval = config.interval;
        subscriptionId = config.subscriptionId;

        vm.deal(player, STARTING_USER_BALANCE);
    }

    // Unit
    function testCreateSubscription() public {
        // Arrange
        CreateSubscription createSub = new CreateSubscription();

        // Act
        (uint256 subId, ) = createSub.createSubscription(
            vrfCoordinator,
            account
        );

        // Assert
        assert(subId != 0);
    }

    function testFundSubscription() public {
        // Arrange
        CreateSubscription createSub = new CreateSubscription();
        (uint256 subId, ) = createSub.createSubscription(
            vrfCoordinator,
            account
        );

        // Act
        FundSubscription fundSub = new FundSubscription();
        fundSub.fundSubscription(vrfCoordinator, subId, linkToken, account);

        // Assert
        (uint96 balance, , , , ) = VRFCoordinatorV2_5Mock(vrfCoordinator)
            .getSubscription(subId);

        assert(balance > 0);
    }

    function testAddConsumer() public {
        // Arrange
        CreateSubscription createSub = new CreateSubscription();
        (uint256 subId, ) = createSub.createSubscription(
            vrfCoordinator,
            account
        );

        address dummyRaffle = address(this);

        // Act
        AddConsumer addConsumerScript = new AddConsumer();
        addConsumerScript.addConsumer(
            dummyRaffle,
            vrfCoordinator,
            subId,
            account
        );

        // Assert
        (, , , , address[] memory consumers) = VRFCoordinatorV2_5Mock(
            vrfCoordinator
        ).getSubscription(subId);

        bool isAdded = false;
        for (uint256 i = 0; i < consumers.length; i++) {
            if (consumers[i] == dummyRaffle) {
                isAdded = true;
                break;
            }
        }

        assert(isAdded);
    }

    // Integration
    function testUserCanEnterAndUpkeepWorksBecauseOfInteractions() public {
        // Arrange
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        raffle.performUpkeep("");

        // Assert
        assert(uint256(raffle.getRaffleState()) == 1);
    }

    // Forked
    modifier onlyOnFork() {
        if (block.chainid == 31337) {
            return;
        }
        _;
    }

    function testVrfCoordinatorIsRealOnFork() public view onlyOnFork {
        // Arrange & Act
        address expectedSepoliaVrf = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B;

        // Assert
        assert(vrfCoordinator == expectedSepoliaVrf);
    }

    function testLinkTokenIsRealOnFork() public view onlyOnFork {
        address expectedSepoliaLink = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
        assert(linkToken == expectedSepoliaLink);
    }

    // Staging
    modifier onlyOnSepolia() {
        if (block.chainid != 11155111) {
            return;
        }
        _;
    }

    function testStagingInteractionsSetupIsCorrectOnLiveNetwork()
        public
        view
        onlyOnSepolia
    {
        // Arrange & Act
        (
            uint96 balance, // nativeBalance // reqCount // owner
            ,
            ,
            ,
            address[] memory consumers
        ) = VRFCoordinatorV2_5Mock(vrfCoordinator).getSubscription(
                subscriptionId
            );

        // Assert 1
        assert(balance > 0);

        // Assert 2
        bool isAdded = false;
        for (uint256 i = 0; i < consumers.length; i++) {
            if (consumers[i] == address(raffle)) {
                isAdded = true;
                break;
            }
        }
        assert(isAdded);
    }

    // Fuzzing Stateless
    function testFuzzFundSubscriptionRevertsWithInvalidSubId(
        uint256 randomSubId
    ) public {
        // Arrange
        vm.assume(randomSubId != subscriptionId);

        FundSubscription fundSub = new FundSubscription();

        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("InvalidSubscription()"));
        fundSub.fundSubscription(
            vrfCoordinator,
            randomSubId,
            linkToken,
            account
        );
    }

    function testFuzzAddConsumerRevertsWithInvalidSubId(
        uint256 randomSubId
    ) public {
        // Arrange
        vm.assume(randomSubId != subscriptionId);

        AddConsumer addConsumerScript = new AddConsumer();

        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("InvalidSubscription()"));
        addConsumerScript.addConsumer(
            address(raffle),
            vrfCoordinator,
            randomSubId,
            account
        );
    }

    // ++Coverage
    function testCreateSubscriptionRun() public {
        // Arrange
        CreateSubscription createSub = new CreateSubscription();

        // Act & Assert
        createSub.run();
    }

    function testFundSubscriptionRun() public {
        // Arrange
        FundSubscription fundSub = new FundSubscription();
        // Act & Assert
        vm.expectRevert(abi.encodeWithSignature("InvalidSubscription()"));
        fundSub.run();
    }

    function testFundSubscriptionOnRealNetwork() public {
        // Arrange
        vm.chainId(11155111);

        CreateSubscription createSub = new CreateSubscription();
        (uint256 subId, ) = createSub.createSubscription(
            vrfCoordinator,
            account
        );

        FundSubscription fundSub = new FundSubscription();
        vm.expectRevert(abi.encodeWithSignature("OnlyCallableFromLink()"));
        fundSub.fundSubscription(vrfCoordinator, subId, linkToken, account);

        // Assert
        vm.chainId(31337);
    }
}
