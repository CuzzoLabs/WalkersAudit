// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import { DSTest } from "ds-test/test.sol";
import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { IVaultFactory } from "../../interfaces/test//IVaultFactory.sol";
import { IFERC1155 } from "../../interfaces/IFERC1155.sol";

import { Walkers } from "../../Walkers.sol";
import { FERC1155Distributor } from "../../FERC1155Distributor.sol";

contract TestFixture is DSTest, Test {
    Walkers public walkers;
    FERC1155Distributor public distributor;

    /* Mainnet :: fractional.art contracts */
    address public constant VAULT_FACTORY = 0x04BB19E64d2C2D92dC84efF75bD0AB757625A5f2;
    address public constant FRACTION_CONTRACT = 0xb2469a7dd9E154c97b99b33E88196f7024F2979e;

    IVaultFactory public vault = IVaultFactory(VAULT_FACTORY);
    IFERC1155 public fractions = IFERC1155(FRACTION_CONTRACT);

    address public constant ALICE = address(0xbabe);
    address public constant BOB = address(0xbeef);

    uint256 public constant RESERVED_TOKENS = 55;

    address public constant SIGNER_ADDRESS = 0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf;
    uint256 public constant PRIVATE_KEY = 1;

    address[] public payees = [ALICE, BOB];
    uint256[] public shares = [97, 3];

    function setUp() public virtual {
        walkers = new Walkers(payees, shares, ALICE);
        distributor = new FERC1155Distributor(address(walkers), FRACTION_CONTRACT);
    }

}