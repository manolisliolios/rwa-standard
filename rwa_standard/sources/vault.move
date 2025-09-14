/// RWA Standard
module rwa::vault;

use rwa::token::{Self, RwaToken};
use sui::balance::{Self, Balance};
use sui::derived_object;
use sui::dynamic_field as df;
use sui::transfer::Receiving;

const ENotOwner: u64 = 1;
const ENonExistentBalance: u64 = 2;

/// The owner of a vault.
public enum Owner has copy, drop, store {
    Address(address),
    Object(ID),
}

/// Tokens can only be transferred between Vaults.
///
/// Vaults are shared by default.
///
/// Clients can query balances by looking at the Balance<T> DFs of the vault.
/// Clients can squash tokens by querying owned objects of type `Token` owned by the vault.
///
/// A vault is derived from `rwa_registry, address`.
/// Objects can have their own vaults (registering with their `&mut UID`)
public struct RwaVault has key {
    id: UID,
    // Used to store the registry id, without requiring it in follow-up transactions.
    registry_id: ID,
    /// The owner of the vault (address or object)
    owner: Owner,
}

/// The key for a Balance of type `T`.
public struct BalanceKey<phantom T>() has copy, drop, store;

/// The key used to generate `RwaVault` for sender (or objects)
public struct RwaVaultKey(address) has copy, drop, store;

/// Proof of ownership for a given vault.
public struct VaultOwnerProof(Owner) has drop;

/// A transfer request that is generated once an RWA
/// Token transfer is initiated.
///
/// A hot potato that is issued when a transfer is initiated.
/// It can only be resolved by the `admin` of `T`.
///
/// This enables the `resolve` function of each smart contract to
/// be flexible and implement its own mechanisms for validation.
/// The individual resolution module can:
///   - Check whitelists/blacklists
///   - Enforce holding periods
///   - Collect fees
///   - Emit regulatory events
///   - Handle dividends/distributions
///   - Implement any jurisdiction-specific rules
public struct RwaTransferRequest<phantom T> {
    from: Owner,
    to: Owner,
    amount: u64,
}

/// Initiates a transfer for a `Token` from Vault A, to another Vault (no squashing involved).
public fun transfer<T>(
    vault: &mut RwaVault,
    proof: &VaultOwnerProof,
    amount: u64,
    // Recipients should always be plain addresses, not vaults.
    to: address,
    ctx: &mut TxContext,
): RwaTransferRequest<T> {
    // verify that the proof is valid for the vault.
    proof.assert_is_valid_for_vault(vault);

    let token = token::new(vault.withdraw_balance<T>(amount), ctx);

    let request = RwaTransferRequest {
        from: vault.owner,
        to: Owner::Address(to),
        amount: token.balance(),
    };

    let receiving_vault = derived_object::derive_address(vault.registry_id, RwaVaultKey(to));

    token.transfer(receiving_vault);
    request
}

/// Initiates a transfer from Vault A to Vault B, with immediate squashing of the balances.
/// This might be useful for defi operations (chaining of actions).
public fun transfer_to_vault<T>(
    vault: &mut RwaVault,
    proof: &VaultOwnerProof,
    amount: u64,
    to: &mut RwaVault,
    _: &mut TxContext,
): RwaTransferRequest<T> {
    proof.assert_is_valid_for_vault(vault);

    let balance = vault.withdraw_balance<T>(amount);

    let request = RwaTransferRequest {
        from: vault.owner,
        to: to.owner,
        amount: balance.value(),
    };

    to.deposit_balance(balance);
    request
}

/// Allow squashing a set of tokens into the vault's balance.
/// This is permissionless -- anyone can squash to claim storage rebates.
///
/// TODO: If there are object address balances, maybe this is the equivalent!
public fun squash_tokens<T>(vault: &mut RwaVault, tokens: vector<Receiving<RwaToken<T>>>) {
    let mut temp_balance = balance::zero<T>();

    tokens.do!(|receiving_token| {
        let token = token::receive(&mut vault.id, receiving_token);
        temp_balance.join(token.extract());
    });

    vault.deposit_balance(temp_balance);
}

/// Generate an ownership proof from the sender of the transaction
public fun proof_as_sender(ctx: &TxContext): VaultOwnerProof {
    VaultOwnerProof(Owner::Address(ctx.sender()))
}

/// Generate an ownership proof from a `UID` object, to allow objects to own vaults.
public fun proof_as_uid(uid: &mut UID): VaultOwnerProof {
    VaultOwnerProof(Owner::Object(uid.to_inner()))
}

/// Internal function to resolve a transfer request.
public(package) fun resolve<T>(request: RwaTransferRequest<T>) {
    let RwaTransferRequest { .. } = request;
}

public(package) fun deposit_balance<T>(vault: &mut RwaVault, balance: Balance<T>) {
    vault.create_balance_if_not_exists<T>();
    let vault_balance: &mut Balance<T> = df::borrow_mut(&mut vault.id, BalanceKey<T>());
    vault_balance.join(balance);
}

public(package) fun withdraw_balance<T>(vault: &mut RwaVault, amount: u64): Balance<T> {
    assert!(df::exists_(&vault.id, BalanceKey<T>()), ENonExistentBalance);
    let vault_balance: &mut Balance<T> = df::borrow_mut(&mut vault.id, BalanceKey<T>());
    vault_balance.split(amount)
}

fun create_balance_if_not_exists<T>(vault: &mut RwaVault) {
    if (!df::exists_(&vault.id, BalanceKey<T>()))
        df::add(&mut vault.id, BalanceKey<T>(), balance::zero<T>());
}

fun assert_is_valid_for_vault(proof: &VaultOwnerProof, vault: &RwaVault) {
    assert!(&proof.0 == &vault.owner, ENotOwner);
}
