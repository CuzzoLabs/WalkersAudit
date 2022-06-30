// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import { TestFixture } from "./utils/TestFixture.t.sol";
import { IFERC1155Distributor } from "../interfaces/IFERC1155Distributor.sol";
import { FERC1155Distributor } from "../FERC1155Distributor.sol";

contract FERC1155DistributorTest is TestFixture {
    
    uint256 public constant FRACTIONS = 15555;
    uint256 public constant FRACTURED_WALKER = 1;
    uint256 public constant HELD_WALKER = 2;

    uint256[] public singleClaim = [2];
    uint256[] public claimIds = [2, 3, 4, 5, 6];
    
    uint256 public fractionId;

    event Claimed(address indexed receiver, uint256 quantity);

    modifier warpForClaim() {
        vm.warp(block.timestamp + 7 days);
        _;
    }

    modifier setSigner() {
        distributor.setSigner(SIGNER_ADDRESS);
        _;
    }

    modifier setSaleState(FERC1155Distributor.SaleStates newSaleState) {
        distributor.setSaleState(uint256(newSaleState));
        _;
    }

    modifier claimFERC1155(uint256 quantity) {
        distributor.setSaleState(uint256(FERC1155Distributor.SaleStates.PUBLIC));

        address account;
        bytes memory signature;
        uint256 price = distributor.FRACTION_PRICE();

        for (uint256 i=1; i<=quantity; i++) {
            account = address(uint160(i));
            signature = _getSignature(account);
            hoax(account, account);
            distributor.claim{value: price}(1, signature);
        }

        _;
    }

    function setUp() public override {
        super.setUp();
        _createFractions();
    }

    /* Regular Claim Tests */

    function testClaim()
        public
        setSigner
        setSaleState(FERC1155Distributor.SaleStates.PUBLIC)
    {
        bytes memory signature = _getSignature(BOB);
        uint256 price = distributor.FRACTION_PRICE();

        hoax(BOB, BOB);
        vm.expectEmit(true, true, false, false);
        emit Claimed(BOB, 1);
        distributor.claim{value: price}(1, signature);
        
        uint256 balance = fractions.balanceOf(BOB, fractionId);
        assertEq(balance, 1);
    }

    function testClaimInTwoTxns()
        public
        setSigner
        setSaleState(FERC1155Distributor.SaleStates.PUBLIC)
    {
        bytes memory signature = _getSignature(BOB);
        uint256 price = distributor.FRACTION_PRICE();

        startHoax(BOB, BOB);
        distributor.claim{value: price}(1, signature);
        distributor.claim{value: price}(1, signature);
        vm.expectRevert(IFERC1155Distributor.OverWalletLimit.selector);
        distributor.claim{value: price}(1, signature);
    }

    function testCannotClaimThoughtContract()
        public
        setSigner
        setSaleState(FERC1155Distributor.SaleStates.PUBLIC)
    {
        bytes memory signature = _getSignature(BOB);
        uint256 price = distributor.FRACTION_PRICE();

        hoax(BOB);
        vm.expectRevert(IFERC1155Distributor.NonEOA.selector);
        distributor.claim{value: price}(1, signature);
    }

    function testCannotClaimInvalidSaleState() public {
        bytes memory signature = _getSignature(BOB);
        uint256 price = distributor.FRACTION_PRICE();

        hoax(BOB, BOB);
        vm.expectRevert(IFERC1155Distributor.InvalidSaleState.selector);
        distributor.claim{value: price}(1, signature);
    }

    function testCannotClaimZeroAmount()
        public
        setSaleState(FERC1155Distributor.SaleStates.PUBLIC)
    {
        bytes memory signature = _getSignature(BOB);
        uint256 price = distributor.FRACTION_PRICE();

        hoax(BOB, BOB);
        vm.expectRevert(IFERC1155Distributor.InvalidTxnAmount.selector);
        distributor.claim{value: price}(0, signature);
    }

    function testCannotClaimInvalidEtherAmount()
        public
        setSaleState(FERC1155Distributor.SaleStates.PUBLIC)
    {
        bytes memory signature = _getSignature(BOB);
        uint256 price = distributor.FRACTION_PRICE();

        startHoax(BOB, BOB);
        vm.expectRevert(IFERC1155Distributor.InvalidEtherAmount.selector);
        distributor.claim{value: price - 1}(1, signature);
        vm.expectRevert(IFERC1155Distributor.InvalidEtherAmount.selector);
        distributor.claim{value: price + 1}(1, signature);
    }

    function testCannotClaimOverWalletLimit()
        public
        setSigner
        setSaleState(FERC1155Distributor.SaleStates.PUBLIC)
    {
        bytes memory signature = _getSignature(BOB);
        uint256 price = distributor.FRACTION_PRICE();
        uint256 limit = distributor.WALLET_LIMIT() + 1;

        hoax(BOB, BOB);
        vm.expectRevert(IFERC1155Distributor.OverWalletLimit.selector);
        distributor.claim{value: price * limit}(limit, signature);
    }

    function testCannotClaimNoFractions()
        public
        setSigner
        setSaleState(FERC1155Distributor.SaleStates.PUBLIC)
    {
        distributor.withdrawFractions();

        bytes memory signature = _getSignature(BOB);
        uint256 price = distributor.FRACTION_PRICE();

        hoax(BOB, BOB);
        vm.expectRevert("ERC1155: insufficient balance for transfer");
        distributor.claim{value: price}(1, signature);
    }

    /* Holder Claim Tests */

    function testHolderClaim()
        public
        setSaleState(FERC1155Distributor.SaleStates.HOLDER)
    {
        vm.warp(block.timestamp + 7 days);

        hoax(ALICE, ALICE);
        vm.expectEmit(true, true, false, false);
        emit Claimed(ALICE, claimIds.length);
        distributor.holderClaim(claimIds);

        uint256 balance = fractions.balanceOf(ALICE, fractionId);

        assertEq(balance, claimIds.length);
    }

    function testCannotHolderClaimThroughContract()
        public
        warpForClaim
        setSaleState(FERC1155Distributor.SaleStates.HOLDER)
    {
        hoax(ALICE);
        vm.expectRevert(IFERC1155Distributor.NonEOA.selector);
        distributor.holderClaim(claimIds);
    }

    function testCannotHolderClaimInvalidSaleState()
        public
        warpForClaim
    {
        hoax(ALICE, ALICE);
        vm.expectRevert(IFERC1155Distributor.InvalidSaleState.selector);
        distributor.holderClaim(claimIds);
    }

    function testCannotHolderClaimNonOwner()
        public
        warpForClaim
        setSaleState(FERC1155Distributor.SaleStates.HOLDER)
    {
        hoax(BOB, BOB);
        vm.expectRevert(IFERC1155Distributor.CallerNotOwner.selector);
        distributor.holderClaim(claimIds);
    }

    function testCannotHolderClaimInvalidHoldTime()
        public
        setSaleState(FERC1155Distributor.SaleStates.HOLDER)
    {
        hoax(ALICE, ALICE);
        vm.expectRevert(IFERC1155Distributor.InvalidHoldTime.selector);
        distributor.holderClaim(claimIds);
    }

    function testCannotHolderClaimTwice()
        public
        warpForClaim
        setSaleState(FERC1155Distributor.SaleStates.HOLDER)
    {
        startHoax(ALICE, ALICE);
        distributor.holderClaim(claimIds);
        vm.expectRevert(IFERC1155Distributor.AlreadyClaimed.selector);
        distributor.holderClaim(claimIds);
    }

    /* Functionality Tests */

    function testHasClaimed()
        public
        warpForClaim
        setSaleState(FERC1155Distributor.SaleStates.HOLDER)
    {
        bool result;

        for (uint256 i=0; i<claimIds.length; i++) {
            result = distributor.hasClaimed(claimIds[i]);
            assertTrue(!result);
        }

        hoax(ALICE, ALICE);
        distributor.holderClaim(claimIds);

        for (uint256 i=0; i<claimIds.length; i++) {
            result = distributor.hasClaimed(claimIds[i]);
            assertTrue(result);
        }
    }

    function testHasClaimedMany()
        public
        warpForClaim
        setSaleState(FERC1155Distributor.SaleStates.HOLDER)
    {
        bool[] memory results = distributor.hasClaimedMany(claimIds);
        
        for (uint256 i=0; i<results.length; i++) {
            assertTrue(!results[i]);
        }

        hoax(ALICE, ALICE);
        distributor.holderClaim(claimIds);

        results = distributor.hasClaimedMany(claimIds);

        for (uint256 i=0; i<results.length; i++) {
            assertTrue(results[i]);
        }
    }

    function testSetSaleState() public {
        distributor.setSaleState(uint256(FERC1155Distributor.SaleStates.PUBLIC));
        uint256 _state = uint256(distributor.saleState());
        assertEq(_state, 1);

        distributor.setSaleState(uint256(FERC1155Distributor.SaleStates.PAUSED));
        _state = uint256(distributor.saleState());
        assertEq(_state, 0);
    }

    function testCannotSetSaleStateNonOwner() public {
        hoax(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        distributor.setSaleState(1);
    }

    function testCannotSetSaleStateInvalidState() public {
        vm.expectRevert(IFERC1155Distributor.InvalidSaleState.selector);
        distributor.setSaleState(3);
    }

    function testSetFractionId(uint256 newFractionId) public {
        distributor.setFractionId(newFractionId);
        uint256 _fractionId = distributor.fractionId();
        assertEq(_fractionId, newFractionId);
    }

    function testCannotSetFractionIdNonOwner() public {
        hoax(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        distributor.setFractionId(1);
    }

    function testSetHoldTimer(uint8 multiplier) public {
        vm.assume(multiplier > 0 && multiplier <= 10);

        uint256 time = 1 days * multiplier;
        distributor.setHoldTimer(time);
        uint256 _time = distributor.holdTimer();
        assertEq(_time, time);
    }

    function testCannotSetDiamondTimerNonOwner() public {
        hoax(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        distributor.setHoldTimer(1 days);
    }
    
    function testCannotSetDiamondTimerInvalidTime() public {
        vm.expectRevert(IFERC1155Distributor.InvalidTime.selector);
        distributor.setHoldTimer(1 days - 1);
    }

    function testSetSigner(address newSigner) public {
        distributor.setSigner(newSigner);
        address _signer = distributor.signer();
        assertEq(_signer, newSigner);
    }

    function testCannotSetSignerNonOwner() public {
        hoax(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        distributor.setSigner(ALICE);
    }

    /* Withdraw Tests */

    function testWithdrawFunds()
        public
        setSigner
        claimFERC1155(10)
    {
        address account = address(this);

        startHoax(account, 0);
        assertEq(account.balance, 0);
        distributor.withdrawFunds();
        assertEq(account.balance, 0.1 ether);
    }

    function testCannotWithdrawFundsNonOwner() public {
        hoax(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        distributor.withdrawFunds();
    }

    function testWithdrawFractions() public {
        distributor.withdrawFractions();
        uint256 balance = fractions.balanceOf(address(this), fractionId);
        assertEq(balance, FRACTIONS);
    }

    function testCannotWithdrawFractionsNonOwner() public {
        hoax(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        distributor.withdrawFractions();
    } 

    /* Helpers */

    /// @dev Fractures Walker ID #1.
    function _createFractions() internal {
        vm.startPrank(ALICE, ALICE);

        walkers.setApprovalForAll(VAULT_FACTORY, true);
        vault.mint(address(walkers), FRACTURED_WALKER, FRACTIONS);
        fractionId = fractions.count();
        fractions.safeTransferFrom(ALICE, address(distributor), fractionId, FRACTIONS, "");

        vm.stopPrank();

        distributor.setFractionId(fractionId);

        uint256 balance = fractions.balanceOf(address(distributor), fractionId);
        assertEq(balance, FRACTIONS);
    }

    receive() external payable {}

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function _getSignature(address account) internal returns (bytes memory) {
        bytes32 _hash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            bytes32(abi.encodePacked(account, 'FERC1155'))
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PRIVATE_KEY, _hash);
        return bytes.concat(bytes32(r), bytes32(s), bytes1(v));
    }

}