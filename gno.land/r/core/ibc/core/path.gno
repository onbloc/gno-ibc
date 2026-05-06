package core

// you can't have byte arrays as a const in go :(
var (
  // 0x0100000000000000000000000000000000000000000000000000000000000000
  COMMITMENT_MAGIC [32]byte = [32]byte{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };

  // 0x0200000000000000000000000000000000000000000000000000000000000000
  COMMITMENT_MAGIC_ACK [32]byte = [32]byte{2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };

  // 0x0000000000000000000000000000000000000000000000000000000000000001
  NON_MEMBERSHIP_COMMITMENT_VALUE [32]byte = [32]byte{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 };

  // /// 0x0000000000000000000000000000000000000000000000000000000000000001
  // NON_MEMBERSHIP_COMMITMENT_VALUE [32]byte = {
  //     let mut bz = [0; 32];
  //     bz[31] = 1;
  //     H256::new(bz)
  // };

  // CLIENT_STATE: U256 = U256::from_limbs([0, 0, 0, 0]);
  // CONSENSUS_STATE: U256 = U256::from_limbs([1, 0, 0, 0]);
  // CONNECTIONS: U256 = U256::from_limbs([2, 0, 0, 0]);
  // CHANNELS: U256 = U256::from_limbs([3, 0, 0, 0]);
  // PACKETS: U256 = U256::from_limbs([4, 0, 0, 0]);
  // PACKET_ACKS: U256 = U256::from_limbs([5, 0, 0, 0]);
  // MEMBERSHIP_PROOF: U256 = U256::from_limbs([6, 0, 0, 0]);
  // NON_MEMBERSHIP_PROOF: U256 = U256::from_limbs([7, 0, 0, 0]);
  // PACKET_TIMEOUTS: U256 = U256::from_limbs([8, 0, 0, 0]);
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

func ClientStatePath(clientId ClientId) (H256) {
  keccak
}

// impl ClientStatePath {
//     #[must_use]
//     pub fn key(&self) -> H256 {
//         Keccak256::new()
//             .chain_update(CLIENT_STATE.to_be_bytes())
//             .chain_update(U256::from(self.client_id.get()).to_be_bytes())
//             .finalize()
//             .into()
//     }
// }

// impl IbcStorePathKey for ClientStatePath {
//     type Spec = IbcUnion;

//     type Value = Bytes;
// }

// pub struct ConsensusStatePath {
//     pub client_id: ClientId,
//     pub height: u64,
// }

// impl ConsensusStatePath {
//     #[must_use]
//     pub fn key(&self) -> H256 {
//         Keccak256::new()
//             .chain_update(CONSENSUS_STATE.to_be_bytes())
//             .chain_update(U256::from(self.client_id.get()).to_be_bytes())
//             .chain_update(U256::from(self.height).to_be_bytes())
//             .finalize()
//             .into()
//     }
// }

// impl IbcStorePathKey for ConsensusStatePath {
//     type Spec = IbcUnion;

//     type Value = Bytes;
// }

// pub struct ConnectionPath {
//     pub connection_id: ConnectionId,
// }

// impl ConnectionPath {
//     #[must_use]
//     pub fn key(&self) -> H256 {
//         Keccak256::new()
//             .chain_update(CONNECTIONS.to_be_bytes())
//             .chain_update(U256::from(self.connection_id.get()).to_be_bytes())
//             .finalize()
//             .into()
//     }
// }

// impl IbcStorePathKey for ConnectionPath {
//     type Spec = IbcUnion;

//     type Value = Connection;
// }

// pub struct ChannelPath {
//     pub channel_id: ChannelId,
// }

// impl ChannelPath {
//     #[must_use]
//     pub fn key(&self) -> H256 {
//         Keccak256::new()
//             .chain_update(CHANNELS.to_be_bytes())
//             .chain_update(U256::from(self.channel_id.get()).to_be_bytes())
//             .finalize()
//             .into()
//     }
// }

// impl IbcStorePathKey for ChannelPath {
//     type Spec = IbcUnion;

//     type Value = Channel;
// }

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
