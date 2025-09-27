// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/DDexRBTC.sol";

contract DeployScript is Script {
    function run() external {
        // Get private key from environment or use default
        uint256 deployerPrivateKey;
        
        // Try to get from environment, fallback to anvil default
        try vm.envUint("PRIVATE_KEY") returns (uint256 key) {
            deployerPrivateKey = key;
        } catch {
            // Default anvil account private key
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
            console.log("Using default anvil private key");
        }
        
        address deployer = vm.addr(deployerPrivateKey);
        
        // Get treasury address from environment or use deployer
        address treasury;
        try vm.envAddress("TREASURY_ADDRESS") returns (address treasuryAddr) {
            treasury = treasuryAddr;
        } catch {
            treasury = deployer;
            console.log("Using deployer as treasury address");
        }
        
        console.log("====== Deployment Configuration ======");
        console.log("Deployer:", deployer);
        console.log("Treasury:", treasury);
        console.log("Balance:", deployer.balance);
        console.log("Chain ID:", block.chainid);
        console.log("=======================================");
        
        vm.startBroadcast(deployerPrivateKey);
        
        DDexRBTC ddex = new DDexRBTC(treasury);
        
        vm.stopBroadcast();
        
        console.log("====== Deployment Successful ======");
        console.log("Contract Address:", address(ddex));
        console.log("Owner:", ddex.owner());
        console.log("Treasury:", ddex.treasury());
        console.log("Transfer Fee:", ddex.transferFee(), "basis points");
        console.log("Withdrawal Fee:", ddex.withdrawalFee(), "basis points");
        console.log("===================================");
        
        // Save deployment info
        string memory networkName = getNetworkName();
        string memory deploymentInfo = string(
            abi.encodePacked(
                "=== DDexRBTC Deployment ===\n",
                "Contract Address: ", vm.toString(address(ddex)), "\n",
                "Owner: ", vm.toString(ddex.owner()), "\n",
                "Treasury: ", vm.toString(ddex.treasury()), "\n",
                "Transfer Fee: ", vm.toString(ddex.transferFee()), " basis points\n",
                "Withdrawal Fee: ", vm.toString(ddex.withdrawalFee()), " basis points\n",
                "Network: ", networkName, "\n",
                "Chain ID: ", vm.toString(block.chainid), "\n",
                "Deployed at: ", vm.toString(block.timestamp), "\n"
            )
        );
        
        string memory filename = string(abi.encodePacked("deployment-", vm.toString(block.chainid), ".txt"));
        vm.writeFile(filename, deploymentInfo);
        console.log("Deployment info saved to:", filename);
    }
    
    function getNetworkName() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        if (chainId == 1) return "Mainnet";
        if (chainId == 11155111) return "Sepolia";
        if (chainId == 62298) return "Citrea Testnet";
        if (chainId == 31337) return "Local Anvil";
        return string(abi.encodePacked("Unknown Chain ID: ", vm.toString(chainId)));
    }
}
