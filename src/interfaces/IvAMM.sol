// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IvAMM
 * @dev Interface for Virtual Automated Market Maker
 */
interface IvAMM {
    
    struct vAMMState {
        uint256 baseAssetReserve;  // virtual base asset (cBTC)
        uint256 quoteAssetReserve; // virtual quote asset (USDC)
        uint256 k;                 // constant product k = x * y
        uint256 totalLongSize;     // total long positions
        uint256 totalShortSize;   // total short positions
        uint256 fundingRate;       // current funding rate (18 decimals, can be negative)
        uint256 lastFundingUpdate; // timestamp of last funding update
    }
    
    struct SwapOutput {
        uint256 outputAmount;
        uint256 markPrice;
        int256 fundingPayment;
    }
    
    // Events
    event vAMMStateUpdated(
        uint256 baseReserve,
        uint256 quoteReserve,
        uint256 markPrice,
        uint256 timestamp
    );
    
    event FundingRateUpdated(
        int256 fundingRate,
        uint256 timestamp
    );
    
    event FundingPayment(
        address indexed user,
        int256 payment,
        uint256 timestamp
    );
    
    // View functions
    function getMarkPrice() external view returns (uint256);
    function getOraclePrice() external view returns (uint256);
    function getFundingRate() external view returns (int256);
    function getSpotPrice() external view returns (uint256);
    function getState() external view returns (vAMMState memory);
    
    // Trading functions
    function swapInput(
        bool isLong,
        uint256 inputAmount
    ) external returns (SwapOutput memory);
    
    function swapOutput(
        bool isLong,
        uint256 outputAmount
    ) external returns (SwapOutput memory);
    
    // Funding functions
    function updateFundingRate() external;
    function calculateFundingPayment(
        address user,
        uint256 positionSize,
        bool isLong,
        uint256 lastFundingIndex
    ) external view returns (int256);
    
    // Admin functions
    function adjustK(uint256 newK) external;
    function updateOraclePrice() external;
} 