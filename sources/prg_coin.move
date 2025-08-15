module sui_swap_amm_contract::prg;
use sui::coin::{Self, TreasuryCap};

public struct AdminCap has key, store {
    id: UID,
}

public struct PRG has drop{}

fun init(witness: PRG, ctx: &mut TxContext) {
    let admin = AdminCap {
        id: object::new(ctx),
    };
    transfer::transfer(admin, tx_context::sender(ctx));

    let (mut treasury, metadata) = coin::create_currency(
        witness, 
        9, 
        b"PRG", 
        b"Power Ranger", 
        b"",
        option::none(),
        ctx,
    );
    transfer::public_freeze_object(metadata);
    transfer::public_transfer(treasury, tx_context::sender(ctx));
}

public entry fun mint(_admin: &AdminCap, treasury: &mut TreasuryCap<PRG>, amount: u64, recipient: address, ctx: &mut TxContext) {
    let coin = coin::mint(treasury, amount, ctx);
    transfer::public_transfer(coin, recipient);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    let witness = PRG{};
    init(witness, ctx);
}