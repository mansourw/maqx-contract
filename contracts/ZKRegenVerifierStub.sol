// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ZKRegenVerifierStub {
    function verifyProof(
        bytes calldata proof,
        address[] calldata users,
        uint256[] calldata amounts
    ) external pure returns (bool) {
        return true;
    }
}