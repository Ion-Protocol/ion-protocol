pragma solidity 0.8.19;

import "forge-std/test.sol";
import {IonPool} from "src/IonPool.sol"; 
import {RewardToken} from "src/token/RewardToken.sol"; 
import {RewardTokenSharedSetup} from "test/helpers/RewardTokenSharedSetup.sol"; 
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract IonPoolTest is Test {
    ERC20PresetMinterPauser underlying;
    ERC20PresetMinterPauser gem; 
    IonPool pool;
    
    uint256 internal constant INITIAL_UNDERYLING = 1000e18;
    address internal TREASURY = vm.addr(99);
    uint8 internal constant DECIMALS = 18;
    string internal constant SYMBOL = "iWETH";
    string internal constant NAME = "Ion Wrapped Ether";

    function setUp() public {

        // base asset 
        underlying = new ERC20PresetMinterPauser("WETH", "Wrapped Ether");
        underlying.mint(address(this), INITIAL_UNDERYLING);

        // collateral asset 
        gem = new ERC20PresetMinterPauser("lstETH", "Liquid Staking Token"); 

        pool = new IonPool(
            address(underlying), TREASURY, DECIMALS, NAME, SYMBOL
        );
    }

    // --- Init --- 
    function test_init() external {
        pool.init("lstETH", address(gem));

    }

    // --- Borrower Joins ---
    function test_joinGemBasic() external {}

    function test_joinGemOverflow() external {}

    function test_exitGemBasic() external {}

    function test_exitGemOverflow() external {}

    // --- Borrower Operations ---
    function test_borrowAndExitBase() external {}

    function test_joinBaseAndPay() external {}
}
