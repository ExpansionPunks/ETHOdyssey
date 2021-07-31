// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import "@superfluid-finance/ethereum-contracts/contracts/interfaces/misc/IResolver.sol";
import {ISuperAgreement, SuperAppDefinitions, ISuperfluid, ISuperToken, ISuperTokenFactory} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {ERC20WithTokenInfo, TokenInfo} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ERC20WithTokenInfo.sol";

contract YourContract is SuperAppBase {
    ISuperfluid private _host; // host
    IConstantFlowAgreementV1 private _cfa; // the stored constant flow agreement class address
    ISuperToken private _acceptedToken; // accepted token
    address private _receiver;
    ISuperToken private _sodaToken;

    constructor(
        ISuperfluid host,
        IConstantFlowAgreementV1 cfa,
        ISuperToken acceptedToken,
        ISuperToken sodaToken
    ) {
        assert(address(host) != address(0));
        assert(address(cfa) != address(0));
        assert(address(acceptedToken) != address(0));
        assert(address(sodaToken) != address(0));
        _host = host;
        _cfa = cfa;
        _acceptedToken = acceptedToken;
        _sodaToken = sodaToken;
        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;
        _host.registerApp(configWord);
    }

    /**************************************************************************
     Managing Payroll
     *************************************************************************/

    struct EntityStruct {
        uint256 entityData;
        bool isEntity;
    }

    mapping(address => EntityStruct) public entityStructs;
    uint256 currentEntityCount;

    function isEntity(address entityAddress)
        public
        view
        returns (bool isIndeed)
    {
        return entityStructs[entityAddress].isEntity;
    }

    function numberOfEntitie() public view returns (uint256 entityCount) {
        return currentEntityCount;
    }

    function newEntity(address entityAddress, uint256 entityData)
        public
        returns (bool success)
    {
        if (isEntity(entityAddress)) revert();
        entityStructs[entityAddress].entityData = entityData;
        entityStructs[entityAddress].isEntity = true;
        currentEntityCount = currentEntityCount + 1;
        return true;
    }

    function deleteEntity(address entityAddress) public returns (bool success) {
        if (!isEntity(entityAddress)) revert();
        entityStructs[entityAddress].isEntity = false;
        currentEntityCount = currentEntityCount - 1;
        return true;
    }

    function updateEntity(address entityAddress, uint256 entityData)
        public
        returns (bool success)
    {
        if (!isEntity(entityAddress)) revert();
        entityStructs[entityAddress].entityData = entityData;
        return true;
    }

    /**************************************************************************
     * SatisfyFlows Logic
     *************************************************************************/
    /// @dev If a new stream is opened, or an existing one is opened
    function _updateOutflow(
        bytes calldata ctx,
        address customer,
        bytes32 agreementId
    ) private returns (bytes memory newCtx) {
        newCtx = ctx;
        (, int96 inFlowRate, , ) = _cfa.getFlowByID(
            _acceptedToken,
            agreementId
        );
        (, int96 outFlowRate, , ) = _cfa.getFlow(
            _sodaToken,
            address(this),
            customer
        );
        if (inFlowRate < 0) inFlowRate = -inFlowRate; // Fixes issue when inFlowRate is negative

        if (outFlowRate != int96(0)) {
            // @dev if there already exists an outflow, then update it.
            (newCtx, ) = _host.callAgreementWithContext(
                _cfa,
                abi.encodeWithSelector(
                    _cfa.updateFlow.selector,
                    _sodaToken,
                    customer,
                    inFlowRate,
                    new bytes(0) // placeholder
                ),
                "0x",
                newCtx
            );
        } else if (inFlowRate == int96(0)) {
            // @dev if inFlowRate is zero, delete outflow.
            (newCtx, ) = _host.callAgreementWithContext(
                _cfa,
                abi.encodeWithSelector(
                    _cfa.deleteFlow.selector,
                    _sodaToken,
                    address(this),
                    customer,
                    new bytes(0) // placeholder
                ),
                "0x",
                newCtx
            );
        } else {
            // @dev If there is no existing outflow, then create new flow to equal inflow
            (newCtx, ) = _host.callAgreementWithContext(
                _cfa,
                abi.encodeWithSelector(
                    _cfa.createFlow.selector,
                    _sodaToken,
                    customer,
                    inFlowRate,
                    new bytes(0) // placeholder
                ),
                "0x",
                newCtx
            );
        }
    }

    /**************************************************************************
     * SuperApp callbacks
     *************************************************************************/
    function afterAgreementCreated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 _agreementId,
        bytes calldata, /*_agreementData*/
        bytes calldata, // _cbdata,
        bytes calldata _ctx
    )
        external
        override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory newCtx)
    {
        address customer = _host.decodeCtx(_ctx).msgSender;
        return _updateOutflow(_ctx, customer, _agreementId);
    }

    function afterAgreementUpdated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 _agreementId,
        bytes calldata, /*_agreementData*/
        bytes calldata, //_cbdata,
        bytes calldata _ctx
    )
        external
        override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory newCtx)
    {
        address customer = _host.decodeCtx(_ctx).msgSender;
        return _updateOutflow(_ctx, customer, _agreementId);
    }

    function afterAgreementTerminated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 _agreementId,
        bytes calldata _agreementData,
        bytes calldata, //_cbdata,
        bytes calldata _ctx
    ) external override onlyHost returns (bytes memory newCtx) {
        // According to the app basic law, we should never revert in a termination callback
        if (!_isSameToken(_superToken) || !_isCFAv1(_agreementClass))
            return _ctx;
        (address customer, ) = abi.decode(_agreementData, (address, address));
        return _updateOutflow(_ctx, customer, _agreementId);
    }

    function getNetFlow() public view returns (int96) {
        return _cfa.getNetFlow(_acceptedToken, address(this));
    }

    function _isSameToken(ISuperToken superToken) private view returns (bool) {
        return address(superToken) == address(_acceptedToken);
    }

    function _isCFAv1(address agreementClass) private view returns (bool) {
        return
            ISuperAgreement(agreementClass).agreementType() ==
            keccak256(
                "org.superfluid-finance.agreements.ConstantFlowAgreement.v1"
            );
    }

    modifier onlyHost() {
        require(
            msg.sender == address(_host),
            "SatisfyFlows: support only one host"
        );
        _;
    }
    modifier onlyExpected(ISuperToken superToken, address agreementClass) {
        require(_isSameToken(superToken), "SatisfyFlows: not accepted token");
        require(_isCFAv1(agreementClass), "SatisfyFlows: only CFAv1 supported");
        _;
    }
}
