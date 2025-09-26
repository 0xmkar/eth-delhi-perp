// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Treasury
 * @dev Simple treasury contract for collecting and managing protocol fees in native cBTC
 * Collects fees from perpetual trading operations
 */
contract Treasury is Ownable, ReentrancyGuard {

    // Events
    event FeeCollected(uint256 amount, address indexed from);
    event FeeWithdrawn(uint256 amount, address indexed to);
    event AuthorizedContractUpdated(address indexed contractAddr, bool authorized);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    // State variables
    address public feeRecipient;
    
    // Authorized contracts that can send fees to treasury
    mapping(address => bool) public authorizedContracts;
    
    // Total fees collected in cBTC
    uint256 public totalFeesCollected;

    // Errors
    error Unauthorized();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance();
    error TransferFailed();

    // modifier onlyAuthorized() {
    //     if (!authorizedContracts[msg.sender]) revert Unauthorized();
    //     _;
    // }

    modifier validAddress(address addr) {
        if (addr == address(0)) revert ZeroAddress();
        _;
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    constructor(address _feeRecipient, address _owner) Ownable(_owner) {
        if (_feeRecipient == address(0)) revert ZeroAddress();
        feeRecipient = _feeRecipient;
    }

    /**
     * @dev Directly receive cBTC fees (for authorized contracts)
     */
    function receiveFee() external payable validAmount(msg.value) {
    // function receiveFee() external payable onlyAuthorized validAmount(msg.value) {
        totalFeesCollected += msg.value;
        emit FeeCollected(msg.value, msg.sender);
    }

    /**
     * @dev Collect fees from a specific user (called by authorized contracts)
     * @param amount Amount of cBTC to collect
     * @param from Address the fees are coming from
     */
    function collectFee(uint256 amount, address from) 
        external 
        payable
        // onlyAuthorized 
        validAmount(amount) 
        validAddress(from) 
    {
        if (msg.value != amount) revert("cBTC amount mismatch");
        
        totalFeesCollected += amount;
        emit FeeCollected(amount, from);
    }

    /**
     * @dev Withdraw collected fees to fee recipient
     * @param amount Amount to withdraw (0 = withdraw all)
     */
    function withdrawFees(uint256 amount) 
        external 
        onlyOwner 
        nonReentrant 
    {
        uint256 withdrawAmount = amount;
        uint256 balance = address(this).balance;
        
        if (withdrawAmount == 0) withdrawAmount = balance;
        if (withdrawAmount > balance) revert InsufficientBalance();
        
        (bool success, ) = payable(feeRecipient).call{value: withdrawAmount}("");
        if (!success) revert TransferFailed();
        
        emit FeeWithdrawn(withdrawAmount, feeRecipient);
    }

    /**
     * @dev Emergency withdraw to owner (in case fee recipient is compromised)
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(uint256 amount) 
        external 
        onlyOwner 
        nonReentrant 
        validAmount(amount) 
    {
        if (amount > address(this).balance) revert InsufficientBalance();
        
        (bool success, ) = payable(owner()).call{value: amount}("");
        if (!success) revert TransferFailed();
        
        emit FeeWithdrawn(amount, owner());
    }

    /**
     * @dev Authorize or deauthorize a contract to send fees
     * @param contractAddr Contract address
     * @param authorized Whether the contract is authorized
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
     * @dev Update fee recipient address
     * @param _feeRecipient New fee recipient address
     */
    function setFeeRecipient(address _feeRecipient) 
        external 
        onlyOwner 
        validAddress(_feeRecipient) 
    {
        address oldRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(oldRecipient, _feeRecipient);
    }

    // View functions

    /**
     * @dev Get treasury balance in cBTC
     * @return Current balance
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Get total fees collected
     * @return Total fees collected in cBTC
     */
    function getTotalFeesCollected() external view returns (uint256) {
        return totalFeesCollected;
    }

    // Receive function to accept cBTC fees
    receive() external payable {
        // Only accept cBTC from authorized contracts
        if (!authorizedContracts[msg.sender]) revert Unauthorized();
        totalFeesCollected += msg.value;
        emit FeeCollected(msg.value, msg.sender);
    }

    // Fallback function
    fallback() external payable {
        revert("Function not found");
    }
} 