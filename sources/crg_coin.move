/*
/// Module: sui_swap_amm_contract
module sui_swap_amm_contract::sui_swap_amm_contract;
*/

// For Move coding conventions, see
// https://docs.sui.io/concepts/sui-move-concepts/conventions

module sui_swap_amm_contract::crg;
use sui::coin::{Self, TreasuryCap};

public struct AdminCap has key, store {
    id: UID,
}
public struct CRG has drop {}

fun init(witness: CRG, ctx: &mut TxContext) {
    let admin = AdminCap {
        id: object::new(ctx),
    };
    transfer::transfer(admin, tx_context::sender(ctx));

    let (mut treasury, metadata) = coin::create_currency(
        witness, 
        9, 
        b"CRG", 
        b"Currency Ranger", 
        b"",
        option::none(),
        ctx,
    );
    transfer::public_freeze_object(metadata);
    transfer::public_transfer(treasury, tx_context::sender(ctx));
}

public entry fun mint(_admin: &AdminCap, treasury: &mut TreasuryCap<CRG>, amount: u64, recipient: address, ctx: &mut TxContext) {
    let coin = coin::mint(treasury, amount, ctx);
    transfer::public_transfer(coin, recipient);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    let witness = CRG{};
    init(witness, ctx);
}
