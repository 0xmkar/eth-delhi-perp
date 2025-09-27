// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/PerpMarket.sol";

contract DeployTestnetScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);
        
        console.log("Deploying to testnet...");
        console.log("Deployer:", deployer);
        console.log("Treasury:", treasury);
        console.log("Balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast(deployerPrivateKey);
        
        DDexRBTC ddex = new DDexRBTC(treasury);
        
        vm.stopBroadcast();
        
        console.log("DDexRBTC deployed to:", address(ddex));
        console.log("Owner:", ddex.owner());
        console.log("Treasury:", ddex.treasury());
        console.log("Transfer Fee:", ddex.transferFee());
        console.log("Withdrawal Fee:", ddex.withdrawalFee());
        
        // Save deployment info
        string memory deploymentInfo = string(
            abi.encodePacked(
                "Contract Address: ", vm.toString(address(ddex)), "\n",
                "Owner: ", vm.toString(ddex.owner()), "\n",
                "Treasury: ", vm.toString(ddex.treasury()), "\n",
                "Transfer Fee: ", vm.toString(ddex.transferFee()), " basis points\n",
                "Withdrawal Fee: ", vm.toString(ddex.withdrawalFee()), " basis points\n",
                "Network: ", getNetworkName(), "\n",
                "Chain ID: ", vm.toString(block.chainid), "\n"
            )
        );
        
        vm.writeFile("deployment-testnet.txt", deploymentInfo);
        console.log("Deployment info saved to deployment-testnet.txt");
    }
    
    function getNetworkName() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        if (chainId == 11155111) return "Sepolia";
        if (chainId == 62298) return "Citrea Testnet";
        return string(abi.encodePacked("Unknown Chain ID: ", vm.toString(chainId)));
    }
}
