// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/misc/IResolver.sol";
import {ISuperAgreement, SuperAppDefinitions, ISuperfluid, ISuperToken, ISuperTokenFactory} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {ERC20WithTokenInfo, TokenInfo} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ERC20WithTokenInfo.sol";

import "hardhat/console.sol";

contract YourContract {
    /**************************************************************************
     Fields
     *************************************************************************/
    struct DAOReceiver {
        address receiverAddress;
        uint8 receiverWeight;
    }

    uint8 public totalReceivers;
    uint16 public totalWeight;
    uint8 public burnPercentage;

    uint96 private _secondsPerYear = 31557600;

    function setBurnPercentage(uint8 newPercentage) public {
        require(newPercentage > 0, "Have to give at least something out");
        require(newPercentage < 100, "Can't spend everything");
        burnPercentage = newPercentage;
    }

    mapping(uint8 => DAOReceiver) public payroll;
    mapping(address => uint8) private indices;

    // Superfluid
    ISuperfluid private _host; // host
    IConstantFlowAgreementV1 private _cfa; // the stored constant flow agreement class address
    ISuperToken private _acceptedToken; // accepted token
    address private _receiver;

    constructor(
        ISuperfluid host,
        IConstantFlowAgreementV1 cfa,
        ISuperToken acceptedToken
    ) {
        assert(address(host) != address(0));
        assert(address(cfa) != address(0));
        assert(address(acceptedToken) != address(0));
        _host = host;
        _cfa = cfa;
        _acceptedToken = acceptedToken;

        totalReceivers = 0;
        totalWeight = 0;
    }

    /**************************************************************************
     Treasury
     *************************************************************************/

    function TreasuryBalance() public view returns (int256 balance) {
        (
            int256 availableBalance,
            uint256 deposit,
            uint256 owedDeposit,
            uint256 timestamp
        ) = _acceptedToken.realtimeBalanceOfNow(address(this));
        return availableBalance;
    }

    /**************************************************************************
     Managing Payroll
     *************************************************************************/

    // This functio adds an address to the payroll of the dao
    function addAddressToPayroll(address newAddress, uint8 weight) public {
        DAOReceiver storage newReceiver = payroll[totalReceivers];
        indices[newAddress] = totalReceivers;
        totalReceivers = totalReceivers + 1;
        // check that weight does not get to big and maybe rebalance
        totalWeight = totalWeight + weight;
        newReceiver.receiverAddress = newAddress;
        newReceiver.receiverWeight = weight;
        _createFlow(newAddress, 1);
        recalculateFlow();
    }

    // This function removes an address from the payroll of the dao
    function removeAddressFromPayroll(address removeAddress) public {
        uint8 index = indices[removeAddress]; // get the index of this address
        _deleteFlow(removeAddress);

        DAOReceiver memory removedReceiver = payroll[index];
        totalReceivers = totalReceivers - 1;
        totalWeight = totalWeight - removedReceiver.receiverWeight;
        // if we were not looking at the last one we need to swap
        if (index != totalReceivers) {
            DAOReceiver memory lastReceiver = payroll[totalReceivers];
            payroll[index] = payroll[totalReceivers]; // write down the last recipient
            indices[lastReceiver.receiverAddress] = index; // update our index
        }
        recalculateFlow();
    }

    // we calculate the flow rate per year for everyone on the payroll
    function recalculateFlow() public {
        int256 _balance = TreasuryBalance();
        int256 _yearlyBurnPerWeight = ((_balance / 100) * burnPercentage) /
            totalWeight /
            _secondsPerYear;
        DAOReceiver memory currentReceiver = payroll[0];
        for (uint8 i = 0; i < totalReceivers; i++) {
            _updateFlow(
                currentReceiver.receiverAddress,
                int96((_yearlyBurnPerWeight * currentReceiver.receiverWeight))
            );
            currentReceiver = payroll[i];
        }
    }

    /**************************************************************************
     * Flows Logic
     *************************************************************************/

    function _createFlow(address newReceiver, int96 flowrate) internal {
        _host.callAgreement(
            _cfa,
            abi.encodeWithSelector(
                _cfa.createFlow.selector,
                _acceptedToken,
                newReceiver,
                flowrate,
                new bytes(0)
            ),
            "0x"
        );
    }

    function _updateFlow(address receiver, int96 newFlowrate) internal {
        _host.callAgreement(
            _cfa,
            abi.encodeWithSelector(
                _cfa.updateFlow.selector,
                _acceptedToken,
                receiver,
                newFlowrate,
                new bytes(0)
            ),
            "0x"
        );
    }

    function _deleteFlow(address receiver) internal {
        _host.callAgreement(
            _cfa,
            abi.encodeWithSelector(
                _cfa.deleteFlow.selector,
                _acceptedToken,
                address(this),
                receiver,
                new bytes(0)
            ),
            "0x"
        );
    }
}
