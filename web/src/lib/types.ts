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

