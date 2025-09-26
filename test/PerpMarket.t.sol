// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PerpMarket.sol";
import "../src/MarginVault.sol";
import "../src/Treasury.sol";

contract PerpMarketTest is Test {
    PerpMarket public perpMarket;
    MarginVault public marginVault;
    Treasury public treasury;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public feeRecipient = address(0x4);
    address public liquidator = address(0x5);
    
    uint256 public constant INITIAL_PRICE = 50000 * 10**18; // $50,000
    uint256 public constant DEPOSIT_AMOUNT = 10000 * 10**18; // 10,000 cBTC
    uint256 public constant POSITION_SIZE = 5 * 10**18; // 5 cBTC

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy core contracts
        marginVault = new MarginVault(owner);
        treasury = new Treasury(feeRecipient, owner);
        
        perpMarket = new PerpMarket(
            marginVault,
            treasury,
            INITIAL_PRICE,
            owner
        );
        
        // Set up authorizations
        marginVault.setAuthorizedContract(address(perpMarket), true);
        treasury.setAuthorizedContract(address(perpMarket), true);
        
        vm.stopPrank();
        
        // Give users native cBTC
        vm.deal(user1, DEPOSIT_AMOUNT * 2);
        vm.deal(user2, DEPOSIT_AMOUNT * 2);
        vm.deal(liquidator, DEPOSIT_AMOUNT);
        
        // Users deposit to margin vault
        vm.prank(user1);
        marginVault.deposit{value: DEPOSIT_AMOUNT}();
        
        vm.prank(user2);
        marginVault.deposit{value: DEPOSIT_AMOUNT}();
        
        vm.prank(liquidator);
        marginVault.deposit{value: DEPOSIT_AMOUNT}();
    }

    function test_Open_Long_Position() public {
        vm.startPrank(user1);
        
        uint256 initialMarginBps = perpMarket.initialMarginBps();
        uint256 tradingFeeBps = perpMarket.tradingFeeBps();
        
        uint256 requiredMargin = (POSITION_SIZE * initialMarginBps) / 10000;
        uint256 tradingFee = (POSITION_SIZE * tradingFeeBps) / 10000;
        uint256 totalRequired = requiredMargin + tradingFee;
        
        // Open long position
        perpMarket.openPosition{value: totalRequired}(true, POSITION_SIZE);
        
        // Check position
        PerpMarket.Position memory pos = perpMarket.getPosition(user1);
        assertEq(pos.size, POSITION_SIZE);
        assertEq(pos.entryPrice, INITIAL_PRICE);
        assertEq(pos.margin, requiredMargin);
        assertTrue(pos.isLong);
        
        // Check global state
        assertEq(perpMarket.totalLongSize(), POSITION_SIZE);
        assertEq(perpMarket.totalShortSize(), 0);
        
        vm.stopPrank();
    }

    function test_Open_Short_Position() public {
        vm.startPrank(user1);
        
        uint256 initialMarginBps = perpMarket.initialMarginBps();
        uint256 tradingFeeBps = perpMarket.tradingFeeBps();
        
        uint256 requiredMargin = (POSITION_SIZE * initialMarginBps) / 10000;
        uint256 tradingFee = (POSITION_SIZE * tradingFeeBps) / 10000;
        uint256 totalRequired = requiredMargin + tradingFee;
        
        // Open short position
        perpMarket.openPosition{value: totalRequired}(false, POSITION_SIZE);
        
        // Check position
        PerpMarket.Position memory pos = perpMarket.getPosition(user1);
        assertEq(pos.size, POSITION_SIZE);
        assertEq(pos.entryPrice, INITIAL_PRICE);
        assertEq(pos.margin, requiredMargin);
        assertFalse(pos.isLong);
        
        // Check global state
        assertEq(perpMarket.totalLongSize(), 0);
        assertEq(perpMarket.totalShortSize(), POSITION_SIZE);
        
        vm.stopPrank();
    }

    function test_Close_Long_Position_With_Profit() public {
        // Open position first
        vm.startPrank(user1);
        uint256 initialMarginBps = perpMarket.initialMarginBps();
        uint256 tradingFeeBps = perpMarket.tradingFeeBps();
        uint256 requiredMargin = (POSITION_SIZE * initialMarginBps) / 10000;
        uint256 tradingFee = (POSITION_SIZE * tradingFeeBps) / 10000;
        uint256 totalRequired = requiredMargin + tradingFee;
        
        perpMarket.openPosition{value: totalRequired}(true, POSITION_SIZE);
        vm.stopPrank();
        
        // Update price upward for profit
        uint256 newPrice = 55000 * 10**18; // $55,000
        vm.prank(owner);
        perpMarket.updateMarkPrice(newPrice);
        
        // Check PnL
        int256 pnl = perpMarket.getCurrentPnL(user1);
        assertTrue(pnl > 0); // Should be profitable
        
        // Close position
        vm.prank(user1);
        perpMarket.closePosition();
        
        // Check position is cleared
        PerpMarket.Position memory pos = perpMarket.getPosition(user1);
        assertEq(pos.size, 0);
        
        // Check global state updated
        assertEq(perpMarket.totalLongSize(), 0);
    }

    function test_Close_Long_Position_With_Loss() public {
        // Open position first
        vm.startPrank(user1);
        uint256 initialMarginBps = perpMarket.initialMarginBps();
        uint256 tradingFeeBps = perpMarket.tradingFeeBps();
        uint256 requiredMargin = (POSITION_SIZE * initialMarginBps) / 10000;
        uint256 tradingFee = (POSITION_SIZE * tradingFeeBps) / 10000;
        uint256 totalRequired = requiredMargin + tradingFee;
        
        perpMarket.openPosition{value: totalRequired}(true, POSITION_SIZE);
        vm.stopPrank();
        
        // Update price downward for loss
        uint256 newPrice = 45000 * 10**18; // $45,000
        vm.prank(owner);
        perpMarket.updateMarkPrice(newPrice);
        
        // Check PnL
        int256 pnl = perpMarket.getCurrentPnL(user1);
        assertTrue(pnl < 0); // Should be losing
        
        // Close position
        vm.prank(user1);
        perpMarket.closePosition();
        
        // Check position is cleared
        PerpMarket.Position memory pos = perpMarket.getPosition(user1);
        assertEq(pos.size, 0);
    }

    function test_Close_Short_Position_With_Profit() public {
        // Open short position first
        vm.startPrank(user1);
        uint256 initialMarginBps = perpMarket.initialMarginBps();
        uint256 tradingFeeBps = perpMarket.tradingFeeBps();
        uint256 requiredMargin = (POSITION_SIZE * initialMarginBps) / 10000;
        uint256 tradingFee = (POSITION_SIZE * tradingFeeBps) / 10000;
        uint256 totalRequired = requiredMargin + tradingFee;
        
        perpMarket.openPosition{value: totalRequired}(false, POSITION_SIZE);
        vm.stopPrank();
        
        // Update price downward for profit on short
        uint256 newPrice = 45000 * 10**18; // $45,000
        vm.prank(owner);
        perpMarket.updateMarkPrice(newPrice);
        
        // Check PnL
        int256 pnl = perpMarket.getCurrentPnL(user1);
        assertTrue(pnl > 0); // Should be profitable for short
        
        // Close position
        vm.prank(user1);
        perpMarket.closePosition();
        
        // Check position is cleared
        PerpMarket.Position memory pos = perpMarket.getPosition(user1);
        assertEq(pos.size, 0);
    }

    function test_Liquidate_Position() public {
        // Open a highly leveraged position
        vm.startPrank(user1);
        uint256 initialMarginBps = perpMarket.initialMarginBps();
        uint256 tradingFeeBps = perpMarket.tradingFeeBps();
        uint256 requiredMargin = (POSITION_SIZE * initialMarginBps) / 10000;
        uint256 tradingFee = (POSITION_SIZE * tradingFeeBps) / 10000;
        uint256 totalRequired = requiredMargin + tradingFee;
        
        perpMarket.openPosition{value: totalRequired}(true, POSITION_SIZE);
        vm.stopPrank();
        console.log("totalRequired", totalRequired);
        
        // Move price significantly down to trigger liquidation
        uint256 newPrice = 35000 * 10**18; // $35,000 - significant drop
        vm.prank(owner);
        perpMarket.updateMarkPrice(newPrice);
        
        // Check if position is liquidatable
        assertTrue(perpMarket.isLiquidatable(user1));
        console.log("isLiquidatable", perpMarket.isLiquidatable(user1));
        
        // Liquidate position
        vm.prank(liquidator);
        perpMarket.liquidatePosition(user1);
        
        // Check position is cleared
        PerpMarket.Position memory pos = perpMarket.getPosition(user1);
        assertEq(pos.size, 0);
    }

    function test_Update_MarkPrice() public {
        uint256 newPrice = 60000 * 10**18; // $60,000
        
        vm.prank(owner);
        perpMarket.updateMarkPrice(newPrice);
        
        assertEq(perpMarket.getMarkPrice(), newPrice);
        assertEq(perpMarket.markPrice(), newPrice);
    }

    function test_RevertWhen_Open_Position_When_Paused() public {
        // Pause trading
        vm.prank(owner);
        perpMarket.setTradingPaused(true);
        
        vm.startPrank(user1);
        uint256 initialMarginBps = perpMarket.initialMarginBps();
        uint256 tradingFeeBps = perpMarket.tradingFeeBps();
        uint256 requiredMargin = (POSITION_SIZE * initialMarginBps) / 10000;
        uint256 tradingFee = (POSITION_SIZE * tradingFeeBps) / 10000;
        uint256 totalRequired = requiredMargin + tradingFee;
        
        // Should fail when paused
        vm.expectRevert(PerpMarket.TradingPaused.selector);
        perpMarket.openPosition{value: totalRequired}(true, POSITION_SIZE);
        
        vm.stopPrank();
    }

    function test_RevertWhen_Open_Position_With_Existing_Position() public {
        // Open first position
        vm.startPrank(user1);
        uint256 initialMarginBps = perpMarket.initialMarginBps();
        uint256 tradingFeeBps = perpMarket.tradingFeeBps();
        uint256 requiredMargin = (POSITION_SIZE * initialMarginBps) / 10000;
        uint256 tradingFee = (POSITION_SIZE * tradingFeeBps) / 10000;
        uint256 totalRequired = requiredMargin + tradingFee;
        
        perpMarket.openPosition{value: totalRequired}(true, POSITION_SIZE);
        
        // Try to open another position - should fail
        vm.expectRevert(PerpMarket.PositionExists.selector);
        perpMarket.openPosition{value: totalRequired}(true, POSITION_SIZE);
        
        vm.stopPrank();
    }

    function test_RevertWhen_Close_Non_Existent_Position() public {
        vm.startPrank(user1);
        
        // Try to close position that doesn't exist
        vm.expectRevert(PerpMarket.NoPosition.selector);
        perpMarket.closePosition();
        
        vm.stopPrank();
    }

    function test_RevertWhen_Liquidate_Healthy_Position() public {
        // Open position
        vm.startPrank(user1);
        uint256 initialMarginBps = perpMarket.initialMarginBps();
        uint256 tradingFeeBps = perpMarket.tradingFeeBps();
        uint256 requiredMargin = (POSITION_SIZE * initialMarginBps) / 10000;
        uint256 tradingFee = (POSITION_SIZE * tradingFeeBps) / 10000;
        uint256 totalRequired = requiredMargin + tradingFee;
        
        perpMarket.openPosition{value: totalRequired}(true, POSITION_SIZE);
        vm.stopPrank();
        
        // Try to liquidate healthy position - should fail
        vm.prank(liquidator);
        vm.expectRevert(PerpMarket.PositionNotLiquidatable.selector);
        perpMarket.liquidatePosition(user1);
    }

    function test_RevertWhen_Insufficient_Margin() public {
        vm.startPrank(user1);
        
        uint256 initialMarginBps = perpMarket.initialMarginBps();
        uint256 tradingFeeBps = perpMarket.tradingFeeBps();
        uint256 requiredMargin = (POSITION_SIZE * initialMarginBps) / 10000;
        uint256 tradingFee = (POSITION_SIZE * tradingFeeBps) / 10000;
        uint256 totalRequired = requiredMargin + tradingFee;
        
        // Try to open position with insufficient cBTC
        vm.expectRevert(PerpMarket.InsufficientMargin.selector);
        perpMarket.openPosition{value: totalRequired - 1}(true, POSITION_SIZE);
        
        vm.stopPrank();
    }

    function test_Get_Margin_Ratio() public {
        // Open position
        vm.startPrank(user1);
        uint256 initialMarginBps = perpMarket.initialMarginBps();
        uint256 tradingFeeBps = perpMarket.tradingFeeBps();
        uint256 requiredMargin = (POSITION_SIZE * initialMarginBps) / 10000;
        uint256 tradingFee = (POSITION_SIZE * tradingFeeBps) / 10000;
        uint256 totalRequired = requiredMargin + tradingFee;
        
        perpMarket.openPosition{value: totalRequired}(true, POSITION_SIZE);
        vm.stopPrank();
        
        uint256 marginRatio = perpMarket.getMarginRatio(user1);
        assertEq(marginRatio, initialMarginBps);
    }

    function test_Get_Market_Stats() public {
        // Open multiple positions
        vm.startPrank(user1);
        uint256 initialMarginBps = perpMarket.initialMarginBps();
        uint256 tradingFeeBps = perpMarket.tradingFeeBps();
        uint256 requiredMargin = (POSITION_SIZE * initialMarginBps) / 10000;
        uint256 tradingFee = (POSITION_SIZE * tradingFeeBps) / 10000;
        uint256 totalRequired = requiredMargin + tradingFee;
        
        perpMarket.openPosition{value: totalRequired}(true, POSITION_SIZE);
        vm.stopPrank();
        
        vm.startPrank(user2);
        perpMarket.openPosition{value: totalRequired}(false, POSITION_SIZE * 2);
        vm.stopPrank();
        
        (uint256 totalLongs, uint256 totalShorts, uint256 volume, uint256 currentPrice) = perpMarket.getMarketStats();
        
        assertEq(totalLongs, POSITION_SIZE);
        assertEq(totalShorts, POSITION_SIZE * 2);
        assertEq(volume, POSITION_SIZE * 3); // Total volume from both positions
        assertEq(currentPrice, INITIAL_PRICE);
    }

    function testConfigUpdates() public {
        vm.startPrank(owner);
        
        // Test maintenance margin update
        uint256 newMaintenanceMargin = 1500; // 15%
        perpMarket.setMaintenanceMarginBps(newMaintenanceMargin);
        assertEq(perpMarket.maintenanceMarginBps(), newMaintenanceMargin);
        
        // Test initial margin update
        uint256 newInitialMargin = 2500; // 25%
        perpMarket.setInitialMarginBps(newInitialMargin);
        assertEq(perpMarket.initialMarginBps(), newInitialMargin);
        
        // Test trading fee update
        uint256 newTradingFee = 20; // 0.2%
        perpMarket.setTradingFeeBps(newTradingFee);
        assertEq(perpMarket.tradingFeeBps(), newTradingFee);
        
        vm.stopPrank();
    }

    function test_Emergency_Functions() public {
        // Open position first
        vm.startPrank(user1);
        uint256 initialMarginBps = perpMarket.initialMarginBps();
        uint256 tradingFeeBps = perpMarket.tradingFeeBps();
        uint256 requiredMargin = (POSITION_SIZE * initialMarginBps) / 10000;
        uint256 tradingFee = (POSITION_SIZE * tradingFeeBps) / 10000;
        uint256 totalRequired = requiredMargin + tradingFee;
        
        perpMarket.openPosition{value: totalRequired}(true, POSITION_SIZE);
        vm.stopPrank();
        
        vm.startPrank(owner);
        
        // Test emergency close
        perpMarket.emergencyClosePosition(user1);
        
        // Check position is cleared
        PerpMarket.Position memory pos = perpMarket.getPosition(user1);
        assertEq(pos.size, 0);
        
        vm.stopPrank();
    }

    function test_PnL_Calculations() public {
        // Open long position
        vm.startPrank(user1);
        uint256 initialMarginBps = perpMarket.initialMarginBps();
        uint256 tradingFeeBps = perpMarket.tradingFeeBps();
        uint256 requiredMargin = (POSITION_SIZE * initialMarginBps) / 10000;
        uint256 tradingFee = (POSITION_SIZE * tradingFeeBps) / 10000;
        uint256 totalRequired = requiredMargin + tradingFee;
        
        perpMarket.openPosition{value: totalRequired}(true, POSITION_SIZE);
        vm.stopPrank();
        
        // Test profit scenario
        uint256 higherPrice = 55000 * 10**18; // $55,000
        vm.prank(owner);
        perpMarket.updateMarkPrice(higherPrice);
        
        int256 pnl = perpMarket.getCurrentPnL(user1);
        // PnL should be positive for long position when price increases
        assertTrue(pnl > 0);
        
        // Test loss scenario
        uint256 lowerPrice = 45000 * 10**18; // $45,000
        vm.prank(owner);
        perpMarket.updateMarkPrice(lowerPrice);
        
        pnl = perpMarket.getCurrentPnL(user1);
        // PnL should be negative for long position when price decreases
        assertTrue(pnl < 0);
    }
} 