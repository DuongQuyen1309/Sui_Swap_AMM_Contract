#[test_only]
module sui_swap_amm_contract::swap_token_test;
use sui_swap_amm_contract::swap_token;
use sui::test_scenario;
use sui_swap_amm_contract::crg;
use sui_swap_amm_contract::prg;
use sui_swap_amm_contract::crg::{CRG};
use sui_swap_amm_contract::prg::{PRG};

const ERROR_NOT_EQUAL_RESULT: u64 = 0;
#[test]
fun test_sort() {
    let (owner, mut scenario) = set_up_scenario();
    test_scenario::next_tx(&mut scenario, owner);
    let result = swap_token::sort<CRG, PRG>();
    assert!(result, ERROR_NOT_EQUAL_RESULT);
    test_scenario::end(scenario);
}

#[test_only]
fun set_up_scenario(): (address, test_scenario::Scenario) {
    let owner = @0xA;
    let scenario_val = test_scenario::begin(owner);
    (owner, scenario_val)
}