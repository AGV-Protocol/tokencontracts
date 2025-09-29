// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title GVT (Green Value Token)
 * @notice Governance and utility token for AGV Protocol
 * @dev Fixed supply of 1,000,000,000 tokens
 * Features:
 * - Capped at 1B total supply
 * - Burnable for deflationary mechanics
 * - EIP-2612 permit for gasless approvals
 * - Role-based minting (restricted to DAO/Buyback modules)
 * - Pausable for emergency situations
 */
contract GVT is ERC20, ERC20Burnable, ERC20Permit, AccessControl, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18; // 1 billion tokens
    uint256 public totalMinted;
    
    // Allocation tracking for transparency
    struct Allocation {
        uint256 amount;
        uint256 released;
        uint256 vestingStart;
        uint256 vestingDuration;
    }
    
    mapping(address => Allocation) public allocations;
    
    event AllocationSet(address indexed beneficiary, uint256 amount, uint256 vestingDuration);
    event TokensReleased(address indexed beneficiary, uint256 amount);
    
    constructor(address admin) ERC20("Green Value Token", "GVT") ERC20Permit("Green Value Token") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }
    
    /**
     * @notice Set vesting allocation for a beneficiary
     * @param beneficiary Address to receive vested tokens
     * @param amount Total amount to vest
     * @param vestingDuration Duration in seconds
     */
    function setAllocation(
        address beneficiary,
        uint256 amount,
        uint256 vestingDuration
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(totalMinted + amount <= MAX_SUPPLY, "Exceeds max supply");
        require(allocations[beneficiary].amount == 0, "Allocation already set");
        
        allocations[beneficiary] = Allocation({
            amount: amount,
            released: 0,
            vestingStart: block.timestamp,
            vestingDuration: vestingDuration
        });
        
        totalMinted += amount;
        
        emit AllocationSet(beneficiary, amount, vestingDuration);
    }
    
    /**
     * @notice Release vested tokens to beneficiary
     */
    function releaseVested() external {
        Allocation storage alloc = allocations[msg.sender];
        require(alloc.amount > 0, "No allocation");
        
        uint256 releasable = _releasableAmount(alloc);
        require(releasable > 0, "No tokens to release");
        
        alloc.released += releasable;
        _mint(msg.sender, releasable);
        
        emit TokensReleased(msg.sender, releasable);
    }
    
    /**
     * @notice Calculate releasable amount for an allocation
     */
    function _releasableAmount(Allocation memory alloc) private view returns (uint256) {
        if (block.timestamp < alloc.vestingStart) {
            return 0;
        }
        
        uint256 elapsed = block.timestamp - alloc.vestingStart;
        
        if (elapsed >= alloc.vestingDuration) {
            return alloc.amount - alloc.released;
        }
        
        uint256 vested = (alloc.amount * elapsed) / alloc.vestingDuration;
        return vested - alloc.released;
    }
    
    /**
     * @notice Mint tokens (restricted to MINTER_ROLE)
     * @dev Used by BondingCurve contract for rGGP conversions
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
    }
    
    /**
     * @notice Pause token transfers
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @notice Unpause token transfers
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    /**
     * @dev Override to add pausable functionality
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
    
    /**
     * @notice Get releasable amount for a beneficiary
     */
    function releasableAmount(address beneficiary) external view returns (uint256) {
        return _releasableAmount(allocations[beneficiary]);
    }
}