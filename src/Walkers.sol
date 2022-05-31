// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/finance/PaymentSplitter.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "erc721a/contracts/extensions/ERC721AQueryable.sol";
import "./interfaces/IWalkers.sol";

contract Walkers is IWalkers, Ownable, ERC721AQueryable, PaymentSplitter {

    using ECDSA for bytes32;

    enum SaleStates {
        PAUSED,
        WHITELIST,
        PUBLIC,
        AUCTION,
        REFUND
    }

    SaleStates public saleState;

    string private _baseTokenURI;
    string private _contractURI;
    address private _signerAddress;

    uint256 public constant MAX_SUPPLY = 5555;
    uint256 public constant RESERVED_TOKENS = 50;

    uint256 public constant FA_WALLET_LIMIT = 20;
    uint256 public constant FA_SUPPLY = 3555;
    uint256 public constant FA_START_PRICE = 1 ether;
    uint256 public constant FA_STEP_DURATION = 5 minutes;
    uint256 public constant FA_DECREMENT = 0.1 ether;
    uint256 public constant FA_RESERVE_PRICE = 0.1 ether;
    uint256 public auctionStartTime;
    uint256 public auctionEndPrice;

    mapping (address => uint256) public spend;

    event Minted(address indexed receiver, uint256 quantity);
    event Refund(address indexed receiver, uint256 amount);

    constructor(
        address[] memory payees,
        uint256[] memory shares_,
        address receiver
    ) ERC721A("Test", "TEST") PaymentSplitter(payees, shares_) {
        teamMint(receiver, RESERVED_TOKENS);
    }

    /// @dev Fair auction.
    function auctionMint(uint256 quantity, bytes calldata signature) external payable {
        if (msg.sender != tx.origin) revert NonEOA();
        if (saleState != SaleStates.AUCTION) revert InvalidSaleState();
        if (auctionStartTime == 0) revert InvalidStartTime();
        if (_numberMinted(msg.sender) + quantity > FA_WALLET_LIMIT) revert WalletLimitExceeded();
        
        uint256 newSupply = _totalMinted() + quantity;
        uint256 price = getAuctionPrice();

        if (newSupply > FA_SUPPLY) revert AuctionSupplyExceeded();
        if (msg.value < price * quantity) revert InvalidEtherAmount();
        if (!_verifySignature(signature, 'AUCTION')) revert InvalidSignature();

        if (newSupply == FA_SUPPLY) {
            auctionEndPrice = price;
        }
        
        unchecked {
            spend[msg.sender] += msg.value;
        }

        _mint(msg.sender, quantity);

        emit Minted(msg.sender, quantity);
    }

    function publicMint(bytes calldata signature) external payable {
        if (msg.sender != tx.origin) revert NonEOA();
        if (saleState != SaleStates.PUBLIC) revert InvalidSaleState();
        if (_totalMinted() + 1 > MAX_SUPPLY) revert MaxSupplyExceeded();
        if (auctionEndPrice == 0) revert InvalidAuctionEndPrice();
        if (msg.value != auctionEndPrice) revert InvalidEtherAmount();
        if (_getAux(msg.sender) != 0) revert TokenAlreadyClaimed();
        if (!_verifySignature(signature, 'PUBLIC')) revert InvalidSignature();

        /// @dev Set arbitrary value to acknowledge user has minted.
        /// Updating aux value to non-zero is cheaper then updating a mapping.
        _setAux(msg.sender, 1);

        _mint(msg.sender, 1);

        emit Minted(msg.sender, 1);
    }

    function whitelistMint(bytes calldata signature) external payable {
        if (msg.sender != tx.origin) revert NonEOA();
        if (saleState != SaleStates.WHITELIST) revert InvalidSaleState();
        if (_totalMinted() + 1 > MAX_SUPPLY) revert MaxSupplyExceeded();
        if (auctionEndPrice == 0) revert InvalidAuctionEndPrice();
        if (msg.value != auctionEndPrice / 2) revert InvalidEtherAmount();
        if (_getAux(msg.sender) != 0) revert TokenAlreadyClaimed();
        if (!_verifySignature(signature, 'WHITELIST')) revert InvalidSignature();

        _setAux(msg.sender, 1);

        _mint(msg.sender, 1);

        emit Minted(msg.sender, 1);
    }

    function getAuctionPrice() public view returns (uint256) {
        if (saleState != SaleStates.AUCTION || auctionStartTime >= block.timestamp) {
            return FA_START_PRICE;
        }

        uint256 decrements = (block.timestamp - auctionStartTime) / FA_STEP_DURATION;
        if (decrements * FA_DECREMENT >= FA_START_PRICE) {
            return FA_RESERVE_PRICE;
        }

        return FA_START_PRICE - decrements * FA_DECREMENT;
    }

    function refund() external {
        if (msg.sender != tx.origin) revert NonEOA();
        if (saleState != SaleStates.REFUND) revert InvalidSaleState();
        
        uint256 amount = spend[msg.sender];
        if (amount == 0) revert InvalidSpendAmount();

        spend[msg.sender] = 0;

        uint256 refundAmount;
        if (_getAux(msg.sender) == 0) {
            refundAmount = amount - auctionEndPrice * _numberMinted(msg.sender);
        } else {
            refundAmount = amount - auctionEndPrice * (_numberMinted(msg.sender) - 1);
        }

        bool success = payable(msg.sender).send(refundAmount);
        if (!success) revert RefundFailed();

        emit Refund(msg.sender, refundAmount);
    }
    
    function release(address payable account) public override {
        if (msg.sender != account) revert AccountMismatch();
        super.release(account);
    }

    /// @notice Function used to get token ownership data for a specified token ID.
    function tokenOwnership(uint256 tokenId) public view returns (TokenOwnership memory) {
        return _ownershipOf(tokenId);
    }

    /// @notice Function used to get the aux value for a specified address.
    function getAux(address account) public view returns (uint64) {
        return _getAux(account);
    }

    function setAuctionStartTime(uint256 newAuctionStartTime) external onlyOwner {
        if (newAuctionStartTime < block.timestamp) revert InvalidStartTime();
        auctionStartTime = newAuctionStartTime;
    }

    function setSaleState(uint256 newSaleState) external onlyOwner {
        if (newSaleState > uint256(SaleStates.REFUND)) revert InvalidSaleState();
        saleState = SaleStates(newSaleState);
    }

    function setSignerAddress(address newSignerAddress) external onlyOwner {
        _signerAddress = newSignerAddress;
    }

    function setBaseTokenURI(string memory newBaseTokenURI) external onlyOwner {
        _baseTokenURI = newBaseTokenURI;
    }

    function setContractURI(string memory newContractURI) external onlyOwner {
        _contractURI = newContractURI;
    }

    function teamMint(address receiver, uint256 quantity) public onlyOwner {
        if (_totalMinted() + quantity > MAX_SUPPLY) revert MaxSupplyExceeded();
        _safeMint(receiver, quantity);
    }

    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    function signerAddress() external view returns (address) {
        return _signerAddress;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }

    function _verifySignature(
        bytes calldata signature,
        string memory phase
    ) internal view returns (bool) {
        return _signerAddress == keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            bytes32(abi.encodePacked(uint160(msg.sender), phase))
        )).recover(signature);
    }

}
