// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import "forge-std/Test.sol";
// import "./PerpMarket.t.sol"; // Reuse mock contracts

// /**
//  * @title Simple Integration Test
//  * @dev Basic integration test without complex console logging
//  */
// contract IntegrationSimpleTest is Test {
//     // Contracts
//     PerpMarket public perpMarket;
//     MarginVault public marginVault;
//     PythOracleAdapter public priceOracle;
//     Treasury public treasury;
//     MockcBTC public cBTC;
//     MockPyth public mockPyth;
    
//     // Users
//     address public owner = address(0x1);
//     address public trader1 = address(0x2);
//     address public trader2 = address(0x3);
//     address public liquidator = address(0x4);
//     address public feeRecipient = address(0x5);
    
//     // Test parameters
//     bytes32 public constant BTC_PRICE_FEED_ID = bytes32(uint256(0x1));
//     uint256 public constant INITIAL_BTC_PRICE = 50000 * 10**18;
//     uint256 public constant INITIAL_BALANCE = 100000 * 10**18;
    
//     function setUp() public {
//         vm.startPrank(owner);
        
//         // Deploy all contracts
//         cBTC = new MockcBTC();
//         mockPyth = new MockPyth();
        
//         marginVault = new MarginVault(address(cBTC), owner);
//         priceOracle = new PythOracleAdapter(address(mockPyth), BTC_PRICE_FEED_ID, 60, owner);
//         treasury = new Treasury(feeRecipient, owner);
        
//         perpMarket = new PerpMarket(
//             marginVault,
//             priceOracle,
//             treasury,
//             cBTC,
//             owner
//         );
        
//         // Configure contracts
//         marginVault.setAuthorizedContract(address(perpMarket), true);
//         treasury.setAuthorizedContract(address(perpMarket), true);
        
//         // Set initial BTC price
//         mockPyth.setPrice(
//             BTC_PRICE_FEED_ID,
//             5000000000000, // $50,000 * 10^8
//             100000000,
//             -8,
//             block.timestamp
//         );
        
//         // Distribute tokens to users
//         cBTC.mint(trader1, INITIAL_BALANCE);
//         cBTC.mint(trader2, INITIAL_BALANCE);
//         cBTC.mint(liquidator, INITIAL_BALANCE);
        
//         vm.stopPrank();
        
//         // Setup user approvals and deposits
//         _setupUser(trader1);
//         _setupUser(trader2);
//         _setupUser(liquidator);
//     }
    
//     function _setupUser(address user) internal {
//         vm.startPrank(user);
//         cBTC.approve(address(marginVault), type(uint256).max);
//         marginVault.deposit(INITIAL_BALANCE);
//         vm.stopPrank();
//     }
    
//     function testFullTradingFlow() public {
//         // 1. Initial state verification
//         assertEq(cBTC.balanceOf(trader1), 0);
//         assertEq(marginVault.getBalance(trader1), INITIAL_BALANCE);
//         assertEq(priceOracle.getMarkPrice(), INITIAL_BTC_PRICE);
        
//         // 2. Open long position
//         vm.startPrank(trader1);
//         uint256 positionSize = 10 * 10**18;
//         perpMarket.openPosition(true, positionSize);
        
//         PerpMarket.Position memory pos1 = perpMarket.getPosition(trader1);
//         assertEq(pos1.size, positionSize);
//         assertEq(pos1.entryPrice, INITIAL_BTC_PRICE);
//         assertTrue(pos1.isLong);
//         vm.stopPrank();
        
//         // 3. Open short position
//         vm.startPrank(trader2);
//         uint256 shortSize = 15 * 10**18;
//         perpMarket.openPosition(false, shortSize);
        
//         PerpMarket.Position memory pos2 = perpMarket.getPosition(trader2);
//         assertEq(pos2.size, shortSize);
//         assertFalse(pos2.isLong);
//         vm.stopPrank();
        
//         // 4. Check global market state
//         (uint256 totalLongs, uint256 totalShorts, uint256 volume,) = perpMarket.getMarketStats();
//         assertEq(totalLongs, positionSize);
//         assertEq(totalShorts, shortSize);
        
//         // 5. Price increases - Long profits, Short loses
//         mockPyth.setPrice(
//             BTC_PRICE_FEED_ID,
//             5500000000000, // $55,000 * 10^8
//             100000000,
//             -8,
//             block.timestamp
//         );
        
//         int256 pnl1 = perpMarket.getCurrentPnL(trader1);
//         int256 pnl2 = perpMarket.getCurrentPnL(trader2);
        
//         assertTrue(pnl1 > 0); // Long should profit
//         assertTrue(pnl2 < 0); // Short should lose
        
//         // 6. Close profitable position
//         vm.startPrank(trader1);
//         uint256 balanceBefore = marginVault.getBalance(trader1);
//         perpMarket.closePosition();
//         uint256 balanceAfter = marginVault.getBalance(trader1);
        
//         assertTrue(balanceAfter > balanceBefore);
        
//         PerpMarket.Position memory closedPos = perpMarket.getPosition(trader1);
//         assertEq(closedPos.size, 0);
//         vm.stopPrank();
        
//         // 7. Test fee collection
//         uint256 treasuryBalance = treasury.getBalance(address(cBTC));
//         assertTrue(treasuryBalance > 0);
        
//         // 8. Test liquidation scenario
//         mockPyth.setPrice(
//             BTC_PRICE_FEED_ID,
//             2500000000000, // $25,000 * 10^8 (extreme drop)
//             100000000,
//             -8,
//             block.timestamp
//         );
        
//         // Open large position for liquidation test
//         vm.startPrank(liquidator);
//         perpMarket.openPosition(true, 50 * 10**18);
//         vm.stopPrank();
        
//         // Check if liquidatable
//         bool isLiquidatable = perpMarket.isLiquidatable(liquidator);
//         if (isLiquidatable) {
//             vm.startPrank(trader2);
//             uint256 liquidatorBalanceBefore = marginVault.getBalance(trader2);
            
//             perpMarket.liquidatePosition(liquidator);
            
//             uint256 liquidatorBalanceAfter = marginVault.getBalance(trader2);
//             assertTrue(liquidatorBalanceAfter > liquidatorBalanceBefore);
            
//             PerpMarket.Position memory liquidatedPos = perpMarket.getPosition(liquidator);
//             assertEq(liquidatedPos.size, 0);
//             vm.stopPrank();
//         }
        
//         // 9. Test admin functions
//         vm.startPrank(owner);
//         perpMarket.setTradingFeeBps(20);
//         assertEq(perpMarket.tradingFeeBps(), 20);
        
//         perpMarket.setMaintenanceMarginBps(1200);
//         assertEq(perpMarket.maintenanceMarginBps(), 1200);
//         vm.stopPrank();
//     }
    
//     function testMarginVaultOperations() public {
//         // Test basic vault operations
//         vm.startPrank(trader1);
        
//         uint256 depositAmount = 1000 * 10**18;
//         uint256 initialBalance = marginVault.getBalance(trader1);
        
//         marginVault.deposit(depositAmount);
//         assertEq(marginVault.getBalance(trader1), initialBalance + depositAmount);
        
//         uint256 withdrawAmount = 500 * 10**18;
//         marginVault.withdraw(withdrawAmount);
//         assertEq(marginVault.getBalance(trader1), initialBalance + depositAmount - withdrawAmount);
        
//         vm.stopPrank();
//     }
    
//     function testOracleOperations() public {
//         // Test oracle functionality
//         uint256 currentPrice = priceOracle.getMarkPrice();
//         assertEq(currentPrice, 50000 * 10**18);
        
//         (uint256 price, uint256 confidence, uint256 publishTime) = priceOracle.getMarkPriceWithConfidence();
//         assertEq(price, 50000 * 10**18);
//         assertTrue(confidence > 0);
//         assertTrue(publishTime > 0);
        
//         assertTrue(priceOracle.isPriceFresh());
//     }
    
//     function testTreasuryOperations() public {
//         // Setup fees
//         vm.startPrank(trader1);
//         perpMarket.openPosition(true, 5 * 10**18);
//         vm.stopPrank();
        
//         // Check fee collection
//         uint256 treasuryBalance = treasury.getBalance(address(cBTC));
//         assertTrue(treasuryBalance > 0);
        
//         // Test fee withdrawal
//         vm.startPrank(owner);
//         uint256 recipientBalanceBefore = cBTC.balanceOf(feeRecipient);
//         treasury.withdrawFees(address(cBTC), 0);
//         uint256 recipientBalanceAfter = cBTC.balanceOf(feeRecipient);
        
//         assertTrue(recipientBalanceAfter > recipientBalanceBefore);
//         vm.stopPrank();
//     }
// } 