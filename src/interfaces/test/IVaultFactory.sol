// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IVaultFactory {
  function mint(address, uint256, uint256) external returns (uint256);
}