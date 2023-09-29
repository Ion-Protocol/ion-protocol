// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Script, console2 } from "forge-std/Script.sol";
import { ApyOracle, _LOOK_BACK, _PROVIDER_PRECISION, _APY_PRECISION, _ILKS } from "src/APYOracle.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { RoundedMath } from "src/math/RoundedMath.sol";

uint256 constant LOOK_BACK = _LOOK_BACK;
uint256 constant PROVIDER_PRECISION = _PROVIDER_PRECISION;
uint256 constant APY_PRECISION = _APY_PRECISION;
uint256 constant ILKS = _ILKS;

contract DeployApyOracleScript is Script {
    using RoundedMath for uint256;
    using SafeCast for uint256;
    error OutOfBounds();

    function _convertStringToUintArray(string memory input) internal pure returns (uint256[7] memory) {
        uint256[LOOK_BACK] memory uintArray;
        bytes memory bytesInput = bytes(input);

        // Split the input string by comma delimiter
        uint256 startIndex = 0;
        uint256 arrayIndex = 0;
        bytes1 comma = bytes1(",");

        for (uint256 i = 0; i < bytesInput.length; i++) {
            if (bytesInput[i] == comma) {
                uintArray[arrayIndex] = _parseInt(_substring(input, startIndex, i));
                startIndex = i + 1;
                arrayIndex++;
            }
        }

        // Parse the last element after the last comma
        if (startIndex < bytesInput.length) {
            uintArray[arrayIndex] = _parseInt(_substring(input, startIndex, bytesInput.length));
        }

        return uintArray;
    }

    function _parseInt(bytes memory bValue) internal pure returns (uint256) {
        uint256 result = 0;
        for (uint256 i = 0; i < bValue.length; i++) {
            if (uint8(bValue[i]) >= 48 && uint8(bValue[i]) <= 57) {
                result = result * 10 + (uint8(bValue[i]) - 48);
            }
        }
        return result;
    }

    function _substring(string memory str, uint256 startIndex, uint256 endIndex) internal pure returns (bytes memory) {
        bytes memory strBytes = bytes(str);
        if (endIndex < startIndex || endIndex > strBytes.length) {
            revert OutOfBounds();
        }
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return result;
    }

    function run() public {
        // make sure to use the right addresses based on your choice of deployment
        address lidoAddress = vm.envAddress("LIDO_CONTRACT_ADDRESS");
        address staderAddress = vm.envAddress("STADER_CONTRACT_ADDRESS");
        address swellAddress = vm.envAddress("SWELL_CONTRACT_ADDRESS");

        // Make sure to fetch latest exchange rates from ion-validator-oracle repository
        string memory lido = vm.envString("LIDO_HISTORICAL_EXCHANGE_RATES");
        string memory stader = vm.envString("STADER_HISTORICAL_EXCHANGE_RATES");
        string memory swell = vm.envString("SWELL_HISTORICAL_EXCHANGE_RATES");

        uint256[LOOK_BACK] memory lidoRates = _convertStringToUintArray(lido);
        uint256[LOOK_BACK] memory staderRates = _convertStringToUintArray(stader);
        uint256[LOOK_BACK] memory swellRates = _convertStringToUintArray(swell);
        uint256 decimalPlaces = PROVIDER_PRECISION - APY_PRECISION;
        uint256 DECIMAL_FACTOR = 10 ** uint256(decimalPlaces);

        uint256[LOOK_BACK] memory historicalExchangeRates;
        for (uint256 i = 0; i < LOOK_BACK; i++) {
            uint32 lidoEr = (lidoRates[i] / DECIMAL_FACTOR).toUint32();
            uint32 staderEr = (staderRates[i] / DECIMAL_FACTOR).toUint32();
            uint32 swellEr = (swellRates[i] / DECIMAL_FACTOR).toUint32();

            uint256 exchangeRate;
            uint32[ILKS] memory order = [lidoEr, staderEr, swellEr];
            // loop over order
            for (uint256 j = 0; j < ILKS; j++) {
                exchangeRate |= uint256(order[j]) << (j * 32);
            }
            historicalExchangeRates[i] = exchangeRate;
        }
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        ApyOracle oracle = new ApyOracle(historicalExchangeRates, lidoAddress, staderAddress, swellAddress);
        vm.stopBroadcast();
    }
}
