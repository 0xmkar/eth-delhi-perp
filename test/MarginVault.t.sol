// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MarginVault.sol";

contract MarginVaultTest is Test {
    MarginVault public vault;
    
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public perpMarket = address(0x4);
    
    uint256 public constant DEPOSIT_AMOUNT = 1000 * 10**18;
    uint256 public constant MARGIN_AMOUNT = 500 * 10**18;

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy vault (no longer needs cBTC token address)
        vault = new MarginVault(owner);
        
        // Authorize perpMarket contract
        vault.setAuthorizedContract(perpMarket, true);
        
        vm.stopPrank();
        
        // Give users native cBTC
        vm.deal(user1, DEPOSIT_AMOUNT * 2);
        vm.deal(user2, DEPOSIT_AMOUNT * 2);
        vm.deal(perpMarket, DEPOSIT_AMOUNT * 10);
    }

    function testDeposit() public {
        vm.startPrank(user1);
        
        uint256 balanceBefore = vault.getBalance(user1);
        
        // Deposit native cBTC
        vault.deposit{value: DEPOSIT_AMOUNT}();
        
        uint256 balanceAfter = vault.getBalance(user1);
        assertEq(balanceAfter, balanceBefore + DEPOSIT_AMOUNT);
        assertEq(vault.getAvailableMargin(user1), DEPOSIT_AMOUNT);
        
        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(user1);
        
        // First deposit
        vault.deposit{value: DEPOSIT_AMOUNT}();
        
        uint256 userEthBefore = user1.balance;
        uint256 withdrawAmount = DEPOSIT_AMOUNT / 2;
        
        // Withdraw
        vault.withdraw(withdrawAmount);
        
        uint256 userEthAfter = user1.balance;
        assertEq(userEthAfter, userEthBefore + withdrawAmount);
        assertEq(vault.getBalance(user1), DEPOSIT_AMOUNT - withdrawAmount);
        
        vm.stopPrank();
    }

    function testDepositMargin() public {
        vm.startPrank(perpMarket);
        
        uint256 balanceBefore = vault.getBalance(user1);
        uint256 lockedBefore = vault.getLockedMargin(user1);
        
        // Deposit margin for user1
        vault.depositMargin{value: MARGIN_AMOUNT}(user1);
        
        uint256 balanceAfter = vault.getBalance(user1);
        uint256 lockedAfter = vault.getLockedMargin(user1);
        
        assertEq(balanceAfter, balanceBefore + MARGIN_AMOUNT);
        assertEq(lockedAfter, lockedBefore + MARGIN_AMOUNT);
        
        vm.stopPrank();
    }

    function testLockMargin() public {
        // First user deposits
        vm.prank(user1);
        vault.deposit{value: DEPOSIT_AMOUNT}();
        
        vm.startPrank(perpMarket);
        
        uint256 lockedBefore = vault.getLockedMargin(user1);
        uint256 availableBefore = vault.getAvailableMargin(user1);
        
        // Lock margin
        vault.lockMargin(user1, MARGIN_AMOUNT);
        
        uint256 lockedAfter = vault.getLockedMargin(user1);
        uint256 availableAfter = vault.getAvailableMargin(user1);
        
        assertEq(lockedAfter, lockedBefore + MARGIN_AMOUNT);
        assertEq(availableAfter, availableBefore - MARGIN_AMOUNT);
        
        vm.stopPrank();
    }

    function testUnlockMargin() public {
        // Setup: deposit and lock margin
        vm.prank(user1);
        vault.deposit{value: DEPOSIT_AMOUNT}();
        
        vm.prank(perpMarket);
        vault.lockMargin(user1, MARGIN_AMOUNT);
        
        vm.startPrank(perpMarket);
        
        uint256 lockedBefore = vault.getLockedMargin(user1);
        uint256 availableBefore = vault.getAvailableMargin(user1);
        
        // Unlock margin
        vault.unlockMargin(user1, MARGIN_AMOUNT);
        
        uint256 lockedAfter = vault.getLockedMargin(user1);
        uint256 availableAfter = vault.getAvailableMargin(user1);
        
        assertEq(lockedAfter, lockedBefore - MARGIN_AMOUNT);
        assertEq(availableAfter, availableBefore + MARGIN_AMOUNT);
        
        vm.stopPrank();
    }

    function testAddBalance() public {
        vm.startPrank(perpMarket);
        
        uint256 balanceBefore = vault.getBalance(user1);
        uint256 addAmount = 100 * 10**18;
        
        // Add balance (for PnL settlement)
        vault.addBalance(user1, addAmount);
        
        uint256 balanceAfter = vault.getBalance(user1);
        assertEq(balanceAfter, balanceBefore + addAmount);
        
        vm.stopPrank();
    }

    function testDeductBalance() public {
        // Setup: deposit first
        vm.prank(user1);
        vault.deposit{value: DEPOSIT_AMOUNT}();
        
        vm.startPrank(perpMarket);
        
        uint256 balanceBefore = vault.getBalance(user1);
        uint256 deductAmount = 100 * 10**18;
        
        // Deduct balance (for losses)
        vault.deductBalance(user1, deductAmount);
        
        uint256 balanceAfter = vault.getBalance(user1);
        assertEq(balanceAfter, balanceBefore - deductAmount);
        
        vm.stopPrank();
    }

    function testTransferBalance() public {
        // Setup: both users deposit
        vm.prank(user1);
        vault.deposit{value: DEPOSIT_AMOUNT}();
        
        vm.prank(user2);
        vault.deposit{value: DEPOSIT_AMOUNT}();
        
        vm.startPrank(perpMarket);
        
        uint256 user1BalanceBefore = vault.getBalance(user1);
        uint256 user2BalanceBefore = vault.getBalance(user2);
        uint256 transferAmount = 200 * 10**18;
        
        // Transfer balance (for liquidation rewards)
        vault.transferBalance(user1, user2, transferAmount);
        
        uint256 user1BalanceAfter = vault.getBalance(user1);
        uint256 user2BalanceAfter = vault.getBalance(user2);
        
        assertEq(user1BalanceAfter, user1BalanceBefore - transferAmount);
        assertEq(user2BalanceAfter, user2BalanceBefore + transferAmount);
        
        vm.stopPrank();
    }

    function testWithdrawTo() public {
        // Setup: deposit to vault
        vm.prank(user1);
        vault.deposit{value: DEPOSIT_AMOUNT}();
        
        vm.startPrank(perpMarket);
        
        uint256 recipientBalanceBefore = user2.balance;
        uint256 withdrawAmount = 100 * 10**18;
        
        // Withdraw to recipient
        vault.withdrawTo(user2, withdrawAmount);
        
        uint256 recipientBalanceAfter = user2.balance;
        assertEq(recipientBalanceAfter, recipientBalanceBefore + withdrawAmount);
        
        vm.stopPrank();
    }

    function test_RevertWhen_UnauthorizedAccess() public {
        vm.startPrank(user1);

        vm.expectRevert(); // or vm.expectRevert("Unauthorized"); if your contract uses a reason string
        vault.lockMargin(user1, MARGIN_AMOUNT);

        vm.stopPrank();
    }

    function test_RevertWhen_InsufficientBalance() public {
        vm.startPrank(user1);

        vm.expectRevert(); // or vm.expectRevert("Insufficient balance");
        vault.withdraw(DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    function testAuthorizeContract() public {
        address newContract = address(0x5);
        
        vm.startPrank(owner);
        
        assertFalse(vault.authorizedContracts(newContract));
        
        vault.setAuthorizedContract(newContract, true);
        
        assertTrue(vault.authorizedContracts(newContract));
        
        vm.stopPrank();
    }

    function testEmergencyWithdraw() public {
        // Setup: deposit to vault
        vm.prank(user1);
        vault.deposit{value: DEPOSIT_AMOUNT}();
        
        vm.startPrank(owner);
        
        uint256 ownerBalanceBefore = owner.balance;
        uint256 emergencyAmount = DEPOSIT_AMOUNT / 2;
        
        // Emergency withdraw
        vault.emergencyWithdraw(emergencyAmount);
        
        uint256 ownerBalanceAfter = owner.balance;
        assertEq(ownerBalanceAfter, ownerBalanceBefore + emergencyAmount);
        
        vm.stopPrank();
    }

    function testReceiveFunction() public {
        uint256 vaultBalanceBefore = vault.getTotalBalance();
        uint256 sendAmount = 1 ether;
        
        // Send cBTC directly to vault
        (bool success,) = payable(address(vault)).call{value: sendAmount}("");
        assertTrue(success);
        
        uint256 vaultBalanceAfter = vault.getTotalBalance();
        assertEq(vaultBalanceAfter, vaultBalanceBefore + sendAmount);
    }
} 