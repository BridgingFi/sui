// Type definitions for vault data structures

export interface VaultInfo {
  vault_id: string;
  reward_manager_id: string;
  coin_type: string;
  created_at_ms: number;
  creator: string;
}

export interface VaultRegistryData {
  id: string;
  admin: string;
  vaults: {
    fields: {
      contents: Array<{
        key: string;
        value: VaultInfo;
      }>;
    };
  };
}

export interface OracleConfig {
  id: string;
  version: number;
  update_interval: number;
  dex_slippage: string;
  aggregators: Map<string, PriceInfo>;
}

export interface PriceInfo {
  aggregator: string;
  /**
   * CoinType's decimals, used for price normalization calculations
   * (e.g., get_normalized_asset_price normalizes to 9 decimals).
   * NOT used for formatting Oracle price display, which uses 18 decimals
   * (ORACLE_DECIMALS = 10^18, matching Switchboard's Decimal format).
   */
  decimals: number;
  price: string;
  last_updated: number;
}

export interface SwitchboardAggregator {
  id: string;
  name: string;
  address: string;
  authority: string;
  created_at_ms: string;
  current_result?: {
    result: {
      value: string;
      neg: boolean;
    };
    timestamp_ms: string;
  };
}
