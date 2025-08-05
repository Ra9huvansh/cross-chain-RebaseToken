//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
 
import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RebaseTokenTest is Test {

    error RebaseTokenTest__PaymentFailed();

    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public user2 = makeAddr("user2");

    uint256 public constant MIN_TRANSACTION_AMOUNT = 1e5;
    uint256 public constant MAX_DEPOSIT_AMOUNT = type(uint96).max;
    uint256 public constant NEW_INTEREST_RATE = 4e10;
    uint256 public constant STARTING_BALANCE = 100 ether;

    function setUp() public {
        //Impersonate the 'owner' address for deployments and role granting
        vm.startPrank(owner);

        rebaseToken = new RebaseToken();

        // Deploy Vault: requires IRebaseToken.
        // Direct casting (IRebaseToken(rebaseToken)) is not allowed.
        // Correct way: cast rebaseToken to address, then to IRebaseToken.
        vault = new Vault(IRebaseToken(address(rebaseToken)));

        // Grant the MINT_AND_BURN_ROLE to the Vault contract
        // The grantMintAndBurnRole function expects an address.
        rebaseToken.grantMintAndBurnRole(address(vault));

        // Send 1 ETH to the Vault to simulate initial funds.
        // The target address must be cast to 'payable'.
        (bool success, ) = payable(address(vault)).call{value: 1 ether}("");
        // It's good practice to handle the success flag, though omitted for brevity here. 

        //Stop impersonating the 'owner'
        vm.stopPrank();
    }

    // Test if interest accrues linearly after a deposit
    // 'amount' will be a fuzzed input
    function testIfInterestAccruesLinearly(uint256 amount) public {
        // Constrain the fuzzed 'amount' to a practical range. 
        // Min: 0.00001 ETH (1e5 wei), Max: type(uint96).max to avoid overflows
        amount = bound(amount, MIN_TRANSACTION_AMOUNT, MAX_DEPOSIT_AMOUNT);

        // I. User deposits 'amount' ETH
        vm.startPrank(user); //Actions performed as 'user'
        vm.deal(user, amount); //Give 'user' the 'amount' of ETH to deposit

        // 1. TODO: Implement deposit logic:
        vault.deposit{value: amount}();

        // 2. TODO: Check initial rebase token balance for 'user'
        uint256 initialBalance = rebaseToken.balanceOf(user);

        // 3. TODO: Warp time forward and check balance again
        uint256 timeDelta = 1 days;
        vm.warp(block.timestamp + timeDelta);
        uint256 balanceAfterFirstWarp = rebaseToken.balanceOf(user);
        uint256 interestFirstPeriod = balanceAfterFirstWarp - initialBalance;

        // 4. TODO: Warp time forward by the same amount and check balance again
        vm.warp(block.timestamp + timeDelta);
        uint256 balanceAfterSecondWarp = rebaseToken.balanceOf(user);
        uint256 interestSecondPeriod = balanceAfterSecondWarp - balanceAfterFirstWarp;

        // 5. TODO: Assert that interestFirstPeriod == interestSecondPeriod
        assertApproxEqAbs(interestFirstPeriod, interestSecondPeriod, 1);

        vm.stopPrank(); // Stop impersonating 'user'

    }

    function testRedeemStraightAway(uint256 amount) public {

        amount = bound(amount, MIN_TRANSACTION_AMOUNT, MAX_DEPOSIT_AMOUNT);

        vm.startPrank(user);
        vm.deal(user, amount);

        vault.deposit{value: amount}();
        vault.redeem(MAX_DEPOSIT_AMOUNT);

        uint256 balanceAfterRedeem = rebaseToken.balanceOf(user);
        assertApproxEqAbs(balanceAfterRedeem, 0, 1);

        uint256 userBalance = address(user).balance;
        assertApproxEqAbs(userBalance, amount, 1);

        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        // send some rewards to the vault using the receive function 
        (bool success, ) = payable(address(vault)).call{value: rewardAmount}("");
        require(success, "Rewards transfer failed");
    }

    function testRedeemAfterTimeHasPassed(uint256 depositAmount, uint256 time) public {
        depositAmount = bound(depositAmount, MIN_TRANSACTION_AMOUNT, MAX_DEPOSIT_AMOUNT);
        time = bound(time, 1000, MAX_DEPOSIT_AMOUNT); // this is crazy number of years (in trillions)!

        vm.startPrank(user);
        vm.deal(user, depositAmount);
        vault.deposit{value: depositAmount}();
        vm.stopPrank();

        vm.warp(block.timestamp + time); 
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);

        uint256 rewardAmount = balanceAfterSomeTime - depositAmount;

        // Fund the vault from a rich address (like owner)
        vm.deal(owner, rewardAmount);
        vm.prank(owner);
        addRewardsToVault(rewardAmount);

        // Now test redeem
        vm.startPrank(user);
        uint256 userInitialBalance = address(user).balance;
        vault.redeem(MAX_DEPOSIT_AMOUNT); // redeem all
        uint256 userFinalBalance = address(user).balance;
        vm.stopPrank();

        uint256 received = userFinalBalance - userInitialBalance;
        assertGt(received, depositAmount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, MIN_TRANSACTION_AMOUNT, MAX_DEPOSIT_AMOUNT);
        
        // Global interest rate reduced to 4e10 by owner.
        vm.prank(owner);
        rebaseToken.setInterestRate(NEW_INTEREST_RATE);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        amountToSend = bound(amountToSend, MIN_TRANSACTION_AMOUNT, rebaseToken.balanceOf(user));

        uint256 initialUserBalance = rebaseToken.balanceOf(user);
        rebaseToken.transfer(user2, amountToSend);
        uint256 finalUserBalance = rebaseToken.balanceOf(user);

        vm.stopPrank();

        assertApproxEqAbs(finalUserBalance, initialUserBalance - amountToSend, 1);
        assertApproxEqAbs(rebaseToken.balanceOf(user2), amountToSend, 1);
        assertEq(rebaseToken.getUserInterestRate(user), rebaseToken.getUserInterestRate(user2));

    }

    function testGetPrincipalAmount(uint256 amount) public {
        amount = bound(amount, MIN_TRANSACTION_AMOUNT, MAX_DEPOSIT_AMOUNT);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        assertEq(rebaseToken.principalBalanceOf(user), amount);

        vm.warp(block.timestamp + 7 days);

        assertEq(rebaseToken.principalBalanceOf(user), amount);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(bytes4(Ownable.OwnableUnauthorizedAccount.selector));
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testCannotCallMintAndBurn() public {
        vm.prank(user);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.mint(user, 1 ether, rebaseToken.getInterestRate());

        vm.startPrank(user);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.burn(user, 1 ether); // Assuming user has some balance to burn for this part
        vm.stopPrank();
    }
} 