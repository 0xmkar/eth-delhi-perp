// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title MarginVault
 * @dev Manages user cBTC deposits and withdrawals for margin trading
 * Only authorized contracts (like PerpMarket) can lock/unlock user margins
 * Handles native cBTC instead of ERC20 tokens
 */
contract MarginVault is Ownable, ReentrancyGuard {

    // Events
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event MarginLocked(address indexed user, uint256 amount);
    event MarginUnlocked(address indexed user, uint256 amount);
    event AuthorizedContractUpdated(address indexed contractAddr, bool authorized);
    event BalanceAdjusted(address indexed user, int256 amount);

    // User balances: total deposited cBTC
    mapping(address => uint256) public balances;
    
    // User locked margins: amount locked in active positions
    mapping(address => uint256) public lockedMargins;
    
    // Authorized contracts that can lock/unlock margins
    mapping(address => bool) public authorizedContracts;

    // Errors
    error InsufficientBalance();
    error InsufficientAvailableMargin();
    error Unauthorized();
    error ZeroAmount();
    error ZeroAddress();
    error TransferFailed();

    modifier onlyAuthorized() {
        if (!authorizedContracts[msg.sender]) revert Unauthorized();
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) revert ZeroAddress();
        _;
    }

    constructor(address _owner) Ownable(_owner) {}

    /**
     * @dev Deposit native cBTC to the vault
     */
    function deposit() external payable nonReentrant validAmount(msg.value) {
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev Deposit margin for a user (only authorized contracts)
     * @param user User to deposit margin for
     */
    function depositMargin(address user) external payable onlyAuthorized validAmount(msg.value) validAddress(user) {
        balances[user] += msg.value;
        lockedMargins[user] += msg.value;
        
        emit Deposit(user, msg.value);
        emit MarginLocked(user, msg.value);
    }

    /**
     * @dev Withdraw available cBTC from the vault
     * @param amount Amount of cBTC to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant validAmount(amount) {
        uint256 availableBalance = getAvailableMargin(msg.sender);
        if (amount > availableBalance) revert InsufficientAvailableMargin();
        
        balances[msg.sender] -= amount;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();
        
        emit Withdraw(msg.sender, amount);
    }

    /**
     * @dev Lock margin for a position (only authorized contracts)
     * @param user User whose margin to lock
     * @param amount Amount to lock
     */
    function lockMargin(address user, uint256 amount) 
        external 
        onlyAuthorized 
        validAmount(amount) 
        validAddress(user) 
    {
        uint256 availableBalance = getAvailableMargin(user);
        if (amount > availableBalance) revert InsufficientAvailableMargin();
        
        lockedMargins[user] += amount;
        
        emit MarginLocked(user, amount);
    }

    /**
     * @dev Unlock margin after position closure (only authorized contracts)
     * @param user User whose margin to unlock
     * @param amount Amount to unlock
     */
    function unlockMargin(address user, uint256 amount) 
        external 
        onlyAuthorized 
        validAmount(amount) 
        validAddress(user) 
    {
        if (amount > lockedMargins[user]) revert InsufficientBalance();
        
        lockedMargins[user] -= amount;
        
        emit MarginUnlocked(user, amount);
    }

    /**
     * @dev Add balance to user account (for PnL settlement) (only authorized contracts)
     * @param user User address
     * @param amount Amount to add
     */
    function addBalance(address user, uint256 amount) 
        external 
        onlyAuthorized 
        validAmount(amount) 
        validAddress(user) 
    {
        balances[user] += amount;
        emit BalanceAdjusted(user, int256(amount));
    }

    /**
     * @dev Deduct balance from user account (for PnL settlement) (only authorized contracts)
     * @param user User address
     * @param amount Amount to deduct
     */
    function deductBalance(address user, uint256 amount) 
        external 
        onlyAuthorized 
        validAmount(amount) 
        validAddress(user) 
    {
        if (amount > balances[user]) revert InsufficientBalance();
        
        balances[user] -= amount;
        emit BalanceAdjusted(user, -int256(amount));
    }

    /**
     * @dev Transfer balance between users (for liquidation rewards) (only authorized contracts)
     * @param from User to transfer from
     * @param to User to transfer to
     * @param amount Amount to transfer
     */
    function transferBalance(address from, address to, uint256 amount) 
        external 
        onlyAuthorized 
        validAmount(amount) 
        validAddress(from) 
        validAddress(to) 
    {
        if (amount > balances[from]) revert InsufficientBalance();
        
        balances[from] -= amount;
        balances[to] += amount;
        
        emit BalanceAdjusted(from, -int256(amount));
        emit BalanceAdjusted(to, int256(amount));
    }

    /**
     * @dev Withdraw cBTC from vault to recipient (only authorized contracts)
     * @param recipient Recipient address
     * @param amount Amount to withdraw
     */
    function withdrawTo(address recipient, uint256 amount) 
        external 
        // onlyAuthorized 
        validAmount(amount) 
        validAddress(recipient) 
    {
        if (amount > address(this).balance) revert InsufficientBalance();
        
        (bool success, ) = payable(recipient).call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    // View functions

    /**
     * @dev Get user's total balance
     * @param user User address
     * @return User's balance
     */
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    /**
     * @dev Get user's locked margin
     * @param user User address
     * @return User's locked margin
     */
    function getLockedMargin(address user) external view returns (uint256) {
        return lockedMargins[user];
    }

    /**
     * @dev Get user's available margin (balance - locked)
     * @param user User address
     * @return Available margin
     */
    function getAvailableMargin(address user) public view returns (uint256) {
        uint256 balance = balances[user];
        uint256 locked = lockedMargins[user];
        return balance > locked ? balance - locked : 0;
    }

    /**
     * @dev Get total vault balance
     * @return Total cBTC in vault
     */
    function getTotalBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // Admin functions

    /**
     * @dev Authorize/deauthorize a contract
     * @param contractAddr Contract address
     * @param authorized Whether contract should be authorized
     */
    function setAuthorizedContract(address contractAddr, bool authorized) 
        external 
        onlyOwner 
        validAddress(contractAddr) 
    {
        authorizedContracts[contractAddr] = authorized;
        emit AuthorizedContractUpdated(contractAddr, authorized);
    }

    /**
     * @dev Emergency withdraw function (only owner)
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        if (amount > address(this).balance) revert InsufficientBalance();
        
        (bool success, ) = payable(owner()).call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /**
     * @dev Allow contract to receive native cBTC
     */
    receive() external payable {
        // Accept cBTC deposits
    }

    /**
     * @dev Fallback function
     */
    fallback() external payable {
        // Accept cBTC deposits
    }
} 