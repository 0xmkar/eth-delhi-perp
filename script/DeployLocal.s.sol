// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/PerpMarket.sol";

contract DeployLocalScript is Script {
    function run() external {
        // Use default anvil account
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);
        address treasury = deployer; // Use deployer as treasury for local testing
        
        console.log("Deploying to local network...");
        console.log("Deployer:", deployer);
        console.log("Treasury:", treasury);
        console.log("Balance:", deployer.balance);
        
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
                "Network: Local Anvil\n"
            )
        );
        
        vm.writeFile("deployment-local.txt", deploymentInfo);
        console.log("Deployment info saved to deployment-local.txt");
    }
}
