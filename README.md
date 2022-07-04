# Multiversal Walkers

This repository contains all smart contracts relating to the Multiversal Walkers project. This project utilises the Ethereum blockchain to deliver an NFT experience like no other and uses [Foundry](https://github.com/foundry-rs/foundry) as its testing framework.

- `Walkers.sol` - ERC721 Genesis Token.
- `Passport.sol` - ERC721 Passport.
- ~~`FERC1155Distributor.sol` - FERC1155 Token Distributor.~~
- ~~`Portal.sol` - ERC1155 Portal.~~

# Testing

Unit tests can be run with the following commands:

`Walkers.sol` Tests: `forge test --match-contract Walkers`

`FERC1155Distributor.sol` Tests: `forge test --match-contract FERC1155Distributor --rpc-url MAINNET_RPC_URL`

NOTE: `FERC1155Distributor` tests must be run with a mainnet RPC as they interact with the mainnet fractional.art contracts.

# Token Distribution / Walkers.sol

For clarity when auditing, it's important to understand the intended distribution of tokens to gain clarity that the code is functioning as intended. For this reason, tokens will be distributed in the following manner, assuming a max supply of `5555` tokens:

- Phase 1: 55 tokens are minted on contract deployment to an address provided within the contract constructor.
- Phase 2: 2500 tokens are available to select wallet addresses and will be minted via the `publicMint` function. The `publicTokens` variable acts as a soft-cap in regards to how many tokens can be minted during this particular phase. The contract is deployed with this value initialised at 2555 to account for the tokens that are minted on deployment (`RESERVED_TOKENS`). Whilst select addresses can mint, this isn't classified as the whitelist mint as there will an over-allocation of addresses within this phase. 
- Phase 3: 3000 tokens are available to those who have been whitelisted for a guranteed mint via `multilistMint`. Whilst most addresses will only be able to mint 1 token, an amount of around ~200 addresses will be able to mint 2. It is acknowledged that this function can only be called once and there will be a prompt on the front-end informing users of this functionality.
- Phase 4: Dependent on how many tokens remain the following actions will take place:
    - A: If an amount of tokens deemed large by the team are still available, the `setPublicTokens` function will be called and `publicTokens` updated to a value of `5555`. From here, another `publicMint` will take place. Prior to this occuring however, additional addresses will be signed and stored on the front-end to allow for additional users the oppurtunity to mint.
    - B: If a relatively small number of tokens remained, these will be minted via the `ownerMint` function and kept for business promotion or any other purpose deemed necessary.
    - C: If no tokens remain, the sale state is set to `PAUSED` indefinitely.

Notes:
- The maximum supply of tokens should never exceed 5555.
- A hard cap of 2 tokens per wallet via `publicMint` is imposed and should never be exceeded.
- Whilst contracts are able to call both `publicMint` and `multilistMint`, `_mint` has been opted over `_safeMint` as users shouldn't be calling through a smart contract to begin with. Check-effects-interaction pattern has been implemented to prevent any form of reentrancy. I believe ERC721A also has built-in reentrancy protection.

# Fractionalization / FERC1155Distributor.sol

We will be leveraing [fractional.art](https://fractional.art/) to fractionalize one of the tokens that are reserved for the team in the initial mint. A total of `15555` fractions will be created whereby 55 will be transferred to the team vault leaving a total of 15500 leftover for a mixture of public sale and holder claims. Distribution of these fractions will take place in the following order:

- Phase 1: A total of 10000 fractions will be transferred to the deployed `FERC1155Distributor` contract. Following this, a public sale will take place via `claim` at a price of 0.01 Ether per fraction until tokens are exhausted or the team chooses to close the sale.
- Phase 2: A total of 5500 fractions will either be transferred to the contract, or some other amount that brings the total balance of the contract to 5500 FERC1155 tokens. The `holderClaim` function will now be made active and assuming a caller is in ownership of a Multiversal Walkers token and has held said token for a period of `holdTimer`, they can claim 1 token for free.
    - It is inferred that if a Multiversal Walkers token is used to claim a FERC1155 token, that same Walker cannot be used to claim another FERC1155 token ever again.
    - The strategy used to implement the bit ticketing claim is described in detail [here](https://medium.com/donkeverse/hardcore-gas-savings-in-nft-minting-part-3-save-30-000-in-presale-gas-c945406e89f0).
    - The purpose of `_frontGas` is for the team to pay the initial 20,000 gas fee associated with the first caller within each index update their bit from 0 to 1, assuming we didn't front the gas cost to begin with.

Notes:
- A caller should not be able to claim more than 2 FERC1155 tokens per wallet in the `claim` function.
- A unique Walker token should not be able to claim a FERC1155 token more than once.
