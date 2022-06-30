// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IFERC1155Distributor {
    error NonEOA();
    error CallerNotOwner();
    error OverWalletLimit();
    error InvalidSaleState();
    error InvalidEtherAmount();
    error InvalidTxnAmount();
    error InvalidHoldTime();
    error TransferFailed();
    error InvalidTime();
    error InvalidSignature();
    error InvalidArrayLength();
    error AlreadyClaimed();
}
