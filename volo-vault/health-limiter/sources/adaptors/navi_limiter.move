module limiter::navi_adaptor;

use lending_core::logic;
use lending_core::storage::Storage;
use oracle::oracle::PriceOracle;
use sui::clock::Clock;
use sui::event::emit;

const DECIMAL_E18: u256 = 1_000_000_000_000_000_000;
const DECIMAL_E9: u256 = 1_000_000_000;

public struct NaviHealthFactorVerified has copy, drop {
    account: address,
    health_factor: u256,
    safe_check_hf: u256,
}

public fun verify_navi_position_healthy(
    clock: &Clock,
    storage: &mut Storage,
    oracle: &PriceOracle,
    account: address,
    min_health_factor: u256,
) {
    let health_factor = logic::user_health_factor(clock, storage, oracle, account);

    emit(NaviHealthFactorVerified {
        account,
        health_factor,
        safe_check_hf: min_health_factor,
    });

    let is_healthy = health_factor > min_health_factor;

    // hf_normalized has 9 decimals
    // e.g. hf = 123456 (123456 * 1e27)
    //      hf_normalized = 123456 * 1e9
    //      hf = 0.5 (5 * 1e26)
    //      hf_normalized = 5 * 1e8 = 0.5 * 1e9
    //      hf = 1.356 (1.356 * 1e27)
    //      hf_normalized = 1.356 * 1e9
    let mut hf_normalized = health_factor / DECIMAL_E18;

    if (hf_normalized > DECIMAL_E9) {
        hf_normalized = DECIMAL_E9;
    };

    assert!(is_healthy, hf_normalized as u64);
}

public fun is_navi_position_healthy(
    clock: &Clock,
    storage: &mut Storage,
    oracle: &PriceOracle,
    account: address,
    min_health_factor: u256,
): bool {
    let health_factor = logic::user_health_factor(clock, storage, oracle, account);
    health_factor > min_health_factor
}
