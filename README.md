> # ⚠️ This project is experimental and work in progress! ⚠️

# RWA Standard - Real World Assets on Sui

## Overview

The RWA Standard is a framework for issuing and managing permissioned tokens on Sui. It enables tokenization of real-world assets with built-in compliance mechanisms, transfer restrictions, and regulatory controls.

## TLDR

1. Each address has a single shared vault (derived address,  so easily discoverable). Objects can own vaults too (to help with account abstractions / defi protocols custom integrations)
2. Vault uses address balances (not in the PoC but that's the plan), so RPCs must work out of the box (wallet just treats the vault address like a normal one). Wallet needs to query for normal address + vault address.
3. RWAs can only move from vault to vault (we can now do this leveraging derived addresses (proof that an object A can only be transferred to object B)
4. When you try to transfer, you issue an explicit TransferRequest, which can be resolved, on the PTB layer, calling the MoveCommand that is specified by the author. The author can "approve" it internally by calling this.
5. Clawback is there by default (shared vault, author can stamp a clawback through their code / witness).

(To be added: Issuers can attach "metadata" to user's Vaults (such as `KYC` stamps or AML stamps they issue), which they can then check on their transfer functions to restrict movement.)


## Key Features

- **Permissioned Transfers**: All transfers must go through vaults and be approved by custom transfer rules
- **Vault-Based Architecture**: Tokens can only be held in vaults, with automatic balance tracking
- **Flexible Rules System**: Each token type has associated rules that govern transfers with jurisdiction-specific compliance
- **Optional Clawback**: Regulatory compliance feature that allows token recovery when legally required

## How It Works

1. **Setup**: Registry is created as a shared object, token issuers register their tokens with rules
2. **Vault Creation**: Vaults are derived for each address that needs to hold tokens
3. **Transfers**: Initiated from source vault, creating a transfer request that must be resolved by the rule
4. **Resolution**: Token-specific smart contracts validate and approve transfers based on compliance rules

## Wallet & SDK Integration

### Simple Discovery
The standard uses derived objects for predictable addresses:
- **Single vault per user** contains all RWA token balances
- **No indexing required** - vault and rule addresses are deterministically computable
- **One query** to see all user balances via dynamic fields on their vault

### Easy Resolution
Each rule contains `MoveCommand` instructions that tell SDKs exactly how to resolve transfers - no need to understand complex on-chain logic. SDKs simply read the command and construct the appropriate transaction.

## Security Features

- **Ownership Proofs**: Ensure only legitimate owners can initiate transfers
- **Transfer Restrictions**: All transfers generate hot potato requests that must be resolved
- **Immutable Clawback**: Optional feature that can only be set at registration

## Benefits

- **Regulatory Compliance**: Built-in KYC/AML support with audit trails
- **Efficiency**: Token squashing reduces storage costs, derived objects optimize state
- **Flexibility**: Custom rules per token type with extensible resolution mechanisms
