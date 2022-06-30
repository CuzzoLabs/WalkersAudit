// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./interfaces/IFERC1155Distributor.sol";
import "./interfaces/IFERC1155.sol";
import "./interfaces/IWalkers.sol";

/// @title FERC1155 Distributor for Multiversal Walkers
/// @author ItsCuzzo

contract FERC1155Distributor is IFERC1155Distributor, Ownable {
    using ECDSA for bytes32;

    enum SaleStates {
        PAUSED,
        PUBLIC,
        HOLDER
    }

    SaleStates public saleState;
    
    address private _signer;

    IFERC1155 public immutable fractions;
    IWalkers public immutable walkers;

    uint256[22] public claims;
    uint256 private constant _MAX_INT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    uint256 public constant FRACTION_PRICE = 0.01 ether;
    uint256 public constant WALLET_LIMIT = 2;
    
    /// @dev The amount of time a Walker must hold to be eligable for a free claim.
    uint256 public holdTimer = 7 days;

    uint256 public fractionId;

    /// @dev `address` => `amount`, how many FERC1155 tokens an address has claimed.
    mapping (address => uint256) public amount;

    event Claimed(address indexed receiver, uint256 quantity);

    /// @dev `walkers_` is the address of the Multiversal Walkers contract.
    /// @dev `fractions_` is the address of the fractional.art FERC1155 contract.
    constructor(
        address walkers_,
        address fractions_
    ) {
        walkers = IWalkers(walkers_);
        fractions = IFERC1155(fractions_);

        _frontGas();
    }

    /// @notice Function used to claim FERC1155 tokens.
    function claim(uint256 quantity, bytes calldata signature) external payable {
        if (msg.sender != tx.origin) revert NonEOA();
        if (saleState != SaleStates.PUBLIC) revert InvalidSaleState();
        
        /// @dev Explicit check if `quantity` is greater than 0 as will not revert otherwise.
        if (quantity == 0) revert InvalidTxnAmount();

        if (msg.value != quantity * FRACTION_PRICE) revert InvalidEtherAmount();
        if (amount[msg.sender] + quantity > WALLET_LIMIT) revert OverWalletLimit();
        if (!_verifySignature(signature)) revert InvalidSignature();

        /// @dev Overflow is not possible in this context as `quantity` will never be greater than `WALLET_LIMIT`.
        unchecked {
            amount[msg.sender] += quantity;
        }

        /// @dev Transfer `quantity` of FERC1155 tokens to caller.
        fractions.safeTransferFrom(address(this), msg.sender, fractionId, quantity, "");

        emit Claimed(msg.sender, quantity);
    }

    /// @notice Function used to claim an FERC1155 token dependent on time a Walker is held.
    /// @param ids A Multiversal Walkers token ID.
    function holderClaim(uint256[] calldata ids) external {
        if (msg.sender != tx.origin) revert NonEOA();
        if (saleState != SaleStates.HOLDER) revert InvalidSaleState();
        if (ids.length == 0) revert InvalidArrayLength();

        uint256 id;
        uint256 indexOffset;
        uint256 offset;
        uint256 bit;

        /// @dev Overflow in this context is not possible.
        unchecked {
            for (uint256 i=0; i<ids.length; i++) {
                id = ids[i];

                IWalkers.TokenOwnership memory tokenOwnership = walkers.tokenOwnership(id);

                if (tokenOwnership.addr != msg.sender) revert CallerNotOwner();
                if (block.timestamp - tokenOwnership.startTimestamp < holdTimer) revert InvalidHoldTime();

                indexOffset = id / 256;
                offset = id % 256;
                bit = claims[indexOffset] >> offset & 1;

                if (bit != 1) revert AlreadyClaimed();

                claims[indexOffset] = claims[indexOffset] & ~(1 << offset);
            }
        }

        fractions.safeTransferFrom(address(this), msg.sender, fractionId, ids.length, "");

        emit Claimed(msg.sender, ids.length);
    }

    /// @notice Function used to see if the user has a FERC1155 token available for claim.
    /// @param id A Multiversal Walkers token ID.
    function hasClaimed(uint256 id) external view returns (bool) {
        return claims[id / 256] >> id % 256 & 1 == 0;
    }

    /// @notice Function used to see if the user has a FERC1155 token available for claim.
    /// @param ids An array of Multiversal Walkers token IDs.
    function hasClaimedMany(uint256[] calldata ids) external view returns (bool[] memory) {
        bool[] memory results = new bool[](ids.length);
        uint256 id;
        
        for (uint256 i=0; i<ids.length; i++) {
            id = ids[i];
            results[i] = claims[id / 256] >> id % 256 & 1 == 0 ? true : false;
        }

        return results;
    }

    /// @notice Function used to view the current `_signer` value.
    function signer() external view returns (address) {
        return _signer;
    }

    /// @notice Function used to set a new `_signer` value.
    function setSigner(address newSigner) external onlyOwner {
        _signer = newSigner;
    }

    /// @notice Function used to set a new `saleState` value.
    /// @dev 0 = PAUSED, 1 = ACTIVE
    function setSaleState(uint256 newSaleState) external onlyOwner {
        if (newSaleState > uint256(SaleStates.HOLDER)) revert InvalidSaleState();
        saleState = SaleStates(newSaleState);
    }

    /// @notice Function used to set a new `fractionId` value.
    /// @dev The `fractionId` value is important as this is the unique
    /// identifier in the fractional.art FERC1155 contract.
    function setFractionId(uint256 newFractionId) external onlyOwner {
        fractionId = newFractionId;
    }

    /// @notice Function used to set a new `holdTimer` value.
    /// @dev `newDiamondTimer` is some number of days in seconds.
    /// E.g. 86400 * n, whereby n represents the amount of days.
    function setHoldTimer(uint256 newHoldTimer) external onlyOwner {
        if (newHoldTimer % 1 days != 0) revert InvalidTime();
        holdTimer = newHoldTimer;
    }

    /// @notice Function used to withdraw Ether from this contract.
    function withdrawFunds() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        if (!success) revert TransferFailed();
    }

    /// @notice Function used to withdraw all fractions in this contract.
    function withdrawFractions() external onlyOwner {
        fractions.safeTransferFrom(
            address(this),
            msg.sender,
            fractionId,
            fractions.balanceOf(address(this), fractionId),
            ""
        );
    }

    /// @dev See {ERC1155Holder}.
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /// @dev See {ERC1155Holder}.
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    /// @dev Called once within the constructor to set all indexes within the
    /// `claims` array to `_MAX_INT` value.
    function _frontGas() internal {
        unchecked {
            for (uint256 i=0; i<22; i++) {
                claims[i] = _MAX_INT;
            }
        }
    }

    function _verifySignature(
        bytes memory signature
    ) internal view returns (bool) {
        return _signer == keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            bytes32(abi.encodePacked(msg.sender, 'FERC1155'))
        )).recover(signature);
    }

}