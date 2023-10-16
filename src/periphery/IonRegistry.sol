// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract IonRegistry is Ownable {
    mapping(uint8 ilkIndex => address) public gemJoins;
    mapping(uint8 ilkIndex => address) public depositContracts;

    constructor(address[] memory _gemJoins, address[] memory _depositContracts, address _owner) Ownable(_owner) {
        assert(_gemJoins.length == _depositContracts.length);
        for (uint8 i = 0; i < _gemJoins.length; i++) {
            gemJoins[i] = _gemJoins[i];
            depositContracts[i] = _depositContracts[i];
        }
    }

    function setGemJoin(uint8 ilkIndex, address gemJoin) external onlyOwner {
        gemJoins[ilkIndex] = gemJoin;
    }

    function setDepositContract(uint8 ilkIndex, address depositContract) external onlyOwner {
        depositContracts[ilkIndex] = depositContract;
    }
}
