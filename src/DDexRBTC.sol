// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Simple D-Dex rBTC Contract
 * @dev A simple decentralized exchange contract for tracking rBTC balances
 * @notice This contract handles rBTC deposits, transfers, and bulk transfers
 */
contract DDexRBTC {
    
    // State variables
    mapping(address => uint256) private balances;
    address public owner;
    address public treasury;
    uint256 public totalDeposited;
    uint256 public treasuryBalance;
    
    // Fee configuration (in basis points, 100 = 1%)
    uint256 public transferFee = 10; // 0.1% default
    uint256 public withdrawalFee = 25; // 0.25% default
    uint256 public constant MAX_FEE = 1000; // 10% maximum fee
    
    // Events
    event Deposit(address indexed user, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount, uint256 fee);
    event BulkTransfer(address indexed from, address[] to, uint256[] amounts, uint256 totalFee);
    event Withdrawal(address indexed user, uint256 amount, uint256 fee);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event TreasuryWithdrawal(address indexed to, uint256 amount);
    event FeeUpdated(string feeType, uint256 oldFee, uint256 newFee);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier validAddress(address _addr) {
        require(_addr != address(0), "Invalid address");
        _;
    }
    
    // Constructor
    constructor(address _treasury) {
        require(_treasury != address(0), "Invalid treasury address");
        owner = msg.sender;
        treasury = _treasury;
    }
    
    /**
     * @dev Deposit rBTC to the contract
     * @notice Send rBTC along with this transaction to deposit
     */
    function deposit() external payable {
        require(msg.value > 0, "Must deposit more than 0 rBTC");
        
        balances[msg.sender] += msg.value;
        totalDeposited += msg.value;
        
        emit Deposit(msg.sender, msg.value);
    }
    
    /**
     * @dev Get balance of a specific address
     * @param _user Address to check balance for
     * @return Balance of the address
     */
    function balanceOf(address _user) external view returns (uint256) {
        return balances[_user];
    }
    
    /**
     * @dev Get caller's balance
     * @return Balance of msg.sender
     */
    function myBalance() external view returns (uint256) {
        return balances[msg.sender];
    }
    
    /**
     * @dev Transfer rBTC from sender to recipient with fee
     * @param _to Recipient address
     * @param _amount Amount to transfer (before fee)
     */
    function transfer(address _to, uint256 _amount) 
        external 
        validAddress(_to) 
    {
        require(_amount > 0, "Amount must be greater than 0");
        require(_to != msg.sender, "Cannot transfer to yourself");
        
        uint256 fee = (_amount * transferFee) / 10000;
        uint256 totalRequired = _amount + fee;
        
        require(balances[msg.sender] >= totalRequired, "Insufficient balance including fee");
        
        balances[msg.sender] -= totalRequired;
        balances[_to] += _amount;
        treasuryBalance += fee;
        
        emit Transfer(msg.sender, _to, _amount, fee);
    }
    
    /**
     * @dev Bulk transfer rBTC from multiple senders to multiple recipients with fees (Owner only)
     * @param _senders Array of sender addresses
     * @param _recipients Array of recipient addresses
     * @param _amounts Array of amounts corresponding to each transfer (before fees)
     */
    function bulkTransfer(
        address[] calldata _senders, 
        address[] calldata _recipients, 
        uint256[] calldata _amounts
    ) 
        external 
        onlyOwner
    {
        require(_senders.length == _recipients.length, "Senders and recipients arrays length mismatch");
        require(_senders.length == _amounts.length, "Senders and amounts arrays length mismatch");
        require(_senders.length > 0, "Empty arrays");
        require(_senders.length <= 100, "Too many transfers (max 100)");
        
        uint256 totalFees = 0;
        
        // Validate all transfers first
        for (uint256 i = 0; i < _senders.length; i++) {
            require(_senders[i] != address(0), "Invalid sender address");
            require(_recipients[i] != address(0), "Invalid recipient address");
            require(_recipients[i] != _senders[i], "Cannot transfer to yourself");
            require(_amounts[i] > 0, "Amount must be greater than 0");
            
            uint256 fee = (_amounts[i] * transferFee) / 10000;
            uint256 totalRequired = _amounts[i] + fee;
            
            require(balances[_senders[i]] >= totalRequired, "Insufficient balance for sender");
            
            totalFees += fee;
        }
        
        // Perform all transfers
        treasuryBalance += totalFees;
        
        for (uint256 i = 0; i < _senders.length; i++) {
            uint256 fee = (_amounts[i] * transferFee) / 10000;
            uint256 totalRequired = _amounts[i] + fee;
            
            balances[_senders[i]] -= totalRequired;
            balances[_recipients[i]] += _amounts[i];
            
            emit Transfer(_senders[i], _recipients[i], _amounts[i], fee);
        }
        
        emit BulkTransfer(address(this), _recipients, _amounts, totalFees);
    }
    
    /**
     * @dev Withdraw rBTC from contract to caller's wallet with fee
     * @param _amount Amount to withdraw (before fee)
     */
    function withdraw(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");
        
        uint256 fee = (_amount * withdrawalFee) / 10000;
        uint256 totalRequired = _amount + fee;
        
        require(balances[msg.sender] >= totalRequired, "Insufficient balance including fee");
        require(address(this).balance >= _amount, "Contract has insufficient rBTC");
        
        balances[msg.sender] -= totalRequired;
        treasuryBalance += fee;
        totalDeposited -= _amount;
        
        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        require(success, "rBTC transfer failed");
        
        emit Withdrawal(msg.sender, _amount, fee);
    }
    
    /**
     * @dev Withdraw all balance with fee
     */
    function withdrawAll() external {
        uint256 totalBalance = balances[msg.sender];
        require(totalBalance > 0, "No balance to withdraw");
        
        uint256 fee = (totalBalance * withdrawalFee) / (10000 + withdrawalFee);
        uint256 withdrawAmount = totalBalance - fee;
        
        require(address(this).balance >= withdrawAmount, "Contract has insufficient rBTC");
        
        balances[msg.sender] = 0;
        treasuryBalance += fee;
        totalDeposited -= withdrawAmount;
        
        (bool success, ) = payable(msg.sender).call{value: withdrawAmount}("");
        require(success, "rBTC transfer failed");
        
        emit Withdrawal(msg.sender, withdrawAmount, fee);
    }
    
    /**
     * @dev Owner function to set balance directly
     * @param _user User address
     * @param _amount New balance amount
     */
    function setBalance(address _user, uint256 _amount) 
        external 
        onlyOwner 
        validAddress(_user) 
    {
        uint256 oldBalance = balances[_user];
        balances[_user] = _amount;
        
        // Update total deposited accordingly
        if (_amount > oldBalance) {
            totalDeposited += (_amount - oldBalance);
        } else if (oldBalance > _amount) {
            totalDeposited -= (oldBalance - _amount);
        }
        
        emit Transfer(address(0), _user, _amount, 0);
    }
    
    // ========== TREASURY FUNCTIONS ==========
    
    /**
     * @dev Get treasury balance
     * @return Current treasury balance
     */
    function getTreasuryBalance() external view returns (uint256) {
        return treasuryBalance;
    }
    
    /**
     * @dev Withdraw fees from treasury to treasury address
     * @param _amount Amount to withdraw from treasury
     */
    function withdrawTreasury(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Amount must be greater than 0");
        require(treasuryBalance >= _amount, "Insufficient treasury balance");
        require(address(this).balance >= _amount, "Contract has insufficient rBTC");
        
        treasuryBalance -= _amount;
        
        (bool success, ) = payable(treasury).call{value: _amount}("");
        require(success, "Treasury transfer failed");
        
        emit TreasuryWithdrawal(treasury, _amount);
    }
    
    /**
     * @dev Withdraw all treasury funds to treasury address
     */
    function withdrawAllTreasury() external onlyOwner {
        uint256 amount = treasuryBalance;
        require(amount > 0, "No treasury balance");
        require(address(this).balance >= amount, "Contract has insufficient rBTC");
        
        treasuryBalance = 0;
        
        (bool success, ) = payable(treasury).call{value: amount}("");
        require(success, "Treasury transfer failed");
        
        emit TreasuryWithdrawal(treasury, amount);
    }
    
    /**
     * @dev Update treasury address
     * @param _newTreasury New treasury address
     */
    function updateTreasury(address _newTreasury) external onlyOwner validAddress(_newTreasury) {
        require(_newTreasury != treasury, "Same treasury address");
        
        address oldTreasury = treasury;
        treasury = _newTreasury;
        
        emit TreasuryUpdated(oldTreasury, _newTreasury);
    }
    
    /**
     * @dev Set transfer fee (in basis points)
     * @param _newFee New transfer fee (100 = 1%)
     */
    function setTransferFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= MAX_FEE, "Fee too high");
        
        uint256 oldFee = transferFee;
        transferFee = _newFee;
        
        emit FeeUpdated("transfer", oldFee, _newFee);
    }
    
    /**
     * @dev Set withdrawal fee (in basis points)
     * @param _newFee New withdrawal fee (100 = 1%)
     */
    function setWithdrawalFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= MAX_FEE, "Fee too high");
        
        uint256 oldFee = withdrawalFee;
        withdrawalFee = _newFee;
        
        emit FeeUpdated("withdrawal", oldFee, _newFee);
    }
    
    /**
     * @dev Calculate transfer fee for a given amount
     * @param _amount Amount to transfer
     * @return Fee amount
     */
    function calculateTransferFee(uint256 _amount) external view returns (uint256) {
        return (_amount * transferFee) / 10000;
    }
    
    /**
     * @dev Calculate withdrawal fee for a given amount
     * @param _amount Amount to withdraw
     * @return Fee amount
     */
    function calculateWithdrawalFee(uint256 _amount) external view returns (uint256) {
        return (_amount * withdrawalFee) / 10000;
    }
    
    /**
     * @dev Emergency function to transfer ownership
     * @param _newOwner New owner address
     */
    function transferOwnership(address _newOwner) 
        external 
        onlyOwner 
        validAddress(_newOwner) 
    {
        require(_newOwner != owner, "Already the owner");
        owner = _newOwner;
    }
    
    /**
     * @dev Get contract's rBTC balance
     * @return Contract's rBTC balance
     */
    function contractBalance() external view returns (uint256) {
        return address(this).balance;
    }
    
    // Fallback function to receive rBTC
    receive() external payable {
        if (msg.value > 0) {
            balances[msg.sender] += msg.value;
            totalDeposited += msg.value;
            emit Deposit(msg.sender, msg.value);
        }
    }
}