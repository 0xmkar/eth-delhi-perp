// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@redstone-finance/evm-connector/contracts/data-services/MainDemoConsumerBase.sol";
import "./interfaces/IvAMM.sol";

/**
 * @title vAMM
 * @dev Virtual Automated Market Maker for perpetual futures
 * Uses RedStone oracle for price feeds and implements funding rate mechanism
 */
contract vAMM is IvAMM, MainDemoConsumerBase, Ownable, ReentrancyGuard {
    // Constants
    uint256 private constant PRECISION = 1e18;
    uint256 private constant FUNDING_PERIOD = 8 hours;
    uint256 private constant MAX_FUNDING_RATE = 1e16; // 1% per funding period
    uint256 private constant PRICE_IMPACT_TOLERANCE = 5e16; // 5% max price impact

    // State variables
    vAMMState public state;
    bytes32 public oracleDataFeedId; // e.g., bytes32("BTC")

    // Funding tracking
    mapping(address => uint256) public lastFundingIndex;
    uint256 public cumulativeFundingIndex;

    // Price impact dampening
    uint256 public dampingFactor = 9e17; // 0.9, reduces price impact

    // Authorized callers (PerpMarket contract)
    mapping(address => bool) public authorizedCallers;

    // Errors
    error UnauthorizedCaller();
    error InvalidReserves();
    error InvalidK();
    error ExcessivePriceImpact();
    error InvalidAmount();
    error FundingUpdateTooSoon();
    error InvalidOraclePrice();

    modifier onlyAuthorized() {
        if (!authorizedCallers[msg.sender] && msg.sender != owner()) {
            revert UnauthorizedCaller();
        }
        _;
    }

    constructor(
        uint256 _initialBaseReserve,
        uint256 _initialQuoteReserve,
        bytes32 _oracleDataFeedId,
        address _owner
    ) Ownable(_owner) {
        if (_initialBaseReserve == 0 || _initialQuoteReserve == 0) {
            revert InvalidReserves();
        }

        state.baseAssetReserve = _initialBaseReserve;
        state.quoteAssetReserve = _initialQuoteReserve;
        state.k = _initialBaseReserve * _initialQuoteReserve;
        state.lastFundingUpdate = block.timestamp;

        oracleDataFeedId = _oracleDataFeedId;
        cumulativeFundingIndex = PRECISION; // Start at 1.0
    }

    /**
     * @dev Get current mark price from vAMM
     */
    function getMarkPrice() public view override returns (uint256) {
        return (state.quoteAssetReserve * PRECISION) / state.baseAssetReserve;
    }

    /**
     * @dev Get oracle price from RedStone
     */
    function getOraclePrice() public view override returns (uint256) {
        uint256 price = getOracleNumericValueFromTxMsg(oracleDataFeedId);
        if (price == 0) revert InvalidOraclePrice();
        return price * 1e10; // Convert from 8 decimals to 18 decimals
    }

    /**
     * @dev Get current funding rate
     */
    function getFundingRate() public view override returns (int256) {
        uint256 markPrice = getMarkPrice();
        uint256 oraclePrice = getOraclePrice();

        // Funding rate = (mark_price - oracle_price) / oracle_price * dampingFactor
        int256 priceDiff = int256(markPrice) - int256(oraclePrice);
        int256 fundingRate = (priceDiff * int256(dampingFactor)) /
            int256(oraclePrice);

        // Cap funding rate
        if (fundingRate > int256(MAX_FUNDING_RATE)) {
            fundingRate = int256(MAX_FUNDING_RATE);
        } else if (fundingRate < -int256(MAX_FUNDING_RATE)) {
            fundingRate = -int256(MAX_FUNDING_RATE);
        }

        return fundingRate;
    }

    /**
     * @dev Get spot price (same as mark price for simplicity)
     */
    function getSpotPrice() public view override returns (uint256) {
        return getMarkPrice();
    }

    /**
     * @dev Get vAMM state
     */
    function getState() external view override returns (vAMMState memory) {
        return state;
    }

    /**
     * @dev Swap with input amount (used for opening positions)
     * @param isLong true for long position, false for short
     * @param inputAmount amount of quote asset to swap
     */
    function swapInput(
        bool isLong,
        uint256 inputAmount
    )
        external
        override
        onlyAuthorized
        nonReentrant
        returns (SwapOutput memory)
    {
        if (inputAmount == 0) revert InvalidAmount();

        uint256 outputAmount;

        if (isLong) {
            // Long: buy base asset with quote asset
            // new_quote_reserve = old_quote_reserve + input
            // new_base_reserve = k / new_quote_reserve
            // output = old_base_reserve - new_base_reserve

            uint256 newQuoteReserve = state.quoteAssetReserve + inputAmount;
            uint256 newBaseReserve = state.k / newQuoteReserve;
            outputAmount = state.baseAssetReserve - newBaseReserve;

            state.quoteAssetReserve = newQuoteReserve;
            state.baseAssetReserve = newBaseReserve;
            state.totalLongSize += outputAmount;
        } else {
            // Short: sell base asset for quote asset
            // Treat as selling virtual base asset to the pool
            // Calculate equivalent base amount that would generate inputAmount of quote

            uint256 newQuoteReserve = state.quoteAssetReserve - inputAmount;
            uint256 newBaseReserve = state.k / newQuoteReserve;
            outputAmount = newBaseReserve - state.baseAssetReserve;

            state.quoteAssetReserve = newQuoteReserve;
            state.baseAssetReserve = newBaseReserve;
            state.totalShortSize += outputAmount;
        }

        // Check price impact
        uint256 priceImpact = _calculatePriceImpact(inputAmount);
        if (priceImpact > PRICE_IMPACT_TOLERANCE) {
            revert ExcessivePriceImpact();
        }

        uint256 newMarkPrice = getMarkPrice();

        emit vAMMStateUpdated(
            state.baseAssetReserve,
            state.quoteAssetReserve,
            newMarkPrice,
            block.timestamp
        );

        return
            SwapOutput({
                outputAmount: outputAmount,
                markPrice: newMarkPrice,
                fundingPayment: 0 // Funding calculated separately
            });
    }

    /**
     * @dev Swap with output amount (used for closing positions)
     * @param isLong true if closing long position, false if closing short
     * @param outputAmount amount of base asset to return
     */
    function swapOutput(
        bool isLong,
        uint256 outputAmount
    )
        external
        override
        onlyAuthorized
        nonReentrant
        returns (SwapOutput memory)
    {
        if (outputAmount == 0) revert InvalidAmount();

        uint256 inputAmount;

        if (isLong) {
            // Closing long: return base asset, get quote asset
            // new_base_reserve = old_base_reserve + output
            // new_quote_reserve = k / new_base_reserve
            // input = old_quote_reserve - new_quote_reserve

            uint256 newBaseReserve = state.baseAssetReserve + outputAmount;
            uint256 newQuoteReserve = state.k / newBaseReserve;
            inputAmount = state.quoteAssetReserve - newQuoteReserve;

            state.baseAssetReserve = newBaseReserve;
            state.quoteAssetReserve = newQuoteReserve;
            state.totalLongSize -= outputAmount;
        } else {
            // Closing short: buy back base asset with quote asset
            // new_base_reserve = old_base_reserve - output
            // new_quote_reserve = k / new_base_reserve
            // input = new_quote_reserve - old_quote_reserve

            uint256 newBaseReserve = state.baseAssetReserve - outputAmount;
            uint256 newQuoteReserve = state.k / newBaseReserve;
            inputAmount = newQuoteReserve - state.quoteAssetReserve;

            state.baseAssetReserve = newBaseReserve;
            state.quoteAssetReserve = newQuoteReserve;
            state.totalShortSize -= outputAmount;
        }

        uint256 newMarkPrice = getMarkPrice();

        emit vAMMStateUpdated(
            state.baseAssetReserve,
            state.quoteAssetReserve,
            newMarkPrice,
            block.timestamp
        );

        return
            SwapOutput({
                outputAmount: inputAmount,
                markPrice: newMarkPrice,
                fundingPayment: 0 // Funding calculated separately
            });
    }

    /**
     * @dev Update funding rate and cumulative index
     */
    function updateFundingRate() external override {
        if (block.timestamp < state.lastFundingUpdate + FUNDING_PERIOD) {
            revert FundingUpdateTooSoon();
        }

        int256 currentFundingRate = getFundingRate();
        state.fundingRate = uint256(
            currentFundingRate >= 0 ? currentFundingRate : -currentFundingRate
        );
        state.lastFundingUpdate = block.timestamp;

        // Update cumulative funding index
        // cumulativeFundingIndex = cumulativeFundingIndex * (1 + fundingRate)
        int256 newIndex = int256(cumulativeFundingIndex) +
            (int256(cumulativeFundingIndex) * currentFundingRate) /
            int256(PRECISION);

        cumulativeFundingIndex = uint256(
            newIndex > 0 ? newIndex : int256(PRECISION)
        );

        emit FundingRateUpdated(currentFundingRate, block.timestamp);
    }

    /**
     * @dev Calculate funding payment for a position
     */
    function calculateFundingPayment(
        // address user,
        uint256 positionSize,
        bool isLong,
        uint256 userLastFundingIndex
    ) external view returns (int256) {
        if (positionSize == 0) return 0;

        uint256 indexDiff = cumulativeFundingIndex - userLastFundingIndex;
        int256 fundingPayment = int256((positionSize * indexDiff) / PRECISION);

        // Long positions pay funding when mark > oracle (positive funding)
        // Short positions receive funding when mark > oracle
        return isLong ? -fundingPayment : fundingPayment;
    }

    /**
     * @dev Calculate price impact of a trade
     */
    function _calculatePriceImpact(
        uint256 inputAmount
    ) internal view returns (uint256) {
        uint256 currentPrice = getMarkPrice();
        uint256 impactedPrice;

        // Simulate the trade to get new price
        uint256 newQuoteReserve = state.quoteAssetReserve + inputAmount;
        uint256 newBaseReserve = state.k / newQuoteReserve;
        impactedPrice = (newQuoteReserve * PRECISION) / newBaseReserve;

        // Calculate percentage impact
        if (impactedPrice > currentPrice) {
            return ((impactedPrice - currentPrice) * PRECISION) / currentPrice;
        } else {
            return ((currentPrice - impactedPrice) * PRECISION) / currentPrice;
        }
    }

    // Admin functions

    /**
     * @dev Adjust K value to manage liquidity
     */
    function adjustK(uint256 newK) external override onlyOwner {
        if (newK == 0) revert InvalidK();

        // Maintain price by adjusting reserves proportionally
        uint256 currentPrice = getMarkPrice();
        state.k = newK;

        // Recalculate reserves to maintain current price
        // price = quote/base, k = quote * base
        // quote = sqrt(k * price), base = sqrt(k / price)
        state.quoteAssetReserve = _sqrt((newK * currentPrice) / PRECISION);
        state.baseAssetReserve = _sqrt((newK * PRECISION) / currentPrice);

        emit vAMMStateUpdated(
            state.baseAssetReserve,
            state.quoteAssetReserve,
            currentPrice,
            block.timestamp
        );
    }

    /**
     * @dev Update oracle price manually if needed
     */
    function updateOraclePrice() external view override {
        // This function can be called to trigger oracle price update
        // The actual price is fetched in getOraclePrice()
        uint256 oraclePrice = getOraclePrice();
        require(oraclePrice > 0, "Invalid oracle price");
    }

    /**
     * @dev Add authorized caller
     */
    function addAuthorizedCaller(address caller) external onlyOwner {
        authorizedCallers[caller] = true;
    }

    /**
     * @dev Remove authorized caller
     */
    function removeAuthorizedCaller(address caller) external onlyOwner {
        authorizedCallers[caller] = false;
    }

    /**
     * @dev Update damping factor for funding rate calculation
     */
    function setDampingFactor(uint256 _dampingFactor) external onlyOwner {
        require(_dampingFactor <= PRECISION, "Invalid damping factor");
        dampingFactor = _dampingFactor;
    }

    /**
     * @dev Simple square root implementation
     */
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function calculateFundingPayment(
        address user,
        uint256 positionSize,
        bool isLong,
        uint256 lastFundingIndex
    ) external view override returns (int256) {}
} 