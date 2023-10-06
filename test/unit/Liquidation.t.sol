pragma solidity ^0.8.19; 

// import { safeconsole as console } from "forge-std/safeconsole.sol";

import { IonPoolSharedSetup } from "../helpers/IonPoolSharedSetup.sol";
import { Liquidation } from "src/Liquidation.sol"; 
import { GemJoin } from "../../src/join/GemJoin.sol";
import { RoundedMath } from "src/math/RoundedMath.sol";
import { ReserveOracle } from "src/ReserveOracles/ReserveOracle.sol";
import { stEthReserveOracle } from "src/ReserveOracles/stEthReserveOracle.sol";
import "forge-std/console.sol"; 

contract MockstEthReserveOracle {

    uint256 public exchangeRate;
    function setExchangeRate(uint256 _exchangeRate) public {
        exchangeRate = _exchangeRate; 
    }
    // @dev called by Liquidation.sol 
    function getExchangeRate(uint256 ilkIndex) public returns (uint256) {
        return exchangeRate; 
    }
}

contract LiquidationTest is IonPoolSharedSetup {

    using RoundedMath for uint256; 
    uint256 constant WAD = 1e18;
    uint256 constant RAY = 1e27;

    uint32 constant ILK_COUNT = 8; // NOTE: Need to match with the ILK_COUNT in Liquidation.sol 
    
    Liquidation public liquidation; 
    GemJoin public stEthJoin; 
    MockstEthReserveOracle public reserveOracle; 
    
    uint8 public stEthIndex;

    address immutable keeper1 = vm.addr(99); 
    address immutable revenueRecipient = vm.addr(100); 

    function setUp() public override {
        super.setUp();

        stEthIndex = ilkIndexes[address(stEth)];
        
        // create supply position
        supply(lender1, 100 ether); 

        // TODO: Make ReserveOracleSharedSetUp
        reserveOracle = new MockstEthReserveOracle(); 
    }

    /** 
     * @dev Converts percentage to WAD. Used for instantiating liquidationThreshold arrays
     * @param percentages number out of 100 ex) 75 input will return 
     */
    function getPercentageInWad(uint8[ILK_COUNT] memory percentages) internal returns (uint64[ILK_COUNT] memory results) {
        for (uint8 i = 0; i < ILK_COUNT; i++) {
            console.log("percentages[i]: ", percentages[i]); 
            results[i] = uint64(uint256(percentages[i]) * WAD / 100); 
            console.log("result[i]: ", results[i]); 
        } 
    }

    /**
     * @dev Helper function to create supply positions. Approves and calls Supply
     */
    function supply(address lender, uint256 supplyAmt) internal {
        vm.startPrank(lender); 
        underlying.approve(address(ionPool), supplyAmt); 
        ionPool.supply(lender, supplyAmt);
        vm.stopPrank(); 
    }

    /**
     * @dev Helper function to create borrow positions. Call gemJoin and modifyPosition. 
     * NOTE: does not normalize. Assumes the rate is 1. 
     */
    function borrow(address borrower, uint256 ilkIndex, uint256 depositAmt, uint256 borrowAmt) internal {
        vm.startPrank(borrower);
        stEthJoin = gemJoins[stEthIndex]; 
        collaterals[stEthIndex].approve(address(stEthJoin), depositAmt); 
        stEthJoin.join(borrower, depositAmt); 
        ionPool.modifyPosition(
            stEthIndex,
            borrower, 
            borrower, 
            borrower, 
            int256(depositAmt), 
            int256(borrowAmt) 
        ); 
        vm.stopPrank(); 
    }

    function test_ExchangeRateCannotBeZero() public {
        // deploy liquidations contract 
        uint64[ILK_COUNT] memory liquidationThresholds = getPercentageInWad([75, 75, 75, 75, 75, 75, 75, 75]);
        liquidation = new Liquidation(address(ionPool), address(reserveOracle), revenueRecipient, liquidationThresholds); 

        // set exchange rate to zero
        reserveOracle.setExchangeRate(0); 

        // create borrow position 
        borrow(borrower1, stEthIndex, 10 ether, 5 ether); 

        // liquidate call 
        vm.startPrank(keeper1);
        vm.expectRevert(
            abi.encodeWithSelector(Liquidation.ExchangeRateCannotBeZero.selector, 0) 
        );        
        liquidation.liquidate(stEthIndex, borrower1, keeper1); 
        vm.stopPrank(); 
    }

    /**
     * @dev Test that not unsafe vaults can't be liquidated
     * healthRatio = 10 ether * 1 ether * 0.75 ether / 5 ether / 1 ether 
     *             = 7.5 / 5 = 1.5 
     */
    function test_VaultIsNotUnsafe() public {
        // deploy liquidations contract 
        uint64[ILK_COUNT] memory liquidationThresholds = getPercentageInWad([75, 75, 75, 75, 75, 75, 75, 75]);

        liquidation = new Liquidation(address(ionPool), address(reserveOracle), revenueRecipient, liquidationThresholds); 

        // set exchange rate 
        reserveOracle.setExchangeRate(1 ether);

        // create borrow position 
        borrow(borrower1, stEthIndex, 10 ether, 5 ether); 

        // liquidate call 
        vm.startPrank(keeper1);
        vm.expectRevert(
            abi.encodeWithSelector(Liquidation.VaultIsNotUnsafe.selector, 1.5 ether) 
        );
        liquidation.liquidate(stEthIndex, borrower1, keeper1); 
        vm.stopPrank(); 
    }   


}
