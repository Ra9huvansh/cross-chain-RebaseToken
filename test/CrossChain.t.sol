// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console } from "forge-std/Test.sol";
import { RebaseToken } from "../src/RebaseToken.sol";
import { RebaseTokenPool } from "../src/RebaseTokenPool.sol";
import { Vault } from "../src/Vault.sol";
import { IRebaseToken } from "../src/interfaces/IRebaseToken.sol";
import { IERC20 } from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import { TokenPool } from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";

// Import the Chainlink Local simulator
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";

import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";

import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";

import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";

import { IRouterClient } from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { CCIPReceiver } from "@ccip/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";


contract CrossChainTest is Test {
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;
    Vault vault; //Vault will only be on the source chain (Sepolia)

    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbSepoliaPool;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    address owner = makeAddr("owner");
    address user = makeAddr("user");

    function setUp() public {
        // 1. Create and select the initial(source) fork (Sepolia)
        // This uses the "sepolia" alias defined in foundry.toml
        sepoliaFork = vm.createSelectFork("sepolia");

        // 2. Create the destination fork (Arbitrum Sepolia) but don't select it yet
        // This uses the "arb-sepolia" alias defined in foundry.toml
        arbSepoliaFork = vm.createFork("arb-sepolia");

        // 3. Deploy the CCIP Local Simulator contract
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();

        // 4. Make the simulator's address persistent across all active forks 
        // This is crucial so both the Sepolia and Arbitrum Sepolia forks
        // can interact with the *same* instance of the simulator.
        vm.makePersistent(address(ccipLocalSimulatorFork));

        /*//////////////////////////////////////////////////////////////
                           SEPOLIA DEPLOYMENTS
        //////////////////////////////////////////////////////////////*/

        vm.startPrank(owner); // All subsequent call will be from 'onwer'

        sepoliaToken = new RebaseToken();

        vault = new Vault(IRebaseToken(address(sepoliaToken))); // Pass the Sepolia token address, cast to IRebaseToken

        vm.stopPrank(); // Crucial to stop impersonating the owner

        /*//////////////////////////////////////////////////////////////
                          ARBITRUM DEPLOYMENTS
        //////////////////////////////////////////////////////////////*/

        vm.selectFork(arbSepoliaFork); // Switch to the Arbitrum Sepolia fork

        vm.startPrank(owner); // Impersonate owner for deployment on Arbitrum Sepolia

        arbSepoliaToken = new RebaseToken(); // Deploy RebaseToken on Arbitrum Sepolia

        vm.stopPrank(); // Stop impersonating

        /*//////////////////////////////////////////////////////////////
                         FETCHING NETWORK DETAILS
        //////////////////////////////////////////////////////////////*/

        // Select Sepolia Fork
        vm.selectFork(sepoliaFork);
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        // Select Arbitrum Sepolia Fork
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid); 

        /*//////////////////////////////////////////////////////////////
                         INSTANTIATING TOKENPOOL
        //////////////////////////////////////////////////////////////*/

        vm.selectFork(sepoliaFork); 
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),                     // Empty allowlist
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        vm.selectFork(arbSepoliaFork); 
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),    
            new address[](0),                     // Empty allowlist
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );

        /*//////////////////////////////////////////////////////////////
                       GRANTING MINT AND BURN ACCESS
        //////////////////////////////////////////////////////////////*/

        // On Sepolia fork
        vm.selectFork(sepoliaFork);
        vm.startPrank(owner); // Assuming 'owner' is the deployer and owner of sepoliaToken
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
        vm.stopPrank();
        
        // On Arbitrum Sepolia fork
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner); // Assuming 'owner' is the deployer and owner of arbSepoliaToken
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));
        vm.stopPrank();

        /*//////////////////////////////////////////////////////////////////
        CLAIMING TOKEN ADMININSTRATOR ROLE THROUGH REGISTER ADMIN VIA OWNER
        //////////////////////////////////////////////////////////////////*/

        // On Sepolia Fork
        vm.selectFork(sepoliaFork);
        vm.startPrank(owner);
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress)
        .registerAdminViaGetCCIPAdmin(address(sepoliaToken));
        vm.stopPrank();

        // On Arbitrum Sepolia Fork
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
        .registerAdminViaGetCCIPAdmin(address(arbSepoliaToken));
        vm.stopPrank();

        /*//////////////////////////////////////////////////////////////
                 ACCEPTING TOKEN ADMINISTRATOR OR ADMIN ROLE
        //////////////////////////////////////////////////////////////*/

        // On Sepolia fork
        vm.selectFork(sepoliaFork);
        vm.startPrank(owner);
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
        .acceptAdminRole(address(sepoliaToken));
        vm.stopPrank();
        
        // On Arbitrum Sepolia fork
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
        .acceptAdminRole(address(arbSepoliaToken));
        vm.stopPrank();

        /*//////////////////////////////////////////////////////////////
                        LINK TOKEN TO POOL VIA ADMIN
        //////////////////////////////////////////////////////////////*/

        // On Sepolia fork
        vm.selectFork(sepoliaFork);
        vm.startPrank(owner);
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
        .setPool(address(sepoliaToken), address(sepoliaPool));
        vm.stopPrank();
        
        // On Arbitrum Sepolia fork
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(owner);
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress)
        .setPool(address(arbSepoliaToken), address(arbSepoliaPool));
        vm.stopPrank();


        /*//////////////////////////////////////////////////////////////
                   ACTIVATING CROSS-CHAIN COMMUNICATION
        //////////////////////////////////////////////////////////////*/

        // Configure Sepolia Pool to interact with Arbitrum Sepolia Pool
        configureTokenPool(
            sepoliaFork,                            // Local chain: Sepolia
            address(sepoliaPool),                   // Local pool: Sepolia's TokenPool
            arbSepoliaNetworkDetails.chainSelector, // Remote chain selector: Arbitrum Sepolia's
            address(arbSepoliaPool),                // Remote pool address: Arbitrum Sepolia's TokenPool
            address(arbSepoliaToken)                // Remote token address: Arbitrum Sepolia's Token
        );
        
        // Configure Arbitrum Sepolia Pool to interact with Sepolia Pool
        configureTokenPool(
            arbSepoliaFork,                         // Local chain: Arbitrum Sepolia
            address(arbSepoliaPool),                // Local pool: Arbitrum Sepolia's TokenPool
            sepoliaNetworkDetails.chainSelector,    // Remote chain selector: Sepolia's
            address(sepoliaPool),                   // Remote pool address: Sepolia's TokenPool
            address(sepoliaToken)                   // Remote token address: Sepolia's Token
        );
    }





    // owner, sepoliaFork, arbSepoliaFork, sepoliaPool, arbSepoliaPool,
    // sepoliaToken, arbSepoliaToken, sepoliaNetworkDetails, arbSepoliaNetworkDetails
    // are assumed to be defined elsewhere in your test setup.

    function configureTokenPool(
        uint256 forkId, // The fork ID of the local chain
        address localPoolAddress, // Address of the pool being configured
        uint64 remoteChainSelector, // Chain selector of the remote chain
        address remotePoolAddress, // Address of the pool on the remote chain
        address remoteTokenAddress // Address of the token on the remote chain
    ) public {
        // 1. Select the correct fork (local chain context)
        vm.selectFork(forkId);

        // 2. Prepare arguments for applyChainUpdates
        // An empty array as we are only adding, not removing.
        // uint64[] memory remoteChainSelectorsToRemove = new uint64[](0);

        // Construct the chainsToAdd array (with one ChainUpdate struct)
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        // The remote pool address needs to be ABI-encoded as bytes.
        // CCIP expects an array of remote pool addresses, even if there's just one primary.
        bytes[] memory remotePoolAddressesBytesArray = new bytes[](1);
        remotePoolAddressesBytesArray[0] = abi.encode(remotePoolAddress);

        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(remotePoolAddressesBytesArray), // ABI-encode the array of bytes
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            // For this example, rate limits are disabled.
            // Consult CCIP documentation for production rate limit configurations.
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            })
        });

        // 3. Execute applyChainUpdates as the owner
        // applyChainUpdates is typically an owner-restricted function.
        vm.prank(owner); // The 'owner' variable should be the deployer/owner of the localPoolAddress
        TokenPool(localPoolAddress).applyChainUpdates(
            // remoteChainSelectorsToRemove,
            chainsToAdd 
        );
    }


    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork, // Source chain fork ID
        uint256 remoteFork, // Destination chain fork ID
        Register.NetworkDetails memory localNetworkDetails, // Struct with source chain info
        Register.NetworkDetails memory remoteNetworkDetails, // Struct with dest. chain info
        RebaseToken localToken, // Source token contract instance
        RebaseToken remoteToken // Destination token contract instance
    ) public {

        vm.selectFork(localFork);

        vm.startPrank(user);
        // 1. Initialize tokenAmounts array 
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(localToken), //Token address on the source chain
            amount: amountToBridge
        });

        // 2. Construct the EVM2AnyMessage
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user), // Receiver on the destination chain
            data: "",                   // No additional data payload for the receiver in this example
            tokenAmounts: tokenAmounts, // The tokens and amounts to transfer
            feeToken: localNetworkDetails.linkAddress, // Using LINK as the fee token
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 0}) // Use default gas limit
            )
        });
        vm.stopPrank();

        // 3. Get the CCIP fee
        uint256 fee = IRouterClient(localNetworkDetails.routerAddress).getFee(
            remoteNetworkDetails.chainSelector, // Destination chain ID
            message
        );

        // 4. Fund the user with LINK (for testing via CCIPLocalSimulatorFork)
        // This step is specific to the local simulator
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);

        // 5. Approve LINK for the Router
        vm.prank(user);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);

        // 6. Approve the actual token to be bridged
        vm.prank(user);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);


        // 7. Get user's balance on the local chain BEFORE sending
        uint256 localBalanceBefore = localToken.balanceOf(user);
        
        // 8. Send the CCIP message
        vm.prank(user);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(
            remoteNetworkDetails.chainSelector, // Destination chain ID
            message
        );
        
        // 9. Get user's balance on the local chain AFTER sending and assert
        uint256 localBalanceAfter = localToken.balanceOf(user);
        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge, "Local balance incorrect after send");


        // 10. Simulate message propagation to the remote chain
        vm.warp(block.timestamp + 20 minutes); // Fast-forward time
        
        // 11. Get user's balance on the remote chain BEFORE message processing
        // Ensure vm.selectFork(remoteFork) is called if not handled by switchChainAndRouteMessage
        uint256 remoteBalanceBefore = remoteToken.balanceOf(user);


        // 12. Process the message on the remote chain (using CCIPLocalSimulatorFork)
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);
        
        // 13. Get user's balance on the remote chain AFTER message processing and assert
        uint256 remoteBalanceAfter = remoteToken.balanceOf(user);
        assertEq(remoteBalanceAfter, remoteBalanceBefore + amountToBridge, "Remote balance incorrect after receive");


        // 14. Check interest rates (specific to RebaseToken logic)
        // IMPORTANT: localUserInterestRate should be fetched *before* switching to remoteFork
        // Example: Fetch localUserInterestRate while still on localFork
        vm.selectFork(localFork);
        uint256 localUserInterestRate = localToken.getUserInterestRate(user);
        vm.selectFork(remoteFork); // Switch back if necessary or rely on switchChainAndRouteMessage
        uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(user); // Called on remoteFork
        assertEq(remoteUserInterestRate, localUserInterestRate, "Interest rates do not match");
    }


    function testBridgeAllTokens() public {
        uint256 DEPOSIT_AMOUNT = 1e5; // Using a small, fixed amount for clarity

        // 1. Deposit into Vault on Sepolia
        vm.selectFork(sepoliaFork);
        vm.deal(user, DEPOSIT_AMOUNT); // Give user some ETH to deposit

        vm.prank(user);
        // To send ETH (msg.value) with a contract call in Foundry:
        // Cast contract instance to address, then to payable, then back to contract type. 
        Vault(payable(address(vault))).deposit{value: DEPOSIT_AMOUNT}();

        assertEq(sepoliaToken.balanceOf(user), DEPOSIT_AMOUNT, "User Sepolia token balance after deposit incorrect");


        // 2. Bridge Tokens: Sepolia -> Arbitrum Sepolia
        bridgeTokens (
            DEPOSIT_AMOUNT,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );

        // Assertions for this step are within bridgeTokens

        // 3. Bridge All Tokens Back: Arbitrum Sepolia -> Sepolia
        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 20 minutes); // Advance time on Arbitrum Sepolia before bridging back

        uint256 arbBalanceToBridgeBack = arbSepoliaToken.balanceOf(user);

        assertTrue(arbBalanceToBridgeBack > 0, "User Arbitrum balance should be non-zero before bridgin back");

        bridgeTokens (
            arbBalanceToBridgeBack,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            arbSepoliaToken,
            sepoliaToken
        );

        // Final state check: User on Sepolia should have their initial deposit back
        // (minus any very small precision differences if applicable to tokenomics, or fees not covered by faucet)
        vm.selectFork(sepoliaFork);
        // Note: Exact final balance might depend on tokenomics if any fees were burnt from principal. 
        // For this example, assume full amount returns 
        assertEq(sepoliaToken.balanceOf(user), DEPOSIT_AMOUNT, "User Sepolia token balance after bridging back incorrect"); 
        
    }

}