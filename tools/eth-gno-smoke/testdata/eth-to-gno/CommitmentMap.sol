// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract CommitmentMap {
    mapping(bytes32 => bytes32) public commitments;

    function set(bytes32 key, bytes32 value) external {
        commitments[key] = value;
    }
}
