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
