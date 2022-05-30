// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "erc721a/contracts/extensions/IERC721AQueryable.sol";

interface IWalkers is IERC721AQueryable {
    error NonEOA();
    error InvalidSaleState();
    error WalletLimitExceeded();
    error AuctionSupplyExceeded();
    error InvalidEtherAmount();
    error InvalidSignature();
    error MaxSupplyExceeded();
    error InvalidAuctionEndPrice();
    error TokenAlreadyClaimed();
    error InvalidSpendAmount();
    error RefundFailed();
    error InvalidStartTime();
    error AccountMismatch();

    function tokenOwnership(uint256) external view returns (TokenOwnership memory);
}