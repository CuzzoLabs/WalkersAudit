// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "../Walkers.sol";
import "../interfaces/IWalkers.sol";

contract WalkersTest is Test {
    using stdStorage for StdStorage;

    Walkers public walkers;

    address[] public payees = [address(0x11111), address(0x22222), address(0x33333)];
    uint256[] public shares = [50, 35, 15];

    address public constant ALICE = address(0xbabe);
    address public constant BOB = address(0xbeef);

    uint256 public constant AUCTION_START_TIME = 1000000000;

    address public constant SIGNER_ADDRESS = 0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf;
    uint256 public constant PRIVATE_KEY = 1;

    event Minted(address indexed receiver, uint256 quantity);
    event Refund(address indexed receiver, uint256 amount);

    modifier userAccount() {
        startHoax(ALICE, ALICE, 100 ether);
        _;
        vm.stopPrank();
    }

    modifier setSignerAddress() {
        walkers.setSignerAddress(SIGNER_ADDRESS);
        _;
    }

    modifier setSaleState(Walkers.SaleStates newSaleState) {
        walkers.setSaleState(uint256(newSaleState));
        _;
    }

    modifier setAuctionStartTime() {
        walkers.setAuctionStartTime(AUCTION_START_TIME);
        vm.warp(AUCTION_START_TIME);
        _;
    }

    modifier mintTokens(uint256 amount, uint256 newSaleState) {
        walkers.setSaleState(newSaleState);

        for (uint i=1; i<=amount; i++) {
            address account = address(uint160(i));

            hoax(account, account, 1 ether);

            bytes memory signature;
            if (newSaleState == 1) {
                signature = _getSignature(account, 'WHITELIST');
                walkers.whitelistMint{value: 0.5 ether}(signature);
            } else if (newSaleState == 2) {
                signature = _getSignature(account, 'PUBLIC');
                walkers.publicMint{value: 1 ether}(signature);
            } else {
                signature = _getSignature(account, 'AUCTION');
                walkers.auctionMint{value: 1 ether}(1, signature);
            }

            vm.stopPrank();
        }

        _;
    }

    function setUp() public {
        walkers = new Walkers(payees, shares, BOB);
    }

    /* Auction Testing */

    function testAuctionMint(
        uint256 quantity
    )
        public
        setSignerAddress
        setAuctionStartTime
        setSaleState(Walkers.SaleStates.AUCTION)
        userAccount
    {
        vm.assume(quantity > 0 && quantity <= 3);

        bytes memory signature = _getSignature(ALICE, 'AUCTION');

        vm.expectEmit(true, true, false, false);
        emit Minted(ALICE, quantity);
        walkers.auctionMint{value: quantity * 1 ether}(quantity, signature);

        uint256 tokenBalance = walkers.balanceOf(ALICE);
        address owner = walkers.ownerOf(51);

        assertEq(tokenBalance, quantity);
        assertEq(owner, ALICE);
    }

    function testAuctionMintUpdatesFinalPrice()
        public
        setSignerAddress
        setAuctionStartTime
        mintTokens(3504, uint8(Walkers.SaleStates.AUCTION))
        userAccount
    {
        bytes memory signature = _getSignature(ALICE, 'AUCTION');
        walkers.auctionMint{value: 1 ether}(1, signature);

        uint256 _finalPrice = walkers.auctionEndPrice();
        assertEq(_finalPrice, 1 ether);
    }

    function testAuctionMintUpdatesAux()
        public
        setSignerAddress
        setAuctionStartTime
        setSaleState(Walkers.SaleStates.AUCTION)
        userAccount
    {
        bytes memory signature = _getSignature(ALICE, 'AUCTION');
        walkers.auctionMint{value: 1 ether}(1, signature);

        uint256 cost = walkers.spend(ALICE);
        assertEq(cost, 1 ether);
    }

    function testAuctionPriceNeverFallsBelowReserve(
        uint64 timestamp
    )
        public
        setSignerAddress
        setAuctionStartTime
        setSaleState(Walkers.SaleStates.AUCTION)
    {
        vm.assume(timestamp >= AUCTION_START_TIME);
        vm.warp(timestamp);
        
        uint256 price = walkers.getAuctionPrice();
        assertTrue(price >= 0.1 ether);
    }

    function testAuctionDecrements()
        public
        setSignerAddress
        setAuctionStartTime
        setSaleState(Walkers.SaleStates.AUCTION)
    {
        uint256 decrements = 10;
        uint256 price;

        for (uint256 i=0; i<decrements; i++) {
            price = walkers.getAuctionPrice();
            assertEq(price, 1 ether - 0.1 ether * i);
            vm.warp(block.timestamp + 5 minutes);
        }
    }

    function testCannotAuctionMintThroughContract()
        public
    {
        bytes memory signature = _getSignature(ALICE, 'AUCTION');

        hoax(ALICE);
        vm.expectRevert(IWalkers.NonEOA.selector);
        walkers.auctionMint{value: 1 ether}(1, signature);
    }

    function testCannotAuctionMintInvalidSaleState(
        uint256 newSaleState
    )
        public
    {
        vm.assume(newSaleState != 3 && newSaleState <= 4);
        walkers.setSaleState(newSaleState);

        bytes memory signature = _getSignature(ALICE, 'AUCTION');
        hoax(ALICE, ALICE, 1 ether);
        vm.expectRevert(IWalkers.InvalidSaleState.selector);
        walkers.auctionMint{value: 1 ether}(1, signature);
    }

    function testCannotAuctionMintOverTxnLimit()
        public
        setSignerAddress
        setAuctionStartTime
        setSaleState(Walkers.SaleStates.AUCTION)
        userAccount
    {
        uint256 quantity = 21;
        bytes memory signature = _getSignature(ALICE, 'AUCTION');
        vm.expectRevert(IWalkers.WalletLimitExceeded.selector);
        walkers.auctionMint{value: quantity * 1 ether}(quantity, signature);
    }

    function testCannotAuctionMintOverMaxSupply()
        public
        setSignerAddress
        setAuctionStartTime
        mintTokens(3505, uint8(Walkers.SaleStates.AUCTION))
        userAccount
    {
        bytes memory signature = _getSignature(ALICE, 'AUCTION');
        vm.expectRevert(IWalkers.AuctionSupplyExceeded.selector);
        walkers.auctionMint{value: 1 ether}(1, signature);
    }

    function testCannotAuctionMintInvalidEther(
        uint256 _ether
    )
        public
        setSignerAddress
        setAuctionStartTime
        setSaleState(Walkers.SaleStates.AUCTION)
        userAccount
    {
        vm.assume(_ether < 1 ether);

        bytes memory signature = _getSignature(ALICE, 'AUCTION');
        vm.expectRevert(IWalkers.InvalidEtherAmount.selector);
        walkers.auctionMint{value: _ether}(1, signature);
    }

    function testCannotAuctionMintInvalidSignature()
        public
        setAuctionStartTime
        setSaleState(Walkers.SaleStates.AUCTION)
        userAccount
    {
        bytes memory signature = _getSignature(ALICE, 'AUCTION');
        vm.expectRevert(IWalkers.InvalidSignature.selector);
        walkers.auctionMint{value: 1 ether}(1, signature); 
    }

    /* Minting Testing */

    function testPublicMint()
        public
        setSignerAddress
        setSaleState(Walkers.SaleStates.PUBLIC)
        userAccount
    {
        bytes memory signature = _getSignature(ALICE, 'PUBLIC');

        stdstore
            .target(address(walkers))
            .sig("auctionEndPrice()")
            .checked_write(1 ether);
        
        vm.expectEmit(true, true, false, false);
        emit Minted(ALICE, 1);
        walkers.publicMint{value: 1 ether}(signature);

        uint256 tokenBalance = walkers.balanceOf(ALICE);
        address owner = walkers.ownerOf(51);

        assertEq(tokenBalance, 1);
        assertEq(owner, ALICE);
    }

    function testCannotPublicMintThroughContract()
        public
    {
        bytes memory signature = _getSignature(ALICE, 'PUBLIC');
        hoax(ALICE);
        vm.expectRevert(IWalkers.NonEOA.selector);
        walkers.publicMint{value: 0.1 ether}(signature);
    }

    function testCannotPublicMintInvalidSaleState(
        uint256 newSaleState
    )
        public
    {
        vm.assume(newSaleState != 2 && newSaleState <= 4);
        walkers.setSaleState(newSaleState);

        bytes memory signature = _getSignature(ALICE, 'PUBLIC');
        hoax(ALICE, ALICE, 1 ether);
        vm.expectRevert(IWalkers.InvalidSaleState.selector);
        walkers.publicMint{value: 0.1 ether}(signature);
    }

    function testCannotPublicMintOverMaxSupply()
        public
        setSignerAddress
        setAuctionStartTime
        mintTokens(3505, uint8(Walkers.SaleStates.AUCTION))
        mintTokens(2000, uint8(Walkers.SaleStates.PUBLIC))
        userAccount
    {
        bytes memory signature = _getSignature(ALICE, 'PUBLIC');
        
        vm.expectRevert(IWalkers.MaxSupplyExceeded.selector);
        walkers.publicMint{value: 0.5 ether}(signature);
    }

    function testCannotPublicMintInvalidEtherAmount(
        uint256 _ether
    )
        public
        setSignerAddress
        setSaleState(Walkers.SaleStates.PUBLIC)
        userAccount
    {
        vm.assume(_ether != 1 ether && _ether <= 100 ether);

        stdstore
            .target(address(walkers))
            .sig("auctionEndPrice()")
            .checked_write(1 ether);

        bytes memory signature = _getSignature(ALICE, 'PUBLIC');
        vm.expectRevert(IWalkers.InvalidEtherAmount.selector);
        walkers.publicMint{value: _ether}(signature);
    }

    function testCannotPublicMintTwice()
        public
        setSignerAddress
        setSaleState(Walkers.SaleStates.PUBLIC)
        userAccount
    {
        stdstore
            .target(address(walkers))
            .sig("auctionEndPrice()")
            .checked_write(1 ether);

        bytes memory signature = _getSignature(ALICE, 'PUBLIC');
        walkers.publicMint{value: 1 ether}(signature);
        vm.expectRevert(IWalkers.TokenAlreadyClaimed.selector);
        walkers.publicMint{value: 1 ether}(signature);
    }

    function testCannotPublicMintInvalidSignature()
        public
        setSaleState(Walkers.SaleStates.PUBLIC)
        userAccount
    {
        bytes memory signature = _getSignature(ALICE, 'PUBLIC');

        stdstore
            .target(address(walkers))
            .sig("auctionEndPrice()")
            .checked_write(1 ether);

        vm.expectRevert(IWalkers.InvalidSignature.selector);
        walkers.publicMint{value: 1 ether}(signature);
    }

    function testWhitelistMint()
        public
        setSignerAddress
        setSaleState(Walkers.SaleStates.WHITELIST)
        userAccount
    {
        bytes memory signature = _getSignature(ALICE, 'WHITELIST');

        stdstore
            .target(address(walkers))
            .sig("auctionEndPrice()")
            .checked_write(1 ether);
        
        vm.expectEmit(true, true, false, false);
        emit Minted(ALICE, 1);
        walkers.whitelistMint{value: 0.5 ether}(signature);

        uint256 tokenBalance = walkers.balanceOf(ALICE);
        address owner = walkers.ownerOf(51);

        assertEq(tokenBalance, 1);
        assertEq(owner, ALICE);
    }

    function testCannotWhitelistMintThroughContract()
        public
    {
        bytes memory signature = _getSignature(ALICE, 'WHITELIST');
        hoax(ALICE);
        vm.expectRevert(IWalkers.NonEOA.selector);
        walkers.whitelistMint{value: 0.1 ether}(signature);
    }

    function testCannotWhitelistMintInvalidSaleState(
        uint256 newSaleState
    )
        public
    {
        vm.assume(newSaleState != 1 && newSaleState <= 4);
        walkers.setSaleState(newSaleState);

        bytes memory signature = _getSignature(ALICE, 'WHITELIST');
        hoax(ALICE, ALICE, 1 ether);
        vm.expectRevert(IWalkers.InvalidSaleState.selector);
        walkers.whitelistMint{value: 0.1 ether}(signature);
    }

    function testCannotWhitelistMintOverMaxSupply()
        public
        setSignerAddress
        setAuctionStartTime
        mintTokens(3505, uint8(Walkers.SaleStates.AUCTION))
        mintTokens(2000, uint8(Walkers.SaleStates.WHITELIST))
        userAccount
    {
        bytes memory signature = _getSignature(ALICE, 'WHITELIST');
        vm.expectRevert(IWalkers.MaxSupplyExceeded.selector);
        walkers.whitelistMint{value: 0.5 ether}(signature);
    }

    function testCannotWhitelistMintInvalidEtherAmount(
        uint256 _ether
    )
        public
        setSignerAddress
        setSaleState(Walkers.SaleStates.WHITELIST)
        userAccount
    {
        vm.assume(_ether != 0.5 ether && _ether <= 100 ether);

        stdstore
            .target(address(walkers))
            .sig("auctionEndPrice()")
            .checked_write(1 ether);

        bytes memory signature = _getSignature(ALICE, 'WHITELIST');
        vm.expectRevert(IWalkers.InvalidEtherAmount.selector);
        walkers.whitelistMint{value: _ether}(signature);
    }

    function testCannotWhitelistMintTwice()
        public
        setSignerAddress
        setSaleState(Walkers.SaleStates.WHITELIST)
        userAccount
    {
        stdstore
            .target(address(walkers))
            .sig("auctionEndPrice()")
            .checked_write(1 ether);

        bytes memory signature = _getSignature(ALICE, 'WHITELIST');
        walkers.whitelistMint{value: 0.5 ether}(signature);
        vm.expectRevert(IWalkers.TokenAlreadyClaimed.selector);
        walkers.whitelistMint{value: 0.5 ether}(signature);
    }

    function testCannotWhitelistMintInvalidSignature()
        public
        setSaleState(Walkers.SaleStates.WHITELIST)
        userAccount
    {
        bytes memory signature = _getSignature(ALICE, 'WHITELIST');

        stdstore
            .target(address(walkers))
            .sig("auctionEndPrice()")
            .checked_write(1 ether);

        vm.expectRevert(IWalkers.InvalidSignature.selector);
        walkers.whitelistMint{value: 0.5 ether}(signature);
    }

    /* Functionality Testing */

    function testRelease()
        public
        setSignerAddress
        setAuctionStartTime
        mintTokens(1000, uint8(Walkers.SaleStates.AUCTION))
    {
        uint256 oldBalance = address(walkers).balance;

        address account;
        for (uint256 i=0; i<payees.length; i++) {
            account = payees[i];
            vm.prank(account);
            walkers.release(payable(account));
        }

        assertEq(oldBalance, 1000 ether);
        assertEq(payees[0].balance, 500 ether);
        assertEq(payees[1].balance, 350 ether);
        assertEq(payees[2].balance, 150 ether);
    }

    function testCannotReleaseNonShareholder()
        public
    {
        vm.prank(ALICE);
        vm.expectRevert("PaymentSplitter: account has no shares");
        walkers.release(payable(ALICE));
    }

    function testCannotReleaseToDifferentAccount()
        public
    {
        vm.prank(ALICE);
        vm.expectRevert(IWalkers.AccountMismatch.selector);
        walkers.release(payable(BOB));
    }

    function testTokensOfOwner()
        public
    {
        uint256[] memory _tokens = walkers.tokensOfOwner(BOB);

        for (uint256 i=1; i<=_tokens.length; i++) {
            assertEq(_tokens[i-1], i);
        }

        assertEq(_tokens.length, 50);
    }

    function testTokenOwnership()
        public
    {
        vm.warp(AUCTION_START_TIME);

        walkers.teamMint(ALICE, 1);

        Walkers.TokenOwnership memory tokenOwnership = walkers.tokenOwnership(51);

        assertEq(tokenOwnership.addr, ALICE);
        assertEq(tokenOwnership.startTimestamp, AUCTION_START_TIME);
        assertEq(tokenOwnership.burned, false);
    }

    function testSetSaleState(
        uint256 newSaleState
    )
        public
    {
        vm.assume(newSaleState <= uint256(Walkers.SaleStates.REFUND));
        
        walkers.setSaleState(newSaleState);
        uint256 saleState = uint256(walkers.saleState());

        assertEq(saleState, newSaleState);
    }

    function testCannotSetSaleStateNonOwner()
        public
    {
        hoax(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        walkers.setSaleState(uint8(Walkers.SaleStates.PAUSED));
    }

    function testCannotSetSaleStateInvalidSaleState()
        public
    {
        vm.expectRevert(IWalkers.InvalidSaleState.selector);
        walkers.setSaleState(uint8(5));
    }

    function testSetAuctionStartTime(
        uint256 timestamp
    )
        public
    {
        vm.assume(timestamp > AUCTION_START_TIME);
        walkers.setAuctionStartTime(timestamp);
        uint256 auctionStartTime = walkers.auctionStartTime();
        assertEq(auctionStartTime, timestamp);
    }

    function testCannotSetAuctionStartTimeNonOwner()
        public
    {
        hoax(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        walkers.setAuctionStartTime(0);
    }

    function testCannotSetAuctionStartTimeInPast(
        uint256 timestamp
    )
        public
    {
        vm.warp(AUCTION_START_TIME);
        vm.assume(timestamp < AUCTION_START_TIME);
        vm.expectRevert(IWalkers.InvalidStartTime.selector);
        walkers.setAuctionStartTime(timestamp);
    }

    function testRefundOnSingleAuctionMint()
        public
        setSignerAddress
        setAuctionStartTime
        mintTokens(3504, uint8(Walkers.SaleStates.AUCTION))
    {
        vm.warp(block.timestamp + 60 minutes);

        bytes memory signature = _getSignature(ALICE, 'AUCTION');

        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE, ALICE);

        walkers.auctionMint{value: 1 ether}(1, signature);
        uint256 oldBalance = ALICE.balance;
        uint256 spent = walkers.spend(ALICE);

        walkers.setSaleState(uint8(Walkers.SaleStates.REFUND));

        vm.prank(ALICE, ALICE);
        vm.expectEmit(true, true, false, false);
        emit Refund(ALICE, 0.9 ether);
        walkers.refund();
        
        uint256 newBalance = ALICE.balance;
        
        assertEq(spent, 1 ether);
        assertTrue(newBalance > oldBalance);
        assertEq(newBalance, 0.9 ether);
    }

    function testRefundOnMultiAuctionMint()
        public
        setSignerAddress
        setAuctionStartTime
        mintTokens(3503, uint8(Walkers.SaleStates.AUCTION))
    {
        vm.warp(block.timestamp + 10 minutes);

        bytes memory signature = _getSignature(ALICE, 'AUCTION');

        vm.deal(ALICE, 2 ether);

        vm.startPrank(ALICE, ALICE);
        walkers.auctionMint{value: 0.8 ether}(1, signature);
        vm.warp(block.timestamp + 60 minutes);
        walkers.auctionMint{value: 0.7 ether}(1, signature);
        vm.stopPrank();

        uint256 spent = walkers.spend(ALICE);

        walkers.setSaleState(uint8(Walkers.SaleStates.REFUND));

        vm.prank(ALICE, ALICE);
        walkers.refund();

        assertEq(spent, 1.5 ether);
        assertEq(ALICE.balance, 1.8 ether);
    }

    function testCannotWhitelistThenPublicMint()
        public
        setSignerAddress
        setAuctionStartTime
        mintTokens(3505, uint8(Walkers.SaleStates.AUCTION))
    {
        walkers.setSaleState(uint8(Walkers.SaleStates.WHITELIST));

        bytes memory signature = _getSignature(ALICE, 'WHITELIST');

        vm.deal(ALICE, 2 ether);
        vm.prank(ALICE, ALICE);
        walkers.whitelistMint{value: 0.5 ether}(signature);

        walkers.setSaleState(uint8(Walkers.SaleStates.PUBLIC));

        signature = _getSignature(ALICE, 'PUBLIC');

        vm.prank(ALICE, ALICE);
        vm.expectRevert(IWalkers.TokenAlreadyClaimed.selector);
        walkers.publicMint{value: 1 ether}(signature);
    }

    function testCannotPublicThenWhitelistMint()
        public
        setSignerAddress
        setAuctionStartTime
        mintTokens(3505, uint8(Walkers.SaleStates.AUCTION))
    {
        walkers.setSaleState(uint8(Walkers.SaleStates.PUBLIC));

        bytes memory signature = _getSignature(ALICE, 'PUBLIC');

        vm.deal(ALICE, 2 ether);
        vm.prank(ALICE, ALICE);
        walkers.publicMint{value: 1 ether}(signature);

        walkers.setSaleState(uint8(Walkers.SaleStates.WHITELIST));

        signature = _getSignature(ALICE, 'WHITELIST');

        vm.prank(ALICE, ALICE);
        vm.expectRevert(IWalkers.TokenAlreadyClaimed.selector);
        walkers.whitelistMint{value: 0.5 ether}(signature);
    }

    function testRefundOnAuctionThenWhitelistMint()
        public
        setSignerAddress
        setAuctionStartTime
        mintTokens(3504, uint8(Walkers.SaleStates.AUCTION))
    {
        vm.warp(block.timestamp + 10 minutes);

        bytes memory signature = _getSignature(ALICE, 'AUCTION');

        vm.deal(ALICE, 2 ether);
        vm.prank(ALICE, ALICE);
        walkers.auctionMint{value: 1 ether}(1, signature);

        walkers.setSaleState(uint8(Walkers.SaleStates.WHITELIST));

        signature = _getSignature(ALICE, 'WHITELIST');

        vm.prank(ALICE, ALICE);
        walkers.whitelistMint{value: 0.4 ether}(signature);

        walkers.setSaleState(uint8(Walkers.SaleStates.REFUND));

        vm.prank(ALICE, ALICE);
        walkers.refund();

        assertEq(ALICE.balance, 0.8 ether);
    }

    function testRefundOnAuctionThenPublicMint()
        public
        setSignerAddress
        setAuctionStartTime
        mintTokens(3504, uint8(Walkers.SaleStates.AUCTION))
    {
        vm.warp(block.timestamp + 10 minutes);

        bytes memory signature = _getSignature(ALICE, 'AUCTION');

        vm.deal(ALICE, 2 ether);
        vm.prank(ALICE, ALICE);
        walkers.auctionMint{value: 1 ether}(1, signature);

        walkers.setSaleState(uint8(Walkers.SaleStates.PUBLIC));

        signature = _getSignature(ALICE, 'PUBLIC');

        vm.prank(ALICE, ALICE);
        walkers.publicMint{value: 0.8 ether}(signature);

        walkers.setSaleState(uint8(Walkers.SaleStates.REFUND));

        vm.prank(ALICE, ALICE);
        walkers.refund();

        assertEq(ALICE.balance, 0.4 ether);
    }

    function testCannotRefundThroughContract()
        public
    {
        hoax(ALICE);
        vm.expectRevert(IWalkers.NonEOA.selector);
        walkers.refund();
    }

    function testCannotRefundInvalidSaleState()
        public
    {
        hoax(ALICE, ALICE);
        vm.expectRevert(IWalkers.InvalidSaleState.selector);
        walkers.refund();
    }

    function testCannotRefundWithoutSpend()
        public
        setSaleState(Walkers.SaleStates.REFUND)
    {
        hoax(ALICE, ALICE);
        vm.expectRevert(IWalkers.InvalidSpendAmount.selector);
        walkers.refund();
    }

    function testTeamMint()
        public
    {
        walkers.teamMint(ALICE, 1);
        
        uint256 tokenBalance = walkers.balanceOf(ALICE);
        uint256 supply = walkers.totalSupply();

        assertEq(tokenBalance, 1);
        assertEq(supply, 51);
    }

    function testCannotTeamMintNonOwner()
        public
    {
        hoax(ALICE, ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        walkers.teamMint(ALICE, 1);        
    }

    function testCannotTeamMintOverMaxSupply()
        public
    {
        vm.expectRevert(IWalkers.MaxSupplyExceeded.selector);
        walkers.teamMint(address(this), 5506);
    }

    function testSetBaseTokenURI()
        public
    {
        walkers.setBaseTokenURI("test/");
        string memory _tokenURI = walkers.tokenURI(1);
        assertEq(_tokenURI, "test/1");
    }

    function testCannotSetBaseTokenURINonOwner()
        public
    {
        hoax(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        walkers.setBaseTokenURI("test/");
    }

    function testSetContractURI()
        public
    {
        walkers.setContractURI("test/contract-metadata");
        string memory _contractURI = walkers.contractURI();
        assertEq(_contractURI, "test/contract-metadata");
    }
    
    function testCannotSetContractURINonOwner()
        public
    {
        hoax(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        walkers.setContractURI("test/contract-metadata");
    }

    function testSetSignerAddress(
        address newSignerAddress
    )
        public
    {
        walkers.setSignerAddress(newSignerAddress);
        address _signerAddress = walkers.signerAddress();
        assertEq(_signerAddress, newSignerAddress);
    }
    
    function testCannotSetSignerAddressNonOwner(
        address newSignerAddress
    )
        public
    {
        hoax(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        walkers.setSignerAddress(newSignerAddress);
    }

    /* Signature Helper */

    function _getSignature(address account, string memory phase) internal returns (bytes memory) {
        bytes32 _hash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                bytes32(abi.encodePacked(account, phase))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRIVATE_KEY, _hash);
        return bytes.concat(bytes32(r), bytes32(s), bytes1(v));
    }

}
