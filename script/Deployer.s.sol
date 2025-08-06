//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from  "forge-std/Script.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";


contract TokenAndPoolDeployer is Script {
    function run() external returns (RebaseToken token, RebaseTokenPool pool) {
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        // The Register.NetworkDetails struct holds crucial addresses for CCIP components.
        // It must be stored in memory.
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startBroadcast();

        token = new RebaseToken();
        pool = new RebaseTokenPool(
            IERC20(address(token)),         // The deployed token address
            new address[](0),               // Empty allowlist
            networkDetails.rmnProxyAddress, // RMN Proxy address from simulator
            networkDetails.routerAddress    // Router address from simulator
        );

        token.grantMintAndBurnRole(address(pool));
        
        RegistryModuleOwnerCustom(networkDetails.registryModuleOwnerCustomAddress)
        .registerAdminViaGetCCIPAdmin(address(token));
        
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress)
        .acceptAdminRole(address(token));

        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress)
        .setPool(address(token), address(pool));

        vm.stopBroadcast();
    }
}

contract VaultDeployer is Script {

    function run(address _rebaseToken) external returns (Vault vault){
        vm.startBroadcast();
        vault = new Vault(IRebaseToken(_rebaseToken));
        IRebaseToken(_rebaseToken).grantMintAndBurnRole(address(vault));
        vm.stopBroadcast();
        // Foundry implicitly returns the 'vault' instance here
    }
}

