# MintHound — Agent ID-gated DYOR board

Smart contract for the Binance Agent ID Hackathon (Innovation Award).
MintHound is a DYOR board for agent projects and free mints where **only
Agent ID holders can submit projects and vote**. An Agent ID is one-per-KYC
and non-transferable, so votes are Sybil-resistant: one person cannot stuff
the ballot with throwaway accounts.

> **Status: LIVE on BNB Chain mainnet.** Contract deployed 18 Nov 2026,
> source verified on BscScan, board seeded with 6 projects.
>
> - Contract: [`0x2bce40d4a534f6a94e00c391f99e24c6e05b3c14`](https://bscscan.com/address/0x2bce40d4a534f6a94e00c391f99e24c6e05b3c14)
> - Board: https://muse.ai/s/minthound-xoxq6xyxpmxyxwxrxwxa/tzoQgpmNSGkwBjs18UREedd4WGtu8PE2Mq1jn3db3zA
> - Tagline: *Sniff first, mint later.*

## Files

```
minthound/
├── foundry.toml                  # src=contracts, test=test, solc 0.8.20
├── remappings.txt                # forge-std vendored under lib/
├── README.md
├── seed-projects.json            # the 6 projects seeded on the live board
├── contracts/
│   └── MintHoundBoard.sol        # the board (single file, no deps)
├── lib/
│   └── forge-std/src/            # vendored Foundry std lib (tests only)
└── test/
    ├── MintHoundBoard.t.sol      # 16 tests
    └── MockAgentId.sol           # settable balanceOf mock (tests only)
```

## Deployment (live)

- **Network:** BNB Chain mainnet (chain 56)
- **Contract:** `0x2bce40d4a534f6a94e00c391f99e24c6e05b3c14`
- **Deploy tx:** [`0xdb477d44196461b7b3592adaf29738689a3a4d6bacb57b22bb431941900669ec`](https://bscscan.com/tx/0xdb477d44196461b7b3592adaf29738689a3a4d6bacb57b22bb431941900669ec) (block 134295079, 18 Nov 2026, gas 922838)
- **Owner:** `0x86Cf9D962258e470177f42766a3dD9874Df7f1E9` (Binance Agentic Wallet agent `ell21.ai`; ownership transferred to the agent wallet after deploy, tx `0x1dc6aa7293dd3a975a87997596805261a507ca00b296e2c0cfab5de1f56f2bae`)
- **Source verification:** Sourcify exact match (creation + runtime) and BscScan "Source Code Verified / Exact Match". Compiler v0.8.20+commit.a1b79de6, optimizer 200 runs, EVM shanghai, SPDX MIT.
- **Seeded:** 6 projects on 18 Nov 2026 (DGF CARD, Pocket Ai, PXIO Miners, Meow Cards, THE WALL, AGI Agent MEME) — `projectCount` 6, all verified on-chain. See `seed-projects.json`.

## Contract design — `MintHoundBoard`

Solidity `^0.8.20`, single file, zero dependencies. The Agent ID gate
address is **hardcoded** as a constant so it can never be misconfigured at
deploy time:

```
AGENT_ID = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F   (SPACE ID Agent ID, BSC)
```

### State

- `Project { submitter, name, projectContract, infoURI, isFreeMint, upvotes, downvotes, timestamp }`, stored in an array.
- `_votes[projectId][voter]`: `0` = no vote, `1` = up, `2` = down.

### Functions

| Function | Who | What |
|---|---|---|
| `submitProject(name, projectContract, infoURI, isFreeMint)` | Agent ID holder | Stores a project, returns its id, emits `ProjectSubmitted`. Reverts on zero contract address. |
| `vote(projectId, up)` | Agent ID holder | One vote per address per project. Flipping up↔down adjusts the counts. Voting the same way twice reverts `AlreadyVoted`. Emits `Voted`. |
| `projectCount()` | anyone | Total submitted projects. |
| `getProject(projectId)` | anyone | All stored fields of one project. |
| `getVote(projectId, voter)` | anyone | `0` none / `1` up / `2` down. |
| `pause()` / `unpause()` | owner only | Emergency stop for submit + vote. Views keep working. |
| `transferOwnership(newOwner)` | owner only | Hands the pause power to a new address. |

### The Agent ID gate

`onlyAgentIdHolder` calls `balanceOf(msg.sender)` on the Agent ID
contract and requires `> 0` — exactly the check documented in the
hackathon announcement. Written as a range check (`> 0`, not `== 0`) so
the linter does not flag an exact equality on an external value.

### Owner limits (deliberately minimal)

- The owner can **only** pause/unpause and transfer ownership.
- The owner **cannot** edit, delete or hide submissions, change votes, or
  touch user funds — the contract holds no funds at all (no payable
  function, no withdrawal function).
- There is intentionally **no `renounceOwnership`**: renouncing while
  paused would brick the board forever. Ownership can be transferred,
  never renounced.

### Hackathon safety rules

- No QR-code login, no session storage, no asset transfers, no
  mnemonic/private-key/API-secret collection, no promised returns.
- No Binance/BNB branding in the contract name, code, events or strings.
  "MintHound" is an original name.

## Tests

16 tests, all passing, no compiler warnings, no lint warnings:

```
forge test
```

Coverage: non-holder reverts on submit and vote; holder submit stores
all fields + emits `ProjectSubmitted`; vote counts once (repeat same-way
vote reverts `AlreadyVoted`); flipping a vote adjusts both counts;
voting / reading an unknown project reverts `ProjectNotFound`; pause
blocks submit + vote while views keep working; unpause restores
function; non-owner cannot pause/unpause; owner is the deployer;
transfer to zero address reverts; the hardcoded gate address equals the
canonical BSC Agent ID address.

How the gate is tested: the mock's runtime code is placed at the **real**
Agent ID address with `vm.etch` in `setUp`, so the board under test
gates on the exact hardcoded address it uses in production. Holder
status is then set per address with `MockAgentId.setBalance`.

### Running them

`forge` lives at `~/.foundry/bin` (Foundry 1.9.0) and is not on `PATH`
by default on this VM:

```bash
export PATH="$HOME/.foundry/bin:$PATH"
cd minthound
forge test        # runs the 16 tests
forge build       # compiles contracts + tests
```

`forge-std` is vendored under `lib/` — no network or git submodule is
needed to build or test. `solc 0.8.20` is downloaded once by forge on
first build (network to `binaries.soliditylang.org`).
