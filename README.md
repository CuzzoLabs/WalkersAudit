# Multiversal Walkers

- `Walkers.sol` - ERC721A minting contract.

# Note

When cloning this repo, you will need to use the `--recursive` flag to correctly include all submodules.

Existing unit tests have been included and can be run with `forge test`.

# Token Distribution

For clarity when auditing, it's important to understand the intended distribution of tokens to gain clarity that the code is functioning as intended. For this reason, tokens will be distributed in the following manner, assuming a max supply of `5555` tokens:

- Phase 1: 50 tokens minted on contract deployment.
- Phase 2: 2000 tokens minted during fair auction mint (`auctionMint`) at a maximum of 20 tokens per wallet, subject to change.
- Phase 3: 3505 tokens minted during whitelist mint (`whitelistMint`) at a reduced price (TBD) determined by the fair auction sellout price.
- Phase 4: Remaining tokens are available to mint (`publicMint`) to those who did not mint during the whitelist mint at the fair auction sellout price.
- Phase 5: Further remaining tokens are available to claim by the team (`teamMint`).

With this in mind, it is important to note that it is entirely possible for both phases 4/5 to not occur based on success of the previous phases. Also, phase 5 may take place prior to phase 4 depending on the amount of tokens remaining from phase 3.
