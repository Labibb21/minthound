// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/MintHoundBoard.sol";
import "./MockAgentId.sol";

contract MintHoundBoardTest is Test {
    MintHoundBoard public board;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public carol = address(0xCA901); // holds no Agent ID

    // Real BSC contract address, used only as inert test data (no calls made).
    address public constant SAMPLE_PROJECT = 0x01f9CA4ff95d49594cC8B6591022186dc5C1Bc72;

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

    function setUp() public {
        board = new MintHoundBoard(); // this test contract becomes the owner
        // (The constructor never touches the Agent ID gate, so the mock can
        // be etched after deployment.)

        // Place the mock's code at the REAL Agent ID address, so the board
        // under test gates on the exact hardcoded address it uses in
        // production. Balances are then set through that same address.
        MockAgentId mock = new MockAgentId();
        vm.etch(board.AGENT_ID(), address(mock).code);

        MockAgentId(board.AGENT_ID()).setBalance(alice, 1);
        MockAgentId(board.AGENT_ID()).setBalance(bob, 1);
        // carol intentionally gets no balance.
    }

    function _submitAs(address who) internal returns (uint256) {
        vm.prank(who);
        return board.submitProject("DGF CARD", SAMPLE_PROJECT, "https://example.invalid/dgf", true);
    }

    // --- Agent ID gate ---

    function test_NonHolderCannotSubmit() public {
        vm.prank(carol);
        vm.expectRevert(MintHoundBoard.NotAgentIdHolder.selector);
        board.submitProject("DGF CARD", SAMPLE_PROJECT, "https://example.invalid/dgf", true);
    }

    function test_NonHolderCannotVote() public {
        uint256 id = _submitAs(alice);
        vm.prank(carol);
        vm.expectRevert(MintHoundBoard.NotAgentIdHolder.selector);
        board.vote(id, true);
    }

    function test_HolderCanSubmit_StoresDataAndEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ProjectSubmitted(0, alice, "DGF CARD", SAMPLE_PROJECT, true);
        vm.prank(alice);
        uint256 id = board.submitProject("DGF CARD", SAMPLE_PROJECT, "https://example.invalid/dgf", true);
        assertEq(id, 0);
        assertEq(board.projectCount(), 1);

        MintHoundBoard.Project memory p = board.getProject(0);
        assertEq(p.submitter, alice);
        assertEq(p.name, "DGF CARD");
        assertEq(p.projectContract, SAMPLE_PROJECT);
        assertEq(p.infoURI, "https://example.invalid/dgf");
        assertTrue(p.isFreeMint);
        assertEq(p.upvotes, 0);
        assertEq(p.downvotes, 0);
        assertEq(p.timestamp, block.timestamp);
    }

    function test_SubmitZeroAddressReverts() public {
        vm.prank(alice);
        vm.expectRevert(MintHoundBoard.ZeroAddress.selector);
        board.submitProject("Nope", address(0), "", true);
    }

    // --- Voting ---

    function test_VoteCountsOnce() public {
        uint256 id = _submitAs(alice);

        vm.prank(alice);
        board.vote(id, true);
        assertEq(board.getProject(id).upvotes, 1);
        assertEq(board.getVote(id, alice), 1);

        // Voting the same way twice reverts; the count stays 1.
        vm.prank(alice);
        vm.expectRevert(MintHoundBoard.AlreadyVoted.selector);
        board.vote(id, true);
        assertEq(board.getProject(id).upvotes, 1);

        // A second holder's vote counts separately.
        vm.prank(bob);
        board.vote(id, true);
        assertEq(board.getProject(id).upvotes, 2);
    }

    function test_ChangeVoteAdjustsCounts() public {
        uint256 id = _submitAs(alice);

        vm.prank(alice);
        board.vote(id, true);
        assertEq(board.getProject(id).upvotes, 1);
        assertEq(board.getProject(id).downvotes, 0);

        vm.prank(alice);
        board.vote(id, false);
        MintHoundBoard.Project memory p = board.getProject(id);
        assertEq(p.upvotes, 0);
        assertEq(p.downvotes, 1);
        assertEq(board.getVote(id, alice), 2);

        vm.prank(alice);
        board.vote(id, true);
        p = board.getProject(id);
        assertEq(p.upvotes, 1);
        assertEq(p.downvotes, 0);
        assertEq(board.getVote(id, alice), 1);
    }

    function test_VoteEmitsEvent() public {
        uint256 id = _submitAs(alice);
        vm.expectEmit(true, true, true, true);
        emit Voted(id, bob, true, 1, 0);
        vm.prank(bob);
        board.vote(id, true);
    }

    function test_VoteOnUnknownProjectReverts() public {
        vm.prank(alice);
        vm.expectRevert(MintHoundBoard.ProjectNotFound.selector);
        board.vote(99, true);
    }

    function test_GetProjectUnknownReverts() public {
        vm.expectRevert(MintHoundBoard.ProjectNotFound.selector);
        board.getProject(0);
    }

    function test_GetVoteUnknownReverts() public {
        vm.expectRevert(MintHoundBoard.ProjectNotFound.selector);
        board.getVote(7, alice);
    }

    // --- Pause ---

    function test_PauseBlocksSubmitAndVote() public {
        uint256 id = _submitAs(alice);

        board.pause();
        assertTrue(board.paused());

        vm.prank(alice);
        vm.expectRevert(MintHoundBoard.ContractPaused.selector);
        board.submitProject("Late", SAMPLE_PROJECT, "", false);

        vm.prank(alice);
        vm.expectRevert(MintHoundBoard.ContractPaused.selector);
        board.vote(id, true);

        // Views keep working while paused.
        assertEq(board.projectCount(), 1);
        assertEq(board.getProject(id).upvotes, 0);
    }

    function test_UnpauseRestoresFunction() public {
        board.pause();
        board.unpause();
        assertFalse(board.paused());

        uint256 id = _submitAs(alice);
        vm.prank(bob);
        board.vote(id, true);
        assertEq(board.getProject(id).upvotes, 1);
    }

    function test_NonOwnerCannotPauseOrUnpause() public {
        vm.prank(carol);
        vm.expectRevert(MintHoundBoard.NotOwner.selector);
        board.pause();

        board.pause(); // owner pauses
        vm.prank(carol);
        vm.expectRevert(MintHoundBoard.NotOwner.selector);
        board.unpause();
    }

    function test_OwnerIsDeployer() public view {
        assertEq(board.owner(), address(this));
    }

    function test_GateAddressIsCanonicalAgentId() public view {
        assertEq(board.AGENT_ID(), 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F);
    }

    function test_TransferOwnershipToZeroReverts() public {
        vm.expectRevert(MintHoundBoard.ZeroAddress.selector);
        board.transferOwnership(address(0));
    }
}
