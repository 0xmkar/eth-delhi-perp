// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Treasury.sol";

contract TreasuryTest is Test {
    Treasury public treasury;
    
    address public owner = address(0x1);
    address public feeRecipient = address(0x2);
    address public perpMarket = address(0x3);
    address public user = address(0x4);
    
    uint256 public constant FEE_AMOUNT = 100 * 10**18;

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy treasury
        treasury = new Treasury(feeRecipient, owner);
        
        // Authorize perpMarket contract
        treasury.setAuthorizedContract(perpMarket, true);
        
        vm.stopPrank();
        
        // Give contracts and users native cBTC
        vm.deal(perpMarket, FEE_AMOUNT * 10);
        vm.deal(user, FEE_AMOUNT * 10);
    }

    function testReceiveFee() public {
        vm.startPrank(perpMarket);
        
        uint256 balanceBefore = treasury.getBalance();
        uint256 feesBefore = treasury.getTotalFeesCollected();
        
        // Send fee directly
        treasury.receiveFee{value: FEE_AMOUNT}();
        
        uint256 balanceAfter = treasury.getBalance();
        uint256 feesAfter = treasury.getTotalFeesCollected();
        
        assertEq(balanceAfter, balanceBefore + FEE_AMOUNT);
        assertEq(feesAfter, feesBefore + FEE_AMOUNT);
        
        vm.stopPrank();
    }

    function testCollectFee() public {
        vm.startPrank(perpMarket);
        
        uint256 balanceBefore = treasury.getBalance();
        uint256 feesBefore = treasury.getTotalFeesCollected();
        
        // Collect fee from user
        treasury.collectFee{value: FEE_AMOUNT}(FEE_AMOUNT, user);
        
        uint256 balanceAfter = treasury.getBalance();
        uint256 feesAfter = treasury.getTotalFeesCollected();
        
        assertEq(balanceAfter, balanceBefore + FEE_AMOUNT);
        assertEq(feesAfter, feesBefore + FEE_AMOUNT);
        
        vm.stopPrank();
    }

    function testWithdrawFees() public {
        // Setup: send some fees first
        vm.prank(perpMarket);
        treasury.receiveFee{value: FEE_AMOUNT}();
        
        vm.startPrank(owner);
        
        uint256 recipientBalanceBefore = feeRecipient.balance;
        uint256 withdrawAmount = FEE_AMOUNT / 2;
        
        // Withdraw fees
        treasury.withdrawFees(withdrawAmount);
        
        uint256 recipientBalanceAfter = feeRecipient.balance;
        assertEq(recipientBalanceAfter, recipientBalanceBefore + withdrawAmount);
        assertEq(treasury.getBalance(), FEE_AMOUNT - withdrawAmount);
        
        vm.stopPrank();
    }

    function testWithdrawAllFees() public {
        // Setup: send some fees first
        vm.prank(perpMarket);
        treasury.receiveFee{value: FEE_AMOUNT}();
        
        vm.startPrank(owner);
        
        uint256 recipientBalanceBefore = feeRecipient.balance;
        
        // Withdraw all fees (amount = 0)
        treasury.withdrawFees(0);
        
        uint256 recipientBalanceAfter = feeRecipient.balance;
        assertEq(recipientBalanceAfter, recipientBalanceBefore + FEE_AMOUNT);
        assertEq(treasury.getBalance(), 0);
        
        vm.stopPrank();
    }

    function testEmergencyWithdraw() public {
        // Setup: send some fees first
        vm.prank(perpMarket);
        treasury.receiveFee{value: FEE_AMOUNT}();
        
        vm.startPrank(owner);
        
        uint256 ownerBalanceBefore = owner.balance;
        uint256 emergencyAmount = FEE_AMOUNT / 2;
        
        // Emergency withdraw
        treasury.emergencyWithdraw(emergencyAmount);
        
        uint256 ownerBalanceAfter = owner.balance;
        assertEq(ownerBalanceAfter, ownerBalanceBefore + emergencyAmount);
        assertEq(treasury.getBalance(), FEE_AMOUNT - emergencyAmount);
        
        vm.stopPrank();
    }

    function testSetFeeRecipient() public {
        address newRecipient = address(0x5);
        
        vm.startPrank(owner);
        
        treasury.setFeeRecipient(newRecipient);
        
        assertEq(treasury.feeRecipient(), newRecipient);
        
        vm.stopPrank();
    }

    function testSetAuthorizedContract() public {
        address newContract = address(0x6);
        
        vm.startPrank(owner);
        
        assertFalse(treasury.authorizedContracts(newContract));
        
        treasury.setAuthorizedContract(newContract, true);
        
        assertTrue(treasury.authorizedContracts(newContract));
        
        vm.stopPrank();
    }

    function testReceiveFunction() public {
        vm.startPrank(perpMarket);
        
        uint256 balanceBefore = treasury.getBalance();
        uint256 feesBefore = treasury.getTotalFeesCollected();
        
        // Send cBTC directly to treasury via receive function
        (bool success,) = payable(address(treasury)).call{value: FEE_AMOUNT}("");
        assertTrue(success);
        
        uint256 balanceAfter = treasury.getBalance();
        uint256 feesAfter = treasury.getTotalFeesCollected();
        
        assertEq(balanceAfter, balanceBefore + FEE_AMOUNT);
        assertEq(feesAfter, feesBefore + FEE_AMOUNT);
        
        vm.stopPrank();
    }

    function test_RevertWhen_UnauthorizedReceiveFee() public {
        vm.startPrank(user);
        
        // Should fail - user is not authorized
        vm.expectRevert(Treasury.Unauthorized.selector);
        treasury.receiveFee{value: FEE_AMOUNT}();
        
        vm.stopPrank();
    }

    function test_RevertWhen_UnauthorizedCollectFee() public {
        vm.startPrank(user);
        
        // Should fail - user is not authorized
        vm.expectRevert(Treasury.Unauthorized.selector);
        treasury.collectFee{value: FEE_AMOUNT}(FEE_AMOUNT, user);
        
        vm.stopPrank();
    }

    function test_RevertWhen_UnauthorizedReceiveFunction() public {
        vm.startPrank(user);
        
        // Should fail - user is not authorized to send directly
        vm.expectRevert(Treasury.Unauthorized.selector);
        (bool success,) = payable(address(treasury)).call{value: FEE_AMOUNT}("");
        
        vm.stopPrank();
    }

    function test_RevertWhen_AmountMismatch() public {
        vm.startPrank(perpMarket);
        
        // Should fail - sent amount doesn't match parameter
        vm.expectRevert("cBTC amount mismatch");
        treasury.collectFee{value: FEE_AMOUNT}(FEE_AMOUNT * 2, user);
        
        vm.stopPrank();
    }

    function test_RevertWhen_InsufficientBalance() public {
        vm.startPrank(owner);
        
        // Try to withdraw more than available
        vm.expectRevert(Treasury.InsufficientBalance.selector);
        treasury.withdrawFees(FEE_AMOUNT);
        
        vm.stopPrank();
    }

    function test_RevertWhen_ZeroAmount() public {
        vm.startPrank(perpMarket);
        
        // Should fail - zero amount
        vm.expectRevert(Treasury.ZeroAmount.selector);
        treasury.receiveFee{value: 0}();
        
        vm.stopPrank();
    }

    function test_RevertWhen_ZeroAddress() public {
        vm.startPrank(owner);
        
        // Should fail - zero address
        vm.expectRevert(Treasury.ZeroAddress.selector);
        treasury.setFeeRecipient(address(0));
        
        vm.stopPrank();
    }

    function testMultipleFeeCollections() public {
        vm.startPrank(perpMarket);
        
        // Collect multiple fees
        treasury.receiveFee{value: FEE_AMOUNT}();
        treasury.receiveFee{value: FEE_AMOUNT * 2}();
        treasury.collectFee{value: FEE_AMOUNT / 2}(FEE_AMOUNT / 2, user);
        
        uint256 totalExpected = FEE_AMOUNT + (FEE_AMOUNT * 2) + (FEE_AMOUNT / 2);
        
        assertEq(treasury.getBalance(), totalExpected);
        assertEq(treasury.getTotalFeesCollected(), totalExpected);
        
        vm.stopPrank();
    }
} 