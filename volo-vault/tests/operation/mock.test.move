#[test_only]
module volo_vault::mock_test;

use sui::clock;
use sui::test_scenario;
use volo_vault::init_vault;
use volo_vault::mock_cetus::{Self, MockCetusPosition};
use volo_vault::mock_suilend::{Self, MockSuilendObligation};
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::test_helpers;
use volo_vault::usdc_test_coin::USDC_TEST_COIN;
use volo_vault::vault_oracle::OracleConfig;

const OWNER: address = @0xa;
const DECIMALS: u256 = 1_000_000_000;
const ORACLE_DECIMALS: u256 = 1_000_000_000_000_000_000; // 18 decimals

#[test]
// [TEST-CASE: Should create mock cetus position.] @test-case MOCK-001
public fun test_create_mock_cetus_position() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut mock_cetus_position = mock_cetus::create_mock_position<
            SUI_TEST_COIN,
            USDC_TEST_COIN,
        >(s.ctx());

        mock_cetus::set_token_amount(&mut mock_cetus_position, 1_000_000_000, 1_000_000_000);

        assert!(mock_cetus_position.amount_a() == 1_000_000_000, 0);
        assert!(mock_cetus_position.amount_b() == 1_000_000_000, 0);

        transfer::public_transfer(mock_cetus_position, OWNER);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should calculate mock cetus position value.] @test-case MOCK-002
public fun test_mock_cetus_position_value() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);
        test_scenario::return_shared(oracle_config);
    };

    s.next_tx(OWNER);
    {
        let mut mock_cetus_position = mock_cetus::create_mock_position<
            SUI_TEST_COIN,
            USDC_TEST_COIN,
        >(s.ctx());

        mock_cetus::set_token_amount(&mut mock_cetus_position, 1_000_000_000, 1_000_000);

        transfer::public_transfer(mock_cetus_position, OWNER);
    };

    s.next_tx(OWNER);
    {
        let mock_cetus_position = s.take_from_sender<
            MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
        >();

        let oracle_config = s.take_shared<OracleConfig>();

        let value = mock_cetus::calculate_cetus_position_value(
            &mock_cetus_position,
            &oracle_config,
            &clock,
        );

        assert!(value == 3 * DECIMALS, 0);

        test_scenario::return_shared(oracle_config);
        s.return_to_sender(mock_cetus_position);
    };

    s.next_tx(OWNER);
    {
        let mut mock_cetus_position = mock_cetus::create_mock_position<
            SUI_TEST_COIN,
            USDC_TEST_COIN,
        >(s.ctx());

        mock_cetus::set_token_amount(&mut mock_cetus_position, 2_000_000_000, 6_000_000);

        transfer::public_transfer(mock_cetus_position, OWNER);
    };

    s.next_tx(OWNER);
    {
        let mock_cetus_position = s.take_from_sender<
            MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
        >();

        let oracle_config = s.take_shared<OracleConfig>();

        let value = mock_cetus::calculate_cetus_position_value(
            &mock_cetus_position,
            &oracle_config,
            &clock,
        );

        assert!(value == 10 * DECIMALS, 0);

        test_scenario::return_shared(oracle_config);
        s.return_to_sender(mock_cetus_position);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should create mock suilend obligation.] @test-case MOCK-003
public fun test_create_mock_suilend_obligation() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mock_suilend_obligation = mock_suilend::create_mock_obligation<SUI_TEST_COIN>(
            s.ctx(),
            (1 * DECIMALS) as u64,
        );

        assert!(mock_suilend_obligation.usd_value() == (1 * DECIMALS) as u64, 0);

        transfer::public_transfer(mock_suilend_obligation, OWNER);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should calculate mock suilend obligation value.] @test-case MOCK-004
public fun test_mock_suilend_obligation_value() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);
        test_scenario::return_shared(oracle_config);
    };

    s.next_tx(OWNER);
    {
        let mock_suilend_obligation = mock_suilend::create_mock_obligation<SUI_TEST_COIN>(
            s.ctx(),
            (1 * DECIMALS) as u64,
        );

        assert!(mock_suilend_obligation.usd_value() == (1 * DECIMALS) as u64, 0);

        transfer::public_transfer(mock_suilend_obligation, OWNER);
    };

    s.next_tx(OWNER);
    {
        let mock_suilend_obligation = s.take_from_sender<MockSuilendObligation<SUI_TEST_COIN>>();

        let oracle_config = s.take_shared<OracleConfig>();

        let value = mock_suilend::calculate_suilend_obligation_value(&mock_suilend_obligation);

        assert!(value == 1 * DECIMALS, 0);

        test_scenario::return_shared(oracle_config);
        s.return_to_sender(mock_suilend_obligation);
    };

    s.next_tx(OWNER);
    {
        let mut mock_suilend_obligation = s.take_from_sender<
            MockSuilendObligation<SUI_TEST_COIN>,
        >();

        mock_suilend::set_usd_value(&mut mock_suilend_obligation, (2 * DECIMALS) as u64);

        let oracle_config = s.take_shared<OracleConfig>();

        let value = mock_suilend::calculate_suilend_obligation_value(&mock_suilend_obligation);

        assert!(value == 2 * DECIMALS, 0);

        test_scenario::return_shared(oracle_config);
        s.return_to_sender(mock_suilend_obligation);
    };

    clock.destroy_for_testing();
    s.end();
}
