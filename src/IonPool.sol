// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IIonPool} from "./interfaces/IIonPool.sol";
import {Vat} from "./Vat.sol";
import {RewardToken} from "./token/RewardToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IERC20Like is IERC20 {
    function decimals() external view returns (uint256);
}

contract IonPool is Vat, RewardToken {
    using SafeERC20 for IERC20Like;

    struct Info {
        uint256 to18ConversionFactor;
        IERC20Like gem;
    }

    mapping(bytes32 ilk => Info info) public infos;

    constructor(address _underlying, address _treasury, uint8 _decimals, string memory _name, string memory _symbol)
        Vat()
        RewardToken(_underlying, _treasury, _decimals, _name, _symbol)
    {}

    // --- Events ---
    event Supply(address indexed sender, uint256 amt);
    event Redeem(address indexed sender, address receiver, uint256 amt);
    event JoinGem(bytes32 indexed ilk, address indexed usr, uint256 indexed amt);
    event ExitGem(bytes32 indexed ilk, address indexed usr, uint256 indexed amt);
    event InitIlk(bytes32 indexed ilk, address indexed gem);
    event ExitBase();
    event JoinBase();

    /// --- Administration ---

    /**
     * @dev Initializes a new ilk that can be collateralized
     * @param ilk the name of the collateral
     * @param gem the address of the ERC20
     */
    function init(bytes32 ilk, address gem) external {
        // TODO: add onlyOwner

        // adds ilk info for join
        Info storage info = infos[ilk];
        info.to18ConversionFactor = 10 ** (18 - IERC20Like(gem).decimals());
        info.gem = IERC20Like(gem);

        // sets up ilk in vat
        _init(ilk); 

        emit InitIlk(ilk, gem);
    }

    /// --- Math --- 
    uint256 constant RAY = 10**27;

    /// --- Lender Operations ---

    /**
     * @dev Lenders transfer WETH to supply liquidity. Takes WETH and mints iWETH
     * @param usr the address that receives the minted iWETH
     * @param amt the amount of WETH to transfer [wad]
     */
    function supply(address usr, uint256 amt) external {
        _mint(usr, amt);
        emit Supply(msg.sender, amt);
    }

    /**
     * @dev Lenders redeem their iWETH for the underlying WETH
     * @param usr the address that receives the underlying WETH
     * @param amt the amount of iWETH to transfer (non-normalized amount) [wad]
     */
    function redeem(address usr, uint256 amt) external {
        _burn(msg.sender, usr, amt);
        emit Redeem(msg.sender, usr, amt);
    }

    // --- Borrower Operations ---

    /**
     * @dev Exits internal weth that was borrowed to ERC20 WETH
     * @param usr The address that receives the borrowed WETH
     * @param amt The amount of weth to tranfer [wad]
     */
    function exitBase(address usr, uint256 amt) external {
        // weth is created when collateral is deposited
        // exit this dai to WETH to be useful (lock dai and transfer WETH)
        // when repaying, bring back WETH, get back the dai. And you can use the dai to pay down the debt.
        super.move(msg.sender, address(this), amt * RAY);
        IERC20Like(underlying).safeTransfer(usr, amt);
        emit ExitBase();
    }

    /**
     * @dev Joins the ERC20 base asset and unlocks internal weth.
     *      The ERC20 base asset returns to supply pool as debtor's payment.
     *      The internal weth can be used in the vat.
     *      NOTE: Borrowers can split their total debt between internal weth and ERC20 WETH.
     *            The ERC20 WETH balance of the Pool does not reflect the amount of utilization or debt created.
     * @param usr The address that receives the internal weth
     * @param amt The amount of ERC20 weth to transfer [wad]
     */
    function joinBase(address usr, uint256 amt) external {
        super.move(address(this), usr, amt);
        IERC20Like(underlying).safeTransferFrom(msg.sender, address(this), amt);
        emit JoinBase();
    }

    /**
     * @dev Lock ERC20 and mint gem
     * @param ilk The collateral type to join
     * @param usr Address to send the ERC20 to
     * @param amt Amount to join in the collateral's native precision
     */
    function joinGem(bytes32 ilk, address usr, uint256 amt) external {
        Info memory info = infos[ilk];
        uint256 wad = amt * info.to18ConversionFactor;
        require(int256(wad) >= 0, "IonPool/joinGem-overflow");
        super.slip(ilk, usr, int256(wad));
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
        Info memory info = infos[ilk];
        uint256 wad = amt * info.to18ConversionFactor;
        require(int256(wad) >= 0, "IonPool/exitGem-overflow");
        super.slip(ilk, msg.sender, -int256(wad));
        info.gem.safeTransfer(usr, amt);
        emit ExitGem(ilk, usr, amt);
    }
}
