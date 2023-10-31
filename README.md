# Web3.0 Lottery Smart Contract

This is a Solidity smart contract for a web3.0 lottery game, which includes features like purchasing tickets, random number generation, and prize distribution. The contract integrates Chainlink's Verifiable Random Function (VRF) for secure random number generation and Chainlink's Automation.

- Contract deployed on Sepolia testnet: https://sepolia.etherscan.io/address/0x2Ebf67e7F231F2dA9D60052e30a135600e167462

- Frontend demo: https://web3-lottery-frontend-app.vercel.app/

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [Getting Started](#getting-started)
- [Usage](#usage)
- [Functions](#functions)
- [Deploy](#deploy)
- [Scripts](#scripts)
- [Testing](#testing)
- [Credit](#credit)

## Overview

This Solidity smart contract implements a lottery game based on the web3.0 blockchain technology. It allows users to participate by purchasing lottery tickets and utilizes Chainlink's VRF for generating random numbers, ensuring the fairness of the game.

## Features

- Users can purchase lottery tickets by selecting a number ranging from 1 to 99, and sending ETH.
- Chainlink VRF is used for random number generation, making the lottery fair and transparent.
- Commission fees are collected from ticket sales and can be withdrawn by the contract owner.
- Prize distribution is performed automatically, with prizes distributed to winners.
- Chainlink's Automation Upkeep functions enable periodic lottery rounds and winner determination.

## Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you did it right if you can run `git --version` and you see a response like `git version x.x.x`
- [foundry](https://getfoundry.sh/)
  - You'll know you did it right if you can run `forge --version` and you see a response like `forge 0.2.0 (816e00b 2023-03-16T00:05:26.396218Z)`

## Getting Started

1. Clone this repository to your local development environment.
2. Configure the necessary parameters in the contract constructor, such as the cost of a ticket, commission rate, and VRF settings.
3. Compile and deploy the smart contract to your preferred Ethereum network (e.g., Sepolia or Mainnet).
4. Ensure that your contract has LINK tokens to fund Chainlink VRF requests.
5. Interact with the contract using your preferred Ethereum wallet, allowing users to buy tickets, withdraw commissions, and check lottery results.

# Usage

## Functions

- `buyTicket(uint256 number)`: Users can buy lottery tickets by specifying a number and sending ETH.
- `withdrawCommision()`: The contract owner can withdraw accumulated commissions.
- Use the provided getter functions to query the contract's state and data.
- After you register the contract as an upkeep, the Chainlink Automation Network frequently simulates your `checkUpkeep()` off-chain. When `checkUpkeep()` returns true, the Chainlink Automation Network calls `performUpkeep()` on-chain and initiates the lottery draw by requesting random numbers from Chainlink VRF. This cycle repeats until the upkeep is cancelled or runs out of funding.

## Deploy

### Anvil

This will default to your local node. You need to have it running in another terminal in order for it to deploy.

```
make deploy
```

### Sepolia testnet

```
make deploy ARGS="--network sepolia"
```

This will setup a ChainlinkVRF Subscription for you. If you already have one, update it in the scripts/HelperConfig.s.sol file. It will also automatically add your contract as a consumer.

## Scripts

After deploying to a testnet or local net, you can run the scripts.

Using cast deployed locally example:

```
cast send <LOTTERY_CONTRACT_ADDRESS> "buyTicket(uint256)" "<NUMBER>" --value "<COST_OF_TICKET>" --private-key <PRIVATE_KEY> --rpc-url $SEPOLIA_RPC_URL
```

or, to create a ChainlinkVRF Subscription:

```
make createSubscription ARGS="--network sepolia"
```

## Testing

```
forge test
```

or

```
forge test --fork-url $SEPOLIA_RPC_URL
```

### Test Coverage

```
forge coverage
```

# Acknowledgments

Learnt from and inspired by https://github.com/Cyfrin/foundry-smart-contract-lottery-f23/tree/main
