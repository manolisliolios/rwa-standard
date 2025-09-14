module rwa::registry;

/// The registry, from which all RWA related objects are namespaced.
public struct RwaRegistry has key {
    id: UID,
}

fun init(ctx: &mut TxContext) {
    transfer::share_object(RwaRegistry {
        id: object::new(ctx),
    });
}
