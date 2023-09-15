// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IIonPool } from "./interfaces/IIonPool.sol";
import { Vat } from "./Vat.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


interface IERC20Like is IERC20 {
    function decimals() external view returns (uint256);
}

contract IonPool is IIonPool {
    using SafeERC20 for IERC20Like;

    Vat public vat;
    IERC20 baseAsset;

    struct Info {
        uint256 to18ConversionFactor; 
        IERC20Like gem; 
    }

    mapping (bytes32 ilk => Info info) public ilks; 

    // mapping(bytes32 ilkId => IERC20 ilk) public ilks; // TODO: add this to the struct

    constructor(Vat _vat) {
        vat = _vat;
    }

    // --- Events ---
    event JoinGem(bytes32 indexed ilk, address indexed usr, uint256 indexed amt); 
    event ExitGem(bytes32 indexed ilk, address indexed usr, uint256 indexed amt); 
    event InitIlk(bytes32 indexed ilk, address indexed gem); 

    /// --- Administration --- 
    
    /**
     * @dev Initializes a new ilk that can be collateralized
     * @param ilk the name of the collateral  
     * @param gem the address of the ERC20
     */
    function initIlk(bytes32 ilk, address gem) public { // TODO: add onlyOwner 
        Info storage info = ilks[ilk]; 
        info.to18ConversionFactor = 10 ** (18 - IERC20Like(gem).decimals()); 
        info.gem = IERC20Like(gem); 
        emit InitIlk(ilk, gem); 
    }

    /// --- Lender Operations --- 

    function supply(uint256 amt) external {}

    function redeem(uint256 amt) external {}

    // --- Borrower Operations --- 

    /**
     * @dev exits internal base asset to ERC20 base asset  
     */
    function exit(uint256 amt) external {

    }

    /**
     * @dev Lock ERC20 and mint gem
     * @param ilk The collateral type to join
     * @param usr Address to send the ERC20 to
     * @param amt Amount to join in the collateral's native precision
     */
    function joinGem(bytes32 ilk, address usr, uint256 amt) external {
        Info memory info = ilks[ilk];
        uint256 wad = amt * info.to18ConversionFactor; 
        require(int256(wad) >= 0, "IonPool/joinGem-overflow"); 
        vat.slip(ilk, usr, int256(wad));  
        info.gem.safeTransferFrom(msg.sender, address(this), amt); 
        emit JoinGem(ilk, usr, amt); 
    }

    /**
     * @dev Exit gem and unlock ERC20 
     * @param ilk The collateral type to exit 
     * @param usr Address to send the collateral to
     * @param amt Amount to exit in the collateral's native precision 
     */
    function exitGem(bytes32 ilk, address usr, uint256 amt) external {
        Info memory info = ilks[ilk]; 
        uint256 wad = amt * info.to18ConversionFactor; 
        require(int256(wad) >= 0, "IonPool/exitGem-overflow"); 
        vat.slip(ilk, msg.sender, -int256(wad)); 
        info.gem.safeTransfer(usr, amt); 
        emit ExitGem(ilk, usr, amt); 
    } 

}
