# Intuition V2 Periphery Smart Contracts

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


## License

This project is licensed under BUSL-1.1


# Deployed Contracts

## Mainnet

### Base Mainnet

| Contract Name               | Address                                    | ProxyAdmin                                 |
|-----------------------------|--------------------------------------------|--------------------------------------------|
| EmissionsAutomationAdapter  | 0xb1ce9Ac324B5C3928736Ec33b5Fd741cb04a2F2d | /                                          |
| TrustSwapAndBridgeRouter    | 0xA1EC6f95A88Bfc7A8Fd35f1296b64ebaf91C93fb | /                                          |

### Intuition Mainnet

| Contract Name                 | Address                                    | ProxyAdmin                                  |
|-------------------------------|--------------------------------------------|---------------------------------------------|
| Multicall3                    | 0xcA11bde05977b3631167028862bE2a173976CA11 | /                                           |
| EntryPoint                    | 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108 | /                                           |
| SafeSingletonFactory          | 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7 | /                                           |

## Testnet

### Base Sepolia

| Contract Name               | Address                                    | ProxyAdmin                                 |
|-----------------------------|--------------------------------------------|--------------------------------------------|
| TestTrust                   | 0xA54b4E6e356b963Ee00d1C947f478d9194a1a210 | /                                          |

### Intuition Testnet

| Contract Name                 | Address                                    | ProxyAdmin                                  |
|-------------------------------|--------------------------------------------|---------------------------------------------|
| Multicall3                    | 0xcA11bde05977b3631167028862bE2a173976CA11 | /                                           |
| EntryPoint                    | 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108 | /                                           |
