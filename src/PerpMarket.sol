// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./MarginVault.sol";
import "./Treasury.sol";

/**
 * @title PerpMarket
 * @dev Core perpetual futures trading contract
 * Manages positions, margin requirements, PnL calculations, and liquidations
 * Uses in-house mark pricing instead of external oracles
 */
contract PerpMarket is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Position struct
    struct Position {
        uint256 size;       // notional position size in cBTC
        uint256 entryPrice; // mark price at entry (18 decimals)
        uint256 margin;     // margin locked
        bool isLong;        // true = long, false = short
        uint256 timestamp;  // when position was opened
    }

    // Events
    event PositionOpened(
        address indexed user,
        bool isLong,
        uint256 size,
        uint256 entryPrice,
        uint256 margin,
        uint256 leverage
    );
    
    event PositionClosed(
        address indexed user,
        uint256 exitPrice,
        int256 pnl,
        uint256 marginReturned
    );
    
    event PositionLiquidated(
        address indexed user,
        address indexed liquidator,
        uint256 liquidationPrice,
        int256 pnl,
        uint256 liquidationReward
    );
    
    event FeeCharged(address indexed user, uint256 feeAmount);
    
    event ConfigUpdated(string parameter, uint256 oldValue, uint256 newValue);
    
    event MarkPriceUpdated(uint256 newPrice, uint256 timestamp);

    // Constants
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MAX_LEVERAGE = 50; // 50x max leverage
    uint256 private constant BPS_DIVISOR = 10000; // For basis points

    // State variables
    MarginVault public immutable marginVault;
    Treasury public immutable treasury;

    // In-house mark pricing
    uint256 public markPrice; // Current mark price (18 decimals)
    uint256 public lastPriceUpdate; // Timestamp of last price update

    // User positions
    mapping(address => Position) public positions;
    
    // Configuration
    uint256 public maintenanceMarginBps = 1000;  // 10% maintenance margin
    uint256 public initialMarginBps = 2000;      // 20% initial margin  
    uint256 public tradingFeeBps = 10;           // 0.1% trading fee
    uint256 public liquidationRewardBps = 500;   // 5% liquidation reward
    
    // Global state
    uint256 public totalLongSize;
    uint256 public totalShortSize;
    uint256 public totalVolume;
    bool public tradingPaused;

    // Errors
    error TradingPaused();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidLeverage();
    error PositionExists();
    error NoPosition();
    error InsufficientMargin();
    error PositionNotLiquidatable();
    error InvalidPrice();
    error ExcessiveImbalance();
    error UnauthorizedLiquidator();

    modifier whenNotPaused() {
        if (tradingPaused) revert TradingPaused();
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) revert ZeroAddress();
        _;
    }

    modifier hasPosition(address user) {
        if (positions[user].size == 0) revert NoPosition();
        _;
    }

    modifier noPosition(address user) {
        if (positions[user].size > 0) revert PositionExists();
        _;
    }

    constructor(
        MarginVault _marginVault,
        Treasury _treasury,
        uint256 _initialMarkPrice,
        address _owner
    ) Ownable(_owner) {
        if (address(_marginVault) == address(0) || address(_treasury) == address(0)) revert ZeroAddress();
        if (_initialMarkPrice == 0) revert InvalidPrice();
            
        marginVault = _marginVault;
        treasury = _treasury;
        markPrice = _initialMarkPrice;
        lastPriceUpdate = block.timestamp;
    }

    /**
     * @dev Update the mark price (only owner)
     * @param newPrice New mark price in 18 decimals
     */
    function updateMarkPrice(uint256 newPrice) external onlyOwner {
        if (newPrice == 0) revert InvalidPrice();
        
        markPrice = newPrice;
        lastPriceUpdate = block.timestamp;
        
        emit MarkPriceUpdated(newPrice, block.timestamp);
    }

    /**
     * @dev Get current mark price
     * @return Current mark price in 18 decimals
     */
    function getMarkPrice() external view returns (uint256) {
        return markPrice;
    }

    /**
     * @dev Open a new perpetual position
     * @param isLong true for long, false for short
     * @param size notional size in cBTC (18 decimals)
     */
    function openPosition(
        bool isLong,
        uint256 size
    ) external payable nonReentrant whenNotPaused noPosition(msg.sender) {
        if (size == 0) revert ZeroAmount();
        
        // Use current mark price
        uint256 currentPrice = markPrice;
        if (currentPrice == 0) revert InvalidPrice();
        
        // Calculate required margin based on initial margin requirement
        uint256 requiredMargin = (size * initialMarginBps) / BPS_DIVISOR;
        
        // Calculate leverage
        uint256 leverage = (size * PRECISION) / requiredMargin;
        if (leverage > MAX_LEVERAGE * PRECISION) revert InvalidLeverage();
        
        // Calculate trading fee
        uint256 tradingFee = (size * tradingFeeBps) / BPS_DIVISOR;
        uint256 totalRequired = requiredMargin + tradingFee;
        
        // Check if user sent enough cBTC
        if (msg.value < totalRequired) revert InsufficientMargin();
        
        // Lock margin in vault
        marginVault.depositMargin{value: requiredMargin}(msg.sender);
        
        // Send fee to treasury
        treasury.receiveFee{value: tradingFee}();
        
        // Refund excess if any
        if (msg.value > totalRequired) {
            payable(msg.sender).transfer(msg.value - totalRequired);
        }
        
        // Update global state
        if (isLong) {
            totalLongSize += size;
        } else {
            totalShortSize += size;
        }
        totalVolume += size;
        
        // Create position
        positions[msg.sender] = Position({
            size: size,
            entryPrice: currentPrice,
            margin: requiredMargin,
            isLong: isLong,
            timestamp: block.timestamp
        });
        
        emit PositionOpened(msg.sender, isLong, size, currentPrice, requiredMargin, leverage / PRECISION);
        emit FeeCharged(msg.sender, tradingFee);
    }

    /**
     * @dev Close an existing position
     */
    function closePosition() external nonReentrant hasPosition(msg.sender) {
        Position memory pos = positions[msg.sender];
        
        // Get current price
        uint256 currentPrice = markPrice;
        if (currentPrice == 0) revert InvalidPrice();
        
        // Calculate PnL
        int256 pnl = _calculatePnL(pos, currentPrice);
        
        // Calculate trading fee for closing
        uint256 tradingFee = (pos.size * tradingFeeBps) / BPS_DIVISOR;
        
        // Settle position
        uint256 marginReturned = _settlePosition(msg.sender, pos, pnl, tradingFee);
        
        // Update global state  
        if (pos.isLong) {
            totalLongSize -= pos.size;
        } else {
            totalShortSize -= pos.size;
        }
        totalVolume += pos.size;
        
        // Clear position
        delete positions[msg.sender];
        
        emit PositionClosed(msg.sender, currentPrice, pnl, marginReturned);
        emit FeeCharged(msg.sender, tradingFee);
    }

    /**
     * @dev Liquidate an undercollateralized position
     * @param user User whose position to liquidate
     */
    function liquidatePosition(address user) 
        external 
        nonReentrant 
        hasPosition(user) 
    {
        Position memory pos = positions[user];
        
        // Get current price
        uint256 currentPrice = markPrice;
        if (currentPrice == 0) revert InvalidPrice();
        
        // Check if position is liquidatable
        if (!_isLiquidatable(pos, currentPrice)) revert PositionNotLiquidatable();
        
        // Calculate PnL
        int256 pnl = _calculatePnL(pos, currentPrice);
        
        // Calculate liquidation reward
        uint256 liquidationReward = (pos.margin * liquidationRewardBps) / BPS_DIVISOR;
        
        // Settle position (no trading fee for liquidation)
        _settlePosition(user, pos, pnl, 0);
        
        // Pay liquidation reward to liquidator
        marginVault.transferBalance(user, msg.sender, liquidationReward);
        
        // Update global state
        if (pos.isLong) {
            totalLongSize -= pos.size;
        } else {
            totalShortSize -= pos.size;
        }
        
        // Clear position
        delete positions[user];
        
        emit PositionLiquidated(user, msg.sender, currentPrice, pnl, liquidationReward);
    }

    /**
     * @dev Calculate PnL for a position
     * @param pos Position struct
     * @param currentPrice Current mark price
     * @return pnl Profit/loss (positive = profit, negative = loss)
     */
    function _calculatePnL(Position memory pos, uint256 currentPrice) internal pure returns (int256 pnl) {
        if (pos.isLong) {
            // Long: profit when price goes up
            pnl = int256((currentPrice * pos.size) / PRECISION) - int256((pos.entryPrice * pos.size) / PRECISION);
        } else {
            // Short: profit when price goes down  
            pnl = int256((pos.entryPrice * pos.size) / PRECISION) - int256((currentPrice * pos.size) / PRECISION);
        }
    }

    /**
     * @dev Check if a position is liquidatable
     * @param pos Position struct
     * @param currentPrice Current mark price
     * @return bool Whether position can be liquidated
     */
    function _isLiquidatable(Position memory pos, uint256 currentPrice) internal view returns (bool) {
        int256 pnl = _calculatePnL(pos, currentPrice);
        
        // Calculate current margin value (margin + pnl)
        int256 currentMarginValue = int256(pos.margin) + pnl;
        
        // Position is liquidatable if margin ratio < maintenance margin
        if (currentMarginValue <= 0) return true;
        
        uint256 marginRatio = (uint256(currentMarginValue) * BPS_DIVISOR) / pos.size;
        return marginRatio < maintenanceMarginBps;
    }

    /**
     * @dev Settle position and handle margin/balance updates
     * @param user User address
     * @param pos Position struct
     * @param pnl Calculated PnL
     * @param tradingFee Trading fee to deduct
     * @return marginReturned Amount of margin returned to user
     */
    function _settlePosition(
        address user,
        Position memory pos,
        int256 pnl,
        uint256 tradingFee
    ) internal returns (uint256 marginReturned) {
        // Unlock margin
        marginVault.unlockMargin(user, pos.margin);
        
        // Calculate net settlement (PnL minus fee)
        int256 netSettlement = pnl - int256(tradingFee);
        
        if (netSettlement >= 0) {
            // Profit case: add to balance and send fee to treasury from vault
            if (uint256(netSettlement) > 0) {
                marginVault.addBalance(user, uint256(netSettlement));
            }
            marginReturned = pos.margin;
            
            // Send trading fee to treasury from vault if applicable
            if (tradingFee > 0) {
                marginVault.withdrawTo(address(treasury), tradingFee);
                treasury.receiveFee{value: tradingFee}();
            }
        } else {
            // Loss case: deduct from margin
            uint256 loss = uint256(-netSettlement);
            if (loss >= pos.margin) {
                // Total loss exceeds margin - deduct entire margin
                marginVault.deductBalance(user, pos.margin);
                marginReturned = 0;
                
                // Still need to pay trading fee from the deducted margin
                if (tradingFee > 0 && tradingFee <= pos.margin) {
                    marginVault.withdrawTo(address(treasury), tradingFee);
                    treasury.receiveFee{value: tradingFee}();
                }
            } else {
                // Partial loss
                marginVault.deductBalance(user, loss);
                marginReturned = pos.margin - loss;
                
                // Send trading fee to treasury
                if (tradingFee > 0) {
                    marginVault.withdrawTo(address(treasury), tradingFee);
                    treasury.receiveFee{value: tradingFee}();
                }
            }
        }
    }

    // View functions

    /**
     * @dev Get position details for a user
     * @param user User address
     * @return Position struct
     */
    function getPosition(address user) external view returns (Position memory) {
        return positions[user];
    }

    /**
     * @dev Get current PnL for a user's position
     * @param user User address
     * @return pnl Current unrealized PnL
     */
    function getCurrentPnL(address user) external view returns (int256 pnl) {
        Position memory pos = positions[user];
        if (pos.size == 0) return 0;
        
        uint256 currentPrice = markPrice;
        return _calculatePnL(pos, currentPrice);
    }

    /**
     * @dev Get margin ratio for a user's position
     * @param user User address
     * @return marginRatio Current margin ratio in basis points
     */
    function getMarginRatio(address user) external view returns (uint256 marginRatio) {
        Position memory pos = positions[user];
        if (pos.size == 0) return 0;
        
        uint256 currentPrice = markPrice;
        int256 pnl = _calculatePnL(pos, currentPrice);
        int256 currentMarginValue = int256(pos.margin) + pnl;
        
        if (currentMarginValue <= 0) return 0;
        return (uint256(currentMarginValue) * BPS_DIVISOR) / pos.size;
    }

    /**
     * @dev Check if a position is liquidatable
     * @param user User address
     * @return bool Whether position can be liquidated
     */
    function isLiquidatable(address user) external view returns (bool) {
        Position memory pos = positions[user];
        if (pos.size == 0) return false;
        
        uint256 currentPrice = markPrice;
        return _isLiquidatable(pos, currentPrice);
    }

    /**
     * @dev Get global market statistics
     * @return totalLongs Total long position size
     * @return totalShorts Total short position size  
     * @return volume Total trading volume
     * @return currentPrice Current mark price
     */
    function getMarketStats() external view returns (
        uint256 totalLongs,
        uint256 totalShorts,
        uint256 volume,
        uint256 currentPrice
    ) {
        return (totalLongSize, totalShortSize, totalVolume, markPrice);
    }

    // Admin functions

    /**
     * @dev Update maintenance margin requirement
     * @param newMaintenanceMarginBps New maintenance margin in basis points
     */
    function setMaintenanceMarginBps(uint256 newMaintenanceMarginBps) external onlyOwner {
        require(newMaintenanceMarginBps > 0 && newMaintenanceMarginBps < 5000, "Invalid margin");
        uint256 oldValue = maintenanceMarginBps;
        maintenanceMarginBps = newMaintenanceMarginBps;
        emit ConfigUpdated("maintenanceMarginBps", oldValue, newMaintenanceMarginBps);
    }

    /**
     * @dev Update initial margin requirement  
     * @param newInitialMarginBps New initial margin in basis points
     */
    function setInitialMarginBps(uint256 newInitialMarginBps) external onlyOwner {
        require(newInitialMarginBps > maintenanceMarginBps && newInitialMarginBps < 10000, "Invalid margin");
        uint256 oldValue = initialMarginBps;
        initialMarginBps = newInitialMarginBps;
        emit ConfigUpdated("initialMarginBps", oldValue, newInitialMarginBps);
    }

    /**
     * @dev Update trading fee
     * @param newTradingFeeBps New trading fee in basis points
     */
    function setTradingFeeBps(uint256 newTradingFeeBps) external onlyOwner {
        require(newTradingFeeBps <= 100, "Fee too high"); // Max 1%
        uint256 oldValue = tradingFeeBps;
        tradingFeeBps = newTradingFeeBps;
        emit ConfigUpdated("tradingFeeBps", oldValue, newTradingFeeBps);
    }

    /**
     * @dev Pause/unpause trading
     * @param paused Whether trading should be paused
     */
    function setTradingPaused(bool paused) external onlyOwner {
        tradingPaused = paused;
    }

    /**
     * @dev Emergency position closure (admin only)
     * @param user User whose position to close
     */
    function emergencyClosePosition(address user) external onlyOwner hasPosition(user) {
        Position memory pos = positions[user];
        uint256 currentPrice = markPrice;
        int256 pnl = _calculatePnL(pos, currentPrice);
        
        // Settle without trading fee in emergency
        uint256 marginReturned = _settlePosition(user, pos, pnl, 0);
        
        // Update global state
        if (pos.isLong) {
            totalLongSize -= pos.size;
        } else {
            totalShortSize -= pos.size;
        }
        
        delete positions[user];
        emit PositionClosed(user, currentPrice, pnl, marginReturned);
    }
} 