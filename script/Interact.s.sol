// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/DDexRBTC.sol";

contract InteractScript is Script {
    DDexRBTC public ddex;
    
    function run() external {
        // Get contract address from environment or use default
        address contractAddress = vm.envOr("CONTRACT_ADDRESS", address(0));
        require(contractAddress != address(0), "Please set CONTRACT_ADDRESS environment variable");
        
        ddex = DDexRBTC(payable(contractAddress));
        
        console.log("Interacting with DDexRBTC at:", contractAddress);
        console.log("Owner:", ddex.owner());
        console.log("Treasury:", ddex.treasury());
        console.log("Transfer Fee:", ddex.transferFee());
        console.log("Withdrawal Fee:", ddex.withdrawalFee());
        console.log("Total Deposited:", ddex.totalDeposited());
        console.log("Treasury Balance:", ddex.getTreasuryBalance());
        console.log("Contract Balance:", ddex.contractBalance());
        
        // Example interactions (uncomment as needed)
        // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // vm.startBroadcast(deployerPrivateKey);
        
        // Example: Deposit 1 ETH
        // ddex.deposit{value: 1 ether}();
        // console.log("Deposited 1 ETH");
        
        // Example: Transfer 0.5 ETH to another address
        // address recipient = makeAddr("recipient");
        // ddex.transfer(recipient, 0.5 ether);
        // console.log("Transferred 0.5 ETH to:", recipient);
        
        // Example: Withdraw 0.3 ETH
        // ddex.withdraw(0.3 ether);
        // console.log("Withdrew 0.3 ETH");
        
        // Example: Update fees
        // ddex.setTransferFee(50); // 0.5%
        // ddex.setWithdrawalFee(100); // 1%
        // console.log("Updated fees");
        
        // vm.stopBroadcast();
        
        console.log("Interaction complete");
    }
}
