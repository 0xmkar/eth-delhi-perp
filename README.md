# Derivative DEX - Perpetual Futures Trading Platform

A comprehensive derivative trading platform built on Citrea testnet, featuring perpetual futures contracts with native cBTC and in-house mark pricing.

## 🏗️ Architecture

The system consists of four main contracts:

### 1. MarginVault
**Purpose**: Hold and track user deposits of native cBTC (collateral)

**Key Functions**:
- `deposit()` payable - Deposit native cBTC to vault (no parameters)
- `withdraw(uint256 amount)` - Withdraw available margin back to user
- `getBalance(address user)` - Get user's total balance
- `getAvailableMargin(address user)` - Get user's available (unlocked) margin
- `getLockedMargin(address user)` - Get user's locked margin amount
- `depositMargin(address user)` payable - Deposit margin for user (authorized contracts only)
- `lockMargin(address user, uint256 amount)` - Lock margin for positions (authorized only)
- `unlockMargin(address user, uint256 amount)` - Unlock margin after position closure (authorized only)
- `addBalance(address user, uint256 amount)` - Add to user balance for PnL settlement (authorized only)
- `deductBalance(address user, uint256 amount)` - Deduct from user balance for losses (authorized only)
- `transferBalance(address from, address to, uint256 amount)` - Transfer between users for liquidation rewards (authorized only)

**Access Control**: Only authorized contracts (like PerpMarket) can manage user margins

### 2. Treasury
**Purpose**: Collect and manage protocol fees in native cBTC

**Key Functions**:
- `receiveFee()` payable - Receive fees directly via payable function
- `collectFee(uint256 amount, address from)` payable - Collect fees from specific users
- `withdrawFees(uint256 amount)` - Withdraw fees to recipient (0 = withdraw all)
- `setFeeRecipient(address _feeRecipient)` - Update fee recipient address
- `setAuthorizedContract(address contractAddr, bool authorized)` - Authorize contracts to send fees
- `getBalance()` - Get current treasury balance
- `getTotalFeesCollected()` - Get total fees collected over time

**Integration**: Accepts native cBTC fees from authorized contracts

### 3. PerpMarket
**Purpose**: Core trading logic managing positions, margin requirements, PnL, and liquidation with in-house pricing

**Key Functions**:
- `openPosition(bool isLong, uint256 size)` payable - Open leveraged position (only 2 parameters)
- `closePosition()` - Close user position and settle PnL
- `liquidatePosition(address user)` - Liquidate undercollateralized positions
- `updateMarkPrice(uint256 newPrice)` - Update mark price (owner only)
- `getMarkPrice()` - Get current mark price
- `getPosition(address user)` - Get position details (size, entryPrice, margin, isLong, timestamp)
- `getCurrentPnL(address user)` - Get unrealized PnL for position
- `getMarginRatio(address user)` - Get current margin ratio in basis points
- `isLiquidatable(address user)` - Check if position can be liquidated
- `getMarketStats()` - Get global market statistics (totalLongs, totalShorts, volume, currentPrice)

**Admin Functions**:
- `setMaintenanceMarginBps(uint256)` - Update maintenance margin requirement
- `setInitialMarginBps(uint256)` - Update initial margin requirement
- `setTradingFeeBps(uint256)` - Update trading fee
- `setTradingPaused(bool)` - Pause/unpause trading
- `emergencyClosePosition(address user)` - Emergency position closure (owner only)

**Position Logic**:
- PnL = (currentPrice - entryPrice) × size (negated for shorts)
- Margin ratio = (margin + PnL) / positionSize
- Liquidation when margin ratio < maintenance threshold (10%)
- In-house mark pricing controlled by contract owner

### 4. CLAggregatorAdapterConsumer (blockSense.sol)
**Purpose**: Chainlink price feed adapter for potential future oracle integration

**Key Functions**:
- `getDecimals()` - Get price feed decimals
- `getDescription()` - Get price feed description
- `getLatestAnswer()` - Get latest price answer
- `getLatestRound()` - Get latest round ID
- `getRoundData(uint80 roundId)` - Get specific round data
- `getLatestRoundData()` - Get latest round data with metadata

## 📊 Trading Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Initial Margin | 20% (2000 bps) | Required margin for opening positions |
| Maintenance Margin | 10% (1000 bps) | Minimum margin to avoid liquidation |
| Trading Fee | 0.1% (10 bps) | Fee charged on position open/close |
| Liquidation Reward | 5% (500 bps) | Reward for liquidators |
| Max Leverage | 50x | Maximum allowed leverage |

## 🚀 Deployment

### Prerequisites
1. Install Foundry
2. Set up environment variables:
   ```bash
   PRIVATE_KEY=your_private_key
   ```
3. Ensure you have native cBTC for testing

### Deploy to Citrea Testnet
```bash
forge script script/Deploy.s.sol:Deploy --rpc-url https://rpc.testnet.citrea.xyz --broadcast --verify
```

### Deploy with Testnet Parameters
```bash
forge script script/Deploy.s.sol --sig "deployTestnet()" --rpc-url https://rpc.testnet.citrea.xyz --broadcast
```

## 🧪 Testing

### Run All Tests
```bash
forge test -vv
```

### Run Specific Test Suites
```bash
# Test individual contracts
forge test --match-contract MarginVaultTest -vv
forge test --match-contract TreasuryTest -vv
forge test --match-contract PerpMarketTest -vv

# Run integration tests
forge test --match-contract IntegrationSimpleTest -vv
```

### Test Coverage
```bash
forge coverage
```

## 📖 Usage Guide

### 1. Deposit Collateral
```solidity
// Deposit native cBTC to vault (function takes no parameters)
marginVault.deposit{value: amount}();
```

### 2. Open Position
```solidity
// Calculate required margin + fee
uint256 size = 5 * 10**18;  // 5 cBTC notional
uint256 requiredMargin = (size * initialMarginBps) / 10000;
uint256 tradingFee = (size * tradingFeeBps) / 10000;
uint256 totalRequired = requiredMargin + tradingFee;

// Open long position (expecting price to go up)
perpMarket.openPosition{value: totalRequired}(
    true,           // isLong
    size            // size (5 cBTC notional)
);

// Open short position (expecting price to go down)
perpMarket.openPosition{value: totalRequired}(
    false,          // isLong  
    10 * 10**18     // size (10 cBTC notional)
);
```

### 3. Monitor Position
```solidity
// Get position details
PerpMarket.Position memory pos = perpMarket.getPosition(user);

// Check current PnL
int256 pnl = perpMarket.getCurrentPnL(user);

// Check margin ratio
uint256 marginRatio = perpMarket.getMarginRatio(user);

// Check if liquidatable
bool canLiquidate = perpMarket.isLiquidatable(user);
```

### 4. Close Position
```solidity
// Close position and realize PnL
perpMarket.closePosition();
```

### 5. Liquidate Positions
```solidity
// Anyone can liquidate undercollateralized positions
if (perpMarket.isLiquidatable(user)) {
    perpMarket.liquidatePosition(user);
    // Liquidator receives reward
}
```

## 🔧 Contract Interactions

### Mark Price Updates (In-House Pricing)
Only contract owner can update mark price:
```solidity
// Update mark price (owner only)
perpMarket.updateMarkPrice(52000 * 10**18); // $52,000
```

### Admin Functions
Contract owners can adjust parameters:
```solidity
// Update trading parameters
perpMarket.setTradingFeeBps(20);           // 0.2% fee
perpMarket.setMaintenanceMarginBps(1200);  // 12% maintenance
perpMarket.setInitialMarginBps(2500);      // 25% initial margin

// Pause trading in emergencies
perpMarket.setTradingPaused(true);

// Emergency position closure
perpMarket.emergencyClosePosition(user);
```

## 🔐 Security Features

### Access Control
- **MarginVault**: Only authorized contracts can manage margins
- **Treasury**: Only authorized contracts can collect fees  
- **PerpMarket**: Only owner can update parameters and emergency actions

### Safety Mechanisms
- **Reentrancy Protection**: All state-changing functions protected with ReentrancyGuard
- **In-House Pricing**: Manual mark price updates by contract owner
- **Margin Requirements**: Strict margin calculations prevent undercollateralization
- **Liquidation System**: Automatic liquidation of risky positions

### Input Validation
- Zero address checks
- Zero amount validation
- Leverage limits (max 50x)
- Price sanity checks

## 📈 Market Dynamics

### Long Positions
- **Profit**: When BTC price increases
- **Loss**: When BTC price decreases
- **Liquidation**: When losses exceed maintenance margin

### Short Positions
- **Profit**: When BTC price decreases
- **Loss**: When BTC price increases
- **Liquidation**: When losses exceed maintenance margin

### Fee Structure
- **Trading Fees**: 0.1% on position open/close
- **Liquidation Rewards**: 5% of position margin to liquidators
- **No Oracle Fees**: Uses in-house mark pricing

## 🌐 Citrea Integration

### Network Details
- **Network**: Citrea Testnet
- **Native Token**: cBTC (Bitcoin wrapped on Citrea)
- **Settlement**: Native cBTC transfers

## 🛠️ Development

### Project Structure
```
/
├── src/
│ ├── MarginVault.sol # User collateral management
│ ├── Treasury.sol # Protocol fee collection
│ ├── PerpMarket.sol # Core trading logic
│ ├── blockSense.sol # blockSense adapter (CLAggregatorAdapterConsumer)
│ └── interfaces/
│ └── IChainlinkAggregator.sol
├── test/
│ ├── MarginVault.t.sol
│ ├── Treasury.t.sol
│ ├── PerpMarket.t.sol
│ └── IntegrationSimple.t.sol
├── script/
│ └── Deploy.s.sol
├── abi/ # Generated contract ABIs
└── foundry.toml
```


### Gas Optimization
- **Immutable Variables**: Core contract addresses
- **Packed Structs**: Efficient storage layout for Position struct
- **Native cBTC**: No ERC20 transfers, direct native token handling
- **View Functions**: Off-chain data queries

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details.
