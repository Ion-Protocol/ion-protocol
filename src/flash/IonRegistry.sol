// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { GemJoin } from "../join/GemJoin.sol";

contract IonRegistry is Ownable {
    GemJoin[] public gemJoins;
    address[] public depositContracts;

    constructor(GemJoin[] memory _gemJoins, address[] memory _depositContracts, address _owner) Ownable(_owner) {
        assert(_gemJoins.length == _depositContracts.length);

        gemJoins = _gemJoins;
        depositContracts = _depositContracts;
    }

    function setGemJoin(uint8 ilkIndex, GemJoin gemJoin) external onlyOwner {
        gemJoins[ilkIndex] = gemJoin;
    }

    function setDepositContract(uint8 ilkIndex, address depositContract) external onlyOwner {
        depositContracts[ilkIndex] = depositContract;
    }
}
