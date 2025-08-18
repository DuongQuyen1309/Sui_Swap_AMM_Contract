#[test_only]
module sui_swap_amm_contract::swap_token_test;
use sui_swap_amm_contract::swap_token;
use sui::test_scenario;
use sui::coin;
use std::debug;
use sui::balance;
use sui_swap_amm_contract::crg;
use sui_swap_amm_contract::prg;
use sui_swap_amm_contract::swap_token::{AdminCap as SwapAdmin};
use sui_swap_amm_contract::swap_token::{Pool, LiquidityToken};
use sui_swap_amm_contract::crg::{AdminCap as AdminCrg};
use sui_swap_amm_contract::prg::{AdminCap as AdminPrg};
use sui_swap_amm_contract::crg::{CRG};
use sui_swap_amm_contract::prg::{PRG};
use sui::coin::{TreasuryCap};

const ERROR_NOT_EQUAL_RESULT: u64 = 0;

//case 1: success: add liquidity 100000 CRG and 1000000 PRG
#[test]
fun test_add_liquidity(){
    set_up_add_liquid<CRG, PRG>(4000000, 1000000, 1000000, 1000000, 4000000, 1000000, 2000000);
}

//case 2: success: remove liquidity 1000000 CRG and 1000000 PRG
#[test]
fun test_remove_liquidity(){
    set_up_remove_liquid<CRG, PRG>(1000000, 1000000, 0, 0, 0);
}

//case 3: success: swap 50000 crg (min_crg 23000 prg) to get 23582 prg with fee = 10 (10/1000)
#[test]
fun test_swap_exact_x_for_y(){
    set_up_swap_exact_x_for_y<CRG, PRG>(50000, 23000, 1050000,476417);
}

//case 4: success: want to get 10000 prg, need to swap 20615 crg (max_crg 30000 crg) with fee = 10 (10/1000)
#[test]
fun test_swap_x_for_y(){
    set_up_swap_x_for_exact_y<CRG, PRG>(30000, 10000, 1020615, 490000);
}

//case 5: success: set fee = 20 (20/1000)
#[test]
fun test_set_fee(){
    set_up_set_fee<CRG, PRG>(20, 20);
}

//case 6: fail: add liquidity with amount_x_min > amount_x that is actual to add pool
#[test]
#[expected_failure]
fun test_add_liquidity_fail(){
    set_up_add_liquid<CRG, PRG>(1000000, 1000000, 2000000, 1000000, 1000000, 1000000, 1000000);
}

//case 7: fail : remove liquidity with amount_coin_x_min > amount_coin_x that is actual for caller to get from pool
#[test]
#[expected_failure]
fun test_remove_liquidity_fail(){
    set_up_remove_liquid<CRG, PRG>(2000000, 1000000, 0, 0, 0);
}

//case 8: fail: swap 50000 crg (min_crg 30000 prg) with fee = 10 (10/1000). min_crg > amount_prg that is actual to get from pool
#[test]
#[expected_failure]
fun test_swap_exact_x_for_y_fail(){
    set_up_swap_exact_x_for_y<CRG, PRG>(50000, 30000, 1050000, 476417);
}


//case 9: fail: want to get 10000 prg, need to swap 20615 crg but max_crg is too little (20614 crg) with fee = 10 (10/1000)
#[test]
#[expected_failure]
fun test_swap_x_for_exact_y_fail(){
    set_up_swap_x_for_exact_y<CRG, PRG>(20614, 10000, 1020615, 490000);
}

#[test_only]
fun set_up_add_liquid<X,Y>(coin_x_value: u64, coin_y_value: u64, amount_x_min: u64, amount_y_min: u64, expected_amount_x: u64, expected_amount_y: u64, expected_amount_lt: u64) {
    let (owner, mut scenario) = set_up_scenario();
    intialize_contract_swap_contract_token(&mut scenario, owner);
    let admin : SwapAdmin = set_up_admin_treasury_pool<X,Y>(10, &mut scenario, owner);

    mint_token(coin_x_value, coin_y_value, &mut scenario, owner);
    
    test_scenario::next_tx(&mut scenario, owner);
    let mut coin_x = test_scenario::take_from_sender<coin::Coin<X>>(&mut scenario); 
    let mut coin_y = test_scenario::take_from_sender<coin::Coin<Y>>(&mut scenario);  

    test_scenario::next_tx(&mut scenario, owner);
    let mut pool = test_scenario::take_shared<Pool<X,Y>>(&mut scenario);

    test_scenario::next_tx(&mut scenario, owner);
    swap_token::add_liquid(&mut pool, coin_x, coin_y, amount_x_min, amount_y_min, test_scenario::ctx(&mut scenario));

    let coin_x_balance = swap_token::get_coin_x_from_pool(&mut pool);
    let coin_y_balance = swap_token::get_coin_y_from_pool(&mut pool);
    let lt_balance = swap_token::get_liquidity_token_supply(&mut pool);

    assert!(coin_x_balance == expected_amount_x,ERROR_NOT_EQUAL_RESULT);
    assert!(coin_y_balance == expected_amount_y,ERROR_NOT_EQUAL_RESULT);
    assert!(lt_balance == expected_amount_lt, ERROR_NOT_EQUAL_RESULT);

    test_scenario::next_tx(&mut scenario, owner);
    transfer::public_transfer(admin, owner);
    test_scenario::return_shared(pool);
    test_scenario::end(scenario);
}

#[test_only]
fun set_up_remove_liquid<X,Y>(amount_coin_x_min: u64, amount_coin_y_min: u64, expected_amount_x: u64, expected_amount_y: u64, expected_amount_lt: u64) {
    let (owner, mut scenario) = set_up_scenario();
    intialize_contract_swap_contract_token(&mut scenario, owner);
    let admin : SwapAdmin = set_up_admin_treasury_pool<X,Y>(10, &mut scenario, owner);

    mint_token(1000000, 1000000, &mut scenario, owner);
    
    test_scenario::next_tx(&mut scenario, owner);
    let mut coin_x = test_scenario::take_from_sender<coin::Coin<X>>(&mut scenario); 
    let mut coin_y = test_scenario::take_from_sender<coin::Coin<Y>>(&mut scenario);  

    test_scenario::next_tx(&mut scenario, owner);
    let mut pool = test_scenario::take_shared<Pool<X,Y>>(&mut scenario);

    test_scenario::next_tx(&mut scenario, owner);
    swap_token::add_liquid(&mut pool, coin_x, coin_y, 1000000, 1000000, test_scenario::ctx(&mut scenario));

    test_scenario::next_tx(&mut scenario, owner);
    let mut coin_liquid_token = test_scenario::take_from_sender<coin::Coin<LiquidityToken<X,Y>>>(&mut scenario);
    swap_token::remove_liquid(&mut pool, coin_liquid_token, amount_coin_x_min, amount_coin_y_min, test_scenario::ctx(&mut scenario));

    let coin_x_balance = swap_token::get_coin_x_from_pool(&mut pool);
    let coin_y_balance = swap_token::get_coin_y_from_pool(&mut pool);
    let lt_balance = swap_token::get_liquidity_token_supply(&mut pool);

    assert!(coin_x_balance == expected_amount_x,ERROR_NOT_EQUAL_RESULT);
    assert!(coin_y_balance == expected_amount_y,ERROR_NOT_EQUAL_RESULT);
    assert!(lt_balance == expected_amount_lt, ERROR_NOT_EQUAL_RESULT);

    test_scenario::next_tx(&mut scenario, owner);
    transfer::public_transfer(admin, owner);
    test_scenario::return_shared(pool);
    test_scenario::end(scenario);
}

#[test_only]
fun set_up_swap_exact_x_for_y<X,Y>(amount_x_to_swap: u64, amount_y_min: u64, expected_amount_x: u64, expected_amount_y: u64) {
    let (owner, mut scenario) = set_up_scenario();
    intialize_contract_swap_contract_token(&mut scenario, owner);
    let admin : SwapAdmin = set_up_admin_treasury_pool<X,Y>(10, &mut scenario, owner);

    mint_token(1000000, 500000, &mut scenario, owner);

    test_scenario::next_tx(&mut scenario, owner);
    let mut coin_x = test_scenario::take_from_sender<coin::Coin<X>>(&mut scenario); 
    let mut coin_y = test_scenario::take_from_sender<coin::Coin<Y>>(&mut scenario);  

    test_scenario::next_tx(&mut scenario, owner);
    let mut pool = test_scenario::take_shared<Pool<X,Y>>(&mut scenario);

    test_scenario::next_tx(&mut scenario, owner);
    swap_token::add_liquid(&mut pool, coin_x, coin_y, 1000000, 500000, test_scenario::ctx(&mut scenario));

    mint_token(amount_x_to_swap, 0, &mut scenario, owner);

    test_scenario::next_tx(&mut scenario, owner);
    let mut coin_x_to_swap = test_scenario::take_from_sender<coin::Coin<X>>(&mut scenario);

    test_scenario::next_tx(&mut scenario, owner);
    swap_token::swap_exact_x_for_y<X,Y>(&mut pool, coin_x_to_swap, amount_y_min , test_scenario::ctx(&mut scenario));

    let coin_x_balance = swap_token::get_coin_x_from_pool(&mut pool);
    let coin_y_balance = swap_token::get_coin_y_from_pool(&mut pool);

    test_scenario::next_tx(&mut scenario, owner);
    transfer::public_transfer(admin, owner);
    test_scenario::return_shared(pool);
    test_scenario::end(scenario);
}

#[test_only]
fun set_up_swap_x_for_exact_y<X,Y>(amount_x_max: u64, amount_y: u64, expected_amount_x: u64, expected_amount_y: u64) {
    let (owner, mut scenario) = set_up_scenario();
    intialize_contract_swap_contract_token(&mut scenario, owner);
    let admin : SwapAdmin = set_up_admin_treasury_pool<X,Y>(10, &mut scenario, owner);

    mint_token(1000000, 500000, &mut scenario, owner);

    test_scenario::next_tx(&mut scenario, owner);
    let mut coin_x = test_scenario::take_from_sender<coin::Coin<X>>(&mut scenario); 
    let mut coin_y = test_scenario::take_from_sender<coin::Coin<Y>>(&mut scenario);  

    test_scenario::next_tx(&mut scenario, owner);
    let mut pool = test_scenario::take_shared<Pool<X,Y>>(&mut scenario);

    test_scenario::next_tx(&mut scenario, owner);
    swap_token::add_liquid(&mut pool, coin_x, coin_y, 1000000, 500000, test_scenario::ctx(&mut scenario));

    mint_token(amount_x_max, 0, &mut scenario, owner);

    test_scenario::next_tx(&mut scenario, owner);
    let mut coin_x_max_to_swap = test_scenario::take_from_sender<coin::Coin<X>>(&mut scenario);

    test_scenario::next_tx(&mut scenario, owner);
    swap_token::swap_x_for_exact_y<X,Y>(&mut pool, coin_x_max_to_swap, amount_y , test_scenario::ctx(&mut scenario));

    let coin_x_balance = swap_token::get_coin_x_from_pool(&mut pool);
    let coin_y_balance = swap_token::get_coin_y_from_pool(&mut pool);

    test_scenario::next_tx(&mut scenario, owner);
    transfer::public_transfer(admin, owner);
    test_scenario::return_shared(pool);
    test_scenario::end(scenario);
}

#[test_only]
fun set_up_set_fee<X,Y>(new_fee: u64, expected_fee: u64) {
    let (owner, mut scenario) = set_up_scenario();
    intialize_contract_swap_contract_token(&mut scenario, owner);
    let admin : SwapAdmin = set_up_admin_treasury_pool<X,Y>(10, &mut scenario, owner);

    test_scenario::next_tx(&mut scenario, owner);
    let mut pool = test_scenario::take_shared<Pool<X,Y>>(&mut scenario);

    test_scenario::next_tx(&mut scenario, owner);
    swap_token::set_fee(&mut pool, new_fee);

    test_scenario::next_tx(&mut scenario, owner);
    let fee = swap_token::get_fee(&mut pool);
    assert!(fee == expected_fee, ERROR_NOT_EQUAL_RESULT);

    test_scenario::next_tx(&mut scenario, owner);
    transfer::public_transfer(admin, owner);
    test_scenario::return_shared(pool);
    test_scenario::end(scenario);
}

#[test_only]
fun set_up_scenario(): (address, test_scenario::Scenario) {
    let owner = @0xA;
    let scenario_val = test_scenario::begin(owner);
    (owner, scenario_val)
}

#[test_only]
fun intialize_contract_swap_contract_token(scenario: &mut test_scenario::Scenario, owner: address){
    //initialize swap_token contract
    test_scenario::next_tx(scenario, owner);
    swap_token::init_for_testing(test_scenario::ctx(scenario));

    //create token CRG to test
    test_scenario::next_tx(scenario, owner);
    crg::init_for_testing(test_scenario::ctx(scenario));

    //create token PRG to test
    test_scenario::next_tx(scenario, owner);
    prg::init_for_testing(test_scenario::ctx(scenario));
}

#[test_only]
fun set_up_admin_treasury_pool<X,Y>(fee: u64,scenario: &mut test_scenario::Scenario, owner: address): (SwapAdmin) {
    test_scenario::next_tx(scenario, owner);
    let admin = test_scenario::take_from_sender<SwapAdmin>(scenario);
    test_scenario::next_tx(scenario, owner);
    swap_token::register_pool<X,Y>(
        &admin, 
        10,
        test_scenario::ctx(scenario),
    );
    admin
}

#[test_only]
fun mint_token(coin_of_crg: u64, coin_of_prg: u64, scenario: &mut test_scenario::Scenario, owner: address){
    test_scenario::next_tx(scenario, owner);
    let mut treasury_crg = test_scenario::take_from_sender<TreasuryCap<CRG>>(scenario);  
    let mut treasury_prg = test_scenario::take_from_sender<TreasuryCap<PRG>>(scenario); 
    let admin_crg = test_scenario::take_from_sender<AdminCrg>(scenario);
    let admin_prg = test_scenario::take_from_sender<AdminPrg>(scenario);

    test_scenario::next_tx(scenario, owner);
    prg::mint(&admin_prg, &mut treasury_prg, coin_of_prg, owner,test_scenario::ctx(scenario));
    crg::mint(&admin_crg, &mut treasury_crg, coin_of_crg, owner,test_scenario::ctx(scenario));
    transfer::public_transfer(treasury_crg, owner);
    transfer::public_transfer(treasury_prg, owner);
    transfer::public_transfer(admin_crg, owner);
    transfer::public_transfer(admin_prg, owner);
}