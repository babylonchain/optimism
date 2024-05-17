// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/// @notice Event emitted when the gas paying token is set.
event GasPayingTokenSet(address indexed token, uint8 indexed decimals, bytes32 name, bytes32 symbol);

/// @notice Event emitted when a new dependency is added to the interop dependency set.
event DependencyAdded(uint256 indexed chainId);

/// @notice Event emitted when a dependency is removed from the interop dependency set.
event DependencyRemoved(uint256 indexed chainId);
