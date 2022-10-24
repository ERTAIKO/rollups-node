// Copyright 2022 Cartesi Pte. Ltd.

// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License"); you may not use
// this file except in compliance with the License. You may obtain a copy of the
// License at http://www.apache.org/licenses/LICENSE-2.0

// Unless required by applicable law or agreed to in writing, software distributed
// under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

/// @title Output Validation Library V1
pragma solidity ^0.8.13;

import {CanonicalMachine} from "../common/CanonicalMachine.sol";
import {Merkle} from "@cartesi/util/contracts/Merkle.sol";

/// @param epochInputIndex which input, in the epoch, the output belongs to
/// @param outputIndex index of output inside the input
/// @param outputHashesRootHash merkle root of all epoch's output metadata hashes
/// @param vouchersEpochRootHash merkle root of all epoch's voucher metadata hashes
/// @param noticesEpochRootHash merkle root of all epoch's notice metadata hashes
/// @param machineStateHash hash of the machine state claimed this epoch
/// @param keccakInHashesSiblings proof that this output metadata is in metadata memory range
/// @param outputHashesInEpochSiblings proof that this output metadata is in epoch's output memory range
struct OutputValidityProofV1 {
    uint64 epochInputIndex;
    uint64 outputIndex;
    bytes32 outputHashesRootHash;
    bytes32 vouchersEpochRootHash;
    bytes32 noticesEpochRootHash;
    bytes32 machineStateHash;
    bytes32[] keccakInHashesSiblings;
    bytes32[] outputHashesInEpochSiblings;
}

library LibOutputValidationV1 {
    using CanonicalMachine for CanonicalMachine.Log2Size;

    /// @notice Make sure the output proof is valid, otherwise revert
    /// @param _v the output validity proof
    /// @param _encodedOutput the encoded output
    /// @param _epochHash the hash of the epoch in which the output was generated
    /// @param _outputsEpochRootHash either _v.vouchersEpochRootHash (for vouchers)
    ///                              or _v.noticesEpochRootHash (for notices)
    /// @param _outputEpochLog2Size either EPOCH_VOUCHER_LOG2_SIZE (for vouchers)
    ///                             or EPOCH_NOTICE_LOG2_SIZE (for notices)
    /// @param _outputHashesLog2Size either VOUCHER_METADATA_LOG2_SIZE (for vouchers)
    ///                              or NOTICE_METADATA_LOG2_SIZE (for notices)
    function validateEncodedOutput(
        OutputValidityProofV1 calldata _v,
        bytes memory _encodedOutput,
        bytes32 _epochHash,
        bytes32 _outputsEpochRootHash,
        uint256 _outputEpochLog2Size,
        uint256 _outputHashesLog2Size
    ) internal pure {
        // prove that outputs hash is represented in a finalized epoch
        require(
            keccak256(
                abi.encodePacked(
                    _v.vouchersEpochRootHash,
                    _v.noticesEpochRootHash,
                    _v.machineStateHash
                )
            ) == _epochHash,
            "incorrect epochHash"
        );

        // prove that output metadata memory range is contained in epoch's output memory range
        require(
            Merkle.getRootAfterReplacementInDrive(
                CanonicalMachine.getIntraMemoryRangePosition(
                    _v.epochInputIndex,
                    CanonicalMachine.KECCAK_LOG2_SIZE
                ),
                CanonicalMachine.KECCAK_LOG2_SIZE.uint64OfSize(),
                _outputEpochLog2Size,
                _v.outputHashesRootHash,
                _v.outputHashesInEpochSiblings
            ) == _outputsEpochRootHash,
            "incorrect outputsEpochRootHash"
        );

        // The hash of the output is converted to bytes (abi.encode) and
        // treated as data. The metadata output memory range stores that data while
        // being indifferent to its contents. To prove that the received
        // output is contained in the metadata output memory range we need to
        // prove that x, where:
        // x = keccak(
        //          keccak(
        //              keccak(hashOfOutput[0:7]),
        //              keccak(hashOfOutput[8:15])
        //          ),
        //          keccak(
        //              keccak(hashOfOutput[16:23]),
        //              keccak(hashOfOutput[24:31])
        //          )
        //     )
        // is contained in it. We can't simply use hashOfOutput because the
        // log2size of the leaf is three (8 bytes) not  five (32 bytes)
        bytes32 merkleRootOfHashOfOutput = Merkle.getMerkleRootFromBytes(
            abi.encodePacked(keccak256(_encodedOutput)),
            CanonicalMachine.KECCAK_LOG2_SIZE.uint64OfSize()
        );

        // prove that merkle root hash of bytes(hashOfOutput) is contained
        // in the output metadata array memory range
        require(
            Merkle.getRootAfterReplacementInDrive(
                CanonicalMachine.getIntraMemoryRangePosition(
                    _v.outputIndex,
                    CanonicalMachine.KECCAK_LOG2_SIZE
                ),
                CanonicalMachine.KECCAK_LOG2_SIZE.uint64OfSize(),
                _outputHashesLog2Size,
                merkleRootOfHashOfOutput,
                _v.keccakInHashesSiblings
            ) == _v.outputHashesRootHash,
            "incorrect outputHashesRootHash"
        );
    }

    /// @notice Make sure the voucher proof is valid, otherwise revert
    /// @param _v the output validity proof
    /// @param _encodedVoucher the encoded voucher
    /// @param _epochHash the hash of the epoch in which the voucher was generated
    function validateEncodedVoucher(
        OutputValidityProofV1 calldata _v,
        bytes memory _encodedVoucher,
        bytes32 _epochHash
    ) internal pure {
        validateEncodedOutput(
            _v,
            _encodedVoucher,
            _epochHash,
            _v.vouchersEpochRootHash,
            CanonicalMachine.EPOCH_VOUCHER_LOG2_SIZE.uint64OfSize(),
            CanonicalMachine.VOUCHER_METADATA_LOG2_SIZE.uint64OfSize()
        );
    }

    /// @notice Make sure the notice proof is valid, otherwise revert
    /// @param _v the output validity proof
    /// @param _encodedNotice the encoded notice
    /// @param _epochHash the hash of the epoch in which the notice was generated
    function validateEncodedNotice(
        OutputValidityProofV1 calldata _v,
        bytes memory _encodedNotice,
        bytes32 _epochHash
    ) internal pure {
        validateEncodedOutput(
            _v,
            _encodedNotice,
            _epochHash,
            _v.noticesEpochRootHash,
            CanonicalMachine.EPOCH_NOTICE_LOG2_SIZE.uint64OfSize(),
            CanonicalMachine.NOTICE_METADATA_LOG2_SIZE.uint64OfSize()
        );
    }

    /// @notice Get the position of a voucher on the bit mask
    /// @param _voucher the index of voucher from those generated by such input
    /// @param _input the index of the input in the DApp's input box
    /// @return position of the voucher on the bit mask
    function getBitMaskPosition(uint256 _voucher, uint256 _input)
        internal
        pure
        returns (uint256)
    {
        // voucher * 2 ** 128 + input
        // this shouldn't overflow because it is impossible to have > 2**128 vouchers
        // and because we are assuming there will be < 2 ** 128 inputs on the input box
        return (((_voucher << 128) | _input));
    }
}