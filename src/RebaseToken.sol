//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title RebaseToken
 * @author Raghuvansh Rastogi
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease.
 * @notice Each user will have their own interest rate that is the global interest rate at the time of deposit.
 */
contract RebaseToken is ERC20{

    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private constant PRECISION_FACTOR = 1e18;

    uint256 private s_interestRate = 5e10;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") {
        //We will handle initial minting later, so this remains empty for now.
    }

    /**
     * @notice Set the global interest rate for the contract.
     * @param _newInterestRate The new interest rate to set(scaled by PRECISION_FACTOR basis points per second). 
     * @dev The interest rate can only decrease. Access control(e.g., onlyOwner) should be added.   
     */
    function setInterestRate(uint256 _newInterestRate) external { //TODO: Add access control
        if(_newInterestRate > s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Gets the locked-in interest rate for a specific user.
     * @param _user The address of the user.
     * @return The user's specific interest rate.
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
     * @notice Mints tokens to a user, typically upon deposit,
     * @dev Also mints accrued interest and locks in the current global rate for the user.
     * @param _to The address to mint tokens to
     * @param _amount The principal amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) external { //TODO: Add access control (e.g., onlyVault)
        _mintAccruedInterest(_to); //Step 1: Mint any existing accrued interest for the user

        //Step 2: Update the user's interest rate for future calculations if necessary
        //This assumes s_interestRate is the current global interest rate.
        //If the user already has a deposit, their rate might be updated.
        s_userInterestRate[_to] = s_interestRate;

        //Step 3: Mint the newly deposited amount
        _mint(_to, _amount);
    }

    /**
     * @dev Internal function to calculate and mint accrued interest for a user.
     * @dev Updates the user's last updated timestamp.
     * @param _user The address of the user.
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find their current balance of rebase tokens that have been minted to the user -> principle balance
        uint256 previousPrincipleBalance = super.balanceOf(_user);

        // (2) calculate their current balance including any interest -> balanceOf
        uint256 currentBalance = balanceOf(_user);

        // calculate the number of tokens that need to be minted to the user -> (2) - (1)
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;

        // set the users last updated timestamp (Effect)
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        
        // Mint the accrued interest (Interaction)
        if (balanceIncrease > 0) { // Optimization: only mint if there's interest
            _mint(_user, balanceIncrease);
        }
    }

    /**
     * @notice Returns the current balance of an account, including accrued interest.
     * @param _user The address of the account.
     * @return The total balance of including interest
     */
    function balanceOf(address _user) public view override returns (uint256) {
        //Get the user's stored principal balance (tokens actually minted to them)
        uint256 principalBalance = super.balanceOf(_user);
        
        //Calculate the growth factor based on accrued interest.
        uint256 growthFactor = _calculateUserAccumulatedInterestSinceLastUpdate(_user);

        //Apply the growth factor to the principal balance.
        //Remember PRECISION_FACTOR is used for scaling, so we divide by it here.
        return (principalBalance * growthFactor) / PRECISION_FACTOR;
    }

    /**
     * @notice Calculates the growth factor due to accumulated interest since the user's last update.
     * @param _user The address of the user.
     * @return The growth factor, scaled by PRECISION_FACTOR. (e.g., 1.05x growth is 1.05*1e18).
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns (uint256) {
        //1. Calculate the time elapsed since the user's balance was last effectively updated.
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];

        //If no time has passed, or if the user has no locked rate (e.g., never interacted),
        //the growth factor is simply 1 (scaled by PRECISION_FACTOR).
        if(timeElapsed == 0 || s_userInterestRate[_user] == 0) {
            return PRECISION_FACTOR;
        }

        //2. Calculate the total fractional interest accrued: UserInterestRate * TimeElapsed.
        //s_userInterestRate[_user] is the rate per second.
        //This product is already scaled appropriately is s_userInterestRate is stored scaled.
        uint256 fractionalInterest = s_userInterestRate[_user] * timeElapsed;

        //3. The growth factor is (1 + fractional_interest_part).
        //Since '1' is represented as PRECISION_FACTOR, and the fractionalInterest is already scaled, we add them.
        uint256 linearInterestFactor = PRECISION_FACTOR + fractionalInterest;
        return linearInterestFactor;
    }

    /**
     * @notice Burn the user tokens, e.g., when they withdraw from a vault or for cross-chain transfers.
     * Handles burning the entire balance if _amount is type(uint256).max.
     * @param _from The user address from which to burn tokens.
     * @param _amount The amount of tokens to burn. Use type(uint256).max to burn all tokens.
     */ 
    function burn(address _from, uint256 _amount) external { //Acess control to be added as needed
        uint256 currentTotalBalance = balanceOf(_from); //Calculate this once for efficiency if needed for checks

        if(_amount == type(uint256).max) {
            _amount = currentTotalBalance; //Set amount to full current balance
        }

        // Ensure _amount does not exceed actual balance after potential interest accrual
        // This check is important especially if _amount wasn't type(uint256).max
        // _mintAccruedInterest will update the super.balanceOf(_from)
        // So, after _mintAccruedInterest, super.balanceOf(_from) should be currentTotalBalance
        // The ERC20 _burn function will typically revert if _amount > super.balanceOf(_from)

        _mintAccruedInterest(_from); // Mint any accrued interest first

        // At this point, super.balanceOf(_from) reflects the balance including all interest up to now.
        // If _amount was type(uint256).max, then _amount == super.balanceOf(_from)
        // If _amount was specific, super.balanceOf(_from) >= _amount for _burn to succeed.

        _burn(_from, _amount);
    }
}