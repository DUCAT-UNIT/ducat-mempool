export interface DucatHeightInfo {
  scanned_height: number;
  remote_height: number;
  synced: boolean;
}

export interface DucatTxData {
  is_ducat: boolean;
  action?: string;
  vault_id?: string;
  outputs: DucatTxOutput[];
  vault_stone?: DucatVaultStone;
  coins: DucatAssetAccount[];
  commits: any[];
  vaults: DucatVaultProfile[];
}

export interface DucatTxOutput {
  vout: number;
  type: string;
  value: number;
  script: string;
  assets: DucatOutputAsset[];
}

export interface DucatOutputAsset {
  asset_id: string;
  amount: number;
  reserve: number;
}

export interface DucatVaultStone {
  encumbered: boolean;
  version: number;
  guardian_indices: number[];
  unit_balance?: number;
  price_stamp?: number;
  base_price?: number;
  thold_price?: number;
  price_commits: DucatPriceCommit[];
}

export interface DucatPriceCommit {
  base_price: number;
  oracle_pubkey: string;
  oracle_sig: string;
  thold_hash: string;
  thold_price: number;
}

export interface DucatAssetAccount {
  asset_id: string;
  asset_balance: number;
  asset_reserve: number;
  coin_id: string;
  coin_script: string;
  coin_value: number;
}

export interface DucatVaultProfile {
  block_height?: number;
  block_index?: number;
  client_pubkey: string;
  coin_id?: string;
  contract_id: string;
  guard_members: string[];
  guard_pubkey: string;
  oracle_members: string[];
  price_commits: DucatPriceCommit[];
  price_stamp?: number;
  root_txid: string;
  spend_height?: number;
  thold_price?: number;
  unit_balance: number;
  unit_price?: number;
  vault_action: string;
  vault_config?: { label: string };
  vault_ratio?: number;
  vault_balance: number;
  vault_value?: number;
  vault_version: number;
  vault_script?: string;
}
