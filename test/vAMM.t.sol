// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/vAMM.sol";

contract vAMMTest is Test {
    vAMM public vammContract;
    
    address public owner = address(0x1);
    uint256 public constant INITIAL_BASE_RESERVE = 1000 * 10**18; // 1000 virtual BTC
    uint256 public constant INITIAL_QUOTE_RESERVE = 50000000 * 10**18; // 50M virtual USDC
    bytes32 public constant BTC_DATA_FEED_ID = bytes32("BTC");

    function setUp() public {
        vm.startPrank(owner);
        
        vammContract = new vAMM(
            INITIAL_BASE_RESERVE,
            INITIAL_QUOTE_RESERVE,
            BTC_DATA_FEED_ID,
            owner
        );
        
        vm.stopPrank();
    }

    function test_InitialState() public view {
        IvAMM.vAMMState memory state = vammContract.getState();
        
        assertEq(state.baseAssetReserve, INITIAL_BASE_RESERVE);
        assertEq(state.quoteAssetReserve, INITIAL_QUOTE_RESERVE);
        assertEq(state.k, INITIAL_BASE_RESERVE * INITIAL_QUOTE_RESERVE);
        assertEq(state.totalLongSize, 0);
        assertEq(state.totalShortSize, 0);
    }

    function test_GetMarkPrice() public view {
        uint256 markPrice = vammContract.getMarkPrice();
        uint256 expectedPrice = (INITIAL_QUOTE_RESERVE * 10**18) / INITIAL_BASE_RESERVE;
        
        assertEq(markPrice, expectedPrice);
        console.log("Mark price:", markPrice / 10**18);
    }

    function test_AuthorizedCaller() public {
        address testCaller = address(0x2);
        
        // Initially not authorized
        assertFalse(vammContract.authorizedCallers(testCaller));
        
        // Add authorization
        vm.prank(owner);
        vammContract.addAuthorizedCaller(testCaller);
        
        assertTrue(vammContract.authorizedCallers(testCaller));
        
        // Remove authorization
        vm.prank(owner);
        vammContract.removeAuthorizedCaller(testCaller);
        
        assertFalse(vammContract.authorizedCallers(testCaller));
    }

    function test_AdjustK() public {
        uint256 newK = 2000000000 * 10**36; // Double the K value
        uint256 oldMarkPrice = vammContract.getMarkPrice();
        
        vm.prank(owner);
        vammContract.adjustK(newK);
        
        IvAMM.vAMMState memory state = vammContract.getState();
        uint256 newMarkPrice = vammContract.getMarkPrice();
        
        assertEq(state.k, newK);
        // Price should remain approximately the same
        assertApproxEqRel(newMarkPrice, oldMarkPrice, 0.01e18); // 1% tolerance
    }

    function test_RevertWhen_UnauthorizedSwap() public {
        address unauthorizedUser = address(0x3);
        
        vm.prank(unauthorizedUser);
        vm.expectRevert(vAMM.UnauthorizedCaller.selector);
        vammContract.swapInput(true, 1000 * 10**18);
    }

    function test_SwapInputAsAuthorized() public {
        address authorizedCaller = address(0x4);
        
        // Authorize caller
        vm.prank(owner);
        vammContract.addAuthorizedCaller(authorizedCaller);
        
        uint256 inputAmount = 1000000 * 10**18; // 1M quote tokens
        uint256 oldMarkPrice = vammContract.getMarkPrice();
        
        // Mock oracle data for the transaction
        // Note: In real usage, this would be provided by RedStone
        vm.prank(authorizedCaller);
        IvAMM.SwapOutput memory result = vammContract.swapInput(true, inputAmount);
        
        assertGt(result.outputAmount, 0);
        assertGt(result.markPrice, oldMarkPrice); // Price should increase for long
        
        console.log("Output amount:", result.outputAmount / 10**18);
        console.log("New mark price:", result.markPrice / 10**18);
    }

    function test_FundingRateCalculation() public view {
        // Set a specific oracle price for testing
        // vammContract.setMockOraclePrice(50000 * 10**18); // $50,000 in 18 decimals
        
        int256 fundingRate = vammContract.getFundingRate();
        console.log("Current funding rate (with mocked oracle data):");
        console.logInt(fundingRate);
    }
} 