// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console } from "forge-std/Test.sol";
import { RebaseToken } from "../src/RebaseToken.sol";
import { RebaseTokenPool } from "../src/RebaseTokenPool.sol";
import { Vault } from "../src/Vault.sol";
import { IRebaseToken } from "../src/interfaces/IRebaseToken.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

// Import the Chainlink Local simulator
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";

import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";

import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";

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


        // Select Sepolia Fork
        vm.selectFork(sepoliaFork);
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        // Select Arbitrum Sepolia Fork
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid); 


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
    }
}