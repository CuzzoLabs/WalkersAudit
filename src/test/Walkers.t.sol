// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "../Walkers.sol";
import "../interfaces/IWalkers.sol";

contract WalkersTest is Test {
    using stdStorage for StdStorage;

    Walkers public walkers;

    address public constant ALICE = address(0xbabe);
    address public constant BOB = address(0xbeef);
    address public constant GRIM = address(0xdead);

    address[] public payees = [ALICE, BOB];
    uint256[] public shares = [97, 3];

    address public constant SIGNER_ADDRESS = 0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf;
    uint256 public constant PRIVATE_KEY = 1;

    event Minted(address indexed receiver, uint256 quantity);

    modifier setPublicTokens(uint256 quantity) {
        walkers.setPublicTokens(quantity);
        _;
    }

    modifier setSigner() {
        walkers.setSigner(SIGNER_ADDRESS);
        _;
    }

    modifier setSaleState(Walkers.SaleStates saleState) {
        walkers.setSaleState(uint256(saleState));
        _;
    }

    modifier mintTokens(uint256 quantity, Walkers.SaleStates newSaleState) {
        
        uint256 _saleState = uint256(newSaleState);
        walkers.setSaleState(_saleState);
        
        for (uint256 i=1; i<=quantity; i++) {
            
            address account = address(uint160(i));
            bytes memory signature;
            uint256 price;

            startHoax(account, account, 1 ether);

            if (_saleState == 1) {
                price = walkers.PUBLIC_PRICE();
                signature = _getSignature(account, 1, 'PUBLIC');
                walkers.publicMint{value: price}(1, signature);
            } else {
                price = walkers.MULTI_PRICE();
                signature = _getSignature(account, 1, 'MULTI');
                walkers.multilistMint{value: price}(1, signature);
            }

            vm.stopPrank();
        }

        _;
    }

    function setUp() public {
        walkers = new Walkers(payees, shares, GRIM);
    }

    /* Mint Tests */

    function testPublicMint()
        public
        setSigner
        setSaleState(Walkers.SaleStates.PUBLIC)
    {
        bytes memory signature = _getSignature(ALICE, 1, 'PUBLIC');
        uint256 price = walkers.PUBLIC_PRICE();

        startHoax(ALICE);
        vm.expectEmit(true, true, false, false);
        emit Minted(ALICE, 1);
        walkers.publicMint{value: price}(1, signature);
        vm.stopPrank();
    }

    function testPublicMintInTwoTxnsFailsThird()
        public
        setSigner
        setSaleState(Walkers.SaleStates.PUBLIC)
    {
        bytes memory signature = _getSignature(ALICE, 1, 'PUBLIC');
        uint256 price = walkers.PUBLIC_PRICE();

        startHoax(ALICE);
        walkers.publicMint{value: price}(1, signature);
        walkers.publicMint{value: price}(1, signature);

        vm.expectRevert(IWalkers.WalletLimitExceeded.selector);
        walkers.publicMint{value: price}(1, signature);
    }

    function testCannotPublicMintInvalidSaleState() public {
        bytes memory signature = _getSignature(ALICE, 1, 'PUBLIC');
        uint256 price = walkers.PUBLIC_PRICE();

        hoax(ALICE);
        vm.expectRevert(IWalkers.InvalidSaleState.selector);
        walkers.publicMint{value: price}(1, signature);
    }

    function testCannotPublicMintInvalidEtherAmount()
        public
        setSigner
        setSaleState(Walkers.SaleStates.PUBLIC)
    {
        bytes memory signature = _getSignature(ALICE, 1, 'PUBLIC');
        uint256 price = walkers.PUBLIC_PRICE();

        startHoax(ALICE);
        vm.expectRevert(IWalkers.InvalidEtherAmount.selector);
        walkers.publicMint{value: price - 1}(1, signature);
        vm.expectRevert(IWalkers.InvalidEtherAmount.selector);
        walkers.publicMint{value: price + 1}(1, signature);
    }

    function testCannotPublicMintOverWalletLimit()
        public
        setSigner
        setSaleState(Walkers.SaleStates.PUBLIC)
    {
        bytes memory signature = _getSignature(ALICE, 1, 'PUBLIC');
        uint256 price = walkers.PUBLIC_PRICE();

        hoax(ALICE);
        vm.expectRevert(IWalkers.WalletLimitExceeded.selector);
        walkers.publicMint{value: price * 3}(3, signature);
    }

    function testCannotPublicMintOverMaxSupply()
        public
        setSigner
        setPublicTokens(5555)
        mintTokens(5500, Walkers.SaleStates.PUBLIC)
    {
        bytes memory signature = _getSignature(ALICE, 1, 'PUBLIC');
        uint256 price = walkers.PUBLIC_PRICE();

        hoax(ALICE);
        vm.expectRevert(IWalkers.MaxSupplyExceeded.selector);
        walkers.publicMint{value: price}(1, signature);
    }

    function testCannotPublicMintOverPublicSupply()
        public
        setSigner
        setPublicTokens(55)
        setSaleState(Walkers.SaleStates.PUBLIC)
    {
        bytes memory signature = _getSignature(ALICE, 1, 'PUBLIC');
        uint256 price = walkers.PUBLIC_PRICE();

        hoax(ALICE);
        vm.expectRevert(IWalkers.PublicSupplyExceeded.selector);
        walkers.publicMint{value: price}(1, signature);        
    }

    function testCannotPublicMintInvalidSignature()
        public
        setSigner
        setSaleState(Walkers.SaleStates.PUBLIC)
    {
        bytes memory signature = _getSignature(ALICE, 2, 'PUBLIC');
        uint256 price = walkers.PUBLIC_PRICE();

        hoax(ALICE);
        vm.expectRevert(IWalkers.InvalidSignature.selector);
        walkers.publicMint{value: price}(1, signature);   
    }

    function testMultilistMint()
        public
        setSigner
        setSaleState(Walkers.SaleStates.MULTI)
    {
        bytes memory signature = _getSignature(ALICE, 1, 'MULTI');
        uint256 price = walkers.MULTI_PRICE();

        uint64 aux = walkers.getAux(ALICE);
        assertEq(aux, 0);

        hoax(ALICE);
        vm.expectEmit(true, true, false, false);
        emit Minted(ALICE, 1);
        walkers.multilistMint{value: price}(1, signature);

        aux = walkers.getAux(ALICE);
        assertEq(aux, 1);
    }

    function testMultilistMintTwoAndOne()
        public
        setSigner
        setSaleState(Walkers.SaleStates.MULTI)
    {
        bytes memory signatureA = _getSignature(ALICE, 2, 'MULTI');
        bytes memory signatureB = _getSignature(BOB, 1, 'MULTI');

        uint256 price = walkers.MULTI_PRICE();

        uint64 auxA = walkers.getAux(ALICE);
        uint64 auxB = walkers.getAux(BOB);

        assertEq(auxA, 0);
        assertEq(auxB, 0);

        hoax(ALICE);
        walkers.multilistMint{value: price * 2}(2, signatureA);

        hoax(BOB);
        walkers.multilistMint{value: price * 1}(1, signatureB);

        uint256 balanceA = walkers.balanceOf(ALICE);
        uint256 balanceB = walkers.balanceOf(BOB);

        auxA = walkers.getAux(ALICE);
        auxB = walkers.getAux(BOB);

        assertEq(balanceA, 2);
        assertEq(balanceB, 1);
        assertEq(auxA, 1);
        assertEq(auxB, 1);
    }

    function testCannotMultilistMintInvalidSaleState()
        public
        setSigner
    {
        bytes memory signature = _getSignature(ALICE, 1, 'MULTI');
        uint256 price = walkers.MULTI_PRICE();

        hoax(ALICE);
        vm.expectRevert(IWalkers.InvalidSaleState.selector);
        walkers.multilistMint{value: price}(1, signature);
    }

    function testCannotMultilistMintInvalidEtherAmount()
        public
        setSigner
        setSaleState(Walkers.SaleStates.MULTI)
    {
        bytes memory signature = _getSignature(ALICE, 1, 'MULTI');
        uint256 price = walkers.MULTI_PRICE();

        startHoax(ALICE);
        vm.expectRevert(IWalkers.InvalidEtherAmount.selector);
        walkers.multilistMint{value: price - 1}(1, signature);
        vm.expectRevert(IWalkers.InvalidEtherAmount.selector);
        walkers.multilistMint{value: price + 1}(1, signature);        
    }

    function testCannotMultilistMintMaxSupplyExceeded()
        public
        setSigner
        mintTokens(5500, Walkers.SaleStates.MULTI)
    {
        bytes memory signature = _getSignature(ALICE, 1, 'MULTI');
        uint256 price = walkers.MULTI_PRICE();

        hoax(ALICE);
        vm.expectRevert(IWalkers.MaxSupplyExceeded.selector);
        walkers.multilistMint{value: price}(1, signature);
    }

    function testCannotMultilistMintTokenClaimed()
        public
        setSigner
        setSaleState(Walkers.SaleStates.MULTI)
    {
        bytes memory signature = _getSignature(ALICE, 1, 'MULTI');
        uint256 price = walkers.MULTI_PRICE();

        startHoax(ALICE);
        walkers.multilistMint{value: price}(1, signature);
        vm.expectRevert(IWalkers.TokenClaimed.selector);
        walkers.multilistMint{value: price}(1, signature);
    }

    function testCannotMultilistMintInvalidSignature()
        public
        setSigner
        setSaleState(Walkers.SaleStates.MULTI)
    {
        bytes memory signature = _getSignature(ALICE, 1, 'PUBLIC');
        uint256 price = walkers.MULTI_PRICE();

        hoax(ALICE);
        vm.expectRevert(IWalkers.InvalidSignature.selector);
        walkers.multilistMint{value: price}(1, signature);
    }

    function testOwnerMint() public {
        walkers.ownerMint(ALICE, 100);
        uint256 balance = walkers.balanceOf(ALICE);
        assertEq(balance, 100);
    }

    function testCannotOwnerMintNonOwner() public {
        hoax(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        walkers.ownerMint(ALICE, 1);
    }

    function testCannotOwnerMintOverMaxSupply() public {
        vm.expectRevert(IWalkers.MaxSupplyExceeded.selector);
        walkers.ownerMint(ALICE, 5555);
    }

    /* Functionality Tests */

    function testSetPublicTokens(uint16 amount) public {
        vm.assume(amount <= 5555);

        walkers.setPublicTokens(amount);
        uint256 tokens = walkers.publicTokens();

        assertEq(tokens, amount);
    }

    function testSetPublicTokensEffectsPublicMintAtCap()
        public
        setSigner
        setSaleState(Walkers.SaleStates.PUBLIC)
    {
        uint256 supply = walkers.RESERVED_TOKENS() + 1;
        walkers.setPublicTokens(supply);

        bytes memory signature = _getSignature(ALICE, 1, 'PUBLIC');
        uint256 price = walkers.PUBLIC_PRICE();

        startHoax(ALICE);
        walkers.publicMint{value: price}(1, signature);
        vm.expectRevert(IWalkers.PublicSupplyExceeded.selector);
        walkers.publicMint{value: price}(1, signature);
        vm.stopPrank();

        walkers.setPublicTokens(supply + 1);

        hoax(ALICE);
        walkers.publicMint{value: price}(1, signature);

        uint256 balance = walkers.balanceOf(ALICE);
        assertEq(balance, 2);
    }

    function testCannotSetPublicTokensNonOwner() public {
        hoax(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        walkers.setPublicTokens(1);
    }

    function testCannotSetPublicTokensInvalidAmount() public {
        uint256 supply = walkers.MAX_SUPPLY() + 1;
        vm.expectRevert(IWalkers.InvalidTokenAmount.selector);
        walkers.setPublicTokens(supply);
    }

    function testSetSaleState() public {
        uint256 _state;

        walkers.setSaleState(uint256(Walkers.SaleStates.PUBLIC));
        _state = uint256(walkers.saleState());
        assertEq(_state, 1);

        walkers.setSaleState(uint256(Walkers.SaleStates.MULTI));
        _state = uint256(walkers.saleState());
        assertEq(_state, 2);

        walkers.setSaleState(uint256(Walkers.SaleStates.PAUSED));
        _state = uint256(walkers.saleState());
        assertEq(_state, 0);
    }

    function testCannotSetSaleStateNonOwner() public {
        hoax(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        walkers.setSaleState(1);
    }

    function testCannotSetSaleStateOOB() public {
        vm.expectRevert(IWalkers.InvalidSaleState.selector);
        walkers.setSaleState(3);
    }

    function testSetSigner(address newSigner) public {
        walkers.setSigner(newSigner);
        address _signer = walkers.signer();
        assertEq(_signer, newSigner);
    }

    function testCannotSetSignerNonOwner() public {
        hoax(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        walkers.setSigner(ALICE);
    }

    function testSetBaseTokenURI() public {
        walkers.setBaseTokenURI("test/");
        string memory tokenURI = walkers.tokenURI(1);
        assertEq(tokenURI, "test/1");
    }

    function testCannotSetBaseTokenURINonOwner() public {
        hoax(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        walkers.setBaseTokenURI("");
    }

    /* Withdraw Tests */

    function testRelease()
        public
        setSigner
        mintTokens(2500, Walkers.SaleStates.PUBLIC)
        mintTokens(3000, Walkers.SaleStates.MULTI)
    {
        uint256 balanceA = ALICE.balance;
        uint256 balanceB = BOB.balance;

        assertEq(balanceA, 0);
        assertEq(balanceB, 0);

        hoax(ALICE, 0);
        walkers.release(payable(ALICE));
        balanceA = ALICE.balance;
        assertEq(balanceA, 1115.5 ether);
        
        hoax(BOB, 0);
        walkers.release(payable(BOB));
        balanceB = BOB.balance;
        assertEq(balanceB, 34.5 ether);
    }

    function testCannotReleaseNonShareHolder() public {
        hoax(GRIM);
        vm.expectRevert("PaymentSplitter: account has no shares");
        walkers.release(payable(GRIM));
    }

    function testCannotReleaseToDifferentAccount() public {
        hoax(ALICE);
        vm.expectRevert(IWalkers.AccountMismatch.selector);
        walkers.release(payable(BOB));
    }

    /* Signature Helper */

    function _getSignature(address account, uint256 quantity, string memory phase) internal returns (bytes memory) {
        bytes32 _hash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            bytes32(abi.encodePacked(account, uint8(quantity), phase))
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRIVATE_KEY, _hash);
        return bytes.concat(bytes32(r), bytes32(s), bytes1(v));
    }

}
