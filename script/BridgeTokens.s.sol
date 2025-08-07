// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BridgeTokensScript is Script {
    function run(
        address receiverAddress,         // Address receiving tokens on the destination chain
        uint64 destinationChainSelector, // CCIP selector for the destination chain
        address tokenToSendAddress,      // Address of the ERC20 token being bridged
        uint256 amountToSend,            // Amount of the token to bridge
        address linkTokenAddress,        // Address of the LINK token (for fees) on the source chain
        address routerAddress            // Address of the CCIP Router on the source chain
    ) public {

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: tokenToSendAddress, // The address of the token being sent
            amount: amountToSend       // The amount of the token to send
        });

        vm.startBroadcast();

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverAddress), // Receiver address MUST be abi.encode()'d
            data: "",                             // Empty bytes as we are sending no data payload
            tokenAmounts: tokenAmounts,           // The array of token transfers defined above
            feeToken: linkTokenAddress,           // Address of the token used for CCIP fees (LINK)
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})) // Encoded extra arguments
        });

        // Cast routerAddress to IRouterClient to call its functions
        uint256 ccipFee = IRouterClient(routerAddress).getFee(destinationChainSelector, message);

        // Approve the CCIP Router to spend the fee token (LINK)
        IERC20(linkTokenAddress).approve(routerAddress, ccipFee);
        
        // Approve the CCIP Router to spend the token being bridged
        IERC20(tokenToSendAddress).approve(routerAddress, amountToSend);

        // Call ccipSend on the router
        IRouterClient(routerAddress).ccipSend(destinationChainSelector, message);

        vm.stopBroadcast();
    }
}