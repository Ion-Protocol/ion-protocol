// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../src/IonPool.sol";
import { BaseScript } from "../Base.s.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

import { InterestRate, IlkData } from "../../src/InterestRate.sol";
import { SpotOracle } from "../../src/oracles/spot/SpotOracle.sol";
import { CreateCall } from "./util/CreateCall.sol";

import { console2 } from "forge-std/console2.sol";

address constant CREATE_CALL = 0xab6050062922Ed648422B44be36e33A3BebE8B3E; // sepolia
address constant SAFE = 0xcecc1978A819D4A3c0A2ee7C260ECb7A10732EEF;

// forge script ./script/TestAuthBatch.s.sol:TestAuthBatch --sig "run(bool)()" $1 --slow -vvv --sender $SIGNER_ADDRESS
// --rpc-url $RPC_URL

contract UpdateParamsBase {
    function getMarket(uint8 marketId) public {
        // read from file based on marketId
    }
}

contract UpdateIlkSpot is BaseScript, BatchScript {
    function run(bool _send, address _newSpot) public {
        console2.log(_send);
        console2.log(_newSpot);
        address ionPool = 0x3faAcB959664ae4556FFD46C1950275d8905e232;
        // address _newSpot = 0x3faAcB959664ae4556FFD46C1950275d8905e232;

        // SpotOracle newSpot = new SpotOracle(_newSpot);

        bytes memory updateIlkSpot = abi.encodeWithSelector(
            IonPool.updateIlkSpot.selector,
            0, // ilkIndex
            _newSpot
        );

        addToBatch(ionPool, updateIlkSpot);
        executeBatch(SAFE, _send);
    }
}

// read from parameters file and validate that it's on mainnet
contract ValidateUpdateIlkSpot is BaseScript, BatchScript {
    function run() public { }
}

contract UpdateIonPoolParams is BaseScript, BatchScript {
    // function run(bool send_) public {
    function run() public {
        address from = vm.envOr({ name: "ETH_FROM", defaultValue: address(0) });
        console2.log("from: ", from);

        // vm.startPrank(from);

        console2.log("sender: ", msg.sender);

        address ionPool = 0x3faAcB959664ae4556FFD46C1950275d8905e232;

        bytes memory pause = abi.encodeWithSelector(IonPool.pause.selector);
        bytes memory unpause = abi.encodeWithSelector(IonPool.unpause.selector);

        console2.log("before addToBatch");
        addToBatch(ionPool, unpause);
        addToBatch(ionPool, pause);

        executeBatch(SAFE, true);
        // vm.stopPrank();
    }
}

contract MultisigTest is BaseScript {
    function run() public returns (address deployed) {
        bytes memory bytecode = type(InterestRate).creationCode;
        console2.logBytes(bytecode);
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(deployed)) { revert(0, 0) }
        }
    }
}

contract DeployCreateCall is BaseScript {
    function run() public broadcast {
        CreateCall createCall = new CreateCall();
    }
}

/**
 * Updating Interest Rate Parameters:
 * //TODO: we might not want to do these atomically
 * 1. Upgrade the interest rate for which market? (ionPool)
 *
 * 1. Deploy new InterestRate contract from local address (can be any address).
 * 2. Update IonPool
 * Validation:
 * 1. IonPool.InterestRateModuleUpdated(address) event
 * 2. Check new interest rate parameters against deployment parameters
 */
contract RedeployInterestRate is BaseScript, BatchScript {
    function run() public {
        // Get new InterestRate parameters
        IlkData memory ilkData;
        ilkData.adjustedProfitMargin = 1;
        ilkData.minimumKinkRate = 2;
        ilkData.reserveFactor = 3;
        ilkData.adjustedBaseRate = 4;
        ilkData.minimumBaseRate = 5;
        ilkData.optimalUtilizationRate = 6;
        ilkData.distributionFactor = 7;
        ilkData.adjustedAboveKinkSlope = 8;
        ilkData.minimumAboveKinkSlope = 9;

        // Get YieldOracle address (new or old)
        address yieldOracleAddress = 0x3faAcB959664ae4556FFD46C1950275d8905e232;

        address newInterestRateAddress;

        // Get initcCode
        bytes memory initCode = type(InterestRate).creationCode;
        // Append constructor args
        bytes memory byteCode = abi.encodePacked(initCode, abi.encode(ilkData, yieldOracleAddress));

        // Can we retrieve the return data from the batch calls?
        // Could use create2 with the IlkData as the salt
        bytes memory deployInterestRate = abi.encodeWithSelector(
            CreateCall.performCreate.selector,
            0, // value
            byteCode
        );

        // bytes memory updateInterestRateModule = abi.encodeWithSelector(
        //     IonPool.updateInterestRateModule.selector,
        //     newInterestRateAddress
        // );

        addToBatch(CREATE_CALL, deployInterestRate);

        executeBatch(SAFE, true);
    }
}

contract ValidateRedeployInterestRate is BaseScript { }
