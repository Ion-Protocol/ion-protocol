contract StEthTest is Test {
    function setUp() public {
        uint256 blockNumber = 100;
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), blockNumber);
        vm.selectFork(mainnetFork);
    }
}
