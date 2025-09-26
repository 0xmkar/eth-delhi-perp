// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MarginVault.sol";
import "../src/Treasury.sol";
import "../src/PerpMarket.sol";
import "../src/vAMM.sol";

/**
 * @title Deploy
 * @dev Deployment script for the derivative DEX on Citrea testnet
 * Deploys all core contracts with native cBTC support and in-house pricing
 */
contract Deploy is Script {
    
    // Deployment parameters
    address public constant FEE_RECIPIENT = 0xAaea98f69ef793E3E3a93De2E748292523CA6034; // Update with actual recipient
    uint256 public constant INITIAL_BTC_PRICE = 50000 * 10**18; // $50,000 - Initial oracle price
    
    // vAMM parameters
    uint256 public constant INITIAL_BASE_RESERVE = 1000 * 10**18; // 1000 virtual BTC
    uint256 public constant INITIAL_QUOTE_RESERVE = 50000000 * 10**18; // 50M virtual USDC (50K * 1000)
    bytes32 public constant BTC_DATA_FEED_ID = bytes32("BTC"); // RedStone data feed ID
    
    // Contract instances
    MarginVault public marginVault;
    Treasury public treasury;
    vAMM public vammContract;
    PerpMarket public perpMarket;
    
    // Deployer address
    address public deployer;

    function run() external virtual {
        // Get deployer private key and address
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);
        
        console.log("Starting deployment...");
        console.log("Deployer:          ", deployer);
        console.log("Initial BTC Price: ", INITIAL_BTC_PRICE);
        console.log("Fee Recipient:     ", FEE_RECIPIENT);
        console.log("vAMM Base Reserve: ", INITIAL_BASE_RESERVE);
        console.log("vAMM Quote Reserve:", INITIAL_QUOTE_RESERVE);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy MarginVault
        console.log("\n=== Deploying MarginVault ===");
        marginVault = new MarginVault(deployer);
        console.log("MarginVault deployed at:", address(marginVault));
        
        // Deploy Treasury
        console.log("\n=== Deploying Treasury ===");
        treasury = new Treasury(FEE_RECIPIENT, deployer);
        console.log("Treasury deployed at:", address(treasury));
        
        // Deploy vAMM
        console.log("\n=== Deploying vAMM ===");
        vammContract = new vAMM(
            INITIAL_BASE_RESERVE,
            INITIAL_QUOTE_RESERVE,
            BTC_DATA_FEED_ID,
            deployer
        );
        console.log("vAMM deployed at:", address(vammContract));
        
        // Deploy PerpMarket
        console.log("\n=== Deploying PerpMarket ===");
        perpMarket = new PerpMarket(
            marginVault,
            treasury,
            vammContract,
            deployer
        );
        console.log("PerpMarket deployed at:", address(perpMarket));
        
        // Set up contract authorizations
        console.log("\n=== Setting up authorizations ===");
        
        // Authorize PerpMarket to interact with MarginVault
        marginVault.setAuthorizedContract(address(perpMarket), true);
        console.log("PerpMarket authorized for MarginVault");
        
        // Authorize PerpMarket to send fees to Treasury
        treasury.setAuthorizedContract(address(perpMarket), true);
        console.log("PerpMarket authorized for Treasury");
        
        // Authorize PerpMarket to trade on vAMM
        vammContract.addAuthorizedCaller(address(perpMarket));
        console.log("PerpMarket authorized for vAMM");
        
        // Verify deployments
        console.log("\n=== Deployment Verification ===");
        
                 // Verify MarginVault
         require(marginVault.owner() == deployer, "MarginVault owner mismatch");
         require(marginVault.authorizedContracts(address(perpMarket)), "PerpMarket not authorized for MarginVault");
         console.log("* MarginVault verified");
         
         // Verify Treasury
         require(treasury.owner() == deployer, "Treasury owner mismatch");
         require(treasury.feeRecipient() == FEE_RECIPIENT, "Treasury fee recipient mismatch");
         require(treasury.authorizedContracts(address(perpMarket)), "PerpMarket not authorized for Treasury");
         console.log("* Treasury verified");
         
         // Verify vAMM
         require(vammContract.owner() == deployer, "vAMM owner mismatch");
         require(vammContract.authorizedCallers(address(perpMarket)), "PerpMarket not authorized for vAMM");
         console.log("* vAMM verified");
         
         // Verify PerpMarket
         require(perpMarket.owner() == deployer, "PerpMarket owner mismatch");
         require(address(perpMarket.marginVault()) == address(marginVault), "PerpMarket marginVault mismatch");
         require(address(perpMarket.treasury()) == address(treasury), "PerpMarket treasury mismatch");
         require(address(perpMarket.vamm()) == address(vammContract), "PerpMarket vAMM mismatch");
         console.log("* PerpMarket verified");
        
        // Print configuration
        console.log("\n=== Current Configuration ===");
        console.log("Maintenance Margin:", perpMarket.maintenanceMarginBps(), "bps");
        console.log("Initial Margin:    ", perpMarket.initialMarginBps(), "bps");
        console.log("Trading Fee:       ", perpMarket.tradingFeeBps(), "bps");
        console.log("Liquidation Reward:", perpMarket.liquidationRewardBps(), "bps");
        console.log("Trading Paused:    ", perpMarket.tradingPaused() ? "Yes" : "No");
        
        // Print final summary
        console.log("\n=== Deployment Summary ===");
        console.log("MarginVault:       ", address(marginVault));
        console.log("Treasury:          ", address(treasury));
        console.log("vAMM:              ", address(vammContract));
        console.log("PerpMarket:        ", address(perpMarket));
        console.log("Current Mark Price:", vammContract.getMarkPrice());
        console.log("Fee Recipient:     ", FEE_RECIPIENT);
        
        console.log("\n=== Post-Deployment Instructions ===");
        console.log("1. Update funding rates using perpMarket.updateFundingRate()");
        console.log("2. Monitor vAMM state and adjust K value if needed using vammContract.adjustK()");
        console.log("3. Monitor positions and liquidations");
        console.log("4. Withdraw fees from treasury when needed");
        console.log("5. Adjust trading parameters as needed for market conditions");
        
        vm.stopBroadcast();
    }
    
    /**
     * @dev Deploy with testnet parameters for easier testing
     */
    function deployTestnet() external {
        // Run base deployment first
        this.run();
        
        console.log("\n=== Testnet Additional Setup ===");
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Set more lenient parameters for testing
        perpMarket.setMaintenanceMarginBps(500);  // 5% for easier testing
        perpMarket.setInitialMarginBps(1000);     // 10% for easier testing
        perpMarket.setTradingFeeBps(50);          // 0.5% for testing
        
        console.log("* Testnet parameters set");
        
        // Add some test scenarios logging
        console.log("\n=== Test Scenarios ===");
        console.log("1. Deposit cBTC: marginVault.deposit{value: amount}()");
        console.log("2. Open position: perpMarket.openPosition{value: margin+fee}(isLong, size)");
        console.log("3. Update funding rate: perpMarket.updateFundingRate() [anyone]");
        console.log("4. Close position: perpMarket.closePosition()");
        console.log("5. Check PnL: perpMarket.getCurrentPnL(user)");
        
        vm.stopBroadcast();
    }
} 