# Derivative DEX - Perpetual Futures Trading Platform

A comprehensive derivative trading platform built on Citrea testnet, featuring perpetual futures contracts with native cBTC and in-house mark pricing.

## 🏗️ Architecture

The system consists of three main contracts:

### 1. MarginVault
**Purpose**: Hold and track user deposits of native cBTC (collateral)

**Key Functions**:
- `deposit()` - Deposit native cBTC to vault via payable function
- `withdraw(uint amount)` - Check available margin, send cBTC back
- `getBalance(address user)` - Get user's margin balance
- `depositMargin(address user)` - Deposit margin for a user (authorized contracts only)

**Access Control**: Only authorized contracts (like PerpMarket) can lock/unlock margins

### 2. Treasury
**Purpose**: Collect and manage protocol fees in native cBTC

**Key Functions**:
- `receiveFee()` - Receive fees directly via payable function
- `collectFee(uint256 amount, address from)` - Collect fees from specific users
- `withdrawFees(uint256 amount)` - Withdraw fees to recipient
- `setFeeRecipient(address recipient)` - Update fee recipient

**Integration**: Accepts native cBTC fees from authorized contracts

### 3. PerpMarket
**Purpose**: Core trading logic managing positions, margin requirements, PnL, and liquidation with in-house pricing

**Key Functions**:
- `openPosition(bool isLong, uint256 size)` - Open leveraged position with native cBTC
- `closePosition()` - Close user position, settle PnL
- `liquidatePosition(address user)` - Liquidate undercollateralized positions
- `updateMarkPrice(uint256 newPrice)` - Update mark price (owner only)
- `getMarkPrice()` - Get current mark price
- `getPosition(address user)` - Get position details
- `getCurrentPnL(address user)` - Get unrealized PnL

**Position Logic**:
- PnL = (currentPrice - entryPrice) × size (negated for shorts)
- Margin ratio = (margin + PnL) / positionSize
- Liquidation when margin ratio < maintenance threshold (10%)
- In-house mark pricing controlled by contract owner

## 📊 Trading Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Initial Margin | 20% | Required margin for opening positions |
| Maintenance Margin | 10% | Minimum margin to avoid liquidation |
| Trading Fee | 0.1% | Fee charged on position open/close |
| Liquidation Reward | 5% | Reward for liquidators |
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
forge test --match-contract IntegrationTest -vv
```

### Test Coverage
```bash
forge coverage
```

## 📖 Usage Guide

### 1. Deposit Collateral
```solidity
// Approve vault to spend cBTC
cBTC.approve(address(marginVault), amount);

// Deposit cBTC to vault
marginVault.deposit(amount);
```

### 2. Open Position
```solidity
// Open long position (expecting price to go up)
perpMarket.openPosition(
    true,           // isLong
    5 * 10**18,     // size (5 cBTC notional)
    100             // maxSlippage (1%)
);

// Open short position (expecting price to go down)
perpMarket.openPosition(
    false,          // isLong
    10 * 10**18,    // size (10 cBTC notional)
    100             // maxSlippage (1%)
);
```

### 3. Monitor Position
```solidity
// Get position details
Position memory pos = perpMarket.getPosition(user);

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

### Price Updates
Users can update Pyth price feeds if needed:
```solidity
// Get required fee
uint256 fee = priceOracle.getUpdateFee(updateData);

// Update price feeds
priceOracle.updatePriceFeeds{value: fee}(updateData);
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
- **Reentrancy Protection**: All state-changing functions protected
- **Price Staleness**: Oracle prices checked for freshness
- **Margin Requirements**: Strict margin calculations prevent undercollateralization
- **Liquidation System**: Automatic liquidation of risky positions

### Input Validation
- Zero address checks
- Zero amount validation
- Leverage limits
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
- **Oracle Fees**: Variable based on Pyth network requirements

## 🌐 Citrea Integration

### Pyth Oracle
- **Contract**: `0x2880aB155794e7179c9eE2e38200202908C17B43`
- **BTC/USD Feed**: `0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43`
- **Update Frequency**: Real-time with sub-second latency

### Network Details
- **RPC URL**: `https://citrea-testnet.rpc.url`
- **Chain ID**: TBD
- **Explorer**: `https://citrea-testnet.etherscan.io`

## 🛠️ Development

### Project Structure
```
derivative-dex/
├── src/
│   ├── MarginVault.sol
│   ├── PythOracleAdapter.sol
│   ├── Treasury.sol
│   ├── PerpMarket.sol
│   └── interfaces/
│       └── IPyth.sol
├── test/
│   ├── MarginVault.t.sol
│   ├── PythOracleAdapter.t.sol
│   ├── Treasury.t.sol
│   ├── PerpMarket.t.sol
│   └── Integration.t.sol
├── script/
│   └── Deploy.s.sol
└── foundry.toml
```

### Gas Optimization
- **Immutable Variables**: Core contract addresses
- **Packed Structs**: Efficient storage layout
- **Batch Operations**: Multiple actions in single transaction
- **View Functions**: Off-chain data queries

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## ⚠️ Disclaimer

This is experimental software. Use at your own risk. Not audited for production use.

## 📞 Support

For questions and support:
- Open an issue on GitHub
- Join our Discord community
- Check documentation at [docs.derivative-dex.io](https://docs.derivative-dex.io)
