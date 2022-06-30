// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IFERC1155 is IERC1155 {
  function count() external view returns (uint256);
  function totalSupply(uint256) external view returns (uint256);
}