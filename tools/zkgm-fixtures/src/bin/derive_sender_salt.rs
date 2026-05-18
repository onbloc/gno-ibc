/// Generates bootstrap vectors for `DeriveSenderSalt` by hashing
/// Union-compatible ABI encoding of `(sender: bytes, salt: bytes32)`.
///
/// Run from the repository root:
///   cargo run --release -p zkgm-fixtures --bin derive_sender_salt
use alloy_primitives::{keccak256, FixedBytes};
use alloy_sol_types::SolValue;

fn derive(sender: &[u8], salt: [u8; 32]) -> FixedBytes<32> {
    let salt32 = FixedBytes::<32>::from(salt);
    let encoded = (sender, salt32).abi_encode();
    keccak256(&encoded)
}

fn main() {
    let cases: &[(&str, Vec<u8>, [u8; 32])] = &[
        (
            "20-byte EVM sender",
            hex::decode("bd1b743615f903a630393f78234b4500fbe5691a").unwrap(),
            [0x11; 32],
        ),
        (
            "gno bech32 sender",
            b"g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm".to_vec(),
            [0x22; 32],
        ),
        ("empty sender", Vec::new(), [0x33; 32]),
    ];

    for (label, sender, salt) in cases {
        let out = derive(sender, *salt);
        println!("{}: 0x{}", label, hex::encode(out));
    }
}
