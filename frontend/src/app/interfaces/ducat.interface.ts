export interface DucatHeightInfo {
  scanned_height: number;
  remote_height: number;
  synced: boolean;
}

export interface DucatStatsVolume {
  btc_volume: number;     // sats (cumulative or scoped)
  unit_volume: number;    // cents (cumulative or scoped)
  btc_locked: number;     // sats (current snapshot)
  unit_borrowed: number;  // cents (current snapshot)
  vaults: number;         // active vault count (current snapshot)
  height: number;
  state_hash: string;
}

export interface DucatPriceLatest {
  base_price: number;     // USD per BTC
  base_stamp: number;
  thold_price: number;
  contract_id: string;
  block_height: number;
}

export interface DucatAssetProfile {
  div: number;       // decimal divisibility
  id: string;        // rune id "height:index"
  label: string;     // e.g. "DUCAT•UNIT•MTNY"
  symbol: string;    // e.g. "$"
  supply: string;
}

export interface DucatProtoMember {
  group: number;     // 21 = guardian, 22 = oracle
  idx: number;
  pubkey: string;
}

export interface DucatProtoTerm {
  group: number;
  key: number;
  value: any[];
}

export interface DucatStatsTxItem {
  txid: string;
  vault_id: string;
  action: string;
  block_time: number;
  btc_value: number;     // sats
  unit_value: number;    // cents
  vault_ratio?: number;  // fraction (1.5 = 150%)
}

export interface DucatStatsTxResp {
  data: DucatStatsTxItem[];
  next_cursor: string | null;
  has_more: boolean;
}

export interface DucatProtoProfile {
  anchor_id: string;
  anchor_height: number;
  anchor_index: number;
  anchor_txid: string;
  boot_height: number;
  chain_network: string;
  domain_hash: string;
  chain_height: number;
  contract_height: number;
  contract_index: number;
  contract_txid: string;
  contract_id: string;
  proto_assets: DucatAssetProfile[];
  proto_members: DucatProtoMember[];
  proto_terms: DucatProtoTerm[];
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
