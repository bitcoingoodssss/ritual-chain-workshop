// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PrecompileConsumer} from "./utils/PrecompileConsumer.sol";

interface IRitualWallet {
    function deposit(uint256 lockDuration) external payable;
    function depositFor(address user, uint256 lockDuration) external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address) external view returns (uint256);
    function lockUntil(address) external view returns (uint256);
}

contract AIJudge is PrecompileConsumer {

    uint256 public constant MAX_SUBMISSIONS = 10;
    uint256 public constant MAX_ANSWER_LENGTH = 2000;

    uint256 public nextBountyId = 1;

    IRitualWallet public immutable ritualWallet = 
        IRitualWallet(0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948);

    struct Bounty {
        address owner;
        string title;
        string rubric;
        uint256 reward;
        uint256 submissionDeadline;
        uint256 revealDeadline;
        bool judged;
        bool finalized;
        bytes aiReview;
        uint256 winnerIndex;
        uint256 submissionCount;
    }

    struct Submission {
        address submitter;
        bytes32 commitment;
        string answer;
        bool revealed;
    }

    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => mapping(uint256 => Submission)) public submissions;
    mapping(uint256 => mapping(address => uint256)) public userSubmissionIndex;
    mapping(uint256 => mapping(address => bool)) public hasSubmitted;

    event BountyCreated(
        uint256 indexed bountyId,
        address indexed owner,
        string title,
        uint256 reward,
        uint256 submissionDeadline,
        uint256 revealDeadline
    );

    event CommitmentSubmitted(
        uint256 indexed bountyId,
        uint256 indexed submissionIndex,
        address indexed submitter
    );

    event AnswerRevealed(
        uint256 indexed bountyId,
        uint256 indexed submissionIndex,
        address indexed submitter
    );

    event AllAnswersJudged(uint256 indexed bountyId, bytes aiReview);
    event WinnerFinalized(uint256 indexed bountyId, uint256 winnerIndex, address winner, uint256 reward);

    modifier onlyBountyOwner(uint256 bountyId) {
        require(msg.sender == bounties[bountyId].owner, "Not bounty owner");
        _;
    }

    modifier bountyExists(uint256 bountyId) {
        require(bounties[bountyId].owner != address(0), "Bounty does not exist");
        _;
    }

    function createBounty(
        string calldata title,
        string calldata rubric,
        uint256 submissionDeadline,
        uint256 revealDeadline
    ) external payable returns (uint256 bountyId) {
        require(msg.value > 0, "Reward required");
        require(submissionDeadline > block.timestamp, "Submission deadline in past");
        require(revealDeadline > submissionDeadline, "Reveal deadline must be after submission deadline");

        bountyId = nextBountyId++;

        Bounty storage newBounty = bounties[bountyId];
        newBounty.owner = msg.sender;
        newBounty.title = title;
        newBounty.rubric = rubric;
        newBounty.reward = msg.value;
        newBounty.submissionDeadline = submissionDeadline;
        newBounty.revealDeadline = revealDeadline;
        newBounty.winnerIndex = type(uint256).max;

        emit BountyCreated(bountyId, msg.sender, title, msg.value, submissionDeadline, revealDeadline);
    }

    function submitCommitment(uint256 bountyId, bytes32 commitment) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(block.timestamp < bounty.submissionDeadline, "Submission phase ended");
        require(!hasSubmitted[bountyId][msg.sender], "Already submitted");
        require(bounty.submissionCount < MAX_SUBMISSIONS, "Max submissions reached");

        uint256 index = bounty.submissionCount;
        submissions[bountyId][index] = Submission({
            submitter: msg.sender,
            commitment: commitment,
            answer: "",
            revealed: false
        });

        userSubmissionIndex[bountyId][msg.sender] = index;
        hasSubmitted[bountyId][msg.sender] = true;
        bounty.submissionCount++;

        emit CommitmentSubmitted(bountyId, index, msg.sender);
    }

    function revealAnswer(uint256 bountyId, string calldata answer, bytes32 salt) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(block.timestamp > bounty.submissionDeadline, "Reveal phase not started");
        require(block.timestamp < bounty.revealDeadline, "Reveal phase ended");
        require(hasSubmitted[bountyId][msg.sender], "No commitment found");

        uint256 index = userSubmissionIndex[bountyId][msg.sender];
        Submission storage sub = submissions[bountyId][index];
        require(!sub.revealed, "Already revealed");

        bytes32 expected = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId));
        require(expected == sub.commitment, "Invalid reveal");

        sub.answer = answer;
        sub.revealed = true;

        emit AnswerRevealed(bountyId, index, msg.sender);
    }

    function judgeAll(uint256 bountyId, bytes calldata llmInput) external bountyExists(bountyId) onlyBountyOwner(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(block.timestamp > bounty.revealDeadline, "Reveal deadline not passed");
        require(!bounty.judged, "Already judged");

        bytes memory output = _executePrecompile(LLM_INFERENCE_PRECOMPILE, llmInput);
        (bool hasError, bytes memory completionData, , string memory errorMessage, ) = 
            abi.decode(output, (bool, bytes, bytes, string, bytes));

        require(!hasError, errorMessage);

        bounty.judged = true;
        bounty.aiReview = completionData;

        emit AllAnswersJudged(bountyId, completionData);
    }

    function finalizeWinner(uint256 bountyId, uint256 winnerIndex) external bountyExists(bountyId) onlyBountyOwner(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(bounty.judged, "Not judged yet");
        require(!bounty.finalized, "Already finalized");
        require(winnerIndex < bounty.submissionCount, "Invalid winner index");
        require(submissions[bountyId][winnerIndex].revealed, "Winner not revealed");

        bounty.finalized = true;
        bounty.winnerIndex = winnerIndex;

        address winner = submissions[bountyId][winnerIndex].submitter;
        uint256 reward = bounty.reward;
        bounty.reward = 0;

        (bool success, ) = payable(winner).call{value: reward}("");
        require(success, "Payment failed");

        emit WinnerFinalized(bountyId, winnerIndex, winner, reward);
    }

    function getBounty(uint256 bountyId) external view bountyExists(bountyId) returns (Bounty memory) {
        return bounties[bountyId];
    }

    function getSubmission(uint256 bountyId, uint256 index) external view bountyExists(bountyId) returns (Submission memory) {
        return submissions[bountyId][index];
    }
}
