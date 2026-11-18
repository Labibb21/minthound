// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal mock of the Agent ID ERC-721, for local Foundry tests only.
/// The real Agent ID contract is a full ERC-721 on BNB Chain, but
/// MintHoundBoard only ever calls balanceOf, so the mock only exposes that
/// (plus a setter so tests can grant / revoke holder status at will).
///
/// @dev In tests this mock's runtime code is placed at the real Agent ID
/// address with vm.etch, so the board under test talks to it through the
/// exact hardcoded address it uses in production. See MintHoundBoard.t.sol.
contract MockAgentId {
    mapping(address => uint256) private _balances;

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function setBalance(address account, uint256 amount) external {
        _balances[account] = amount;
    }
}
