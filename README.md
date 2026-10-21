# Intuition V2 Periphery Smart Contracts

## npm alpha package

This branch prepares `@0xintuition/contracts-v2-periphery@1.1.0-alpha.0` for the `alpha` tag. It ships the
TrustSwapAndBridgeRouter Solidity source and required interfaces, ABI and creation bytecode, ESM/CommonJS exports,
TypeScript declarations, and `artifact-manifest.json`. Other periphery contracts remain repository-only in this release.
No Solidity business logic is changed by the packaging work.

After publication:

```ts
import { TrustSwapAndBridgeRouterAbi } from "@0xintuition/contracts-v2-periphery/abis";
import { TrustSwapAndBridgeRouterBytecode } from "@0xintuition/contracts-v2-periphery/bytecodes";
```

Foundry source consumers need these remappings:

```text
@0xintuition/contracts-v2-periphery/=node_modules/@0xintuition/contracts-v2-periphery/
node_modules/@0xintuition/contracts-v2-periphery/:contracts/=node_modules/@0xintuition/contracts-v2-periphery/contracts/
@openzeppelin/contracts/=node_modules/@openzeppelin/contracts/
```

Run `bun install --frozen-lockfile`, `bun run release:check`, and `bun run test:router`. Release checks build and test
the package, install its tarball in an isolated JS/TS consumer, and reproduce the Solidity ABI/bytecode using only npm
dependencies. `npm pack` and `npm publish` run these checks through `prepack`. With a permitted npm login and an unused
version, publish using `npm publish --access public --tag alpha`; leave `latest` unchanged. This publishes artifacts
only and does not deploy contracts. Check the registry integrity and record the final git revision after publication.

The package build uses the pinned OpenZeppelin v5.4.0 submodule; consumers install the matching exact npm version. The
legacy core submodule's v4 dependencies remain development-only aliases for repository tests. The router is pinned to
Base mainnet protocol addresses; publishing its bytecode does not establish compatibility with other chains or deployed
revisions.

A set of periphery smart contracts for the Intuition protocol, built using [Foundry](https://book.getfoundry.sh/).

## What's Inside

- [Forge](https://github.com/foundry-rs/foundry/blob/master/forge): compile, test, fuzz, format, and deploy smart
  contracts
- [Bun]: Foundry defaults to git submodules, but this template also uses Node.js packages for managing dependencies
- [Forge Std](https://github.com/foundry-rs/forge-std): collection of helpful contracts and utilities for testing
- [Prettier](https://github.com/prettier/prettier): code formatter for non-Solidity files
- [Solhint](https://github.com/protofire/solhint): linter for Solidity code

## Usage

This is a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
$ forge build
```

### Clean

Delete the build artifacts and cache directories:

```sh
$ forge clean
```

### Deploy

Deploy to Anvil:

```sh
$ forge script script/Deploy.s.sol --broadcast --fork-url http://localhost:8545
```

For this script to work, you need to have a `MNEMONIC` environment variable set to a valid
[BIP39 mnemonic](https://iancoleman.io/bip39/).

For instructions on how to deploy to a testnet or mainnet, check out the
[Solidity Scripting](https://book.getfoundry.sh/tutorials/solidity-scripting.html) tutorial.

### Format

Format the contracts:

```sh
$ forge fmt
```

### Gas Usage

Get a gas report:

```sh
$ forge test --gas-report
```

### Lint

Lint the contracts:

```sh
$ bun run lint
```

### Test

Run the tests:

```sh
$ forge test
```

### Test Coverage

Generate test coverage and output result to the terminal:

```sh
$ bun run test:coverage
```

### Test Coverage Report

Generate test coverage with lcov report (you'll have to open the `./coverage/index.html` file in your browser, to do so
simply copy paste the path):

```sh
$ bun run test:coverage:report
```

> [!NOTE]
>
> This command requires you to have [`lcov`](https://github.com/linux-test-project/lcov) installed on your machine. On
> macOS, you can install it with Homebrew: `brew install lcov`.

## Claude Slash Commands (Shared)

This repo includes team-shared Claude slash commands in `.claude/commands`.

Use `/help` in Claude Code to see them, then run:

- `/audit-solidity [codebase-path] [spec-document-optional]`
- `/audit-context [codebase-path] [--focus <module>]`
- `/audit-entry-points [directory-path]`
- `/audit-static-analysis [codebase-path]`
- `/audit-spec-compliance <spec-document> [codebase-path]`
- `/audit-variants [vulnerability-description]`

Generated reports are written to `audits/automated-reports/`.

## Audits

- [Diligence: v1.1.0 core upgrade (October 2026)](audits/Diligence-Audit-Report-3.pdf)
- [Code4rena (April 2026)](audits/CodeArena-audit-report-April-2026.pdf)
- [Diligence: MultiVault (September 2025)](audits/Diligence-Audit-Report-2.pdf)
- [Diligence: TRUST token, bonding and emissions (September 2025)](audits/Diligence-Audit-Report-1.pdf)

## License

This project is licensed under BUSL-1.1

# Deployed Contracts

## Mainnet

### Base Mainnet

| Contract Name              | Address                                    | ProxyAdmin                                 |
| -------------------------- | ------------------------------------------ | ------------------------------------------ |
| EmissionsAutomationAdapter | 0xb1ce9Ac324B5C3928736Ec33b5Fd741cb04a2F2d | /                                          |
| MetaERC20Hub (TRUST)       | 0xE12aaF1529Ae21899029a9b51cca2F2Bc2cfC421 | 0x2A627d89f08b9c23c8CF1dff0C475B9Ea7eDF696 |
| MetaERC20Hub (USDC)        | 0x7e41962bE9B2640e653BfA8c8713A905659FE157 | 0x6635a40EA4DdB5aa0Cc720A6883E934f4385AA23 |
| MetaERC20Hub (WETH)        | 0xFB4BAa05BF339AD6074047176F90757A6C87f944 | 0x42d2100553eB21e1CB79864C0BCbFA3C963957c7 |

### Intuition Mainnet

| Contract Name           | Address                                    | ProxyAdmin                                 |
| ----------------------- | ------------------------------------------ | ------------------------------------------ |
| MetaNativeSpoke (TRUST) | 0x375135fe908dD62f3C7939FA4e65bf41Da721AB9 | 0xe433e1e8Fb2dBD028900BC8b073Fd4392d3b3A63 |
| MetaERC20Spoke (USDC)   | 0x7e41962bE9B2640e653BfA8c8713A905659FE157 | 0x6635a40EA4DdB5aa0Cc720A6883E934f4385AA23 |
| MetaERC20Spoke (WETH)   | 0xFB4BAa05BF339AD6074047176F90757A6C87f944 | 0x42d2100553eB21e1CB79864C0BCbFA3C963957c7 |

The Metalayer hubs on Base and spokes on Intuition bridge TRUST, USDC and WETH between the two chains. TRUST arrives on
Intuition as the native token through MetaNativeSpoke; the USDC and WETH hubs share an address with their spokes.

There are no periphery deployments on testnet. The core contracts, including Multicall3, EntryPoint and
SafeSingletonFactory, are listed in the
[intuition-contracts-v2 README](https://github.com/0xIntuition/intuition-contracts-v2#deployed-contracts).
