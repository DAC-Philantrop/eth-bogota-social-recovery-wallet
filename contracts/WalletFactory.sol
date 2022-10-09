// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";


interface IWalletFactory {
    event NewWallet(address wallet, address firstOwner);

    error WalletAlreadyExists(bytes32 accountHash, address wallet);
}

contract WalletFactory is IWalletFactory {
    address public immutable WALLET_IMPLEMENTATION;

    constructor(address imp) {
        WALLET_IMPLEMENTATION = imp;
    }

    function newWallet(
        bytes32 accountHash,
        address initialOwner,
        address[] calldata initialGuardians
    ) public returns(address wallet) {
        wallet = Clones.cloneDeterministic(WALLET_IMPLEMENTATION, accountHash);
        (bool ok,) = wallet.call(abi.encodeWithSelector(0x946d9204, initialOwner, initialGuardians));

        if(!ok) revert WalletAlreadyExists(accountHash, getCounterfactualWallet(accountHash));
    }

    function getCounterfactualWallet(bytes32 accountHash) public view returns(address) {
        return Clones.predictDeterministicAddress(WALLET_IMPLEMENTATION, accountHash);
    }
}