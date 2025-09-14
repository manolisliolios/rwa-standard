module rwa::rule;

use rwa::vault::{RwaTransferRequest, RwaVault};
use std::string::String;
use std::type_name::{Self, TypeName};
use sui::balance::Balance;

const EInvalidProof: u64 = 0;
const EClawbackNotAllowed: u64 = 1;

/// A rule is set by the owner of `T`, and points to a `TypeName` that needs
/// to be verified by the entity's contract.
///
/// This is derived from `rwa_registry, TypeName<T>`
public struct RwaRule<phantom T> has key {
    id: UID,
    /// If the rule has clawback, the owner can arbitrarily clawback tokens from vaults.
    /// This is only set on registration and cannot be updated in the future.
    clawback_allowed: bool,
    /// The typename used to prove
    proof: TypeName,
    // TODO: Come up with a standard way of saying "how do I generate the stamp?".
    // This can be used by wallets and SDKs to build "resolve_transfer" command in the
    // defining module.
    //
    // Example;
    // `0xb::resolve::rule`
    // with the following arguments:
    // - request: RwaTransferRequest<T>
    // - policy_object: shared_mut('0xfoo')
    //
    // Should we validate the struct here? e.g. make it so that it has an expected format?
    // Should we build a "Command" format like
    // `Function(address, module, function)`
    // `Arguments(Vector<Argument>)
    // where each argument is either a placeholder (OwnerVault, ReceiverVault, Rule, Request)
    // OR a Shared Object(ID), or an Immutable Object(ID)?
    resolution_info: String,
}

/// U is a witness, which has to match the rule's witness.
/// This is callable by the smart contract that has to approve a transfer.
public fun resolve_transfer<T, U: drop>(
    rule: &RwaRule<T>,
    request: RwaTransferRequest<T>,
    _stamp: U,
) {
    rule.assert_is_valid_creator_proof<T, U>();
    // destructuring the request to finalize the transfer.
    request.resolve();
}

/// Allows the creator to clawback tokens from vaults, as long as it is allowed.
public fun clawback<T, U: drop>(
    rule: &RwaRule<T>,
    vault: &mut RwaVault,
    amount: u64,
    _stamp: U,
): Balance<T> {
    assert!(rule.clawback_allowed, EClawbackNotAllowed);
    rule.assert_is_valid_creator_proof<T, U>();

    vault.withdraw_balance<T>(amount)
}

fun assert_is_valid_creator_proof<T, U: drop>(rule: &RwaRule<T>) {
    assert!(type_name::with_defining_ids<U>() == rule.proof, EInvalidProof);
}
