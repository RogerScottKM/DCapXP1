# DCapX Vault

This folder holds the configuration for the DCapX Vault service.

Current mode:
- non-dev Vault server
- persistent single-node Raft storage
- local HTTP listener on 127.0.0.1:8200 via Docker port binding

This is a production-like bootstrap for DCapX development and pre-production hardening.

Still recommended before real production rollout:
- TLS certificates
- auto-unseal
- 3-node HA Raft cluster
- audit shipping / monitoring
