// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ISemver } from "src/universal/ISemver.sol";
import { SuperchainConfig } from "src/L1/SuperchainConfig.sol";

/// @title DelayedVetoable
/// @notice This contract enables a delay before a call is forwarded to a target contract, and during the delay period
///         the call can be vetoed by the authorized vetoer.
///         This contract does not support value transfers, only data is forwarded.
///         Additionally, this contract cannot be used to forward calls with data beginning with the function selector
///         of the queuedAt(bytes32) function. This is because of input validation checks which solidity performs at
///         runtime on functions which take an argument.
contract DelayedVetoable is ISemver {
    /// @notice Error for when the delay has already been set.
    error AlreadyDelayed();

    /// @notice Error for when attempting to forward too early.
    error ForwardingEarly();

    /// @notice Error for the target is not set.
    error TargetUnitialized();

    /// @notice Error for unauthorized calls.
    error Unauthorized(address expected, address actual);

    /// @notice An event that is emitted when the delay is activated.
    /// @param delay The delay that was activated.
    event DelayActivated(uint256 delay);

    /// @notice An event that is emitted when a call is initiated.
    /// @param callHash The hash of the call data.
    /// @param data The data of the initiated call.
    event Initiated(bytes32 indexed callHash, bytes data);

    /// @notice An event that is emitted each time a call is forwarded.
    /// @param callHash The hash of the call data.
    /// @param data The data forwarded to the target.
    event Forwarded(bytes32 indexed callHash, bytes data);

    /// @notice An event that is emitted each time a call is vetoed.
    /// @param callHash The hash of the call data.
    /// @param data The data forwarded to the target.
    event Vetoed(bytes32 indexed callHash, bytes data);

    /// @notice The target for calls from this contract.
    address internal immutable TARGET;

    /// @notice The superchain config contract.
    SuperchainConfig internal immutable SUPERCHAIN_CONFIG;

    /// @notice The current amount of time to wait before forwarding a call.
    uint256 internal _delay;

    /// @notice The time that a call was initiated.
    mapping(bytes32 => uint256) internal _queuedAt;

    /// @notice A modifier that reverts if not called by the vetoer or by address(0) to allow
    ///         eth_call to interact with this proxy without needing to use low-level storage
    ///         inspection. We assume that nobody is able to trigger calls from address(0) during
    ///         normal EVM execution.
    modifier readOrHandle() {
        if (msg.sender == address(0)) {
            _;
        } else {
            // This WILL halt the call frame on completion.
            _handleCall();
        }
    }

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice Sets the target admin during contract deployment.
    /// @param superchainConfig_ Address of the superchain config contract.
    /// @param target_ Address of the target contract.
    constructor(SuperchainConfig superchainConfig_, address target_) {
        SUPERCHAIN_CONFIG = superchainConfig_;
        TARGET = target_;
    }

    /// @notice Gets the initiator
    /// @return initiator_ Initiator address.
    function _initiator() internal returns (address initiator_) {
        initiator_ = SUPERCHAIN_CONFIG.initiator();
    }

    function initiator() external readOrHandle returns (address initiator_) {
        initiator_ = _initiator();
    }

    //// @notice Queries the vetoer address.
    /// @return vetoer_ Vetoer address.
    function _vetoer() internal returns (address vetoer_) {
        vetoer_ = SUPERCHAIN_CONFIG.vetoer();
    }

    function vetoer() external readOrHandle returns (address vetoer_) {
        vetoer_ = _vetoer();
    }

    //// @notice Queries the target address.
    /// @return target_ Target address.
    function _target() internal returns (address target_) {
        target_ = TARGET;
    }

    function target() external readOrHandle returns (address target_) {
        target_ = _target();
    }

    /// @notice Gets the operating delay.
    /// @return operatingDelay_ Delay address.
    function _operatingDelay() internal returns (uint256 operatingDelay_) {
        operatingDelay_ = SUPERCHAIN_CONFIG.delay();
    }

    function operatingDelay() external readOrHandle returns (uint256 operatingDelay_) {
        operatingDelay_ = _operatingDelay();
    }

    /// @notice Gets the SuperchainConfig contract address.
    /// @return superchainConfig_ Address of the SuperchainConfig contract.
    function superchainConfig() external readOrHandle returns (address superchainConfig_) {
        superchainConfig_ = address(SUPERCHAIN_CONFIG);
    }

    /// @notice Gets the delay
    /// @return delay_ Delay value.
    function delay() external readOrHandle returns (uint256 delay_) {
        delay_ = _delay;
    }

    /// @notice Gets entries in the _queuedAt mapping.
    /// @param callHash The hash of the call data.
    /// @return queuedAt_ The time the callHash was recorded.
    function queuedAt(bytes32 callHash) external readOrHandle returns (uint256 queuedAt_) {
        queuedAt_ = _queuedAt[callHash];
    }

    /// @notice Used for all calls that pass data to the contract.
    fallback() external {
        _handleCall();
    }

    /// @notice Receives all calls other than those made by the vetoer.
    ///         This enables transparent initiation and forwarding of calls to the target and avoids
    ///         the need for additional layers of abi encoding.
    function _handleCall() internal {
        // The initiator and vetoer activate the delay by passing in null data.
        if (msg.data.length == 0 && _delay == 0) {
            if (msg.sender != _initiator() && msg.sender != _vetoer()) {
                revert Unauthorized(_initiator(), msg.sender);
            }
            _delay = _operatingDelay();
            emit DelayActivated(_delay);
            return;
        }

        bytes32 callHash = keccak256(msg.data);

        // Case 1: The initiator is calling the contract to initiate a call.
        if (msg.sender == _initiator() && _queuedAt[callHash] == 0) {
            if (_delay == 0) {
                // This forward function will halt the call frame on completion.
                _forwardAndHalt(callHash);
            }
            _queuedAt[callHash] = block.timestamp;
            emit Initiated(callHash, msg.data);
            return;
        }

        // Case 2: The vetoer is calling the contract to veto a call.
        // Note: The vetoer retains the ability to veto even after the delay has passed. This makes censoring the vetoer
        //       more costly, as there is no time limit after which their transaction can be included.
        if (msg.sender == _vetoer() && _queuedAt[callHash] != 0) {
            delete _queuedAt[callHash];
            emit Vetoed(callHash, msg.data);
            return;
        }

        // Case 3: The call is from an unpermissioned actor. We'll forward the call if the delay has
        // passed.
        if (_queuedAt[callHash] == 0) {
            // The call has not been initiated, so we'll treat this is an unauthorized initiation attempt.
            revert Unauthorized(_initiator(), msg.sender);
        }

        if (_queuedAt[callHash] + _delay < block.timestamp) {
            // Not enough time has passed, so we'll revert.
            revert ForwardingEarly();
        }

        // Delete the call to prevent replays
        delete _queuedAt[callHash];
        _forwardAndHalt(callHash);
    }

    /// @notice Forwards the call to the target and halts the call frame.
    function _forwardAndHalt(bytes32 callHash) internal {
        // Forward the call
        emit Forwarded(callHash, msg.data);
        (bool success, bytes memory returndata) = _target().call(msg.data);
        if (success == true) {
            assembly {
                return(add(returndata, 0x20), mload(returndata))
            }
        } else {
            assembly {
                revert(add(returndata, 0x20), mload(returndata))
            }
        }
    }
}
