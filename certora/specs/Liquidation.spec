import "erc20.spec";

using ERC20A as underlying;
using ERC20B as underlyingForPool;
using IonPool as Ion;

use builtin rule sanity;

methods {
    function _.currentExchangeRate() external => DISPATCHER(true);

    // mulDiv summary for better run time
    function _.mulDiv(uint x, uint y, uint denominator) internal => cvlMulDiv(x,y,denominator) expect uint;

    // InterestRate
    // Summarizing this function will improve run time, use NONDET if output doesn't matter
    function _.calculateInterestRate(uint256,uint256,uint256) external => DISPATCHER(true);

    // YieldOracle
    function _.apys(uint256) external => PER_CALLEE_CONSTANT;

    // envfree definitions
    function Ion.underlying() external returns (address) envfree;
    function underlying.balanceOf(address) external returns (uint256) envfree;
    function underlyingForPool.balanceOf(address) external returns (uint256) envfree;
}

function cvlMulDiv(uint x, uint y, uint denominator) returns uint {
    require(denominator != 0);
    return require_uint256(x*y/denominator);
}

rule basicFRule(env e) {
    uint8 ilkIndex; 
    address vault; 
    address kpr;

    require Ion.underlying() == underlyingForPool;

    uint256 underlyingBalanceBefore = underlying.balanceOf(currentContract);
    uint256 underForPoolBefore = underlyingForPool.balanceOf(currentContract);

    // aliasing assumptions
    // require vault != kpr;
    // require e.msg.sender != currentContract;

    liquidate(e, ilkIndex, vault, kpr);

    uint256 underlyingBalanceAfter = underlying.balanceOf(currentContract);
    uint256 underForPoolAfter = underlyingForPool.balanceOf(currentContract);

    assert underlyingBalanceAfter > underlyingBalanceBefore => underForPoolAfter > underForPoolBefore, "Unexpected balance change";
}