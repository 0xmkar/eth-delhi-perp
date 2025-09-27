// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/DDexRBTC.sol";

contract DDexRBTCTest is Test {
    DDexRBTC public ddex;
    address public owner;
    address public treasury;
    address public user1;
    address public user2;
    address public user3;
    
    // Events to test
    event Deposit(address indexed user, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount, uint256 fee);
    event BulkTransfer(address indexed from, address[] to, uint256[] amounts, uint256 totalFee);
    event Withdrawal(address indexed user, uint256 amount, uint256 fee);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event TreasuryWithdrawal(address indexed to, uint256 amount);
    event FeeUpdated(string feeType, uint256 oldFee, uint256 newFee);
    
    function setUp() public {
        owner = address(this);
        treasury = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        
        // Deploy contract
        ddex = new DDexRBTC(treasury);
        
        // Give users some ETH for testing
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);
    }
    
    // ========== DEPLOYMENT TESTS ==========
    
    function testDeployment() public view {
        assertEq(ddex.owner(), owner);
        assertEq(ddex.treasury(), treasury);
        assertEq(ddex.transferFee(), 10); // 0.1%
        assertEq(ddex.withdrawalFee(), 25); // 0.25%
        assertEq(ddex.totalDeposited(), 0);
        assertEq(ddex.getTreasuryBalance(), 0);
    }
    
    function testDeploymentWithZeroTreasury() public {
        vm.expectRevert("Invalid treasury address");
        new DDexRBTC(address(0));
    }
    
    // ========== DEPOSIT TESTS ==========
    
    function testDeposit() public {
        uint256 depositAmount = 1 ether;
        
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit Deposit(user1, depositAmount);
        ddex.deposit{value: depositAmount}();
        
        assertEq(ddex.balanceOf(user1), depositAmount);
        assertEq(ddex.totalDeposited(), depositAmount);
        assertEq(address(ddex).balance, depositAmount);
    }
    
    function testDepositZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("Must deposit more than 0 rBTC");
        ddex.deposit{value: 0}();
    }
    
    function testDepositViaReceive() public {
        uint256 depositAmount = 1 ether;
        
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit Deposit(user1, depositAmount);
        (bool success,) = address(ddex).call{value: depositAmount}("");
        require(success, "Transfer failed");
        
        assertEq(ddex.balanceOf(user1), depositAmount);
        assertEq(ddex.totalDeposited(), depositAmount);
    }
    
    function testMyBalance() public {
        uint256 depositAmount = 1 ether;
        
        vm.prank(user1);
        ddex.deposit{value: depositAmount}();
        
        vm.prank(user1);
        assertEq(ddex.myBalance(), depositAmount);
    }
    
    // ========== TRANSFER TESTS ==========
    
    function testTransfer() public {
        uint256 depositAmount = 1 ether;
        uint256 transferAmount = 0.5 ether;
        uint256 expectedFee = (transferAmount * 10) / 10000; // 0.1%
        
        // User1 deposits
        vm.prank(user1);
        ddex.deposit{value: depositAmount}();
        
        // User1 transfers to user2
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit Transfer(user1, user2, transferAmount, expectedFee);
        ddex.transfer(user2, transferAmount);
        
        assertEq(ddex.balanceOf(user1), depositAmount - transferAmount - expectedFee);
        assertEq(ddex.balanceOf(user2), transferAmount);
        assertEq(ddex.getTreasuryBalance(), expectedFee);
    }
    
    function testTransferToZeroAddress() public {
        vm.prank(user1);
        ddex.deposit{value: 1 ether}();
        
        vm.prank(user1);
        vm.expectRevert("Invalid address");
        ddex.transfer(address(0), 0.5 ether);
    }
    
    function testTransferToSelf() public {
        vm.prank(user1);
        ddex.deposit{value: 1 ether}();
        
        vm.prank(user1);
        vm.expectRevert("Cannot transfer to yourself");
        ddex.transfer(user1, 0.5 ether);
    }
    
    function testTransferZeroAmount() public {
        vm.prank(user1);
        ddex.deposit{value: 1 ether}();
        
        vm.prank(user1);
        vm.expectRevert("Amount must be greater than 0");
        ddex.transfer(user2, 0);
    }
    
    function testTransferInsufficientBalance() public {
        vm.prank(user1);
        ddex.deposit{value: 1 ether}();
        
        vm.prank(user1);
        vm.expectRevert("Insufficient balance including fee");
        ddex.transfer(user2, 1 ether); // Would need 1 ETH + fee
    }
    
    // ========== BULK TRANSFER TESTS ==========
    
    function testBulkTransfer() public {
        // Setup: Users deposit funds
        vm.prank(user1);
        ddex.deposit{value: 2 ether}();
        vm.prank(user2);
        ddex.deposit{value: 2 ether}();
        
        // Prepare bulk transfer data
        address[] memory senders = new address[](2);
        address[] memory recipients = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        
        senders[0] = user1;
        senders[1] = user2;
        recipients[0] = user2;
        recipients[1] = user3;
        amounts[0] = 0.5 ether;
        amounts[1] = 0.3 ether;
        
        uint256 expectedTotalFees = ((0.5 ether * 10) / 10000) + ((0.3 ether * 10) / 10000);
        
        // Execute bulk transfer
        vm.expectEmit(true, false, false, true);
        emit BulkTransfer(address(ddex), recipients, amounts, expectedTotalFees);
        ddex.bulkTransfer(senders, recipients, amounts);
        
        // Check balances
        assertEq(ddex.balanceOf(user1), 2 ether - 0.5 ether - ((0.5 ether * 10) / 10000));
        assertEq(ddex.balanceOf(user2), 2 ether + 0.5 ether - 0.3 ether - ((0.3 ether * 10) / 10000));
        assertEq(ddex.balanceOf(user3), 0.3 ether);
        assertEq(ddex.getTreasuryBalance(), expectedTotalFees);
    }
    
    function testBulkTransferOnlyOwner() public {
        address[] memory senders = new address[](1);
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        
        vm.prank(user1);
        vm.expectRevert("Only owner can call this function");
        ddex.bulkTransfer(senders, recipients, amounts);
    }
    
    function testBulkTransferArrayLengthMismatch() public {
        address[] memory senders = new address[](2);
        address[] memory recipients = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        
        vm.expectRevert("Senders and recipients arrays length mismatch");
        ddex.bulkTransfer(senders, recipients, amounts);
    }
    
    // ========== WITHDRAWAL TESTS ==========
    
    function testWithdraw() public {
        uint256 depositAmount = 1 ether;
        uint256 withdrawAmount = 0.5 ether;
        uint256 expectedFee = (withdrawAmount * 25) / 10000; // 0.25%
        
        // Deposit
        vm.prank(user1);
        ddex.deposit{value: depositAmount}();
        
        uint256 initialBalance = user1.balance;
        
        // Withdraw
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit Withdrawal(user1, withdrawAmount, expectedFee);
        ddex.withdraw(withdrawAmount);
        
        assertEq(ddex.balanceOf(user1), depositAmount - withdrawAmount - expectedFee);
        assertEq(user1.balance, initialBalance + withdrawAmount);
        assertEq(ddex.getTreasuryBalance(), expectedFee);
        assertEq(ddex.totalDeposited(), depositAmount - withdrawAmount);
    }
    
    function testWithdrawAll() public {
        uint256 depositAmount = 1 ether;
        
        // Deposit
        vm.prank(user1);
        ddex.deposit{value: depositAmount}();
        
        uint256 initialBalance = user1.balance;
        uint256 expectedFee = (depositAmount * 25) / (10000 + 25); // Fee calculation for withdrawAll
        uint256 expectedWithdrawAmount = depositAmount - expectedFee;
        
        // Withdraw all
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit Withdrawal(user1, expectedWithdrawAmount, expectedFee);
        ddex.withdrawAll();
        
        assertEq(ddex.balanceOf(user1), 0);
        assertEq(user1.balance, initialBalance + expectedWithdrawAmount);
        assertEq(ddex.getTreasuryBalance(), expectedFee);
    }
    
    function testWithdrawZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("Amount must be greater than 0");
        ddex.withdraw(0);
    }
    
    function testWithdrawInsufficientBalance() public {
        vm.prank(user1);
        vm.expectRevert("Insufficient balance including fee");
        ddex.withdraw(1 ether);
    }
    
    // ========== OWNER FUNCTIONS TESTS ==========
    
    function testSetBalance() public {
        uint256 newBalance = 5 ether;
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), user1, newBalance, 0);
        ddex.setBalance(user1, newBalance);
        
        assertEq(ddex.balanceOf(user1), newBalance);
        assertEq(ddex.totalDeposited(), newBalance);
    }
    
    function testSetBalanceOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("Only owner can call this function");
        ddex.setBalance(user2, 1 ether);
    }
    
    function testSetBalanceZeroAddress() public {
        vm.expectRevert("Invalid address");
        ddex.setBalance(address(0), 1 ether);
    }
    
    // ========== TREASURY TESTS ==========
    
    function testWithdrawTreasury() public {
        // Generate some treasury balance through transfers
        vm.prank(user1);
        ddex.deposit{value: 1 ether}();
        
        vm.prank(user1);
        ddex.transfer(user2, 0.5 ether);
        
        uint256 treasuryBalance = ddex.getTreasuryBalance();
        assertTrue(treasuryBalance > 0);
        
        uint256 initialTreasuryBalance = treasury.balance;
        
        vm.expectEmit(true, false, false, true);
        emit TreasuryWithdrawal(treasury, treasuryBalance);
        ddex.withdrawTreasury(treasuryBalance);
        
        assertEq(ddex.getTreasuryBalance(), 0);
        assertEq(treasury.balance, initialTreasuryBalance + treasuryBalance);
    }
    
    function testWithdrawAllTreasury() public {
        // Generate some treasury balance
        vm.prank(user1);
        ddex.deposit{value: 1 ether}();
        
        vm.prank(user1);
        ddex.transfer(user2, 0.5 ether);
        
        uint256 treasuryBalance = ddex.getTreasuryBalance();
        uint256 initialTreasuryBalance = treasury.balance;
        
        vm.expectEmit(true, false, false, true);
        emit TreasuryWithdrawal(treasury, treasuryBalance);
        ddex.withdrawAllTreasury();
        
        assertEq(ddex.getTreasuryBalance(), 0);
        assertEq(treasury.balance, initialTreasuryBalance + treasuryBalance);
    }
    
    function testUpdateTreasury() public {
        address newTreasury = makeAddr("newTreasury");
        
        vm.expectEmit(true, true, false, false);
        emit TreasuryUpdated(treasury, newTreasury);
        ddex.updateTreasury(newTreasury);
        
        assertEq(ddex.treasury(), newTreasury);
    }
    
    function testUpdateTreasuryOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("Only owner can call this function");
        ddex.updateTreasury(makeAddr("newTreasury"));
    }
    
    // ========== FEE MANAGEMENT TESTS ==========
    
    function testSetTransferFee() public {
        uint256 newFee = 50; // 0.5%
        
        vm.expectEmit(false, false, false, true);
        emit FeeUpdated("transfer", 10, newFee);
        ddex.setTransferFee(newFee);
        
        assertEq(ddex.transferFee(), newFee);
    }
    
    function testSetWithdrawalFee() public {
        uint256 newFee = 100; // 1%
        
        vm.expectEmit(false, false, false, true);
        emit FeeUpdated("withdrawal", 25, newFee);
        ddex.setWithdrawalFee(newFee);
        
        assertEq(ddex.withdrawalFee(), newFee);
    }
    
    function testSetFeeExceedsMaximum() public {
        vm.expectRevert("Fee too high");
        ddex.setTransferFee(1001); // > 10%
        
        vm.expectRevert("Fee too high");
        ddex.setWithdrawalFee(1001); // > 10%
    }
    
    function testCalculateFees() public view {
        uint256 amount = 1 ether;
        
        assertEq(ddex.calculateTransferFee(amount), (amount * 10) / 10000);
        assertEq(ddex.calculateWithdrawalFee(amount), (amount * 25) / 10000);
    }
    
    // ========== OWNERSHIP TESTS ==========
    
    function testTransferOwnership() public {
        address newOwner = makeAddr("newOwner");
        
        ddex.transferOwnership(newOwner);
        assertEq(ddex.owner(), newOwner);
    }
    
    function testTransferOwnershipOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("Only owner can call this function");
        ddex.transferOwnership(user1);
    }
    
    function testTransferOwnershipToSameOwner() public {
        vm.expectRevert("Already the owner");
        ddex.transferOwnership(owner);
    }
    
    // ========== VIEW FUNCTIONS TESTS ==========
    
    function testContractBalance() public {
        vm.prank(user1);
        ddex.deposit{value: 1 ether}();
        
        assertEq(ddex.contractBalance(), 1 ether);
        assertEq(ddex.contractBalance(), address(ddex).balance);
    }
    
    // ========== EDGE CASES AND SECURITY TESTS ==========
    
    function testLargeAmounts() public {
        uint256 largeAmount = 1000 ether;
        vm.deal(user1, largeAmount);
        
        vm.prank(user1);
        ddex.deposit{value: largeAmount}();
        
        assertEq(ddex.balanceOf(user1), largeAmount);
    }
    
    function testMultipleUsersInteractions() public {
        // Multiple users deposit
        vm.prank(user1);
        ddex.deposit{value: 2 ether}();
        
        vm.prank(user2);
        ddex.deposit{value: 3 ether}();
        
        vm.prank(user3);
        ddex.deposit{value: 1 ether}();
        
        // Users transfer between each other
        vm.prank(user1);
        ddex.transfer(user2, 0.5 ether);
        
        vm.prank(user2);
        ddex.transfer(user3, 1 ether);
        
        // Check final balances
        assertTrue(ddex.balanceOf(user1) < 2 ether); // Reduced by transfer + fee
        assertTrue(ddex.balanceOf(user2) < 3 ether); // Reduced by net outgoing transfer + fees
        assertTrue(ddex.balanceOf(user3) > 1 ether); // Increased by received transfer
        assertTrue(ddex.getTreasuryBalance() > 0); // Accumulated fees
    }
    
    function testFuzzDeposit(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1000 ether);
        vm.deal(user1, amount);
        
        vm.prank(user1);
        ddex.deposit{value: amount}();
        
        assertEq(ddex.balanceOf(user1), amount);
        assertEq(ddex.totalDeposited(), amount);
    }
    
    function testFuzzTransfer(uint256 depositAmount, uint256 transferAmount) public {
        vm.assume(depositAmount > 0 && depositAmount <= 1000 ether);
        vm.assume(transferAmount > 0 && transferAmount < depositAmount);
        
        uint256 fee = (transferAmount * 10) / 10000;
        vm.assume(depositAmount >= transferAmount + fee);
        
        vm.deal(user1, depositAmount);
        
        vm.prank(user1);
        ddex.deposit{value: depositAmount}();
        
        vm.prank(user1);
        ddex.transfer(user2, transferAmount);
        
        assertEq(ddex.balanceOf(user2), transferAmount);
        assertEq(ddex.balanceOf(user1), depositAmount - transferAmount - fee);
    }
}
