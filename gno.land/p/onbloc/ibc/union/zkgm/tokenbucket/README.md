# ZKGM Token Bucket Package

Pure package for the UCS03-ZKGM per-denom rate-limit bucket.

The ZKGM app stores `TokenBucket` values in its proxy-owned store. The v1
implementation refills buckets from block time and charges sends through
`RateLimit`.

## Files

- [tokenbucket.gno](tokenbucket.gno) defines bucket construction, refill,
  charge, and update behavior.
