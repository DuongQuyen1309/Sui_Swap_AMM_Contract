module sui_swap_amm_contract::swap_token;
use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance, Supply};
use std::ascii::{Self, String};
use std::type_name;
use std::vector;
use sui::event;

const NOT_ORDERED: u64 = 1;
const NOT_POSITIVE: u64 = 2;
const INVALID_WITH_INPUT_AMOUNT: u64 = 3;
const NOT_ENOUGH_LIQUIDITY: u64 = 4;

public struct AdminCap has key, store {
    id: UID,
}

fun init(ctx: &mut TxContext) {
    let admin = AdminCap {
        id: object::new(ctx),
    };
    transfer::transfer(admin, tx_context::sender(ctx));
}

public struct LiquidityToken<phantom X, phantom Y> has store, drop {}

public struct Pool<phantom X, phantom Y> has key {
    id: UID,
    coin_x : Balance<X>,
    coin_y : Balance<Y>,
    liquidity_token_supply: Supply<LiquidityToken<X, Y>>,
    liquidity_token_sum: Balance<LiquidityToken<X, Y>>,
    fee: u64,
}

public fun sort<X,Y>() : bool {
    let vector_x = ascii::into_bytes(type_name::into_string(type_name::get<X>()));
    let vector_y = ascii::into_bytes(type_name::into_string(type_name::get<Y>()));

    let length_vector_x = vector::length(&vector_x);
    let length_vector_y = vector::length(&vector_y);

    let mut index = 0;
    let mut result: bool = false;
    while (index < length_vector_x && index < length_vector_y) {
        let char_x = *vector::borrow(&vector_x, index);
        let char_y = *vector::borrow(&vector_y, index);
        if (char_x < char_y) {
            result = true;
            break;
        };
        if (char_x > char_y) {
            break;
        };
        index = index + 1;
    };
    if (length_vector_x < length_vector_y) {
        result = true;
    };
    result
}

public entry fun register_pool<X,Y>(_admin: &AdminCap, fee: u64, ctx: &mut TxContext) {
    let liquid_token = LiquidityToken<X, Y>{};
    let is_ordered = sort<X, Y>();
    assert!(is_ordered, NOT_ORDERED);
    let pool = Pool<X, Y> {
        id: object::new(ctx),
        coin_x: balance::zero<X>(),
        coin_y: balance::zero<Y>(),
        liquidity_token_supply: balance::create_supply(LiquidityToken<X, Y>{}),
        // liquidity_token_sum: balance::zero<LiquidityToken<X, Y>>(),
        fee: fee,
    };
    transfer::share_object(pool);
}


//Not check case that first time to add liquidity
public entry fun add_liquid<X,Y>(pool: &mut Pool<X,Y>,coin_x_desired: Coin<X>, coin_y_desired: Coin<Y>, amount_x_min: u64, amount_y_min: u64, ctx: &mut TxContext){
    let is_ordered = sort<X, Y>();
    assert!(is_ordered, NOT_ORDERED);
    let amount_x_desired = balance::value(&coin_x_desired);
    let amount_y_desired = balance::value(&coin_y_desired);
    assert!(amount_x_desired >= amount_x_min && amount_y_desired >= amount_y_min, INVALID_WITH_INPUT_AMOUNT);
    assert!(amount_x_desired > 0 && amount_y_desired > 0 && amount_x_min > 0 && amount_y_min > 0, NOT_POSITIVE);
    
    //calcalate optimal amount of coins to add into pool
    let (amount_x_optimal, amount_y_optimal) = calculate_amount_optimal_into_liquidity(amount_x_desired, amount_y_desired, amount_x_min, amount_y_min, pool);
    
    //get amount of coins according to rate of pool
    let coin_x_optimal = coin::split(coin_x_desired, amount_x_optimal, ctx);
    let coin_y_optimal = coin::split(coin_y_desired, amount_y_optimal, ctx);

    //transfer liquidity token amount 
    let (reserver_x, reserver_y) = get_reserve(pool);
    let value_x_optimal = coin::value(&coin_x_optimal);
    let liquid_token_balance = calculate_liquid_token(pool, reserver_x, value_x_optimal);
    transfer::public_transfer(liquid_token_balance, tx_context::sender(ctx));

    //transfer coins to pool according to rate of pool
    transfer::public_transfer(coin_x_optimal, &mut pool.coin_x);
    transfer::public_transfer(coin_y_optimal, &mut pool.coin_y);

    //transfer remain coins back to sender
    transfer::public_transfer(coin_x_desired, tx_context::sender(ctx));
    transfer::public_transfer(coin_y_desired, tx_context::sender(ctx));

    //EMIT EVENT
}

//check name of variable
public entry fun remove_liquid<X,Y>(pool: &mut Pool<X,Y>, balance_liquid_token: Balance<LiquidityToken<X,Y>>, amount_x_min: u64, amount_y_min: u64){
    let is_ordered = sort<X, Y>();
    assert!(is_ordered, NOT_ORDERED);
    let (reserve_x, reserve_y) = get_reserve(pool);
    let liquid_token_amount = balance::value(&balance_liquid_token);
    let amount_coin_x = calc_coin_amount_correspond_liqud_token(pool, liquid_token_amount, reserve_x);
    let amount_coin_y = calc_coin_amount_correspond_liqud_token(pool, liquid_token_amount, reserve_y);
    assert!(amount_coin_x >= amount_x_min && amount_coin_y >= amount_y_min, INVALID_WITH_INPUT_AMOUNT);
    balance::decrease_supply(&mut pool.liquidity_token_supply, balance_liquid_token);

    let coin_x_withdraw_from_pool = coin::take(&mut pool.coin_x, amount_coin_x, ctx);
    let coin_y_withdraw_from_pool = coin::take(&mut pool.coin_y, amount_coin_y, ctx);
    transfer::public_transfer(coin_x_withdraw_from_pool, tx_context::sender(ctx));
    transfer::public_transfer(coin_y_withdraw_from_pool, tx_context::sender(ctx));
}

public entry fun swap_exact_x_for_y<X,Y>(pool: &mut Pool<X,Y>, coin_in: Coin<X>, amount_out_min: u64, ctx: &mut TxContext){
    let is_ordered = sort<X, Y>();
    assert!(is_ordered, NOT_ORDERED);
    let (reserve_x, reserve_y) = get_reserve(pool);
    let coin_in_value = coin::value(&coin_in);
    assert!(reserve_x > 0 && reserve_y > 0, NOT_ENOUGH_LIQUIDITY);
    assert!(coin_in_value > 0 && amount_out_min > 0, NOT_POSITIVE);
    let amount_out = calculate_amount_out(pool, coin_in_value, reserve_x, reserve_y);
    assert!(amount_out >= amount_out_min, INVALID_WITH_INPUT_AMOUNT);
    
    handle_coin_x_from(pool, coin_in);
    
    handle_coin_y_to(pool, amount_out, ctx);
}

public entry fun swap_exact_y_for_x<X,Y>(pool: &mut Pool<X,Y>, coin_in: Coin<Y>, amount_out_min: u64, ctx: &mut TxContext){
    let is_ordered = sort<X, Y>();
    assert!(is_ordered, NOT_ORDERED);
    let (reserve_x, reserve_y) = get_reserve(pool);
    let coin_in_value = coin::value(&coin_in);
    assert!(reserve_x > 0 && reserve_y > 0, NOT_ENOUGH_LIQUIDITY);
    assert!(coin_in_value > 0 && amount_out_min > 0, NOT_POSITIVE);
    let amount_out = calculate_amount_out(pool, coin_in_value, reserve_y, reserve_x);
    assert!(amount_out >= amount_out_min, INVALID_WITH_INPUT_AMOUNT);
    
    handle_coin_y_from(pool, coin_in);
    
    handle_coin_x_to(pool, amount_out, ctx);
}

public entry fun swap_x_for_exact_y<X,Y>(pool: &mut Pool<X,Y>, coin_in_max: Coin<X>, amount_out: u64, ctx: &mut TxContext) {
    let is_ordered = sort<X, Y>();
    assert!(is_ordered, NOT_ORDERED);
    let (reserve_x, reserve_y) = get_reserve(pool);
    assert!(reserve_x > 0 && reserve_y > 0, NOT_ENOUGH_LIQUIDITY);
    assert!(amount_out > 0, NOT_POSITIVE);
    let amount_in = calculate_amount_in(pool, amount_out, reserve_x, reserve_y);
    let value_coin_in_max = coin::value(&coin_in_max);
    assert!(value_coin_in_max >= amount_in, INVALID_WITH_INPUT_AMOUNT);

    handle_coin_x_from(pool, coin_in);
    
    handle_coin_y_to(pool, amount_out, ctx);
}

public entry fun swap_y_for_exact_x<X,Y>(pool: &mut Pool<X,Y>, coin_in_max: Coin<Y>, amount_out: u64, ctx: &mut TxContext){
    let is_ordered = sort<X, Y>();
    assert!(is_ordered, NOT_ORDERED);
    let (reserve_x, reserve_y) = get_reserve(pool);
    assert!(reserve_x > 0 && reserve_y > 0, NOT_ENOUGH_LIQUIDITY);
    assert!(amount_out > 0, NOT_POSITIVE);
    let amount_in = calculate_amount_in(pool, amount_out, reserve_y, reserve_x);
    let value_coin_in_max = coin::value(&coin_in_max);
    assert!(amount_out >= amount_out_min, INVALID_WITH_INPUT_AMOUNT);
    
    handle_coin_y_from(pool, coin_in);
    
    handle_coin_x_to(pool, amount_out, ctx);
}

public entry fun set_fee<X,Y>(pool: &mut Pool<X,Y>, new_fee: u64) {
    let is_ordered = sort<X, Y>();
    assert!(is_ordered, NOT_ORDERED);
    assert!(fee > 0 && fee < 1000, NOT_POSITIVE);
    pool.fee = fee;
}

public fun handle_coin_x_from<X,Y>(pool: &mut Pool<X,Y>, coin_from: Coin<X>){
    let coin_from_balance = coin::into_balance(coin_from);
    balance::join(&mut pool.coin_x, coin_from_balance);
}

public fun handle_coin_y_from<X,Y>(pool: &mut Pool<X,Y>, coin_from: Coin<Y>){
    let coin_from_balance = coin::into_balance(coin_from);
    balance::join(&mut pool.coin_y, coin_from_balance);
}

public fun handle_coin_y_to<X,Y>(pool: &mut Pool<X,Y>, amount_out:u64, ctx: &mut TxContext){
    let coin_to_balance = balance::take(&mut pool.coin_y, amount_out, ctx);
    transfer::public_transfer(coin_to_balance, tx_context::sender(ctx));
}

public fun handle_coin_x_to<X,Y>(pool: &mut Pool<X,Y>, amount_out:u64, ctx: &mut TxContext){
    let coin_to_balance = balance::take(&mut pool.coin_x, amount_out, ctx);
    transfer::public_transfer(coin_to_balance, tx_context::sender(ctx));
}

// given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
public fun calculate_amount_out<X,Y>(pool: &Pool<X,Y>, amount_in: u64, reserve_in: u64, reserve_out: u64) : u64 {
    let fee = pool.fee;
    let numerator = amount_in * reserve_out * (1000 - fee);
    let denominator = reserve_in * 1000 + amount_in * (1000 - fee);
    let amount_out = numerator / denominator;
    amount_out
}

// given an output amount of an asset and pair reserves, returns a required input amount of the other asset
public fun calculate_amount_in<X,Y>(pool: &Pool<X,Y>, amount_out: u64, reserve_in: u64, reserve_out: u64) : u64 {
    let fee = pool.fee;
    let numerator = reserve_in * amount_out * 1000;
    let denominator = (reserve_out - amount_out) * (1000 - fee);
    let amount_in = (numerator / denominator) + 1;
    amount_in
}

public fun calc_coin_amount_correspond_liqud_token<X,Y>(pool: &mut Pool<X, Y>, liquid_token_amount: u64, reserve_coin: u64) : u64 {
    let liquid_token_supply = balance::supply_value(&pool.liquidity_token_supply);
    let amount_coin = quote(liquid_token_amount, liquid_token_supply, reserve_coin);
    amount_coin
}

public entry fun get_reserve<X, Y>(pool: &mut Pool<X, Y>) : (u64, u64) {
    let balance_x = balance::value(&pool.coin_x);
    let balance_y = balance::value(&pool.coin_y);
    (balance_x, balance_y)
}   

public fun quote(amount_x:u64, reverser_x: u64, reverser_y: u64) : u64 {
    assert!(reverser_x > 0 && reverser_y > 0, NOT_POSITIVE);
    let amount_y = (amount_x * reverser_y) / reverser_x;
    amount_y
}

public fun calculate_amount_optimal_into_liquid<X, Y>(amount_x_desired: u64, amount_y_desired: u64, amount_x_min: u64, amount_y_min: u64, pool: &mut Pool<X,Y>) : u64 {
    let (reserve_x, reserve_y) = get_reserve(pool);
    if (reserve_x == 0 && reserve_y == 0) {
        (reserve_x, reserve_y)
    };
    amount_y_optimal = quote(amount_x_desired, reserve_x, reserve_y);
    if ((amount_y_optimal <= amount_y_desired) && (amount_y_optimal >= amount_y_min)) {
        (amount_x_desired, amount_y_optimal)
    };
    amount_x_optimal = quote(amount_y_desired, reserve_y, reserve_x);
    if((amount_x_optimal <= amount_x_desired) && (amount_x_optimal >= amount_x_min)) {
        (amount_x_optimal, amount_y_desired)
    };
}

//not include fee for protocol 
public fun calculate_liquid_token<X,Y>(pool: &mut Pool<X,Y>, reserve_x: u64, amount_x_transferred: u64) : Balance<LiquidityToken<X, Y>>{
    let liquid_token_supply_value = balance::supply_value(&pool.liquidity_token_supply);
    let liquid_token_for_lp = quote(amount_x_transferred, reserve_x, liquid_token_supply_value);
    let balance_liquid_token_for_lp = balance::increase_supply(&mut pool.liquidity_token_supply, liquid_token_for_lp);
    balance_liquid_token_for_lp
}

//this function is temporary
public entry fun create_coin_zero<X>(ctx: &mut TxContext) {
    let coin = coin::zero<X>(ctx);
    transfer::public_transfer(coin, tx_context::sender(ctx));
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}
