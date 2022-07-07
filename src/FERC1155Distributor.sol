// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

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

    /// @dev Variables used for bit-ticketing claim, further details of this implementation
    /// can be found here: https://bit.ly/3nqshRB
    uint256[22] public claims;
    uint256 private constant _MAX_INT = type(uint256).max;

    uint256 public constant FRACTION_PRICE = 0.01 ether;
    uint256 public constant WALLET_LIMIT = 2;
    
    /// @dev Amount of time (in seconds) a Walker must be held to be eligable for a free claim.
    uint256 public holdTimer = 7 days;

    uint256 public fractionId;

    /// @dev Indicates the `amount` of FERC1155 tokens an `address` has claimed.
    mapping (address => uint256) public amount;

    event Claimed(address indexed receiver, uint256 quantity);
    event SetSaleState(address indexed account, uint256 saleState);
    event SetSigner(address indexed account, address signer);
    event SetFractionId(address indexed account, uint256 fractionId);
    event SetHoldTimer(address indexed account, uint256 holdTimer);

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

    /// @notice Function used to purchase FERC1155 tokens during the `PUBLIC` sale state.
    /// @param quantity Desired number of FERC1155 tokens to purchase.
    /// @param signature Signed message digest.
    function claim(uint256 quantity, bytes calldata signature) external payable {
        if (msg.sender != tx.origin) revert NonEOA();
        if (saleState != SaleStates.PUBLIC) revert InvalidSaleState();
        
        if (quantity == 0) revert InvalidTxnAmount();

        if (msg.value != quantity * FRACTION_PRICE) revert InvalidEtherAmount();
        if (amount[msg.sender] + quantity > WALLET_LIMIT) revert OverWalletLimit();
        if (!_verifySignature(signature)) revert InvalidSignature();

        unchecked {
            amount[msg.sender] += quantity;
        }

        fractions.safeTransferFrom(address(this), msg.sender, fractionId, quantity, "");

        emit Claimed(msg.sender, quantity);
    }

    /// @notice Function used to claim a varying amount of FERC1155 tokens.
    /// @param ids An array of Multiversal Walkers token IDs.
    function holderClaim(uint256[] calldata ids) external {
        if (msg.sender != tx.origin) revert NonEOA();
        if (saleState != SaleStates.HOLDER) revert InvalidSaleState();
        if (ids.length == 0) revert InvalidArrayLength();

        uint256 id;
        uint256 indexOffset;
        uint256 offset;
        uint256 bit;

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

    /// @notice Function used to check if a Multiversal Walker token can claim a FERC1155 token.
    /// @param id A Multiversal Walkers token ID.
    /// @return Returns a boolean value indicating whether `id` has claimed, a value of `true`
    /// indicates that `id` has already claimed.
    function hasClaimed(uint256 id) external view returns (bool) {
        return claims[id / 256] >> id % 256 & 1 == 0;
    }

    /// @notice Function used to check if many Multiversal Walker tokens can claim a FERC1155 token.
    /// @param ids An array of Multiversal Walkers token IDs.
    /// @return Returns an array of  boolean value indicating whether `id` of `ids` has claimed, a value
    /// of `true` indicates that `id` has already claimed.
    function hasClaimedMany(uint256[] calldata ids) external view returns (bool[] memory) {
        bool[] memory results = new bool[](ids.length);
        uint256 id;
        
        for (uint256 i=0; i<ids.length; i++) {
            id = ids[i];
            results[i] = claims[id / 256] >> id % 256 & 1 == 0 ? true : false;
        }

        return results;
    }

    function signer() external view returns (address) {
        return _signer;
    }

    function setSigner(address newSigner) external onlyOwner {
        _signer = newSigner;

        emit SetSigner(msg.sender, newSigner);
    }

    /// @notice Function used to set a new `saleState` value.
    /// @dev 0 = PAUSED, 1 = ACTIVE.
    function setSaleState(uint256 newSaleState) external onlyOwner {
        if (newSaleState > uint256(SaleStates.HOLDER)) revert InvalidSaleState();
        
        saleState = SaleStates(newSaleState);

        emit SetSaleState(msg.sender, newSaleState);
    }

    /// @notice Function used to set a new `fractionId` value.
    /// @dev The `fractionId` value is important as this is the unique
    /// identifier in the fractional.art FERC1155 contract.
    function setFractionId(uint256 newFractionId) external onlyOwner {
        fractionId = newFractionId;

        emit SetFractionId(msg.sender, newFractionId);
    }

    /// @notice Function used to set a new `holdTimer` value.
    /// @param newHoldTimer The amount of time, in seconds, that a user must holder a
    /// Multiversal Walkers token for to be eligable for a free claim.
    /// @dev 86400 * n, whereby n represents the amount of days.
    function setHoldTimer(uint256 newHoldTimer) external onlyOwner {
        if (newHoldTimer % 1 days != 0) revert InvalidTime();
        
        holdTimer = newHoldTimer;

        emit SetHoldTimer(msg.sender, newHoldTimer);
    }

    /// @notice Function used to withdraw Ether from this contract.
    function withdrawFunds() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        if (!success) revert TransferFailed();
    }

    /// @notice Function used to withdraw all fractions from this contract.
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