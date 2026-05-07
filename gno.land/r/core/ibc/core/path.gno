package core

import (
	"bytes"
	"encoding/binary"
)

// you can't have byte arrays as a const in go :(
var (
	// 0x0100000000000000000000000000000000000000000000000000000000000000
	COMMITMENT_MAGIC [32]byte = [32]byte{
		0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	}

	// 0x0200000000000000000000000000000000000000000000000000000000000000
	COMMITMENT_MAGIC_ACK [32]byte = [32]byte{
		0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	}

	CLIENT_STATE [32]byte = [32]byte{
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	}
	CONSENSUS_STATE [32]byte = [32]byte{
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
	}
	CONNECTIONS [32]byte = [32]byte{
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02,
	}
	CHANNELS [32]byte = [32]byte{
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03,
	}
	PACKETS [32]byte = [32]byte{
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04,
	}
	PACKET_ACKS [32]byte = [32]byte{
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05,
	}
)

// #[cfg(feature = "ethabi")]
// #[must_use]
// pub fn commit_packets(packets: &[Packet]) -> H256 {
//     use alloy_sol_types::SolValue;

//     Keccak256::new()
//         .chain_update(packets.abi_encode())
//         .finalize()
//         .into()
// }

func u32ToH256(n uint32) []byte {
	bz := [32]byte{}
	binary.BigEndian.PutUint32(bz[28:], n)
	return bz[:]
}

func u64ToH256(n uint64) []byte {
	bz := [32]byte{}
	binary.BigEndian.PutUint64(bz[24:], n)
	return bz[:]
}

func ClientStatePath(clientId ClientId) H256 {
	return keccak(bytes.Join([][]byte{
		CLIENT_STATE[:],
		u32ToH256(uint32(clientId)),
	}, []byte{}))
}

func ConsensusStatePath(clientId ClientId, height Height) H256 {
	return keccak(bytes.Join([][]byte{
		CONSENSUS_STATE[:],
		u32ToH256(uint32(clientId)),
		u64ToH256(uint64(height)),
	}, []byte{}))
}

func ConnectionPath(connectionId ConnectionId) H256 {
	return keccak(bytes.Join([][]byte{
		CONNECTIONS[:],
		u32ToH256(uint32(connectionId)),
	}, []byte{}))
}

func ChannelPath(channelId ChannelId) H256 {
	return keccak(bytes.Join([][]byte{
		CHANNELS[:],
		u32ToH256(uint32(channelId)),
	}, []byte{}))
}

// pub struct BatchReceiptsPath {
//     pub batch_hash [32]byte,
// }

// impl BatchReceiptsPath {
//     #[cfg(feature = "ethabi")]
//     #[must_use]
//     pub fn from_packets(packets: &[Packet]) -> Self {
//         Self {
//             batch_hash: commit_packets(packets),
//         }
//     }

//     #[cfg(feature = "ethabi")]
//     #[must_use]
//     pub fn from_packet(packet: &Packet) -> Self {
//         Self::from_packets(core::slice::from_ref(packet))
//     }

//     #[must_use]
//     pub fn key(&self) -> H256 {
//         Keccak256::new()
//             .chain_update(PACKET_ACKS.to_be_bytes())
//             .chain_update(self.batch_hash)
//             .finalize()
//             .into()
//     }
// }

// impl IbcStorePathKey for BatchReceiptsPath {
//     type Spec = IbcUnion;

//     type Value = H256;
// }

// pub struct BatchPacketsPath {
//     pub batch_hash [32]byte,
// }

// impl BatchPacketsPath {
//     #[cfg(feature = "ethabi")]
//     #[must_use]
//     pub fn from_packets(packets: &[Packet]) -> Self {
//         use alloy_sol_types::SolValue;
//         Self {
//             batch_hash: Keccak256::new()
//                 .chain_update(packets.abi_encode())
//                 .finalize()
//                 .into(),
//         }
//     }

//     #[cfg(feature = "ethabi")]
//     #[must_use]
//     pub fn from_packet(packet: &Packet) -> Self {
//         Self::from_packets(core::slice::from_ref(packet))
//     }

//     #[must_use]
//     pub fn key(&self) -> H256 {
//         Keccak256::new()
//             .chain_update(PACKETS.to_be_bytes())
//             .chain_update(self.batch_hash)
//             .finalize()
//             .into()
//     }
// }

// impl IbcStorePathKey for BatchPacketsPath {
//     type Spec = IbcUnion;

//     type Value = H256;
// }

// pub struct MembershipProofPath {
//     pub client_id: ClientId,
//     pub proof_height: u64,
//     pub path: Bytes,
// }

// impl MembershipProofPath {
//     #[must_use]
//     pub fn key(&self) -> H256 {
//         Keccak256::new()
//             .chain_update(MEMBERSHIP_PROOF.to_be_bytes())
//             .chain_update(U256::from(self.client_id.get()).to_be_bytes())
//             .chain_update(U256::from(self.proof_height).to_be_bytes())
//             .chain_update(&self.path)
//             .finalize()
//             .into()
//     }
// }

// impl IbcStorePathKey for MembershipProofPath {
//     type Spec = IbcUnion;

//     type Value = Bytes;
// }

// pub struct NonMembershipProofPath {
//     pub client_id: ClientId,
//     pub proof_height: u64,
//     pub path: Bytes,
// }

// impl NonMembershipProofPath {
//     #[must_use]
//     pub fn key(&self) -> H256 {
//         Keccak256::new()
//             .chain_update(NON_MEMBERSHIP_PROOF.to_be_bytes())
//             .chain_update(U256::from(self.client_id.get()).to_be_bytes())
//             .chain_update(U256::from(self.proof_height).to_be_bytes())
//             .chain_update(&self.path)
//             .finalize()
//             .into()
//     }
// }

// impl IbcStorePathKey for NonMembershipProofPath {
//     type Spec = IbcUnion;

//     type Value = ();
// }

// pub struct BatchTimeoutPath {
//     pub batch_hash [32]byte,
// }

// impl BatchTimeoutPath {
//     #[cfg(feature = "ethabi")]
//     #[must_use]
//     pub fn from_packet(packet: &Packet) -> Self {
//         use alloy_sol_types::SolValue;

//         Self {
//             batch_hash: {
//                 Keccak256::new()
//                     .chain_update(packet.abi_encode())
//                     .finalize()
//                     .into()
//             },
//         }
//     }

//     #[must_use]
//     pub fn key(&self) -> H256 {
//         Keccak256::new()
//             .chain_update(PACKET_TIMEOUTS.to_be_bytes())
//             .chain_update(self.batch_hash)
//             .finalize()
//             .into()
//     }
// }

// impl IbcStorePathKey for BatchTimeoutPath {
//     type Spec = IbcUnion;

//     type Value = H256;
// }
