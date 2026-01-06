/// Vault logic
module pvs::vault;

use pvs::namespace::Namespace;
use sui::{balance::{Self, Balance}, derived_object};

use fun balance::withdraw_funds_from_object as UID.withdraw_funds_from_object;

#[error(code = 1)]
const ENotOwner: vector<u8> = b"The owner is not valid for the vault.";
#[error(code = 2)]
const EVaultAlreadyExists: vector<u8> = b"The vault already exists.";

/// There is only one Vault per address (guaranteed by derived objects).
/// - Balances can only be transferred from Vault A to Vault B.
/// - Vaults are shared by default.
/// - Vaults creation is permission-less
/// - A `UID` (object) can also own a vault
public struct Vault has key {
    id: UID,
    /// The owner of the vault (address or object)
    owner: address,
}

/// The key used to create `Vault` ids for addresses (or objects).
public struct VaultKey(address) has copy, drop, store;

/// A proof that address has authenticated. This allows for uniform access control between both
/// `UID` and `ctx.sender()` (keeping a single API for both).
public struct Auth(address) has drop;

/// A transfer request that is generated once a Permissioned Transfer is initiated.
///
/// A hot potato that is issued when a transfer is initiated.
/// It can only be resolved by presenting a witness `U` that is the witness of `Rule<T>`
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
public struct TransferRequest<phantom T> {
    from: address,
    to: address,
    amount: u64,
}

/// Create a new vault for `owner`. This is a permission-less action.
public fun create(namespace: &mut Namespace, owner: address): Vault {
    assert!(!namespace.exists(VaultKey(owner)), EVaultAlreadyExists);

    Vault {
        id: derived_object::claim(namespace.uid_mut(), VaultKey(owner)),
        owner,
    }
}

/// The only way to finalize the TX is by sharing the vault.
/// All vaults are shared by default.
public fun share(vault: Vault) {
    transfer::share_object(vault);
}

/// Create and share a vault in a single step.
entry fun create_and_share(namespace: &mut Namespace, owner: address) {
    create(namespace, owner).share()
}

/// Initiate a transfer from vault A to vault B to a vault.
public fun transfer<T>(
    from: &mut Vault,
    auth: &Auth,
    to: &Vault,
    amount: u64,
    _ctx: &mut TxContext,
): TransferRequest<T> {
    auth.assert_is_valid_for_vault(from);
    from.internal_transfer<T>(object::id(to).to_address(), amount)
}

/// Transfer `amount` from vault to an address. This unlocks transfers to a vault before it has been created.
///
/// It's marked as `unsafe_` as it's easy to accidentally pick the wrong recipient address.
public fun unsafe_transfer<T>(
    namespace: &Namespace,
    from: &mut Vault,
    auth: &Auth,
    // Recipients should always be the user or object address, not the vault's.
    // It's recommended to use `transfer` instead.
    recipient_address: address,
    amount: u64,
    _ctx: &mut TxContext,
): TransferRequest<T> {
    use fun vault_address as Namespace.vault_address;

    auth.assert_is_valid_for_vault(from);

    from.internal_transfer<T>(namespace.vault_address(recipient_address), amount)
}

/// Derive the address of a vault for a given owner address.
public fun vault_address(namespace: &Namespace, owner: address): address {
    derived_object::derive_address(object::id(namespace), VaultKey(owner))
}

/// Generate an ownership proof from the sender of the transaction.
public fun new_auth(ctx: &TxContext): Auth {
    Auth(ctx.sender())
}

/// Generate an ownership proof from a `UID` object, to allow objects to own vaults.
public fun new_auth_as_object(uid: &mut UID): Auth {
    Auth(uid.to_inner().to_address())
}

// ========== Request Getter Functions ==========
public use fun request_from as TransferRequest.from;
public use fun request_to as TransferRequest.to;
public use fun request_amount as TransferRequest.amount;

public fun request_from<T>(request: &TransferRequest<T>): address { request.from }

public fun request_to<T>(request: &TransferRequest<T>): address { request.to }

public fun request_amount<T>(request: &TransferRequest<T>): u64 { request.amount }

/// Internal function to resolve a transfer request.
public(package) fun resolve_transfer<T>(request: TransferRequest<T>) {
    let TransferRequest { .. } = request;
}

public(package) fun deposit<T>(vault: &Vault, balance: Balance<T>) {
    balance::send_funds(balance, object::id(vault).to_address());
}

public(package) fun withdraw<T>(vault: &mut Vault, amount: u64): Balance<T> {
    balance::redeem_funds(vault.id.withdraw_funds_from_object(amount))
}

/// Verify that the ownership proof matches the vaults owner.
public(package) fun assert_is_valid_for_vault(proof: &Auth, vault: &Vault) {
    assert!(&proof.0 == &vault.owner, ENotOwner);
}

/// The internal implementation for transferring `amount` from Vault towards another address.
///
/// INTERNAL WARNING: Callers must verify that `to` is indeed a vault address. That means that it either has
/// to be a `object::id(&Vault).to_address()` call, OR a derived address with `VaultKey(address)`.
/// Failure to do so can cause assets to move out of the closed loop, breaking the system assurances
fun internal_transfer<T>(from: &mut Vault, to: address, amount: u64): TransferRequest<T> {
    let balance = from.withdraw<T>(amount);

    let request = TransferRequest {
        from: from.owner,
        to,
        amount: balance.value(),
    };

    balance::send_funds(balance, to);
    request
}

#[test_only]
public fun vault_key_for_testing(sender: address): VaultKey {
    VaultKey(sender)
}
