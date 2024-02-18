# Auction

This is an Auction contract where people can list items for sale. Other users get to place bids and the highest bidder gets the item.

It has 4 entry points:

1. The `list item` entry point: This is where the user supplies the information about the item and the starting bid price.
2. The `bid` entry point: This is where other users can place bids on the item they want. The users are given a receipt object which can be used to claim back their bids if they're unlucky.
3. The `settle bid` entry point: This can only be called by the item creator, it settles the bid and transfers the item to highest bidder.
4. The `get refund` entry point: This is where other users who weren't the highest bidder can reclaim their bids, all they need to do is supply the receipt they got after bidding.

## Installation

To deploy and use the smart contract, follow these steps:

1. **Move Compiler Installation:**
   Ensure you have the Move compiler installed. You can find the Move compiler and instructions on how to install it at [Sui Docs](https://docs.sui.io/).

2. **Compile the Smart Contract:**
   For this contract to compile successfully, please ensure you switch the dependencies to whichever you installed. 
`framework/devnet` for Devnet, `framework/testnet` for Testnet

```bash
   Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/devnet" }
```

then build the contract by running

```
sui move build
```

3. **Deployment:**
   Deploy the compiled smart contract to your blockchain platform of choice.

```
sui client publish --gas-budget 100000000 --json
```

4. **Test:**

```
sui move test
```